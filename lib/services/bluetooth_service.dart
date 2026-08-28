import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

class BluetoothService {
  // ============================================================
  // GeoScan AI
  // Flutter <-> ESP32 BLE
  //
  // SHARED SINGLETON SERVICE
  // جميع شاشات التطبيق تستخدم نفس الاتصال
  // ============================================================

  static final BluetoothService _instance =
      BluetoothService._internal();

  factory BluetoothService() {
    return _instance;
  }

  BluetoothService._internal();

  // ============================================================
  // BLE UUIDs
  // ============================================================

  static final fbp.Guid serviceUuid = fbp.Guid(
    '12345678-1234-1234-1234-1234567890ab',
  );

  static final fbp.Guid notifyUuid = fbp.Guid(
    '12345678-1234-1234-1234-1234567890ac',
  );

  static final fbp.Guid writeUuid = fbp.Guid(
    '12345678-1234-1234-1234-1234567890ad',
  );

  // ============================================================
  // DEVICE
  // ============================================================

  fbp.BluetoothDevice? device;

  fbp.BluetoothCharacteristic? notifyCharacteristic;
  fbp.BluetoothCharacteristic? writeCharacteristic;

  // ============================================================
  // SUBSCRIPTIONS
  // ============================================================

  StreamSubscription<List<int>>? _notifySubscription;

  StreamSubscription<fbp.BluetoothConnectionState>?
      _connectionSubscription;

  // ============================================================
  // STREAM CONTROLLERS
  // ============================================================

  final StreamController<double> _signalController =
      StreamController<double>.broadcast();

  final StreamController<String> _dataController =
      StreamController<String>.broadcast();

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  // ============================================================
  // PUBLIC STREAMS
  // ============================================================

  Stream<double> get signalStream =>
      _signalController.stream;

  Stream<String> get dataStream =>
      _dataController.stream;

  Stream<bool> get connectionStream =>
      _connectionController.stream;

  // ============================================================
  // CONNECTION STATE
  // ============================================================

  bool get isConnected =>
      device != null && device!.isConnected;

  // ============================================================
  // BLE SCAN
  // ============================================================

  Future<List<fbp.ScanResult>> scan({
    Duration timeout =
        const Duration(seconds: 8),
  }) async {
    final List<fbp.ScanResult> results = [];

    StreamSubscription<List<fbp.ScanResult>>?
        subscription;

    try {
      await fbp.FlutterBluePlus.stopScan();

      subscription =
          fbp.FlutterBluePlus.scanResults.listen(
        (scanResults) {
          for (final result in scanResults) {
            final exists = results.any(
              (item) =>
                  item.device.remoteId ==
                  result.device.remoteId,
            );

            if (!exists) {
              results.add(result);
            }
          }
        },
      );

      await fbp.FlutterBluePlus.startScan(
        timeout: timeout,
      );

      await Future.delayed(timeout);

      await fbp.FlutterBluePlus.stopScan();

      await subscription.cancel();
      subscription = null;
    } catch (e) {
      print(
        'GeoScan AI Scan Error: $e',
      );

      try {
        await fbp.FlutterBluePlus.stopScan();
      } catch (_) {}

      await subscription?.cancel();
    }

    return results;
  }

  // ============================================================
  // CONNECT
  // ============================================================

