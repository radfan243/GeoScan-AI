import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';

import '../services/bluetooth_services.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final BluetoothService _bluetooth = BluetoothService();

  StreamSubscription<Map<String, dynamic>>? _dataSubscription;
  StreamSubscription<bool>? _connectionSubscription;

  final List<double> signalHistory = [];

  double signal = 0;
  double stability = 0;
  double depth = 0;
  double sensitivity = 75;

  bool scanning = false;
  bool connected = false;

  String filter = 'متوسطة';
  String deviceStatus = 'غير متصل';

  @override
  void initState() {
    super.initState();

    // ==========================================================
    // استقبال البيانات الحقيقية من ESP32
    // ==========================================================

    _dataSubscription =
        _bluetooth.dataStream.listen((data) {
      if (!mounted) return;

      setState(() {
        if (data.containsKey('signal')) {
          signal =
              _toDouble(data['signal']);
        }

        if (data.containsKey('stability')) {
          stability =
              _toDouble(data['stability']);
        }

        if (data.containsKey('depth')) {
          depth =
              _toDouble(data['depth']);
        }

        if (data.containsKey('status')) {
          deviceStatus =
              data['status'].toString();
        }

        signalHistory.add(signal);

        if (signalHistory.length > 60) {
          signalHistory.removeAt(0);
        }

        scanning =
            deviceStatus == 'يمسح' ||
            deviceStatus == 'SCANNING';
      });
    });

    // ==========================================================
    // مراقبة اتصال Bluetooth
    // ==========================================================

    _connectionSubscription =
        _bluetooth.connectionStream.listen(
      (isConnected) {
        if (!mounted) return;

        setState(() {
          connected = isConnected;

          if (!connected) {
            scanning = false;
            deviceStatus = 'غير متصل';
          }
        });
      },
    );

    // ==========================================================
    // إذا كان الاتصال موجودًا مسبقًا
    // ==========================================================

    connected = _bluetooth.isConnected;

    if (connected) {
      deviceStatus = 'متصل';
    }
  }

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value.toString(),
        ) ??
        0;
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _connectionSubscription?.cancel();

    super.dispose();
  }

  // ==========================================================
  // بدء المسح الحقيقي
  // ==========================================================

  Future<void> startScan() async {
    if (!connected) {
      _showMessage(
        'يجب الاتصال بجهاز ESP32 أولًا',
      );
      return;
    }

    try {
      await _bluetooth.startScan();

      if (!mounted) return;

      setState(() {
        scanning = true;
        deviceStatus = 'يمسح';
      });
    } catch (e) {
      _showMessage(
        'تعذر بدء المسح',
      );
    }
  }

  // ==========================================================
  // إيقاف المسح الحقيقي
  // ==========================================================

  Future<void> stopScan() async {
    if (!connected) return;

    try {
      await _bluetooth.stopScan();

      if (!mounted) return;

      setState(() {
        scanning = false;
      });
    } catch (e) {
      _showMessage(
        'تعذر إيقاف المسح',
      );
    }
  }

  // ==========================================================
  // المعايرة
  // ==========================================================

  Future<void> calibrate() async {
    if (!connected) {
      _showMessage(
        'يجب الاتصال بجهاز ESP32 أولًا',
      );
      return;
    }

    try {
      await _bluetooth.calibrate();

      if (!mounted) return;

      setState(() {
        signal = 0;
        stability = 100;
        depth = 0;
        signalHistory.clear();
        deviceStatus = 'معايرة';
      });
    } catch (e) {
      _showMessage(
        'تعذر تنفيذ المعايرة',
      );
    }
  }

  // ==========================================================
  // تغيير الحساسية
  // ==========================================================

  Future<void> changeSensitivity(
    double value,
  ) async {
    if (!connected) return;

    try {
      await _bluetooth.setSensitivity(
        value,
      );

      if (!mounted) return;

      setState(() {
        sensitivity = value;
      });
    } catch (_) {}
  }

  // ==========================================================
  // لون الإشارة
  // ==========================================================

  Color get signalColor {
    if (signal < 25) {
      return Colors.redAccent;
    }

    if (signal < 50) {
      return Colors.orangeAccent;
    }

    if (signal < 75) {
      return Colors.amberAccent;
    }

    return Colors.greenAccent;
  }

  String get signalText {
    if (signal < 25) {
      return 'إشارة ضعيفة';
    }

    if (signal < 50) {
      return 'إشارة متوسطة';
    }

    if (signal < 75) {
      return 'إشارة جيدة';
    }

    return 'إشارة قوية';
  }

  // ==========================================================
  // رسالة
  // ==========================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          textDirection: TextDirection.rtl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = signalColor;

    return Scaffold(
      backgroundColor: const Color(0xFF050B16),

      appBar: AppBar(
        backgroundColor: const Color(0xFF050B16),
        elevation: 0,

        centerTitle: true,

        title: Column(
          children: [
            const Text(
              'GeoScan AI',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              'المسح المباشر',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ],
        ),

        actions: [
          Padding(
            padding: const EdgeInsets.only(
              right: 10,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.bluetooth,
                  color: connected
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  size: 26,
                ),
                const SizedBox(width: 4),
                Text(
                  connected
                      ? 'متصل'
                      : 'غير متصل',
                  style: TextStyle(
                    color: connected
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
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

              // ==================================================
              // العداد الرئيسي
              // ==================================================

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
                      top: 105,
                      child: Column(
                        children: [
                          const Text(
                            'LIVE SCAN',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),

                          const SizedBox(height: 4),

                          Text(
                            '${signal.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: color,
                              fontSize: 56,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          Text(
                            connected
                                ? signalText
                                : 'غير متصل',
                            style: TextStyle(
                              color: connected
                                  ? color
                                  : Colors.redAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ==================================================
              // المعلومات
              // ==================================================

              Row(
                children: [
                  Expanded(
                    child: _infoCard(
                      title: 'شدة الإشارة',
                      value:
                          '${signal.toStringAsFixed(1)}%',
                      subtitle: signalText,
                      icon:
                          Icons.signal_cellular_alt,
                      color: color,
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Column(
                      children: [
                        _smallInfoCard(
                          title: 'العمق',
                          value:
                              depth > 0
                                  ? '${depth.toStringAsFixed(2)} m'
                                  : '--',
                          icon:
                              Icons.gps_fixed,
                          color:
                              Colors.greenAccent,
                        ),

                        const SizedBox(height: 10),

                        _smallInfoCard(
                          title: 'الاستقرار',
                          value:
                              '${stability.toStringAsFixed(0)}%',
                          icon:
                              Icons.graphic_eq,
                          color:
                              Colors.greenAccent,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // ==================================================
              // عداد الشرائح
              // ==================================================

              Container(
                padding:
                    const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color:
                      const Color(0xFF07111F),
                  borderRadius:
                      BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white
                        .withOpacity(0.08),
                  ),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 28,
                      child: Row(
                        children:
                            List.generate(
                          40,
                          (index) {
                            final level =
                                ((index + 1) /
                                        40) *
                                    100;

                            final active =
                                signal >= level;

                            Color barColor;

                            if (index < 10) {
                              barColor =
                                  Colors.redAccent;
                            } else if (index <
                                20) {
                              barColor =
                                  Colors.orangeAccent;
                            } else if (index <
                                30) {
                              barColor =
                                  Colors.amberAccent;
                            } else {
                              barColor =
                                  Colors.greenAccent;
                            }

                            return Expanded(
                              child:
                                  AnimatedContainer(
                                duration:
                                    const Duration(
                                  milliseconds:
                                      120,
                                ),
                                margin:
                                    const EdgeInsets
                                        .symmetric(
                                  horizontal: 1,
                                ),
                                decoration:
                                    BoxDecoration(
                                  color: active
                                      ? barColor
                                      : Colors.white
                                          .withOpacity(
                                          0.08,
                                        ),
                                  borderRadius:
                                      BorderRadius
                                          .circular(
                                    3,
                                  ),
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
                          MainAxisAlignment
                              .spaceBetween,
                      children: [
                        Text(
                          'ضعيفة',
                          style: TextStyle(
                            color:
                                Colors.redAccent,
                          ),
                        ),
                        Text(
                          'متوسطة',
                          style: TextStyle(
                            color:
                                Colors.amberAccent,
                          ),
                        ),
                        Text(
                          'قوية',
                          style: TextStyle(
                            color:
                                Colors.greenAccent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ==================================================
              // الرسم
              // ==================================================

              _sectionCard(
                title: 'حركة الإشارة الحقيقية',
                icon: Icons.show_chart,
                height: 240,
                child: CustomPaint(
                  painter: SignalPainter(
                    values: signalHistory,
                  ),
                  child:
                      const SizedBox.expand(),
                ),
              ),

              const SizedBox(height: 14),

              // ==================================================
              // حالة الجهاز
              // ==================================================

              _sectionCard(
                title: 'حالة جهاز ESP32',
                icon: Icons.memory,
                child: Column(
                  children: [
                    Icon(
                      connected
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth_disabled,
                      size: 55,
                      color: connected
                          ? Colors.greenAccent
                          : Colors.redAccent,
                    ),

                    const SizedBox(height: 10),

                    Text(
                      connected
                          ? deviceStatus
                          : 'غير متصل',
                      style: TextStyle(
                        color: connected
                            ? Colors.greenAccent
                            : Colors.redAccent,
                        fontSize: 22,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      connected
                          ? 'البيانات تصل من ESP32 عبر Bluetooth'
                          : 'اتصل بجهاز ESP32 أولًا',
                      textAlign:
                          TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ==================================================
              // إعدادات
              // ==================================================

              _sectionCard(
                title: 'إعدادات المسح',
                icon: Icons.settings,
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.tune,
                          color:
                              Colors.cyanAccent,
                        ),

                        const SizedBox(width: 10),

                        const Text(
                          'الحساسية',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        const Spacer(),

                        Text(
                          '${sensitivity.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color:
                                Colors.cyanAccent,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    Slider(
                      value: sensitivity,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      activeColor:
                          Colors.cyanAccent,
                      onChanged: connected
                          ? changeSensitivity
                          : null,
                    ),

                    const SizedBox(height: 8),

                    Row(
                      children: [
                        const Icon(
                          Icons.filter_alt,
                          color:
                              Colors.cyanAccent,
                        ),

                        const SizedBox(width: 10),

                        const Text(
                          'الفلترة',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        const Spacer(),

                        DropdownButton<String>(
                          value: filter,
                          dropdownColor:
                              const Color(
                            0xFF07111F,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'منخفضة',
                              child: Text(
                                'منخفضة',
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'متوسطة',
                              child: Text(
                                'متوسطة',
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'عالية',
                              child: Text(
                                'عالية',
                              ),
                            ),
                          ],
                          onChanged: connected
                              ? (value) async {
                                  if (value ==
                                      null) {
                                    return;
                                  }

                                  try {
                                    await _bluetooth
                                        .setFilter(
                                      value,
                                    );

                                    if (!mounted) {
                                      return;
                                    }

                                    setState(() {
                                      filter =
                                          value;
                                    });
                                  } catch (_) {}
                                }
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ==================================================
              // أزرار التحكم
              // ==================================================

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 58,
                      child: FilledButton.icon(
                        onPressed:
                            scanning ||
                                    !connected
                                ? null
                                : startScan,
                        icon: const Icon(
                          Icons.play_arrow,
                          size: 28,
                        ),
                        label: const Text(
                          'بدء المسح',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        style:
                            FilledButton.styleFrom(
                          backgroundColor:
                              Colors.greenAccent
                                  .withOpacity(
                            0.12,
                          ),
                          foregroundColor:
                              Colors.greenAccent,
                          side:
                              const BorderSide(
                            color:
                                Colors.greenAccent,
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
                            scanning
                                ? stopScan
                                : null,
                        icon: const Icon(
                          Icons.stop,
                          size: 24,
                        ),
                        label: const Text(
                          'إيقاف المسح',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        style:
                            OutlinedButton.styleFrom(
                          foregroundColor:
                              Colors.redAccent,
                          side:
                              const BorderSide(
                            color:
                                Colors.redAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ==================================================
              // معايرة
              // ==================================================

              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed:
                      connected && !scanning
                          ? calibrate
                          : null,
                  icon: const Icon(
                    Icons.refresh,
                  ),
                  label: const Text(
                    'معايرة الحساس',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // ==================================================
              // تنبيه مهم
              // ==================================================

              Container(
                padding:
                    const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber
                      .withOpacity(0.05),
                  borderRadius:
                      BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.amber
                        .withOpacity(0.15),
                  ),
                ),
                child: const Text(
                  'القراءة المعروضة تأتي من ESP32 عبر Bluetooth. دقة كشف المعدن والعمق تعتمد على دائرة الحساس والمعايرة والاختبارات الفعلية.',
                  textAlign:
                      TextAlign.center,
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

  // ==========================================================
  // Info Card
  // ==========================================================

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
        borderRadius:
            BorderRadius.circular(18),
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
              fontWeight:
                  FontWeight.bold,
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

  // ==========================================================
  // Small Info Card
  // ==========================================================

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
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white
              .withOpacity(0.1),
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
                  style:
                      const TextStyle(
                    color:
                        Colors.white60,
                    fontSize: 11,
                  ),
                ),

                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 19,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // Section Card
  // ==========================================================

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
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white
              .withOpacity(0.08),
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
                color:
                    Colors.cyanAccent,
              ),

              const SizedBox(width: 8),

              Text(
                title,
                style:
                    const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight:
                      FontWeight.bold,
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
}

// ============================================================
// Gauge Painter
// ============================================================

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

    final radius = 110.0;

    const startAngle =
        math.pi * 1.05;

    const sweepAngle =
        math.pi * 0.90;

    const segments = 42;

    for (int i = 0;
        i < segments;
        i++) {
      final progress =
          i / segments;

      final angle =
          startAngle +
              sweepAngle *
                  progress;

      Color color;

      if (progress < 0.25) {
        color =
            Colors.redAccent;
      } else if (progress < 0.5) {
        color =
            Colors.orangeAccent;
      } else if (progress < 0.75) {
        color =
            Colors.amberAccent;
      } else {
        color =
            Colors.greenAccent;
      }

      final active =
          value >=
              progress * 100;

      final paint = Paint()
        ..color = active
            ? color
            : Colors.white
                .withOpacity(0.08)
        ..strokeWidth = 17
        ..strokeCap =
            StrokeCap.square;

      final inner = Offset(
        center.dx +
            math.cos(angle) *
                radius,
        center.dy +
            math.sin(angle) *
                radius,
      );

      final outer = Offset(
        center.dx +
            math.cos(angle) *
                (radius + 8),
        center.dy +
            math.sin(angle) *
                (radius + 8),
      );

      canvas.drawLine(
        inner,
        outer,
        paint,
      );
    }

    final pointerValue =
        value.clamp(0, 100) /
            100;

    final pointerAngle =
        startAngle +
            sweepAngle *
                pointerValue;

    final pointerEnd =
        Offset(
      center.dx +
          math.cos(pointerAngle) *
              (radius - 12),
      center.dy +
          math.sin(pointerAngle) *
              (radius - 12),
    );

    final pointerPaint =
        Paint()
          ..color = value < 25
              ? Colors.redAccent
              : value < 50
                  ? Colors.orangeAccent
                  : value < 75
                      ? Colors.amberAccent
                      : Colors.greenAccent
          ..strokeWidth = 7
          ..strokeCap =
              StrokeCap.round;

    canvas.drawLine(
      center,
      pointerEnd,
      pointerPaint,
    );

    canvas.drawCircle(
      center,
      9,
      Paint()
        ..color =
            pointerPaint.color,
    );
  }

  @override
  bool shouldRepaint(
    covariant GaugePainter oldDelegate,
  ) {
    return oldDelegate.value !=
        value;
  }
}

// ============================================================
// Signal Painter
// ============================================================

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
      ..color = Colors.white
          .withOpacity(0.06)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y =
          size.height * i / 4;

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    if (values.length < 2) {
      return;
    }

    final path = Path();

    for (int i = 0;
        i < values.length;
        i++) {
      final x =
          i *
              size.width /
              (values.length - 1);

      final normalized =
          values[i]
                  .clamp(0, 100) /
              100;

      final y =
          size.height -
              normalized *
                  size.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color =
          Colors.cyanAccent
      ..strokeWidth = 4
      ..style =
          PaintingStyle.stroke
      ..strokeCap =
          StrokeCap.round
      ..strokeJoin =
          StrokeJoin.round;

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
