import 'dart:math' as math;
import 'package:flutter/material.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final List<double> signalHistory = [];

  double signal = 0;
  bool scanning = false;

  void addTestSignal() {
    final random = math.Random();

    setState(() {
      signal = random.nextDouble() * 100;

      signalHistory.add(signal);

      if (signalHistory.length > 40) {
        signalHistory.removeAt(0);
      }
    });
  }

  void startTest() {
    setState(() {
      scanning = true;
    });

    Future.doWhile(() async {
      if (!mounted || !scanning) {
        return false;
      }

      addTestSignal();

      await Future.delayed(
        const Duration(milliseconds: 200),
      );

      return mounted && scanning;
    });
  }

  void stopTest() {
    setState(() {
      scanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المسح المباشر'),
        centerTitle: true,
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [

              const Text(
                'LIVE SCAN',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'إشارة المستشعر',
                style: TextStyle(
                  color: Colors.white70,
                ),
              ),

              const SizedBox(height: 25),

              // نسبة الإشارة
              Text(
                '${signal.toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: Colors.cyanAccent,
                ),
              ),

              const SizedBox(height: 15),

              LinearProgressIndicator(
                value: signal / 100,
                minHeight: 16,
                borderRadius: BorderRadius.circular(10),
              ),

              const SizedBox(height: 30),

              // الرسم البياني
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white24,
                    ),
                    color: Colors.white.withOpacity(0.03),
                  ),
                  child: CustomPaint(
                    painter: SignalPainter(
                      values: signalHistory,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // الحالة
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    scanning
                        ? Icons.circle
                        : Icons.circle_outlined,
                    size: 14,
                    color: scanning
                        ? Colors.greenAccent
                        : Colors.white38,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    scanning
                        ? 'المسح يعمل'
                        : 'المسح متوقف',
                  ),
                ],
              ),

              const SizedBox(height: 15),

              // الأزرار
              Row(
                children: [

                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          scanning ? null : startTest,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('بدء'),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          scanning ? stopTest : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('إيقاف'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 15),

              const Text(
                'تنبيه: البيانات الحالية تجريبية فقط. سيتم استبدالها ببيانات ESP32 الحقيقية بعد اكتمال دائرة PI.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SignalPainter extends CustomPainter {
  final List<double> values;

  SignalPainter({
    required this.values,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    if (values.length < 2) {
      return;
    }

    final paint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final path = Path();

    final maxPoints = values.length;

    for (int i = 0; i < maxPoints; i++) {
      final x = maxPoints == 1
          ? 0
          : i * size.width / (maxPoints - 1);

      final normalized =
          values[i].clamp(0, 100) / 100;

      final y =
          size.height - (normalized * size.height);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(
    covariant SignalPainter oldDelegate,
  ) {
    return oldDelegate.values != values;
  }
}