  Future<bool> connect(
    fbp.BluetoothDevice target,
  ) async {
    try {
      // إذا كان هناك اتصال سابق، نفصله أولًا
      if (device != null) {
        await disconnect();
      }

      device = target;

      await device!.connect(
        license: fbp.License.free,
        timeout:
            const Duration(seconds: 15),
        autoConnect: false,
      );

      _connectionController.add(true);

      // مراقبة حالة الاتصال
      await _connectionSubscription?.cancel();

      _connectionSubscription =
          device!.connectionState.listen(
        (state) {
          final connected =
              state ==
                  fbp.BluetoothConnectionState
                      .connected;

          _connectionController.add(
            connected,
          );

          if (!connected) {
            notifyCharacteristic = null;
            writeCharacteristic = null;
          }
        },
        onError: (error) {
          print(
            'GeoScan AI Connection State Error: $error',
          );
        },
      );

      // اكتشاف الخدمات
      final services =
          await device!.discoverServices();

      notifyCharacteristic = null;
      writeCharacteristic = null;

      for (final service in services) {
        if (service.uuid != serviceUuid) {
          continue;
        }

        for (final characteristic
            in service.characteristics) {
          if (characteristic.uuid ==
              notifyUuid) {
            notifyCharacteristic =
                characteristic;
          }

          if (characteristic.uuid ==
              writeUuid) {
            writeCharacteristic =
                characteristic;
          }
        }
      }

      // التأكد من وجود الخصائص المطلوبة
      if (notifyCharacteristic == null ||
          writeCharacteristic == null) {
        print(
          'GeoScan AI: BLE characteristics not found',
        );

        await disconnect();

        return false;
      }

      // تشغيل استقبال البيانات
      final notificationStarted =
          await startNotifications();

      if (!notificationStarted) {
        await disconnect();

        return false;
      }

      // طلب حالة ESP32 الحالية
      await getStatus();

      return true;
    } catch (e) {
      print(
        'GeoScan AI Connection Error: $e',
      );

      _connectionController.add(false);

      device = null;

      return false;
    }
  }

  // ============================================================
  // NOTIFICATIONS
  // ============================================================

  Future<bool> startNotifications() async {
    if (notifyCharacteristic == null) {
      return false;
    }

    try {
      await _notifySubscription?.cancel();

      await notifyCharacteristic!
          .setNotifyValue(true);

      _notifySubscription =
          notifyCharacteristic!
              .lastValueStream
              .listen(
        (value) {
          _handleIncomingData(value);
        },
        onError: (error) {
          print(
            'GeoScan AI Notification Error: $error',
          );
        },
      );

      return true;
    } catch (e) {
      print(
        'GeoScan AI Notification Start Error: $e',
      );

      return false;
    }
  }

  // ============================================================
  // ESP32 DATA
  // ============================================================

  void _handleIncomingData(
    List<int> value,
  ) {
    if (value.isEmpty) {
      return;
    }

    try {
      final text = utf8
          .decode(
            value,
            allowMalformed: true,
          )
          .trim();

      if (text.isEmpty) {
        return;
      }

      print(
        'GeoScan AI <- ESP32: $text',
      );

      // إرسال البيانات الخام إلى جميع الشاشات
      _dataController.add(text);

      // محاولة قراءة JSON
      final decoded =
          _tryParseJson(text);

      if (decoded != null) {
        final incomingSignal =
            decoded['signal'] ??
                decoded['value'] ??
                decoded['strength'] ??
                decoded['reading'];

        if (incomingSignal != null) {
          final parsedSignal =
              double.tryParse(
                    incomingSignal.toString(),
                  ) ??
                  0.0;

          final safeSignal =
              parsedSignal
                  .clamp(0.0, 100.0)
                  .toDouble();

          _signalController.add(
            safeSignal,
          );
        }
      }
    } catch (e) {
      print(
        'GeoScan AI Data Error: $e',
      );
    }
  }

  Map<String, dynamic>? _tryParseJson(
    String data,
  ) {
    try {
      final decoded = jsonDecode(data);

      if (decoded is Map) {
        return Map<String, dynamic>.from(
          decoded,
        );
      }
    } catch (_) {}

    return null;
  }

  // ============================================================
  // SEND COMMAND
  // ============================================================

  Future<bool> sendCommand(
    String command,
  ) async {
    if (!isConnected ||
        writeCharacteristic == null) {
      print(
        'GeoScan AI: Write characteristic unavailable',
      );

      return false;
    }

    try {
      final bytes = utf8.encode(command);

      final withoutResponse =
          writeCharacteristic!
              .properties
              .writeWithoutResponse;

      await writeCharacteristic!.write(
        bytes,
        withoutResponse:
            withoutResponse,
      );

      print(
        'GeoScan AI -> ESP32: $command',
      );

      return true;
    } catch (e) {
      print(
        'GeoScan AI Write Error: $e',
      );

      return false;
    }
  }

