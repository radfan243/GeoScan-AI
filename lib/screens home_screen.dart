import 'package:flutter/material.dart';
import 'bluetooth_screen.dart';
import 'scan_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'GeoScan AI',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              const SizedBox(height: 25),

              // شعار التطبيق
              Container(
                height: 130,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF123B4A),
                      Color(0xFF0D1728),
                    ],
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.radar,
                    size: 75,
                    color: Colors.cyanAccent,
                  ),
                ),
              ),

              const SizedBox(height: 25),

              const Text(
                'GeoScan AI',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'نظام تحليل الإشارات الأرضية',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  color: Colors.white70,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'تطبيق يعمل بدون إنترنت ويتصل بجهاز ESP32 الحقيقي عبر Bluetooth.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white54,
                ),
              ),

              const SizedBox(height: 35),

              // الاتصال
              SizedBox(
                height: 58,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BluetoothScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.bluetooth),
                  label: const Text(
                    'الاتصال بجهاز ESP32',
                    style: TextStyle(fontSize: 17),
                  ),
                ),
              ),

              const SizedBox(height: 15),

              // المسح
              SizedBox(
                height: 58,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ScanScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.radar),
                  label: const Text(
                    'فتح شاشة المسح',
                    style: TextStyle(fontSize: 17),
                  ),
                ),
              ),

              const SizedBox(height: 35),

              // معلومات المشروع
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: const [
                      Icon(
                        Icons.info_outline,
                        size: 35,
                        color: Colors.cyanAccent,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'حالة المشروع',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'V1 — واجهة أولية جاهزة للربط مع جهاز PI وESP32.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 25),

              const Text(
                'ملاحظة: التطبيق لا يستخدم مستشعر الهاتف للكشف عن الذهب. البيانات ستأتي من جهاز الاستشعار الخارجي الحقيقي.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white38,
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
