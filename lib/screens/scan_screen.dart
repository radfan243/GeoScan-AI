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

  final List<String> targets = [
    'ذهب',
    'معدن',
    'فضة',
    'نحاس',
    'ألماس',
    'ماء',
  ];

  final Set<String> selectedTargets = {
    'ذهب',
    'معدن',
    'فضة',
    'نحاس',
    'ألماس',
    'ماء',
  };

  void addTestSignal() {
    final random = math.Random();

    final double newSignal =
        (signal * 0.70) + (random.nextDouble() * 100 * 0.30);

    setState(() {
      signal = newSignal.clamp(0, 100).toDouble();

      signalHistory.add(signal);

      if (signalHistory.length > 60) {
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
      const Duration(milliseconds: 350),
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

  void toggleTarget(String target) {
    setState(() {
      if (selectedTargets.contains(target)) {
        selectedTargets.remove(target);
      } else {
        selectedTargets.add(target);
      }
    });
  }

  void selectAllTargets() {
    setState(() {
      selectedTargets
        ..clear()
        ..addAll(targets);
    });
  }

  Color get signalColor {
    if (signal < 25) return Colors.redAccent;
    if (signal < 50) return Colors.deepOrangeAccent;
    if (signal < 75) return Colors.amberAccent;
    return Colors.greenAccent;
  }

  String get signalStatus {
    if (signal < 25) return 'إشارة ضعيفة';
    if (signal < 50) return 'إشارة متوسطة';
    if (signal < 75) return 'إشارة جيدة';
    return 'إشارة قوية';
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = signalColor;

    return Scaffold(
      backgroundColor: const Color(0xFF060B18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF060B18),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'GeoScan AI',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            children: [
              const Text(
                'المسح المباشر',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 4),

              const Text(
                'تحليل الإشارة لحظيًا',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 18),

              // مؤشر رئيسي
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF10243A),
                      Color(0xFF091221),
                    ],
                  ),
                  border: Border.all(
                    color: color.withOpacity(0.45),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      signal.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 58,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const Text(
                      'SIGNAL',
                      style: TextStyle(
                        color: Colors.white38,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      signalStatus,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // عداد الدرجات
              Container(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.025),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 65,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(
                          30,
                          (index) {
                            final level = ((index + 1) / 30) * 100;
                            final active = signal >= level;

                            Color barColor;

                            if (index < 8) {
                              barColor = Colors.redAccent;
                            } else if (index < 15) {
                              barColor = Colors.deepOrangeAccent;
                            } else if (index < 22) {
                              barColor = Colors.amberAccent;
                            } else {
                              barColor = Colors.greenAccent;
                            }

                            return Expanded(
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 250),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1.5,
                                ),
                                height: 18 + (index * 1.5),
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(4),
                                  color: active
                                      ? barColor
                                      : Colors.white.withOpacity(0.07),
                                  boxShadow: active
                                      ? [
                                          BoxShadow(
                                            color:
                                                barColor.withOpacity(0.25),
                                            blurRadius: 6,
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

                    const SizedBox(height: 5),

                    const Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ضعيفة',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          'متوسطة',
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          'قوية',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // اختيار نوع الهدف
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1424),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🎯 ماذا تريد أن تبحث عنه؟',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'يمكنك اختيار هدف واحد أو عدة أهداف',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // زر الكل
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: selectAllTargets,
                        icon: const Icon(
                          Icons.select_all,
                          color: Colors.cyanAccent,
                        ),
                        label: const Text(
                          'تحديد الكل',
                          style: TextStyle(
                            color: Colors.cyanAccent,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: targets.map((target) {
                        final selected =
                            selectedTargets.contains(target);

                        return FilterChip(
                          selected: selected,
                          label: Text(target),
                          onSelected: (_) {
                            toggleTarget(target);
                          },
                          selectedColor:
                              Colors.cyanAccent.withOpacity(0.18),
                          checkmarkColor: Colors.cyanAccent,
                          labelStyle: TextStyle(
                            color: selected
                                ? Colors.cyanAccent
                                : Colors.white70,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          backgroundColor:
                              Colors.white.withOpacity(0.05),
                          side: BorderSide(
                            color: selected
                                ? Colors.cyanAccent
                                : Colors.white12,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // الرسم البياني
              Container(
                width: double.infinity,
                height: 270,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1424),
                  borderRadius: BorderRadius.circular(22),
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
                        ),
                        SizedBox(width: 8),
                        Text(
                          'حركة الإشارة',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    Expanded(
                      child: CustomPaint(
                        painter: SignalPainter(
                          values: signalHistory,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // تحليل الهدف
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1424),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🔬 تحليل الهدف',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      selectedTargets.isEmpty
                          ? 'لم يتم اختيار هدف'
                          : 'الأهداف المحددة: ${selectedTargets.join('، ')}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(height: 14),

                    if (selectedTargets.isNotEmpty)
                      ...selectedTargets.map(
                        (target) {
                          final score = targetScore(target);

                          return Padding(
                            padding:
                                const EdgeInsets.only(bottom: 12),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      target,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '${score.toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        color: scoreColor(score),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 6),

                                ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: score / 100,
                                    minHeight: 10,
                                    backgroundColor:
                                        Colors.white.withOpacity(0.08),
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
                                      scoreColor(score),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                    if (selectedTargets.isEmpty)
                      const Center(
                        child: Text(
                          'اختر هدفًا للبدء بالتحليل',
                          style: TextStyle(
                            color: Colors.white38,
                          ),
                        ),
                      ),

                    const SizedBox(height: 5),

                    const Text(
                      '⚠️ التحليل الحالي تجريبي. سيتم ربطه بالبيانات الحقيقية للحساس بعد توصيل ESP32 وإجراء الاختبارات.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white30,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // أزرار التشغيل
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          scanning ? null : startTest,
                      icon: const Icon(
                        Icons.play_arrow,
                      ),
                      label: const Text(
                        'بدء المسح',
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          scanning ? stopTest : null,
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

              const SizedBox(height: 10),

              Row(
                mainAxisAlignment:
                    MainAxisAlignment.center,
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
                        ? 'المسح يعمل'
                        : 'الجهاز جاهز',
                    style: const TextStyle(
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  double targetScore(String target) {
    if (signal <= 0) return 0;

    // أرقام تجريبية فقط.
    // لاحقًا سيتم استبدالها بخوارزمية تعتمد على
    // البيانات الحقيقية القادمة من ESP32.
    final factors = {
      'ذهب': 0.92,
      'معدن': 0.78,
      'فضة': 0.84,
      'نحاس': 0.72,
      'ألماس': 0.30,
      'ماء': 0.58,
    };

    final factor = factors[target] ?? 0.5;

    final variation =
        math.sin(signal / 12 + target.length) * 8;

    return (signal * factor + variation)
        .clamp(0, 100)
        .toDouble();
  }

  Color scoreColor(double value) {
    if (value < 25) return Colors.redAccent;
    if (value < 50) return Colors.deepOrangeAccent;
    if (value < 75) return Colors.amberAccent;
    return Colors.greenAccent;
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

    // شبكة خلفية
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 1;

    for (int i = 1; i < 5; i++) {
      final y = size.height * i / 5;

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    // الخط الرئيسي
    final paint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();

    final count = values.length;

    for (int i = 0; i < count; i++) {
      final x = i * size.width / (count - 1);

      final normalized =
          (values[i].clamp(0.0, 100.0) / 100.0)
              .toDouble();

      final y =
          size.height - normalized * size.height;

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
    return true;
  }
}