  // ============================================================
  // START SCAN
  // ESP32: START
  // ============================================================

  Future<bool> startScanning() async {
    return sendCommand('START');
  }

  // توافق مع الأكواد القديمة
  Future<bool> startScan() async {
    return startScanning();
  }

  // ============================================================
  // STOP SCAN
  // ESP32: STOP
  // ============================================================

  Future<bool> stopScanning() async {
    return sendCommand('STOP');
  }

  // توافق مع الأكواد القديمة
  Future<bool> stopScan() async {
    return stopScanning();
  }

  // ============================================================
  // CALIBRATION
  // ESP32: CALIBRATE
  // ============================================================

  Future<bool> calibrate() async {
    return sendCommand('CALIBRATE');
  }

  // ============================================================
  // STATUS
  // ESP32: GET_STATUS
  // ============================================================

  Future<bool> getStatus() async {
    return sendCommand('GET_STATUS');
  }

  // ============================================================
  // SENSITIVITY
  // ESP32: SENSITIVITY:x
  // ============================================================

  Future<bool> setSensitivity(
    double value,
  ) async {
    final safe =
        value
            .clamp(0.0, 100.0)
            .toDouble();

    return sendCommand(
      'SENSITIVITY:${safe.toStringAsFixed(0)}',
    );
  }

  // ============================================================
  // FILTER
  // Flutter Arabic -> ESP32
  // ============================================================

  Future<bool> setFilter(
    String value,
  ) async {
    String filter;

    switch (value) {
      case 'منخفضة':
        filter = 'LOW';
        break;

      case 'عالية':
        filter = 'HIGH';
        break;

      case 'متوسطة':
      default:
        filter = 'MEDIUM';
        break;
    }

    return sendCommand(
      'FILTER:$filter',
    );
  }

  // ============================================================
  // AUDIO
  // ============================================================

  Future<bool> setAudio(
    bool enabled,
  ) async {
    return sendCommand(
      enabled
          ? 'AUDIO:ON'
          : 'AUDIO:OFF',
    );
  }

  // ============================================================
  // VIBRATION
  // ============================================================

  Future<bool> setVibration(
    bool enabled,
  ) async {
    return sendCommand(
      enabled
          ? 'VIBRATION:ON'
          : 'VIBRATION:OFF',
    );
  }

  // ============================================================
  // TARGET
  // ESP32 الحالي لا يملك TARGET
  // ============================================================

  Future<bool> setTarget(
    String target,
  ) async {
    print(
      'GeoScan AI: Target selection is handled by Flutter.',
    );

    return true;
  }

  // ============================================================
  // DEVICE INFO
  // ============================================================

  String get deviceName {
    if (device == null) {
      return 'غير متصل';
    }

    final name =
        device!.platformName;

    if (name.isEmpty) {
      return 'GeoScan-AI';
    }

    return name;
  }

  String get deviceId {
    return device?.remoteId.str ?? '';
  }

  // ============================================================
  // DISCONNECT
  // ============================================================

  Future<void> disconnect() async {
    try {
      await _notifySubscription?.cancel();

      _notifySubscription = null;

      await _connectionSubscription?.cancel();

      _connectionSubscription = null;

      if (notifyCharacteristic != null) {
        try {
          await notifyCharacteristic!
              .setNotifyValue(false);
        } catch (_) {}
      }

      if (device != null) {
        try {
          await device!.disconnect();
        } catch (_) {}
      }
    } catch (e) {
      print(
        'GeoScan AI Disconnect Error: $e',
      );
    }

    notifyCharacteristic = null;
    writeCharacteristic = null;
    device = null;

    _connectionController.add(false);
  }

  // ============================================================
  // IMPORTANT
  //
  // لا نغلق StreamControllers هنا.
  //
  // BluetoothService مشترك طوال عمر التطبيق.
  // ============================================================

  Future<void> dispose() async {
    await disconnect();
  }
}
