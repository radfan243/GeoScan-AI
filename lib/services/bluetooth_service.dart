import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

class BluetoothService {
  // ============================================================
  // GeoScan AI - Bluetooth Service
  // Flutter <-> ESP32
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
  // Bluetooth state
  // ============================================================

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

  Stream<double> get signalStream =>
      _signalController.stream;

  Stream<String> get dataStream =>
      _dataController.stream;

  Stream<bool> get connectionStream =>
      _connectionController.stream;

  bool get isConnected =>
      device != null && device!.isConnected;

  // ============================================================
  // SCAN
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

      await for (final scanResults
          in fbp.FlutterBluePlus.scanResults) {
        for (final result in scanResults) {
          final alreadyExists = results.any(
            (item) =>
                item.device.remoteId ==
                result.device.remoteId,
          );

          if (!alreadyExists) {
            results.add(result);
          }
        }
      }
    } catch (e) {
      print(
        'GeoScan AI - Scan Error: $e',
      );
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

      // FlutterBluePlus 2.x
      // يحتاج license عند connect.
      //
      // نستخدم License.free للاستخدام الشخصي/التعليمي.
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

      final discovered =
          await discoverServices();

      if (!discovered) {
        await disconnect();
        return false;
      }

      final notifications =
          await startNotifications();

      if (!notifications) {
        await disconnect();
        return false;
      }

      return true;
    } catch (e) {
      print(
        'GeoScan AI - Connection Error: $e',
      );

      _connectionController.add(false);

      device = null;

      return false;
    }
  }

  // ============================================================
  // DISCOVER SERVICES
  // ============================================================

  Future<bool> discoverServices() async {
    if (device == null) {
      return false;
    }

    try {
      final services =
          await device!.discoverServices();

      for (final service in services) {
        if (service.uuid == serviceUuid) {
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
      }

      if (notifyCharacteristic == null) {
        print(
          'GeoScan AI: Notify characteristic not found',
        );
      }

      if (writeCharacteristic == null) {
        print(
          'GeoScan AI: Write characteristic not found',
        );
      }

      return notifyCharacteristic != null &&
          writeCharacteristic != null;
    } catch (e) {
      print(
        'GeoScan AI - Service Discovery Error: $e',
      );

      return false;
    }
  }

  // ============================================================
  // ENABLE NOTIFICATIONS
  // ============================================================

  Future<bool> startNotifications() async {
    if (notifyCharacteristic == null) {
      return false;
    }

    try {
      await _notifySubscription?.cancel();

      await notifyCharacteristic!.setNotifyValue(
        true,
      );

      _notifySubscription =
          notifyCharacteristic!.lastValueStream.listen(
        (value) {
          _handleIncomingData(value);
        },
        onError: (error) {
          print(
            'GeoScan AI - Notification Error: $error',
          );
        },
      );

      return true;
    } catch (e) {
      print(
        'GeoScan AI - Start Notification Error: $e',
      );

      return false;
    }
  }

  // ============================================================
  // HANDLE ESP32 DATA
  // ============================================================

  void _handleIncomingData(List<int> value) {
    if (value.isEmpty) {
      return;
    }

    try {
      final text =
          utf8.decode(
            value,
            allowMalformed: true,
          ).trim();

      if (text.isEmpty) {
        return;
      }

      print(
        'GeoScan AI <- ESP32: $text',
      );

      // إرسال JSON الكامل إلى ScanScreen
      _dataController.add(text);

      final signal =
          _extractSignal(text);

      if (signal != null) {
        final normalized =
            signal.clamp(0.0, 100.0);

        _signalController.add(
          normalized,
        );
      }
    } catch (e) {
      print(
        'GeoScan AI - Data Parsing Error: $e',
      );
    }
  }

  // ============================================================
  // EXTRACT SIGNAL
  // ============================================================

  double? _extractSignal(String data) {
    try {
      final jsonData =
          _tryParseJson(data);

      if (jsonData != null) {
        final possibleValues = [
          jsonData['signal'],
          jsonData['value'],
          jsonData['strength'],
          jsonData['reading'],
        ];

        for (final value in possibleValues) {
          final number =
              double.tryParse(
            value.toString(),
          );

          if (number != null) {
            return number;
          }
        }
      }

      final match = RegExp(
        r'[-+]?\d*\.?\d+',
      ).firstMatch(data);

      if (match != null) {
        return double.tryParse(
          match.group(0)!,
        );
      }
    } catch (e) {
      print(
        'GeoScan AI - Signal Extraction Error: $e',
      );
    }

    return null;
  }

  // ============================================================
  // JSON PARSER
  // ============================================================

  Map<String, dynamic>? _tryParseJson(
    String data,
  ) {
    try {
      final decoded =
          jsonDecode(data);

      if (decoded
          is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // البيانات ليست JSON
    }

    return null;
  }

  // ============================================================
  // SEND COMMAND
  // ============================================================

  Future<bool> sendCommand(
    String command,
  ) async {
    if (writeCharacteristic == null) {
      print(
        'GeoScan AI: Write characteristic unavailable',
      );

      return false;
    }

    try {
      final bytes =
          utf8.encode(command);

      await writeCharacteristic!.write(
        bytes,
        withoutResponse:
            writeCharacteristic!
                .properties
                .writeWithoutResponse,
      );

      print(
        'GeoScan AI -> ESP32: $command',
      );

      return true;
    } catch (e) {
      print(
        'GeoScan AI - Write Error: $e',
      );

      return false;
    }
  }

  // ============================================================
  // SCAN CONTROL
  // ============================================================

  Future<bool> startScanning() async {
    return await sendCommand(
      'START_SCAN',
    );
  }

  Future<bool> stopScanning() async {
    return await sendCommand(
      'STOP_SCAN',
    );
  }

  // ============================================================
  // TARGET CONTROL
  // ============================================================

  Future<bool> setTarget(
    String target,
  ) async {
    return await sendCommand(
      'TARGET:$target',
    );
  }

  // ============================================================
  // SENSITIVITY
  // ============================================================

  Future<bool> setSensitivity(
    double value,
  ) async {
    final sensitivity =
        value.clamp(
      0.0,
      100.0,
    );

    return await sendCommand(
      'SENSITIVITY:${sensitivity.toStringAsFixed(0)}',
    );
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
      return 'ESP32';
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
        'GeoScan AI - Disconnect Error: $e',
      );
    }

    notifyCharacteristic = null;
    writeCharacteristic = null;
    device = null;

    _connectionController.add(false);
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  Future<void> dispose() async {
    await disconnect();

    await _notifySubscription?.cancel();
    await _connectionSubscription?.cancel();

    await _signalController.close();
    await _dataController.close();
    await _connectionController.close();
  }
}
