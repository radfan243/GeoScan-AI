import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  List<ScanResult> devices = [];
  bool scanning = false;

  Future<void> startScan() async {
    setState(() {
      devices.clear();
      scanning = true;
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
      );

      final results = await FlutterBluePlus.scanResults.first;

      if (!mounted) return;

      setState(() {
        devices = results;
        scanning = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        scanning = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء البحث: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اتصال Bluetooth'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(
              Icons.bluetooth_searching,
              size: 80,
              color: Colors.cyanAccent,
            ),

            const SizedBox(height: 20),

            const Text(
              'البحث عن جهاز ESP32',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              'قم بتشغيل ESP32 ثم اضغط زر البحث.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),

            const SizedBox(height: 25),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: FilledButton.icon(
                onPressed: scanning ? null : startScan,
                icon: const Icon(Icons.search),
                label: Text(
                  scanning ? 'جاري البحث...' : 'البحث عن الأجهزة',
                ),
              ),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: devices.isEmpty
                  ? const Center(
                      child: Text(
                        'لا توجد أجهزة مكتشفة حتى الآن.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final device = devices[index].device;

                        final name = device.platformName.isEmpty
                            ? 'ESP32 غير مسمى'
                            : device.platformName;

                        return Card(
                          child: ListTile(
                            leading: const Icon(
                              Icons.bluetooth,
                              color: Colors.cyanAccent,
                            ),
                            title: Text(name),
                            subtitle: Text(
                              device.remoteId.toString(),
                            ),
                            trailing: const Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
