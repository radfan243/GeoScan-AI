import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import '../services/bluetooth_service.dart';

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  final BluetoothService _btManager = BluetoothService();

  List<fbp.ScanResult> _devices = [];
  bool _scanning = false;

  Future<void> _scan() async {
    if (!mounted) return;

    setState(() {
      _scanning = true;
    });

    try {
      final results = await _btManager.scanForDevices();

      if (!mounted) return;

      setState(() {
        _devices = results;
      });
    } catch (e) {
      debugPrint('Scan error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل البحث عن أجهزة Bluetooth: $e'),
        ),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _scanning = false;
      });
    }
  }

  @override
  void dispose() {
    _btManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              ElevatedButton.icon(
                onPressed: _scanning ? null : _scan,
                icon: const Icon(Icons.bluetooth_searching),
                label: Text(
                  _scanning ? 'Scanning...' : 'Scan for devices',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _devices.isEmpty
                    ? const Center(
                        child: Text(
                          'لا توجد أجهزة مكتشفة.\nاضغط Scan للبحث.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: _devices.length,
                        itemBuilder: (context, index) {
                          final result = _devices[index];
                          final device = result.device;

                          final name = device.name.isNotEmpty
                              ? device.name
                              : device.id.id;

                          return ListTile(
                            leading: const Icon(Icons.bluetooth),
                            title: Text(name),
                            subtitle: Text(device.id.id),
                            trailing: FilledButton(
                              onPressed: () async {
                                try {
                                  await _btManager.connect(device);

                                  if (!mounted) return;

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Connected'),
                                    ),
                                  );
                                } catch (e) {
                                  if (!mounted) return;

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Connect failed: $e',
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: const Text('Connect'),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
