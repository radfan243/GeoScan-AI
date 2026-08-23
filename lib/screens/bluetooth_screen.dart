import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import '../services/bluetooth_service.dart';

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  final BluetoothService _btService = BluetoothService();
  List<fbp.ScanResult> _devices = [];
  bool _scanning = false;

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
    });

    try {
      final results = await _btService.scanForDevices();
      setState(() {
        _devices = results;
      });
    } catch (e) {
      // ignore errors for now; keep UI minimal
      debugPrint('Scan error: $e');
    } finally {
      setState(() {
        _scanning = false;
      });
    }
  }

  @override
  void dispose() {
    _btService.dispose();
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
                label: Text(_scanning ? 'Scanning...' : 'Scan for devices'),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final r = _devices[index];
                    final name = r.device.name.isNotEmpty ? r.device.name : r.device.id.id;
                    return ListTile(
                      title: Text(name),
                      subtitle: Text(r.device.id.id),
                      trailing: FilledButton(
                        onPressed: () async {
                          try {
                            await _btService.connect(r.device);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Connected')),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Connect failed: $e')),
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
