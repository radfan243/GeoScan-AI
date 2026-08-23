
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothService {
  BluetoothDevice? connectedDevice;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  Future<List<ScanResult>> scanForDevices({
    Duration duration = const Duration(seconds: 6),
  }) async {
    final List<ScanResult> results = [];

    await _scanSubscription?.cancel();

    final completer = Completer<List<ScanResult>>();

    _scanSubscription =
        FlutterBluePlus.scanResults.listen((scanResults) {
      results.clear();
      results.addAll(scanResults);
    });

    try {
      await FlutterBluePlus.startScan(timeout: duration);

      if (!completer.isCompleted) {
        completer.complete(results);
      }
    } catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }

    return completer.future;
  }

  Future<void> connect(BluetoothDevice device) async {
    await device.connect(
      timeout: const Duration(seconds: 10),
      autoConnect: false,
    );

    connectedDevice = device;
  }

  Future<void> disconnect() async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      connectedDevice = null;
    }
  }

  bool get isConnected => connectedDevice != null;

  Future<List<BluetoothService>> discoverServices() async {
    if (connectedDevice == null) {
      throw Exception('لا يوجد جهاز ESP32 متصل');
    }

    return await connectedDevice!.discoverServices();
  }

  Future<void> dispose() async {
    await _scanSubscription?.cancel();
    await _connectionSubscription?.cancel();
  }
}
