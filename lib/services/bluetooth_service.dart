import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

class BluetoothService {
  // ============================================================
  // GeoScan AI
  // Flutter <-> ESP32 BLE
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

  fbp.BluetoothDevice? device;

  fbp.BluetoothCharacteristic? notifyCharacteristic;
  fbp.BluetoothCharacteristic? writeCharacteristic;

  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<fbp.BluetoothConnectionState>?
      _connectionSubscription;

  final StreamController<double> _signalController =
      StreamController<double>.broadcast();

  final StreamController<String> _dataController =
      StreamController<String>.broadcast();

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<double> get signalStream => _signalController.stream;

  Stream<String> get dataStream => _dataController.stream;

  Stream<bool> get connectionStream =>
      _connectionController.stream;

  bool get isConnected =>
      device != null && device!.isConnected;

  // ============================================================
  // BLE SCAN
  // ============================================================

  Future<List<fbp.ScanResult>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final List<fbp.ScanResult> results = [];

    try {
      await fbp.FlutterBluePlus.stopScan();

      await fbp.FlutterBluePlus.startScan(
        timeout: timeout,
      );

      final subscription =
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

      await Future.delayed(timeout);

      await subscription.cancel();

      await fbp.FlutterBluePlus.stopScan();
    } catch (e) {
      print('GeoScan AI Scan Error: $e');
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
      await disconnect();

      device = target;

      await device!.connect(
        license: fbp.License.free,
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      _connectionController.add(true);

      _connectionSubscription =
          device!.connectionState.listen(
        (state) {
          final connected =
              state ==
                  fbp.BluetoothConnectionState.connected;

          _connectionController.add(connected);

          if (!connected) {
            notifyCharacteristic = null;
            writeCharacteristic = null;
          }
        },
      );

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
          if (characteristic.uuid == notifyUuid) {
            notifyCharacteristic =
                characteristic;
          }

          if (characteristic.uuid == writeUuid) {
            writeCharacteristic =
                characteristic;
          }
        }
      }

      if (notifyCharacteristic == null ||
          writeCharacteristic == null) {
        print(
          'GeoScan AI: BLE characteristics not found',
        );

        await disconnect();

        return false;
      }

      final notificationStarted =
          await startNotifications();

      if (!notificationStarted) {
        await disconnect();
        return false;
      }

      // طلب الحالة الحالية من ESP32
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

      await notifyCharacteristic!.setNotifyValue(true);

      _notifySubscription =
          notifyCharacteristic!.lastValueStream.listen(
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

  void _handleIncomingData(List<int> value) {
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

      // نرسل JSON كنص إلى ScanScreen
      _dataController.add(text);

      final decoded = _tryParseJson(text);

      if (decoded != null) {
        final value =
            decoded['signal'] ??
            decoded['value'] ??
            decoded['strength'] ??
            decoded['reading'];

        if (value != null) {
          final signal =
              double.tryParse(
                    value.toString(),
                  ) ??
                  0.0;

          final safeSignal =
              signal
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
      final bytes =
          utf8.encode(command);

      final withoutResponse =
          writeCharacteristic!
              .properties
              .writeWithoutResponse;

      await writeCharacteristic!.write(
        bytes,
        withoutResponse: withoutResponse,
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
  // ESP32 expects: START
  // ============================================================

  Future<bool> startScanning() async {
    return sendCommand('START');
  }

  // اسم متوافق مع ScanScreen القديمة
  Future<bool> startScan() async {
    return startScanning();
  }

  // ============================================================
  // STOP SCAN
  // ESP32 expects: STOP
  // ============================================================

  Future<bool> stopScanning() async {
    return sendCommand('STOP');
  }

  // اسم متوافق مع ScanScreen القديمة
  Future<bool> stopScan() async {
    return stopScanning();
  }

  // ============================================================
  // CALIBRATION
  // ESP32 expects: CALIBRATE
  // ============================================================

  Future<bool> calibrate() async {
    return sendCommand('CALIBRATE');
  }

  // ============================================================
  // STATUS
  // ============================================================

  Future<bool> getStatus() async {
    return sendCommand('GET_STATUS');
  }

  // ============================================================
  // SENSITIVITY
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
  //
  // Flutter Arabic -> ESP32 protocol
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
  // ============================================================
  //
  // ESP32 الحالي لا يملك أمر TARGET.
  // نحتفظ بالدالة حتى لا ينكسر أي كود قديم.
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
  // DISPOSE
  // ============================================================

  Future<void> dispose() async {
    await disconnect();

    await _signalController.close();
    await _dataController.close();
    await _connectionController.close();
  }
}
