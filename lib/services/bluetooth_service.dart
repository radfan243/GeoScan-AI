import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

class BluetoothService {
  fbp.BluetoothDevice? connectedDevice;

  StreamSubscription<List<fbp.ScanResult>>? _scanSubscription;
  StreamSubscription<fbp.BluetoothDeviceState>? _connectionSubscription;

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

      // Wait for the timeout to finish so results can accumulate.
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

    // Optionally track connection state
    _connectionSubscription =
        connectedDevice?.state.listen((state) {
      // handle state changes if needed
    });
  }

  Future<void> disconnect() async {
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

    // discoverServices() returns Future<List<fbp.BluetoothService>>
    final services = await connectedDevice!.discoverServices();
    return services;
  }

  Future<void> dispose() async {
    await _scanSubscription?.cancel();
    await _connection_subscription?.cancel();
  }
}
