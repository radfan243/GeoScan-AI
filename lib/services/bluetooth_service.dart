import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

class BluetoothService {
  // ============================================================
  // GeoScan AI - Bluetooth Service
  // الهاتف <-> ESP32
  // ============================================================

  static const String serviceUuid =
      '12345678-1234-1234-1234-1234567890ab';

  static const String notifyCharacteristicUuid =
      '12345678-1234-1234-1234-1234567890ac';

  static const String writeCharacteristicUuid =
      '12345678-1234-1234-1234-1234567890ad';

  fbp.BluetoothDevice? connectedDevice;

  fbp.BluetoothCharacteristic? _notifyCharacteristic;
  fbp.BluetoothCharacteristic? _writeCharacteristic;

  StreamSubscription<List<fbp.ScanResult>>? _scanSubscription;
  StreamSubscription<fbp.BluetoothConnectionState>?
      _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;

  // ============================================================
  // حالة الاتصال
  // ============================================================

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<bool> get connectionStream =>
      _connectionController.stream;

  bool get isConnected =>
      connectedDevice != null &&
      _notifyCharacteristic != null &&
      _writeCharacteristic != null;

  // ============================================================
  // بيانات ESP32
  // ============================================================

  final StreamController<Map<String, dynamic>> _dataController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get dataStream =>
      _dataController.stream;

  // ============================================================
  // البحث عن أجهزة Bluetooth
  // ============================================================

  Future<List<fbp.ScanResult>> scanForDevices({
    Duration duration = const Duration(seconds: 6),
  }) async {
    final Map<String, fbp.ScanResult> devices = {};

    await _scanSubscription?.cancel();

    _scanSubscription =
        fbp.FlutterBluePlus.scanResults.listen(
      (results) {
        for (final result in results) {
          final id = result.device.remoteId.str;

          devices[id] = result;
        }
      },
    );

    try {
      await fbp.FlutterBluePlus.startScan(
        timeout: duration,
      );

      await Future.delayed(duration);
    } finally {
      await fbp.FlutterBluePlus.stopScan();

      await _scanSubscription?.cancel();

      _scanSubscription = null;
    }

    return devices.values.toList();
  }

  // ============================================================
  // الاتصال بـ ESP32
  // ============================================================

  Future<void> connect(
    fbp.BluetoothDevice device,
  ) async {
    await disconnect();

    await device.connect(
      timeout: const Duration(seconds: 10),
      autoConnect: false,
    );

    connectedDevice = device;

    _connectionSubscription =
        device.connectionState.listen(
      (state) async {
        final connected =
            state == fbp.BluetoothConnectionState.connected;

        _connectionController.add(connected);

        if (!connected) {
          _notifyCharacteristic = null;
          _writeCharacteristic = null;
        }
      },
    );

    // ==========================================================
    // اكتشاف الخدمات
    // ==========================================================

    final services =
        await device.discoverServices();

    fbp.BluetoothCharacteristic? notifyCharacteristic;
    fbp.BluetoothCharacteristic? writeCharacteristic;

    for (final service in services) {
      final serviceId =
          service.uuid.toString().toLowerCase();

      if (serviceId != serviceUuid.toLowerCase()) {
        continue;
      }

      for (final characteristic
          in service.characteristics) {
        final id =
            characteristic.uuid.toString().toLowerCase();

        if (
          id ==
          notifyCharacteristicUuid.toLowerCase()
        ) {
          notifyCharacteristic =
              characteristic;
        }

        if (
          id ==
          writeCharacteristicUuid.toLowerCase()
        ) {
          writeCharacteristic =
              characteristic;
        }
      }
    }

    if (notifyCharacteristic == null) {
      throw Exception(
        'لم يتم العثور على Characteristic استقبال البيانات من ESP32',
      );
    }

    if (writeCharacteristic == null) {
      throw Exception(
        'لم يتم العثور على Characteristic إرسال الأوامر إلى ESP32',
      );
    }

    _notifyCharacteristic =
        notifyCharacteristic;

    _writeCharacteristic =
        writeCharacteristic;

    // ==========================================================
    // تفعيل استقبال البيانات
    // ==========================================================

    await _notifyCharacteristic!.setNotifyValue(true);

    await _notifySubscription?.cancel();

    _notifySubscription =
        _notifyCharacteristic!.lastValueStream.listen(
      (value) {
        _handleIncomingData(value);
      },
    );

    _connectionController.add(true);
  }

  // ============================================================
  // استقبال البيانات من ESP32
  // ============================================================

  void _handleIncomingData(
    List<int> bytes,
  ) {
    if (bytes.isEmpty) {
      return;
    }

    try {
      final text =
          utf8.decode(bytes).trim();

      if (text.isEmpty) {
        return;
      }

      final decoded =
          jsonDecode(text);

      if (decoded is Map<String, dynamic>) {
        _dataController.add(decoded);
      }
    } catch (e) {
      // إذا وصلت بيانات غير JSON نتجاهلها
      // حتى لا يتوقف التطبيق.
    }
  }

  // ============================================================
  // إرسال أمر إلى ESP32
  // ============================================================

  Future<void> sendCommand(
    String command,
  ) async {
    if (_writeCharacteristic == null) {
      throw Exception(
        'ESP32 غير متصل أو لم يتم اكتشاف قناة الأوامر',
      );
    }

    await _writeCharacteristic!.write(
      utf8.encode(command),
      withoutResponse: true,
    );
  }

  // ============================================================
  // أوامر GeoScan AI
  // ============================================================

  Future<void> startScan() async {
    await sendCommand('START');
  }

  Future<void> stopScan() async {
    await sendCommand('STOP');
  }

  Future<void> calibrate() async {
    await sendCommand('CALIBRATE');
  }

  Future<void> getStatus() async {
    await sendCommand('GET_STATUS');
  }

  Future<void> setSensitivity(
    double value,
  ) async {
    final sensitivity =
        value.clamp(0, 100).toStringAsFixed(0);

    await sendCommand(
      'SENSITIVITY:$sensitivity',
    );
  }

  Future<void> setFilter(
    String filter,
  ) async {
    await sendCommand(
      'FILTER:$filter',
    );
  }

  Future<void> setAudio(
    bool enabled,
  ) async {
    await sendCommand(
      enabled
          ? 'AUDIO:ON'
          : 'AUDIO:OFF',
    );
  }

  Future<void> setVibration(
    bool enabled,
  ) async {
    await sendCommand(
      enabled
          ? 'VIBRATION:ON'
          : 'VIBRATION:OFF',
    );
  }

  // ============================================================
  // فصل الاتصال
  // ============================================================

  Future<void> disconnect() async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;

    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    if (connectedDevice != null) {
      try {
        await connectedDevice!.disconnect();
      } catch (_) {}
    }

    connectedDevice = null;

    _notifyCharacteristic = null;
    _writeCharacteristic = null;

    _connectionController.add(false);
  }

  // ============================================================
  // تنظيف الموارد
  // ============================================================

  Future<void> dispose() async {
    await _scanSubscription?.cancel();
    await _notifySubscription?.cancel();
    await _connectionSubscription?.cancel();

    await _connectionController.close();
    await _dataController.close();
  }
}
