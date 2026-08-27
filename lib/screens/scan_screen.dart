import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/bluetooth_service.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  final BluetoothService _bluetoothService = BluetoothService();

  StreamSubscription<double>? _signalSubscription;

  double signal = 0;
  double stability = 0;
  double estimatedDepth = 0;

  bool scanning = false;
  bool soundEnabled = true;
  bool vibrationEnabled = true;

  String selectedTarget = 'ذهب';

  final List<double> history = [];

  late AnimationController _pulseController;

  final List<String> targets = [
    'ذهب',
    'نحاس',
    'فضة',
    'حديد',
    'ماء',
  ];

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _signalSubscription =
        _bluetoothService.signalStream.listen((value) {
      if (!mounted) return;

      final newValue = value.clamp(0.0, 100.0);

      setState(() {
        signal = newValue;

        history.add(newValue);

        if (history.length > 60) {
          history.removeAt(0);
        }

        stability = _calculateStability();

        // هذه قيمة تقديرية للواجهة فقط.
        // لا تعتبر عمق كشف حقيقي حتى يتم ربط
        // خوارزمية القياس الفعلية بالحساس.
        estimatedDepth = (newValue / 100) * 2.5;
      });
    });
  }

  double _calculateStability() {
    if (history.length < 5) {
      return signal;
    }

    final recent = history.length > 10
        ? history.sublist(history.length - 10)
        : history;

    final average =
        recent.reduce((a, b) => a + b) / recent.length;

    final variance = recent
            .map((v) => math.pow(v - average, 2))
            .reduce((a, b) => a + b) /
        recent.length;

    final deviation = math.sqrt(variance);

    return (100 - deviation * 2).clamp(0.0, 100.0);
  }

  Color get signalColor {
    if (signal < 25) return Colors.redAccent;
    if (signal < 50) return Colors.orangeAccent;
    if (signal < 75) return Colors.amberAccent;
    return Colors.greenAccent;
  }

  String get signalStatus {
    if (signal < 25) return 'إشارة ضعيفة';
    if (signal < 50) return 'إشارة متوسطة';
    if (signal < 75) return 'إشارة جيدة';
    return 'إشارة قوية';
  }

  String get targetStatus {
    if (signal >= 75) return 'محتمل';
    if (signal >= 50) return 'ممكن';
    return 'ضعيف';
  }

  Future<void> _startScan() async {
    if (scanning) return;

    if (!_bluetoothService.isConnected) {
      _showMessage('يجب الاتصال بجهاز ESP32 أولاً');
      return;
    }

    final success =
        await _bluetoothService.startScanning();

    if (!mounted) return;

    if (success) {
      setState(() {
        scanning = true;
        history.clear();
      });

      _showMessage('بدأ المسح');
    } else {
      _showMessage('تعذر بدء المسح');
    }
  }

  Future<void> _stopScan() async {
    await _bluetoothService.stopScanning();

    if (!mounted) return;

    setState(() {
      scanning = false;
    });

    _showMessage('تم إيقاف المسح');
  }

  Future<void> _selectTarget(String target) async {
    setState(() {
      selectedTarget = target;
    });

    if (_bluetoothService.isConnected) {
      await _bluetoothService.setTarget(target);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          textDirection: TextDirection.rtl,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _signalSubscription?.cancel();
    _pulseController.dispose();
    _bluetoothService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030812),
      body: SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              _buildTopBar(),

              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    20,
                  ),
                  child: Column(
                    children: [
                      _buildGauge(),

                      const SizedBox(height: 14),

                      _buildSignalMeter(),

                      const SizedBox(height: 16),

                      _buildGraphAndTargets(),

                      const SizedBox(height: 14),

                      _buildLikelyTarget(),

                      const SizedBox(height: 14),

                      _buildControlCards(),

                      const SizedBox(height: 14),

                      _buildButtons(),
                    ],
                  ),
                ),
              ),

              _buildBottomNavigation(),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // TOP BAR
  // ============================================================

  Widget _buildTopBar() {
    final connected =
        _bluetoothService.isConnected;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0xFF142235),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.menu,
              color: Colors.white,
              size: 30,
            ),
          ),

          Expanded(
            child: Column(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) {
                    return const LinearGradient(
                      colors: [
                        Colors.white,
                        Colors.lightBlueAccent,
                      ],
                    ).createShader(bounds);
                  },
                  child: const Text(
                    'GeoScan AI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 1),

                const Text(
                  'المسح المباشر',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),

          Row(
            children: [
              Icon(
                Icons.bluetooth,
                color: connected
                    ? Colors.cyanAccent
                    : Colors.white30,
                size: 28,
              ),
              const SizedBox(width: 5),
              Text(
                connected ? 'متصل' : 'غير متصل',
                style: TextStyle(
                  color: connected
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.more_vert,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // GAUGE
  // ============================================================

  Widget _buildGauge() {
    return SizedBox(
      height: 320,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(
              double.infinity,
              320,
            ),
            painter: _GaugePainter(
              value: signal,
              color: signalColor,
            ),
          ),

          Positioned(
            top: 82,
            child: Column(
              children: [
                const Text(
                  'LIVE SCAN',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 15),

                Text(
                  '${signal.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: signalColor,
                    fontSize: 57,
                    fontWeight: FontWeight.w300,
                  ),
                ),

                const SizedBox(height: 2),

                Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      color: signalColor,
                      size: 21,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      signalStatus,
                      style: TextStyle(
                        color: signalColor,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Positioned(
            right: 0,
            top: 30,
            child: _infoCard(
              title: 'العمق التقديري',
              value:
                  '${estimatedDepth.toStringAsFixed(2)} m',
              icon: Icons.gps_fixed,
            ),
          ),

          Positioned(
            right: 0,
            top: 178,
            child: _infoCard(
              title: 'استقرار الإشارة',
              value:
                  '${stability.toStringAsFixed(0)}%',
              icon: Icons.show_chart,
            ),
          ),

          Positioned(
            left: 0,
            top: 30,
            child: _signalSideCard(),
          ),
        ],
      ),
    );
  }

  Widget _infoCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      width: 190,
      height: 105,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF07121F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.cyanAccent.withOpacity(0.25),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 23,
              ),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            value,
            style: TextStyle(
              color: Colors.greenAccent,
              fontSize: 27,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _signalSideCard() {
    return Container(
      width: 190,
      height: 155,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF07121F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.cyanAccent.withOpacity(0.25),
        ),
      ),
      child: Column(
        children: [
          const Text(
            'شدة الإشارة',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              crossAxisAlignment:
                  CrossAxisAlignment.end,
              children: List.generate(
                5,
                (index) {
                  final height =
                      15.0 + index * 8;

                  final active =
                      signal >=
                          ((index + 1) * 20);

                  return Container(
                    width: 9,
                    height: height,
                    margin:
                        const EdgeInsets.symmetric(
                      horizontal: 4,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.greenAccent
                          : Colors.white12,
                      borderRadius:
                          BorderRadius.circular(5),
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 8),

          Text(
            '${signal.toStringAsFixed(1)}%',
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 27,
              fontWeight: FontWeight.bold,
            ),
          ),

          Text(
            signalStatus,
            style: TextStyle(
              color: signalColor,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // METER
  // ============================================================

  Widget _buildSignalMeter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        10,
        10,
        10,
        14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF07121F),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.white10,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceAround,
            children: const [
              Text('0',
                  style: TextStyle(
                      color: Colors.white70)),
              Text('20',
                  style: TextStyle(
                      color: Colors.white70)),
              Text('40',
                  style: TextStyle(
                      color: Colors.white70)),
              Text('60',
                  style: TextStyle(
                      color: Colors.white70)),
              Text('80',
                  style: TextStyle(
                      color: Colors.white70)),
              Text('100',
                  style: TextStyle(
                      color: Colors.white70)),
            ],
          ),

          const SizedBox(height: 6),

          SizedBox(
            height: 24,
            child: Row(
              children: List.generate(
                40,
                (index) {
                  final value =
                      index * 2.5;

                  Color color;

                  if (value < 25) {
                    color = Colors.redAccent;
                  } else if (value < 50) {
                    color = Colors.orange;
                  } else if (value < 75) {
                    color = Colors.amber;
                  } else {
                    color = Colors.greenAccent;
                  }

                  final active =
                      signal >= value;

                  return Expanded(
                    child: Container(
                      margin:
                          const EdgeInsets.symmetric(
                        horizontal: 1,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? color
                            : color.withOpacity(0.12),
                        borderRadius:
                            BorderRadius.circular(3),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 7),

          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceAround,
            children: const [
              Text(
                'ضعيفة',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'متوسطة',
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'قوية',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // GRAPH + TARGETS
  // ============================================================

  Widget _buildGraphAndTargets() {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: _buildGraph(),
        ),

        const SizedBox(width: 10),

        Expanded(
          flex: 4,
          child: _buildTargets(),
        ),
      ],
    );
  }

  Widget _buildGraph() {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF07121F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            'حركة الإشارة',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          Expanded(
            child: CustomPaint(
              painter: _GraphPainter(
                values: history,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargets() {
    final values = [
      signal,
      signal * .62,
      signal * .37,
      signal * .22,
      signal * .75,
    ];

    return Container(
      height: 300,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF07121F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text(
                'تحليل الهدف',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Spacer(),
              Icon(
                Icons.help_outline,
                color: Colors.white54,
              ),
            ],
          ),

          const SizedBox(height: 8),

          ...List.generate(
            targets.length,
            (index) {
              return _targetRow(
                targets[index],
                values[index],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _targetRow(
    String name,
    double value,
  ) {
    final color = name == 'ذهب'
        ? Colors.greenAccent
        : name == 'نحاس'
            ? Colors.orange
            : name == 'فضة'
                ? Colors.lightBlueAccent
                : name == 'حديد'
                    ? Colors.redAccent
                    : Colors.cyanAccent;

    return Expanded(
      child: Container(
        margin:
            const EdgeInsets.only(bottom: 6),
        padding:
            const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF091522),
          borderRadius:
              BorderRadius.circular(12),
          border:
              Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(
                  name == 'ماء'
                      ? Icons.water_drop
                      : Icons.circle,
                  size: 20,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  '${value.clamp(0, 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 5),

            LinearProgressIndicator(
              value:
                  (value / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor:
                  Colors.white10,
              valueColor:
                  AlwaysStoppedAnimation(color),
              borderRadius:
                  BorderRadius.circular(10),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // LIKELY TARGET
  // ============================================================

  Widget _buildLikelyTarget() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF07121F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.amberAccent.withOpacity(.25),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            'نوع الهدف المحتمل',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Container(
                width: 95,
                height: 75,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.amber.withOpacity(.08),
                ),
                child: const Icon(
                  Icons.diamond,
                  size: 58,
                  color: Colors.amber,
                ),
              ),

              const SizedBox(width: 18),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$selectedTarget $targetStatus',
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      '${signal.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 3),

                    const Text(
                      'الثقة',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(height: 5),

                    const Text(
                      'يرجى تأكيد النتيجة بالحفر والاختبار الفعلي.',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CONTROL CARDS
  // ============================================================

  Widget _buildControlCards() {
    return Row(
      children: [
        Expanded(
          child: _controlCard(
            icon: Icons.monitor_heart,
            title: 'حالة الجهاز',
            value: _bluetoothService.isConnected
                ? 'مستقر'
                : 'غير متصل',
            color: _bluetoothService.isConnected
                ? Colors.greenAccent
                : Colors.redAccent,
          ),
        ),

        const SizedBox(width: 7),

        Expanded(
          child: _controlCard(
            icon: Icons.gps_fixed,
            title: 'الحساسية',
            value: '75%',
            color: Colors.greenAccent,
          ),
        ),

        const SizedBox(width: 7),

        Expanded(
          child: _controlCard(
            icon: Icons.filter_alt_outlined,
            title: 'الفلترة',
            value: 'متوسطة',
            color: Colors.cyanAccent,
          ),
        ),

        const SizedBox(width: 7),

        Expanded(
          child: _controlCard(
            icon: Icons.volume_up,
            title: 'التنبيه الصوتي',
            value: soundEnabled
                ? 'يعمل'
                : 'متوقف',
            color: soundEnabled
                ? Colors.greenAccent
                : Colors.white54,
            onTap: () {
              setState(() {
                soundEnabled =
                    !soundEnabled;
              });
            },
          ),
        ),

        const SizedBox(width: 7),

        Expanded(
          child: _controlCard(
            icon: Icons.vibration,
            title: 'الاهتزاز',
            value: vibrationEnabled
                ? 'يعمل'
                : 'متوقف',
            color: vibrationEnabled
                ? Colors.greenAccent
                : Colors.white54,
            onTap: () {
              setState(() {
                vibrationEnabled =
                    !vibrationEnabled;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _controlCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 105,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF07121F),
          borderRadius:
              BorderRadius.circular(15),
          border:
              Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: color,
              size: 29,
            ),

            const SizedBox(height: 7),

            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUTTONS
  // ============================================================

  Widget _buildButtons() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 58,
            child: ElevatedButton.icon(
              onPressed:
                  scanning ? null : _startScan,
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
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    const Color(0xFF071B12),
                foregroundColor:
                    Colors.greenAccent,
                side: const BorderSide(
                  color: Colors.greenAccent,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(15),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: SizedBox(
            height: 58,
            child: ElevatedButton.icon(
              onPressed:
                  scanning ? _stopScan : null,
              icon: const Icon(
                Icons.stop,
                size: 26,
              ),
              label: const Text(
                'إيقاف المسح',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    const Color(0xFF241015),
                foregroundColor:
                    Colors.redAccent,
                side: const BorderSide(
                  color: Colors.redAccent,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(15),
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
              onPressed: () {
                _showMessage(
                  'حفظ القراءة سيتم ربطه بالسجلات لاحقاً',
                );
              },
              icon: const Icon(
                Icons.save_outlined,
              ),
              label: const Text(
                'حفظ القراءة',
                style: TextStyle(
                  fontSize: 15,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    Colors.white70,
                side: const BorderSide(
                  color: Colors.white24,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(15),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // BOTTOM NAVIGATION
  // ============================================================

  Widget _buildBottomNavigation() {
    return Container(
      height: 80,
      decoration: const BoxDecoration(
        color: Color(0xFF07111D),
        border: Border(
          top: BorderSide(
            color: Color(0xFF172638),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceAround,
        children: [
          _navItem(
            Icons.home_outlined,
            'الرئيسية',
            false,
          ),
          _navItem(
            Icons.folder_outlined,
            'السجلات',
            false,
          ),
          _navItem(
            Icons.radar,
            'المسح',
            true,
          ),
          _navItem(
            Icons.bar_chart,
            'التحليل',
            false,
          ),
          _navItem(
            Icons.settings_outlined,
            'الإعدادات',
            false,
          ),
        ],
      ),
    );
  }

  Widget _navItem(
    IconData icon,
    String title,
    bool active,
  ) {
    return Column(
      mainAxisAlignment:
          MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: active ? 30 : 27,
          color: active
              ? Colors.cyanAccent
              : Colors.white38,
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            color: active
                ? Colors.cyanAccent
                : Colors.white38,
            fontSize: 11,
            fontWeight: active
                ? FontWeight.bold
                : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

// ================================================================
// GAUGE PAINTER
// ================================================================

class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;

  _GaugePainter({
    required this.value,
    required this.color,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final center = Offset(
      size.width / 2,
      size.height * .67,
    );

    final radius =
        math.min(size.width * .40, size.height * .55);

    const startAngle = math.pi * 1.08;
    const sweepAngle = math.pi * .84;

    final rect = Rect.fromCircle(
      center: center,
      radius: radius,
    );

    // الخلفية
    final backgroundPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 23
      ..strokeCap = StrokeCap.butt
      ..color = Colors.white10;

    canvas.drawArc(
      rect,
      startAngle,
      sweepAngle,
      false,
      backgroundPaint,
    );

    // الشرائح الملونة
    const segments = 36;

    for (int i = 0; i < segments; i++) {
      final ratio = i / segments;

      Color segmentColor;

      if (ratio < .25) {
        segmentColor = Colors.redAccent;
      } else if (ratio < .50) {
        segmentColor = Colors.orange;
      } else if (ratio < .75) {
        segmentColor = Colors.amber;
      } else {
        segmentColor = Colors.greenAccent;
      }

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20
        ..color = segmentColor;

      final segmentStart =
          startAngle +
          sweepAngle * ratio;

      final segmentSweep =
          sweepAngle / segments * .72;

      canvas.drawArc(
        rect,
        segmentStart,
        segmentSweep,
        false,
        paint,
      );
    }

    // المؤشر
    final valueRatio =
        value.clamp(0.0, 100.0) / 100;

    final angle =
        startAngle +
        sweepAngle * valueRatio;

    final needleLength =
        radius * .72;

    final needleEnd = Offset(
      center.dx +
          math.cos(angle) * needleLength,
      center.dy +
          math.sin(angle) * needleLength,
    );

    final needlePaint = Paint()
      ..color = color
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      center,
      needleEnd,
      needlePaint,
    );

    final circlePaint = Paint()
      ..color = color;

    canvas.drawCircle(
      center,
      9,
      circlePaint,
    );

    // العلامات الرقمية
    const labels = [
      '0',
      '20',
      '40',
      '50',
      '60',
      '80',
      '100',
    ];

    final textStyle = const TextStyle(
      color: Colors.white,
      fontSize: 13,
    );

    for (int i = 0; i < labels.length; i++) {
      final ratio = i / (labels.length - 1);

      final labelAngle =
          startAngle +
          sweepAngle * ratio;

      final labelRadius =
          radius + 35;

      final position = Offset(
        center.dx +
            math.cos(labelAngle) *
                labelRadius,
        center.dy +
            math.sin(labelAngle) *
                labelRadius,
      );

      final painter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: textStyle,
        ),
        textDirection: TextDirection.ltr,
      );

      painter.layout();

      painter.paint(
        canvas,
        Offset(
          position.dx -
              painter.width / 2,
          position.dy -
              painter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(
    _GaugePainter oldDelegate,
  ) {
    return oldDelegate.value != value ||
        oldDelegate.color != color;
  }
}

// ================================================================
// GRAPH PAINTER
// ================================================================

class _GraphPainter extends CustomPainter {
  final List<double> values;

  _GraphPainter({
    required this.values,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final gridPaint = Paint()
      ..color = Colors.white10
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

    for (int i = 0; i <= 6; i++) {
      final x =
          size.width * i / 6;

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );
    }

    if (values.length < 2) {
      return;
    }

    final path = Path();

    for (int i = 0; i < values.length; i++) {
      final x =
          size.width *
              i /
              (values.length - 1);

      final y =
          size.height -
              (values[i].clamp(0, 100) /
                      100) *
                  size.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
      path,
      linePaint,
    );

    final last = values.last;

    final lastX = size.width;

    final lastY =
        size.height -
            (last.clamp(0, 100) /
                    100) *
                size.height;

    canvas.drawCircle(
      Offset(lastX, lastY),
      5,
      Paint()..color = Colors.greenAccent,
    );
  }

  @override
  bool shouldRepaint(
    _GraphPainter oldDelegate,
  ) {
    return oldDelegate.values != values;
  }
}
