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

  Timer? _timer;
  final math.Random _random = math.Random();

  double signal = 0;
  bool scanning = false;

  double sensitivity = 75;
  double stability = 78;
  double depth = 0;

  String filter = 'متوسطة';

  final List<String> targets = [
    'ذهب',
    'نحاس',
    'فضة',
    'حديد',
    'ماء',
  ];

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void startScan() {
    if (scanning) return;

    setState(() {
      scanning = true;
    });

    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) {
        if (!mounted || !scanning) return;

        final variation = (_random.nextDouble() - 0.5) * 18;

        setState(() {
          signal = (signal + variation).clamp(0, 100).toDouble();

          if (signal < 5) {
            signal = 10 + _random.nextDouble() * 15;
          }

          signalHistory.add(signal);

          if (signalHistory.length > 50) {
            signalHistory.removeAt(0);
          }

          stability =
              (70 + _random.nextDouble() * 25).clamp(0, 100);

          depth =
              ((signal / 100) * 2.5).clamp(0.05, 2.5).toDouble();
        });
      },
    );
  }

  void stopScan() {
    _timer?.cancel();
    _timer = null;

    if (!mounted) return;

    setState(() {
      scanning = false;
    });
  }

  Color get signalColor {
    if (signal < 25) return Colors.redAccent;
    if (signal < 50) return Colors.orangeAccent;
    if (signal < 75) return Colors.amberAccent;
    return Colors.greenAccent;
  }

  String get signalText {
    if (signal < 25) return 'إشارة ضعيفة';
    if (signal < 50) return 'إشارة متوسطة';
    if (signal < 75) return 'إشارة جيدة';
    return 'إشارة قوية';
  }

  double targetScore(String target) {
    if (!scanning && signal == 0) return 0;

    final factors = {
      'ذهب': 0.92,
      'نحاس': 0.72,
      'فضة': 0.84,
      'حديد': 0.38,
      'ماء': 0.58,
    };

    final factor = factors[target] ?? 0.5;

    final variation =
        math.sin(signal / 12 + target.length) * 8;

    return (signal * factor + variation)
        .clamp(0, 100)
        .toDouble();
  }

  Color targetColor(String target) {
    switch (target) {
      case 'ذهب':
        return Colors.amberAccent;
      case 'نحاس':
        return Colors.orangeAccent;
      case 'فضة':
        return Colors.lightBlueAccent;
      case 'حديد':
        return Colors.redAccent;
      case 'ماء':
        return Colors.cyanAccent;
      default:
        return Colors.white;
    }
  }

  IconData targetIcon(String target) {
    switch (target) {
      case 'ذهب':
        return Icons.diamond;
      case 'نحاس':
        return Icons.hexagon;
      case 'فضة':
        return Icons.circle;
      case 'حديد':
        return Icons.landscape;
      case 'ماء':
        return Icons.water_drop;
      default:
        return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = signalColor;

    return Scaffold(
      backgroundColor: const Color(0xFF050B16),

      appBar: AppBar(
        backgroundColor: const Color(0xFF050B16),
        elevation: 0,

        leading: IconButton(
          icon: const Icon(
            Icons.menu,
            size: 30,
            color: Colors.white,
          ),
          onPressed: () {},
        ),

        centerTitle: true,

        title: Column(
          children: [
            const Text(
              'GeoScan AI',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              'المسح المباشر',
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ],
        ),

        actions: [
          Row(
            children: [
              const Icon(
                Icons.bluetooth,
                color: Colors.cyanAccent,
                size: 28,
              ),
              const SizedBox(width: 3),
              Text(
                'متصل',
                style: TextStyle(
                  color: scanning
                      ? Colors.greenAccent
                      : Colors.greenAccent,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(
              Icons.more_vert,
              color: Colors.white,
            ),
            onPressed: () {},
          ),
        ],
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            14,
            8,
            14,
            30,
          ),
          child: Column(
            children: [

              // =========================
              // العداد الرئيسي
              // =========================

              SizedBox(
                height: 300,
                child: Stack(
                  alignment: Alignment.center,
                  children: [

                    Positioned.fill(
                      child: CustomPaint(
                        painter: GaugePainter(
                          value: signal,
                        ),
                      ),
                    ),

                    Positioned(
                      top: 110,
                      child: Column(
                        children: [
                          const Text(
                            'LIVE SCAN',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),

                          const SizedBox(height: 4),

                          Text(
                            '${signal.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: color,
                              fontSize: 58,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          Text(
                            signalText,
                            style: TextStyle(
                              color: color,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // =========================
              // معلومات جانبية
              // =========================

              Row(
                children: [

                  Expanded(
                    child: _infoCard(
                      title: 'شدة الإشارة',
                      value:
                          '${signal.toStringAsFixed(1)}%',
                      subtitle: signalText,
                      icon: Icons.signal_cellular_alt,
                      color: color,
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Column(
                      children: [

                        _smallInfoCard(
                          title: 'العمق التقريبي',
                          value:
                              '${depth.toStringAsFixed(2)} m',
                          icon: Icons.gps_fixed,
                          color: Colors.greenAccent,
                        ),

                        const SizedBox(height: 10),

                        _smallInfoCard(
                          title: 'استقرار الإشارة',
                          value:
                              '${stability.toStringAsFixed(0)}%',
                          icon: Icons.graphic_eq,
                          color: Colors.greenAccent,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // =========================
              // شريط الإشارة
              // =========================

              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF07111F),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
                child: Column(
                  children: [

                    SizedBox(
                      height: 28,
                      child: Row(
                        children: List.generate(
                          40,
                          (index) {
                            final level =
                                ((index + 1) / 40) * 100;

                            final active =
                                signal >= level;

                            Color barColor;

                            if (index < 10) {
                              barColor =
                                  Colors.redAccent;
                            } else if (index < 20) {
                              barColor =
                                  Colors.orangeAccent;
                            } else if (index < 30) {
                              barColor =
                                  Colors.amberAccent;
                            } else {
                              barColor =
                                  Colors.greenAccent;
                            }

                            return Expanded(
                              child: AnimatedContainer(
                                duration:
                                    const Duration(
                                  milliseconds: 180,
                                ),
                                margin:
                                    const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: active
                                      ? barColor
                                      : Colors.white
                                          .withOpacity(0.08),
                                  borderRadius:
                                      BorderRadius.circular(3),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 5),

                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          'ضعيفة',
                          style: TextStyle(
                            color: Colors.redAccent,
                          ),
                        ),
                        Text(
                          'متوسطة',
                          style: TextStyle(
                            color: Colors.amberAccent,
                          ),
                        ),
                        Text(
                          'قوية',
                          style: TextStyle(
                            color: Colors.greenAccent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // =========================
              // الرسم البياني
              // =========================

              _sectionCard(
                title: 'حركة الإشارة',
                icon: Icons.show_chart,
                height: 250,
                child: CustomPaint(
                  painter: SignalPainter(
                    values: signalHistory,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),

              const SizedBox(height: 14),

              // =========================
              // تحليل الهدف
              // =========================

              _sectionCard(
                title: 'تحليل الهدف',
                icon: Icons.track_changes,
                child: Column(
                  children: targets.map(
                    (target) {

                      final score =
                          targetScore(target);

                      final targetColorValue =
                          targetColor(target);

                      return Padding(
                        padding:
                            const EdgeInsets.only(
                          bottom: 12,
                        ),
                        child: Row(
                          children: [

                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: targetColorValue
                                    .withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                targetIcon(target),
                                color:
                                    targetColorValue,
                              ),
                            ),

                            const SizedBox(width: 10),

                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [

                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment
                                            .spaceBetween,
                                    children: [

                                      Text(
                                        target,
                                        style:
                                            const TextStyle(
                                          color:
                                              Colors.white,
                                          fontSize: 15,
                                          fontWeight:
                                              FontWeight.bold,
                                        ),
                                      ),

                                      Text(
                                        '${score.toStringAsFixed(0)}%',
                                        style: TextStyle(
                                          color:
                                              targetColorValue,
                                          fontWeight:
                                              FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 6),

                                  ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(
                                      8,
                                    ),
                                    child:
                                        LinearProgressIndicator(
                                      value:
                                          score / 100,
                                      minHeight: 8,
                                      backgroundColor:
                                          Colors.white
                                              .withOpacity(
                                        0.08,
                                      ),
                                      valueColor:
                                          AlwaysStoppedAnimation<
                                              Color>(
                                        targetColorValue,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ).toList(),
                ),
              ),

              const SizedBox(height: 14),

              // =========================
              // الهدف المحتمل
              // =========================

              _sectionCard(
                title: 'نوع الهدف المحتمل',
                icon: Icons.search,
                child: Column(
                  children: [

                    Text(
                      signal >= 70
                          ? 'إشارة قوية — هدف محتمل'
                          : signal >= 40
                              ? 'إشارة متوسطة — يحتاج إلى اختبار'
                              : 'لا توجد إشارة قوية',
                      style: TextStyle(
                        color: color,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      signal >= 70
                          ? '${signal.toStringAsFixed(0)}% ثقة تجريبية'
                          : 'استمر بالمسح للحصول على بيانات أكثر',
                      style: const TextStyle(
                        color: Colors.white54,
                      ),
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      'هذه النتيجة تجريبية حاليًا وليست كشفًا حقيقيًا لنوع المعدن أو العمق.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white30,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // =========================
              // معلومات الجهاز
              // =========================

              Row(
                children: [

                  Expanded(
                    child: _statusCard(
                      icon: Icons.graphic_eq,
                      title: 'حالة الجهاز',
                      value: 'مستقر',
                      color: Colors.greenAccent,
                    ),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: _statusCard(
                      icon: Icons.gps_fixed,
                      title: 'الحساسية',
                      value:
                          '${sensitivity.toStringAsFixed(0)}%',
                      color: Colors.greenAccent,
                    ),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: _statusCard(
                      icon: Icons.filter_alt,
                      title: 'الفلترة',
                      value: filter,
                      color: Colors.cyanAccent,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Row(
                children: [

                  Expanded(
                    child: _statusCard(
                      icon: Icons.volume_up,
                      title: 'التنبيه الصوتي',
                      value: scanning
                          ? 'يعمل'
                          : 'جاهز',
                      color: Colors.greenAccent,
                    ),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: _statusCard(
                      icon: Icons.vibration,
                      title: 'الاهتزاز',
                      value: 'يعمل',
                      color: Colors.greenAccent,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // =========================
              // أزرار التشغيل
              // =========================

              Row(
                children: [

                  Expanded(
                    child: SizedBox(
                      height: 58,
                      child: FilledButton.icon(
                        onPressed:
                            scanning ? null : startScan,
                        icon: const Icon(
                          Icons.play_arrow,
                          size: 28,
                        ),
                        label: const Text(
                          'بدء المسح',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              Colors.greenAccent
                                  .withOpacity(0.12),
                          foregroundColor:
                              Colors.greenAccent,
                          side: const BorderSide(
                            color: Colors.greenAccent,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: SizedBox(
                      height: 58,
                      child: OutlinedButton.icon(
                        onPressed:
                            scanning ? stopScan : null,
                        icon: const Icon(
                          Icons.stop,
                          size: 24,
                        ),
                        label: const Text(
                          'إيقاف المسح',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              Colors.redAccent,
                          side: const BorderSide(
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // =========================
              // تنبيه
              // =========================

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.amber.withOpacity(0.15),
                  ),
                ),
                child: const Text(
                  'تنبيه: البيانات الحالية تجريبية. بعد توصيل دائرة ESP32 والحساس سيتم استبدالها بالبيانات الحقيقية.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // Widgets
  // =====================================================

  Widget _infoCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF07111F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [

          Icon(
            icon,
            color: color,
            size: 28,
          ),

          const SizedBox(height: 5),

          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),

          Text(
            subtitle,
            style: TextStyle(
              color: color,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallInfoCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF07111F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [

          Icon(
            icon,
            color: color,
            size: 25,
          ),

          const SizedBox(width: 8),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [

                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                ),

                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    double? height,
  }) {
    return Container(
      width: double.infinity,
      height: height,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF07111F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [

          Row(
            children: [

              Icon(
                icon,
                color: Colors.cyanAccent,
              ),

              const SizedBox(width: 8),

              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Expanded(
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _statusCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 12,
        horizontal: 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF07111F),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        children: [

          Icon(
            icon,
            color: color,
            size: 25,
          ),

          const SizedBox(height: 5),

          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
            ),
          ),

          const SizedBox(height: 2),

          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// =======================================================
// Gauge
// =======================================================

class GaugePainter extends CustomPainter {
  final double value;

  GaugePainter({
    required this.value,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final center = Offset(
      size.width / 2,
      size.height * 0.78,
    );

    final radius =
        math.min(size.width * 0.43, size.height * 0.62);

    const startAngle = math.pi * 1.05;
    const sweepAngle = math.pi * 0.90;

    final segments = 42;

    for (int i = 0; i < segments; i++) {
      final progress = i / segments;

      final angle =
          startAngle + sweepAngle * progress;

      Color color;

      if (progress < 0.25) {
        color = Colors.redAccent;
      } else if (progress < 0.5) {
        color = Colors.orangeAccent;
      } else if (progress < 0.75) {
        color = Colors.amberAccent;
      } else {
        color = Colors.greenAccent;
      }

      final active =
          value >= progress * 100;

      final paint = Paint()
        ..color = active
            ? color
            : Colors.white.withOpacity(0.08)
        ..strokeWidth = 17
        ..strokeCap = StrokeCap.square;

      final inner = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );

      final outer = Offset(
        center.dx + math.cos(angle) * (radius + 8),
        center.dy + math.sin(angle) * (radius + 8),
      );

      canvas.drawLine(
        inner,
        outer,
        paint,
      );
    }

    // المؤشر
    final pointerValue =
        value.clamp(0, 100) / 100;

    final pointerAngle =
        startAngle + sweepAngle * pointerValue;

    final pointerEnd = Offset(
      center.dx +
          math.cos(pointerAngle) *
              (radius - 12),
      center.dy +
          math.sin(pointerAngle) *
              (radius - 12),
    );

    final pointerPaint = Paint()
      ..color = value < 25
          ? Colors.redAccent
          : value < 50
              ? Colors.orangeAccent
              : value < 75
                  ? Colors.amberAccent
                  : Colors.greenAccent
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      center,
      pointerEnd,
      pointerPaint,
    );

    canvas.drawCircle(
      center,
      9,
      Paint()..color = pointerPaint.color,
    );
  }

  @override
  bool shouldRepaint(
    covariant GaugePainter oldDelegate,
  ) {
    return oldDelegate.value != value;
  }
}

// =======================================================
// Signal Chart
// =======================================================

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
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    if (values.length < 2) return;

    final path = Path();

    for (int i = 0; i < values.length; i++) {
      final x =
          i * size.width / (values.length - 1);

      final normalized =
          values[i].clamp(0, 100) / 100;

      final y =
          size.height -
              normalized * size.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
      path,
      paint,
    );
  }

  @override
  bool shouldRepaint(
    covariant SignalPainter oldDelegate,
  ) {
    return true;
  }
}
