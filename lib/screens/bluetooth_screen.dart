import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothService {
  BluetoothDevice? connectedDevice;

  StreamSubscription<List<ScanResult>>? scanSubscription;

  Future<List<ScanResult>> scanForDevices({
    Duration duration = const Duration(seconds: 6),
  }) async {
    final List<ScanResult> results = [];

    await scanSubscription?.cancel();

    scanSubscription =
        FlutterBluePlus.scanResults.listen((scanResults) {
      results.clear();
      results.addAll(scanResults);
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: duration,
      );

      await Future.delayed(duration);

      return results;
    } finally {
      await FlutterBluePlus.stopScan();
    }
  }

  Future<void> connect(
    BluetoothDevice device,
  ) async {
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

  bool get isConnected {
    return connectedDevice != null;
  }

  Future<List<BluetoothService>>
      discoverServices() async {
    if (connectedDevice == null) {
      throw Exception(
        'لا يوجد جهاز ESP32 متصل',
      );
    }

    final services =
        await connectedDevice!.discoverServices();

    return services;
  }

  Future<void> dispose() async {
    await scanSubscription?.cancel();
  }
}
