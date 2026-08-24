import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

class BluetoothService {
  fbp.BluetoothDevice? connectedDevice;

  StreamSubscription<List<fbp.ScanResult>>? _scanSubscription;
  StreamSubscription<fbp.BluetoothConnectionState>? _connectionSubscription;

  Future<List<fbp.ScanResult>> scanForDevices({
    Duration duration = const Duration(seconds: 6),
  }) async {
    final List<fbp.ScanResult> results = [];

    await _scanSubscription?.cancel();

    final completer = Completer<List<fbp.ScanResult>>();

    _scanSubscription =
        fbp.FlutterBluePlus.scanResults.listen((scanResults) {
      results.clear();
      results.addAll(scanResults);
    });

    try {
      await fbp.FlutterBluePlus.startScan(timeout: duration);

      await Future.delayed(duration);

      if (!completer.isCompleted) {
        completer.complete(results);
      }
    } catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    } finally {
      await fbp.FlutterBluePlus.stopScan();
    }

    return completer.future;
  }

  Future<void> connect(fbp.BluetoothDevice device) async {
    await device.connect(
      timeout: const Duration(seconds: 10),
      autoConnect: false,
    );

    connectedDevice = device;

    _connectionSubscription =
        connectedDevice?.state.listen((state) {
      // يمكن التعامل مع حالة الاتصال هنا عند الحاجة
    });
  }

  Future<void> disconnect() async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      connectedDevice = null;
    }
  }

  bool get isConnected => connectedDevice != null;

  Future<List<fbp.BluetoothService>> discoverServices() async {
    if (connectedDevice == null) {
      throw Exception('لا يوجد جهاز ESP32 متصل');
    }

    return await connectedDevice!.discoverServices();
  }

  Future<void> dispose() async {
    await _scanSubscription?.cancel();
    await _connectionSubscription?.cancel();

    _scanSubscription = null;
    _connectionSubscription = null;
  }
}
