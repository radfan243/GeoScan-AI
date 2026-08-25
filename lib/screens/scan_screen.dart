import 'dart:async';
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
  Timer? _scanTimer;

  void addTestSignal() {
    final random = math.Random();

    // محاكاة قراءة مستشعر مؤقتة.
    // سيتم استبدالها لاحقًا ببيانات ESP32 الحقيقية.
    final double target = random.nextDouble() * 100;

    setState(() {
      signal = target;

      signalHistory.add(signal);

      if (signalHistory.length > 50) {
        signalHistory.removeAt(0);
      }
    });
  }

  void startTest() {
    if (scanning) return;

    setState(() {
      scanning = true;
    });

    _scanTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) {
        if (mounted && scanning) {
          addTestSignal();
        }
      },
    );
  }

  void stopTest() {
    _scanTimer?.cancel();
    _scanTimer = null;

    if (!mounted) return;

    setState(() {
      scanning = false;
    });
  }

  Color get signalColor {
    if (signal < 35) {
      return Colors.redAccent;
    }

    if (signal < 70) {
      return Colors.orangeAccent;
    }

    return Colors.greenAccent;
  }

  String get signalStatus {
    if (signal < 10) {
      return 'لا توجد إشارة';
    }

    if (signal < 35) {
      return 'إشارة ضعيفة';
    }

    if (signal < 70) {
      return 'إشارة متوسطة';
    }

    return 'إشارة قوية';
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color activeColor = signalColor;

    return Scaffold(
      backgroundColor: const Color(0xFF070D1D),

      appBar: AppBar(
        backgroundColor: const Color(0xFF070D1D),
        elevation: 0,
        title: const Text(
          'GeoScan AI',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),

          child: Column(
            children: [
              const Text(
                'LIVE SCAN',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                  color: Colors.white70,
                ),
              ),

              const SizedBox(height: 5),

              const Text(
                'تحليل الإشارة لحظيًا',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 15),

              // بطاقة القراءة الرئيسية
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),

                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),

                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF10233A),
                      const Color(0xFF091221),
                    ],
                  ),

                  border: Border.all(
                    color: activeColor.withOpacity(0.35),
                    width: 1.5,
                  ),

                  boxShadow: [
                    BoxShadow(
                      color: activeColor.withOpacity(0.08),
                      blurRadius: 25,
                      spreadRadius: 2,
                    ),
                  ],
                ),

                child: Column(
                  children: [
                    Text(
                      signal.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 54,
                        fontWeight: FontWeight.bold,
                        color: activeColor,
                      ),
                    ),

                    const Text(
                      'SIGNAL',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 3,
                        color: Colors.white54,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      signalStatus,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: activeColor,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 15),

              // عداد بشكل درجات
              SizedBox(
                height: 55,

                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,

                  children: List.generate(
                    20,
                    (index) {
                      final double level = (index + 1) * 5;

                      final bool active = signal >= level;

                      Color color;

                      if (index < 7) {
                        color = Colors.redAccent;
                      } else if (index < 14) {
                        color = Colors.orangeAccent;
                      } else {
                        color = Colors.greenAccent;
                      }

                      return Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),

                          margin: const EdgeInsets.symmetric(
                            horizontal: 2,
                          ),

                          height: 15 + (index * 2.0),

                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),

                            color: active
                                ? color
                                : Colors.white.withOpacity(0.08),

                            boxShadow: active
                                ? [
                                    BoxShadow(
                                      color: color.withOpacity(0.25),
                                      blurRadius: 7,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 6),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,

                children: const [
                  Text(
                    'ضعيف',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 11,
                    ),
                  ),

                  Text(
                    'متوسط',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 11,
                    ),
                  ),

                  Text(
                    'قوي',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 15),

              // الرسم البياني
              Expanded(
                child: Container(
                  width: double.infinity,

                  padding: const EdgeInsets.all(12),

                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),

                    color: Colors.white.withOpacity(0.035),

                    border: Border.all(
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.show_chart,
                            color: Colors.cyanAccent,
                            size: 20,
                          ),

                          SizedBox(width: 7),

                          Text(
                            'حركة الإشارة',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      Expanded(
                        child: CustomPaint(
                          painter: SignalPainter(
                            values: signalHistory,
                            lineColor: activeColor,
                          ),

                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // حالة الجهاز
              Row(
                mainAxisAlignment: MainAxisAlignment.center,

                children: [
                  Container(
                    width: 10,
                    height: 10,

                    decoration: BoxDecoration(
                      shape: BoxShape.circle,

                      color: scanning
                          ? Colors.greenAccent
                          : Colors.white30,
                    ),
                  ),

                  const SizedBox(width: 8),

                  Text(
                    scanning
                        ? 'اختبار الإشارة يعمل'
                        : 'جاهز للمسح',

                    style: const TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: scanning ? null : startTest,

                      icon: const Icon(
                        Icons.play_arrow,
                      ),

                      label: const Text(
                        'بدء الاختبار',
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: scanning ? stopTest : null,

                      icon: const Icon(
                        Icons.stop,
                      ),

                      label: const Text(
                        'إيقاف',
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              const Text(
                'القراءة الحالية تجريبية. سيتم استبدالها ببيانات ESP32 الحقيقية لاحقًا.',
                textAlign: TextAlign.center,

                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white30,
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
  final Color lineColor;

  SignalPainter({
    required this.values,
    required this.lineColor,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    if (values.length < 2) {
      return;
    }

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 1;

    // خطوط الشبكة
    for (int i = 1; i < 5; i++) {
      final double y = size.height * i / 5;

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();

    final int count = values.length;

    for (int i = 0; i < count; i++) {
      final double x = count == 1
          ? 0
          : i * size.width / (count - 1);

      final double normalized =
          (values[i].clamp(0.0, 100.0) / 100.0).toDouble();

      final double y =
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
    return oldDelegate.values != values ||
        oldDelegate.lineColor != lineColor;
  }
}
