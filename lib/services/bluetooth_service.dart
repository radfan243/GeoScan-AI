import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();

  factory BluetoothService() => _instance;

  BluetoothService._internal();

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
  StreamSubscription<fbp.BluetoothConnectionState>? _connectionSubscription;

  final StreamController<double> _signalController =
      StreamController<double>.broadcast();
  final StreamController<String> _dataController =
      StreamController<String>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<double> get signalStream => _signalController.stream;
  Stream<String> get dataStream => _dataController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  bool get isConnected => device != null && device!.isConnected;

  Future<List<fbp.ScanResult>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final List<fbp.ScanResult> results = <fbp.ScanResult>[];
    StreamSubscription<List<fbp.ScanResult>>? subscription;

    try {
      await fbp.FlutterBluePlus.stopScan();
      subscription = fbp.FlutterBluePlus.scanResults.listen((scanResults) {
        for (final result in scanResults) {
          final exists = results.any(
            (item) => item.device.remoteId == result.device.remoteId,
          );
          if (!exists) results.add(result);
        }
      });

      await fbp.FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: false,
      );

      await Future<void>.delayed(timeout + const Duration(milliseconds: 250));
      await fbp.FlutterBluePlus.stopScan();
      await subscription.cancel();
      subscription = null;
    } catch (e) {
      print('GeoScan AI Scan Error: $e');
      try {
        await fbp.FlutterBluePlus.stopScan();
      } catch (_) {}
      await subscription?.cancel();
    }

    return results;
  }

  Future<bool> connect(fbp.BluetoothDevice target) async {
    try {
      if (device != null && device!.remoteId != target.remoteId) {
        await disconnect();
      }

      device = target;

      if (!device!.isConnected) {
        await device!.connect(
          license: fbp.License.free,
          timeout: const Duration(seconds: 15),
          autoConnect: false,
        );
      }

      await _connectionSubscription?.cancel();
      _connectionSubscription = device!.connectionState.listen((state) {
        final connected = state == fbp.BluetoothConnectionState.connected;
        _connectionController.add(connected);
        if (!connected) {
          notifyCharacteristic = null;
          writeCharacteristic = null;
        }
      });

      final services = await device!.discoverServices();
      notifyCharacteristic = null;
      writeCharacteristic = null;

      for (final service in services) {
        if (service.uuid != serviceUuid) continue;
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == notifyUuid) {
            notifyCharacteristic = characteristic;
          } else if (characteristic.uuid == writeUuid) {
            writeCharacteristic = characteristic;
          }
        }
      }

      if (notifyCharacteristic == null || writeCharacteristic == null) {
        print('GeoScan AI: required BLE characteristics not found');
        await disconnect();
        return false;
      }

      if (!await startNotifications()) {
        await disconnect();
        return false;
      }

      _connectionController.add(true);
      await getStatus();
      return true;
    } catch (e) {
      print('GeoScan AI Connection Error: $e');
      _connectionController.add(false);
      try {
        await device?.disconnect();
      } catch (_) {}
      device = null;
      return false;
    }
  }

  Future<bool> startNotifications() async {
    final characteristic = notifyCharacteristic;
    if (characteristic == null) return false;

    try {
      await _notifySubscription?.cancel();
      await characteristic.setNotifyValue(true);
      _notifySubscription = characteristic.lastValueStream.listen(
        _handleIncomingData,
        onError: (error) => print('GeoScan AI Notification Error: $error'),
      );
      return true;
    } catch (e) {
      print('GeoScan AI Notification Start Error: $e');
      return false;
    }
  }

  void _handleIncomingData(List<int> value) {
    if (value.isEmpty) return;

    try {
      final text = utf8.decode(value, allowMalformed: true).trim();
      if (text.isEmpty) return;

      print('GeoScan AI <- ESP32: $text');
      _dataController.add(text);

      final decoded = _tryParseJson(text);
      final incomingSignal = decoded?['signal'] ??
          decoded?['value'] ??
          decoded?['strength'] ??
          decoded?['reading'];

      if (incomingSignal != null) {
        final parsed = double.tryParse(incomingSignal.toString()) ?? 0.0;
        _signalController.add(parsed.clamp(0.0, 100.0).toDouble());
      }
    } catch (e) {
      print('GeoScan AI Data Error: $e');
    }
  }

  Map<String, dynamic>? _tryParseJson(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  Future<bool> sendCommand(String command) async {
    final characteristic = writeCharacteristic;
    if (!isConnected || characteristic == null) {
      print('GeoScan AI: Write characteristic unavailable');
      return false;
    }

    try {
      final bytes = utf8.encode(command);
      await characteristic.write(
        bytes,
        withoutResponse: characteristic.properties.writeWithoutResponse,
      );
      print('GeoScan AI -> ESP32: $command');
      return true;
    } catch (e) {
      print('GeoScan AI Write Error: $e');
      return false;
    }
  }

  Future<bool> startScanning() => sendCommand('START');
  Future<bool> startScan() => startScanning();
  Future<bool> stopScanning() => sendCommand('STOP');
  Future<bool> stopScan() => stopScanning();
  Future<bool> calibrate() => sendCommand('CALIBRATE');
  Future<bool> getStatus() => sendCommand('GET_STATUS');

  Future<bool> setSensitivity(double value) {
    final safe = value.clamp(0.0, 100.0).toDouble();
    return sendCommand('SENSITIVITY:${safe.toStringAsFixed(0)}');
  }

  Future<bool> setFilter(String value) {
    final String filter;
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
    return sendCommand('FILTER:$filter');
  }

  Future<bool> setAudio(bool enabled) =>
      sendCommand(enabled ? 'AUDIO:ON' : 'AUDIO:OFF');

  Future<bool> setVibration(bool enabled) =>
      sendCommand(enabled ? 'VIBRATION:ON' : 'VIBRATION:OFF');

  Future<bool> setTarget(String target) {
    final cleaned = target.trim();
    if (cleaned.isEmpty || cleaned.length > 24) return Future<bool>.value(false);
    return sendCommand('TARGET:$cleaned');
  }

  String get deviceName {
    final current = device;
    if (current == null) return 'غير متصل';
    final name = current.platformName;
    return name.isEmpty ? 'GeoScan-AI' : name;
  }

  String get deviceId => device?.remoteId.str ?? '';

  Future<void> disconnect() async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    try {
      await notifyCharacteristic?.setNotifyValue(false);
    } catch (_) {}

    try {
      await device?.disconnect();
    } catch (_) {}

    notifyCharacteristic = null;
    writeCharacteristic = null;
    device = null;
    _connectionController.add(false);
  }

  Future<void> dispose() => disconnect();
}
