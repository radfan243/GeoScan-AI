import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/bluetooth_service.dart';
import 'bluetooth_screen.dart';
import 'home_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  final BluetoothService _bluetoothService = BluetoothService();

  StreamSubscription<double>? _signalSubscription;
  StreamSubscription<bool>? _connectionSubscription;

  late AnimationController _radarController;

  double signal = 0;
  double stability = 0;
  double peak = 0;

  bool scanning = false;
  bool soundEnabled = true;
  bool vibrationEnabled = true;

  double filterStrength = 50;

  String selectedTarget = 'ذهب';

  final List<double> history = [];

  final List<String> targets = const [
    'ذهب',
    'نحاس',
    'فضة',
    'حديد',
    'ماء',
  ];

  final List<Map<String, dynamic>> savedReadings = [];

  @override
  void initState() {
    super.initState();

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _listenToSignal();
    _listenToConnection();
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _signalSubscription?.cancel();
    _connectionSubscription?.cancel();
    _radarController.dispose();
    super.dispose();
  }

  // ============================================================
  // REAL ESP32 SIGNAL
  // ============================================================

  void _listenToSignal() {
    _signalSubscription =
        _bluetoothService.signalStream.listen((value) {
      if (!mounted) return;

      final newValue = value.clamp(0.0, 100.0).toDouble();

      setState(() {
        signal = newValue;

        history.add(newValue);

        if (history.length > 80) {
          history.removeAt(0);
        }

        stability = _calculateStability();

        if (newValue > peak) {
          peak = newValue;
        }

        if (vibrationEnabled && newValue >= 80) {
          HapticFeedback.selectionClick();
        }
      });
    });
  }

  void _listenToConnection() {
    _connectionSubscription =
        _bluetoothService.connectionStream.listen((connected) {
      if (!mounted) return;

      setState(() {
        if (!connected) {
          scanning = false;
        }
      });
    });
  }

  double _calculateStability() {
    if (history.length < 5) {
      return signal;
    }

    final recent = history.length > 12
        ? history.sublist(history.length - 12)
        : history;

    final average =
        recent.reduce((a, b) => a + b) / recent.length;

    final variance = recent
            .map(
              (v) => math.pow(v - average, 2).toDouble(),
            )
            .reduce((a, b) => a + b) /
        recent.length;

    final deviation = math.sqrt(variance);

    return (100 - deviation * 2.2)
        .clamp(0.0, 100.0)
        .toDouble();
  }

  // ============================================================
  // COLORS / STATUS
  // ============================================================

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

  String get signalStatus {
    if (signal < 25) {
      return 'ضعيفة';
    }

    if (signal < 50) {
      return 'متوسطة';
    }

    if (signal < 75) {
      return 'جيدة';
    }

    return 'قوية';
  }

  // ============================================================
  // TARGET
  // ============================================================

  double _targetValue(String target) {
    switch (target) {
      case 'ذهب':
        return signal;

      case 'نحاس':
        return signal * .62;

      case 'فضة':
        return signal * .37;

      case 'حديد':
        return signal * .22;

      case 'ماء':
        return signal * .75;

      default:
        return signal;
    }
  }

  Color _targetColor(String target) {
    switch (target) {
      case 'ذهب':
        return Colors.greenAccent;

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

  IconData _targetIcon(String target) {
    switch (target) {
      case 'ذهب':
        return Icons.diamond;

      case 'نحاس':
        return Icons.layers;

      case 'فضة':
        return Icons.hexagon;

      case 'حديد':
        return Icons.circle;

      case 'ماء':
        return Icons.water_drop;

      default:
        return Icons.circle;
    }
  }

  // ============================================================
  // START SCAN
  // ============================================================

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
        peak = 0;
        signal = 0;
        stability = 0;
      });

      _showMessage('بدأ المسح الحقيقي من ESP32');
    } else {
      _showMessage('تعذر بدء المسح');
    }
  }

  // ============================================================
  // STOP SCAN
  // ============================================================

  Future<void> _stopScan() async {
    if (!scanning) return;

    final success =
        await _bluetoothService.stopScanning();

    if (!mounted) return;

    setState(() {
      scanning = false;
    });

    if (success) {
      _showMessage('تم إيقاف المسح');
    } else {
      _showMessage('تم إيقاف المسح محليًا');
    }
  }

  // ============================================================
  // TARGET
  // ============================================================

  Future<void> _selectTarget(String target) async {
    setState(() {
      selectedTarget = target;
    });

    if (_bluetoothService.isConnected) {
      final success =
          await _bluetoothService.setTarget(target);

      if (!success && mounted) {
        _showMessage('تعذر إرسال الهدف إلى ESP32');
      }
    }
  }

  // ============================================================
  // SAVE
  // ============================================================

  void _saveReading() {
    if (signal <= 0) {
      _showMessage('لا توجد قراءة لحفظها');
      return;
    }

    setState(() {
      savedReadings.add({
        'signal': signal,
        'stability': stability,
        'peak': peak,
        'target': selectedTarget,
        'time': DateTime.now(),
      });
    });

    HapticFeedback.mediumImpact();

    _showMessage('تم حفظ القراءة بنجاح');
  }

  // ============================================================
  // RESET
  // ============================================================

  void _resetReading() {
    setState(() {
      signal = 0;
      stability = 0;
      peak = 0;
      history.clear();
    });

    _showMessage('تم تصفير القراءة');
  }

  // ============================================================
  // SOUND
  // ============================================================

  void _toggleSound() {
    setState(() {
      soundEnabled = !soundEnabled;
    });

    if (soundEnabled) {
      SystemSound.play(SystemSoundType.alert);
    }

    _showMessage(
      soundEnabled
          ? 'تم تشغيل التنبيه الصوتي'
          : 'تم إيقاف التنبيه الصوتي',
    );
  }

  // ============================================================
  // VIBRATION
  // ============================================================

  void _toggleVibration() {
    setState(() {
      vibrationEnabled = !vibrationEnabled;
    });

    if (vibrationEnabled) {
      HapticFeedback.mediumImpact();
    }

    _showMessage(
      vibrationEnabled
          ? 'تم تشغيل الاهتزاز'
          : 'تم إيقاف الاهتزاز',
    );
  }

  // ============================================================
  // MENU
  // ============================================================

  void _openMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF07121F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(25),
        ),
      ),
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 45,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius:
                          BorderRadius.circular(10),
                    ),
                  ),

                  const SizedBox(height: 20),

                  ListTile(
                    leading: const Icon(
                      Icons.bluetooth,
                      color: Colors.cyanAccent,
                    ),
                    title: const Text(
                      'الاتصال بجهاز ESP32',
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const BluetoothScreen(),
                        ),
                      );
                    },
                  ),

                  ListTile(
                    leading: const Icon(
                      Icons.refresh,
                      color: Colors.greenAccent,
                    ),
                    title: const Text(
                      'تصفير القراءة',
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _resetReading();
                    },
                  ),

                  ListTile(
                    leading: const Icon(
                      Icons.save,
                      color: Colors.amberAccent,
                    ),
                    title: const Text(
                      'حفظ القراءة الحالية',
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _saveReading();
                    },
                  ),

                  ListTile(
                    leading: const Icon(
                      Icons.info_outline,
                      color: Colors.white70,
                    ),
                    title: const Text(
                      'حول GeoScan AI',
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _showAbout();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // MORE MENU
  // ============================================================

  void _openMore() {
    showDialog(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF07121F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: const Text(
              'خيارات المسح',
              style: TextStyle(
                color: Colors.white,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogAction(
                  Icons.volume_up,
                  'التنبيه الصوتي',
                  soundEnabled ? 'يعمل' : 'متوقف',
                  _toggleSound,
                ),
                _dialogAction(
                  Icons.vibration,
                  'الاهتزاز',
                  vibrationEnabled ? 'يعمل' : 'متوقف',
                  _toggleVibration,
                ),
                _dialogAction(
                  Icons.delete_sweep,
                  'تصفير البيانات',
                  'مسح القراءة الحالية',
                  _resetReading,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  'إغلاق',
                  style: TextStyle(
                    color: Colors.cyanAccent,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dialogAction(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback action,
  ) {
    return ListTile(
      leading: Icon(
        icon,
        color: Colors.cyanAccent,
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: Colors.white54,
        ),
      ),
      onTap: () {
        Navigator.pop(context);
        action();
      },
    );
  }

  // ============================================================
  // ABOUT
  // ============================================================

  void _showAbout() {
    showDialog(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF07121F),
            title: const Text(
              'GeoScan AI',
              style: TextStyle(
                color: Colors.white,
              ),
            ),
            content: const Text(
              'نظام تحليل إشارات يعمل مع جهاز ESP32 الخارجي عبر Bluetooth.\n\n'
              'القراءة تأتي من الحساس الخارجي، وليست من مستشعر الهاتف.',
              style: TextStyle(
                color: Colors.white70,
                height: 1.6,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  'حسنًا',
                  style: TextStyle(
                    color: Colors.cyanAccent,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

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

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020711),
      body: SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              _buildHeader(),

              Expanded(
                child: SingleChildScrollView(
                  physics:
                      const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    5,
                    16,
                    18,
                  ),
                  child: Column(
                    children: [
                      _buildScanner(),

                      const SizedBox(height: 8),

                      _buildMeter(),

                      const SizedBox(height: 14),

                      _buildAnalysisArea(),

                      const SizedBox(height: 14),

                      _buildLikelyTarget(),

                      const SizedBox(height: 14),

                      _buildStatusCards(),

                      const SizedBox(height: 14),

                      _buildMainButtons(),
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
  // HEADER
  // ============================================================

  Widget _buildHeader() {
    final connected =
        _bluetoothService.isConnected;

    return Container(
      height: 88,
      padding:
          const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF020711),
        border: Border(
          bottom: BorderSide(
            color: Color(0xFF142235),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _openMenu,
            icon: const Icon(
              Icons.menu,
              color: Colors.white,
              size: 32,
            ),
          ),

          Expanded(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) {
                    return const LinearGradient(
                      colors: [
                        Colors.white,
                        Color(0xFF8ED8FF),
                      ],
                    ).createShader(bounds);
                  },
                  child: const Text(
                    'GeoScan AI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
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
                connected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                color: connected
                    ? Colors.cyanAccent
                    : Colors.white30,
                size: 29,
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
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          IconButton(
            onPressed: _openMore,
            icon: const Icon(
              Icons.more_vert,
              color: Colors.white,
              size: 30,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MAIN SCANNER
  // ============================================================

  Widget _buildScanner() {
    return SizedBox(
      height: 345,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _radarController,
            builder: (context, child) {
              return CustomPaint(
                size: const Size(
                  double.infinity,
                  345,
                ),
                painter: _RadarBackgroundPainter(
                  progress: _radarController.value,
                ),
              );
            },
          ),

          CustomPaint(
            size: const Size(
              double.infinity,
              345,
            ),
            painter: _MainGaugePainter(
              value: signal,
              color: signalColor,
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
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 13),

                Text(
                  '${signal.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: signalColor,
                    fontSize: 58,
                    fontWeight: FontWeight.w300,
                  ),
                ),

                const SizedBox(height: 2),

                Row(
                  children: [
                    Icon(
                      Icons.verified_outlined,
                      color: signalColor,
                      size: 21,
                    ),

                    const SizedBox(width: 6),

                    Text(
                      'إشارة $signalStatus',
                      style: TextStyle(
                        color: signalColor,
                        fontSize: 16,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Positioned(
            left: 0,
            top: 30,
            child: _buildSignalCard(),
          ),

          Positioned(
            right: 0,
            top: 30,
            child: _buildDepthCard(),
          ),

          Positioned(
            right: 0,
            top: 178,
            child: _buildStabilityCard(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SIGNAL CARD
  // ============================================================

  Widget _buildSignalCard() {
    return _glassCard(
      width: 190,
      height: 155,
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

          const SizedBox(height: 11),

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
                  final active =
                      signal >= ((index + 1) * 20);

                  return AnimatedContainer(
                    duration: const Duration(
                      milliseconds: 200,
                    ),
                    width: 9,
                    height: 15.0 + index * 8,
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
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: Colors
                                    .greenAccent
                                    .withOpacity(.35),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 7),

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
  // DEPTH
  // ============================================================

  Widget _buildDepthCard() {
    return _glassCard(
      width: 190,
      height: 105,
      child: Column(
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: const [
              Icon(
                Icons.gps_fixed,
                color: Colors.white,
                size: 23,
              ),
              SizedBox(width: 7),
              Text(
                'العمق التقديري',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
            ],
          ),

          const SizedBox(height: 7),

          const Text(
            '-- m',
            style: TextStyle(
              color: Colors.greenAccent,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STABILITY
  // ============================================================

  Widget _buildStabilityCard() {
    return _glassCard(
      width: 190,
      height: 105,
      child: Column(
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: const [
              Icon(
                Icons.graphic_eq,
                color: Colors.white,
                size: 23,
              ),
              SizedBox(width: 7),
              Text(
                'استقرار الإشارة',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
            ],
          ),

          const SizedBox(height: 7),

          Text(
            '${stability.toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassCard({
    required double width,
    required double height,
    required Widget child,
  }) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF07121F)
            .withOpacity(.90),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.cyanAccent.withOpacity(.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.25),
            blurRadius: 14,
          ),
        ],
      ),
      child: child,
    );
  }

  // ============================================================
  // METER
  // ============================================================

  Widget _buildMeter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        10,
        6,
        10,
        12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF06101C),
        borderRadius: BorderRadius.circular(14),
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
                  style:
                      TextStyle(color: Colors.white70)),
              Text('20',
                  style:
                      TextStyle(color: Colors.white70)),
              Text('40',
                  style:
                      TextStyle(color: Colors.white70)),
              Text('60',
                  style:
                      TextStyle(color: Colors.white70)),
              Text('80',
                  style:
                      TextStyle(color: Colors.white70)),
              Text('100',
                  style:
                      TextStyle(color: Colors.white70)),
            ],
          ),

          const SizedBox(height: 5),

          SizedBox(
            height: 27,
            child: Row(
              children: List.generate(
                40,
                (index) {
                  final value = index * 2.5;

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

                  final active = signal >= value;

                  return Expanded(
                    child: AnimatedContainer(
                      duration:
                          const Duration(
                        milliseconds: 120,
                      ),
                      margin:
                          const EdgeInsets.symmetric(
                        horizontal: 1,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? color
                            : color.withOpacity(.12),
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
  // GRAPH + TARGET ANALYSIS
  // ============================================================

  Widget _buildAnalysisArea() {
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
          child: _buildTargetAnalysis(),
        ),
      ],
    );
  }

  Widget _buildGraph() {
    return Container(
      height: 325,
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

          const SizedBox(height: 8),

          Expanded(
            child: CustomPaint(
              painter: _SignalGraphPainter(
                values: history,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetAnalysis() {
    return Container(
      height: 325,
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
            children: [
              const Expanded(
                child: Text(
                  'تحليل الهدف',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              IconButton(
                onPressed: _showAnalysisInfo,
                icon: const Icon(
                  Icons.help_outline,
                  color: Colors.white60,
                ),
                iconSize: 22,
              ),
            ],
          ),

          const SizedBox(height: 3),

          Expanded(
            child: Column(
              children: targets.map(
                (target) {
                  return Expanded(
                    child: _targetRow(target),
                  );
                },
              ).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetRow(String target) {
    final value = _targetValue(target)
        .clamp(0.0, 100.0)
        .toDouble();

    final color = _targetColor(target);

    return Container(
      margin: const EdgeInsets.only(
        bottom: 5,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF081522),
        borderRadius:
            BorderRadius.circular(12),
        border: Border.all(
          color: selectedTarget == target
              ? color.withOpacity(.55)
              : Colors.white10,
        ),
      ),
      child: GestureDetector(
        onTap: () => _selectTarget(target),
        child: Row(
          children: [
            Container(
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                color: color.withOpacity(.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _targetIcon(target),
                color: color,
                size: 22,
              ),
            ),

            const SizedBox(width: 7),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  Text(
                    target,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 5),

                  ClipRRect(
                    borderRadius:
                        BorderRadius.circular(10),
                    child:
                        LinearProgressIndicator(
                      minHeight: 7,
                      value: value / 100,
                      backgroundColor:
                          Colors.white10,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(
                        color,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 7),

            Text(
              '${value.toStringAsFixed(0)}%',
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ANALYSIS INFO
  // ============================================================

  void _showAnalysisInfo() {
    showDialog(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor:
                const Color(0xFF07121F),
            title: const Text(
              'معلومة مهمة',
              style: TextStyle(
                color: Colors.white,
              ),
            ),
            content: const Text(
              'النسب الموجودة في تحليل الهدف حاليًا هي مؤشرات مبنية على قوة الإشارة فقط.\n\n'
              'لا تعتبر إثباتًا أن الهدف ذهب أو نحاس أو فضة حتى نبني خوارزمية تمييز المواد من بيانات الحساس الحقيقية.',
              style: TextStyle(
                color: Colors.white70,
                height: 1.6,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  'حسنًا',
                  style: TextStyle(
                    color: Colors.cyanAccent,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // LIKELY TARGET
  // ============================================================

  Widget _buildLikelyTarget() {
    final value = _targetValue(
      selectedTarget,
    ).clamp(0.0, 100.0).toDouble();

    final color =
        _targetColor(selectedTarget);

    final strong = value >= 75;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF07121F),
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 105,
            height: 105,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(.07),
              border: Border.all(
                color: color.withOpacity(.25),
              ),
            ),
            child: Icon(
              _targetIcon(selectedTarget),
              color: color,
              size: 58,
            ),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'نوع الهدف المحتمل',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  strong
                      ? 'مؤشر قوي: $selectedTarget'
                      : 'مؤشر $selectedTarget',
                  style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 2),

                Row(
                  children: [
                    Text(
                      '${value.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(width: 10),

                    const Text(
                      'مؤشر',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                const Text(
                  'تأكيد النتيجة بالحفر والاختبار الميداني مطلوب.',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STATUS CARDS
  // ============================================================

  Widget _buildStatusCards() {
    return SizedBox(
      height: 112,
      child: Row(
        children: [
          Expanded(
            child: _statusCard(
              Icons.monitor_heart,
              'حالة الجهاز',
              _bluetoothService.isConnected
                  ? 'مستقر'
                  : 'غير متصل',
              _bluetoothService.isConnected
                  ? Colors.greenAccent
                  : Colors.redAccent,
            ),
          ),

          const SizedBox(width: 6),

          Expanded(
            child: _statusCard(
              Icons.gps_fixed,
              'الحساسية',
              '75%',
              Colors.greenAccent,
            ),
          ),

          const SizedBox(width: 6),

          Expanded(
            child: _statusCard(
              Icons.filter_alt_outlined,
              'الفلترة',
              '${filterStrength.toStringAsFixed(0)}%',
              Colors.cyanAccent,
              onTap: _showFilterDialog,
            ),
          ),

          const SizedBox(width: 6),

          Expanded(
            child: _statusCard(
              Icons.volume_up,
              'التنبيه الصوتي',
              soundEnabled ? 'يعمل' : 'متوقف',
              soundEnabled
                  ? Colors.greenAccent
                  : Colors.white54,
              onTap: _toggleSound,
            ),
          ),

          const SizedBox(width: 6),

          Expanded(
            child: _statusCard(
              Icons.vibration,
              'الاهتزاز',
              vibrationEnabled
                  ? 'يعمل'
                  : 'متوقف',
              vibrationEnabled
                  ? Colors.greenAccent
                  : Colors.white54,
              onTap: _toggleVibration,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(
    IconData icon,
    String title,
    String value,
    Color color, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: const Color(0xFF07121F),
          borderRadius:
              BorderRadius.circular(15),
          border: Border.all(
            color: Colors.white10,
          ),
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

            const SizedBox(height: 5),

            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow:
                  TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // FILTER DIALOG - FIXED
  // ============================================================

  void _showFilterDialog() {
    double dialogFilter = filterStrength;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (
              context,
              setDialogState,
            ) {
              return AlertDialog(
                backgroundColor:
                    const Color(0xFF07121F),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(22),
                  side: BorderSide(
                    color: Colors.cyanAccent
                        .withOpacity(.20),
                  ),
                ),
                title: const Text(
                  'قوة الفلترة',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                content: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    const Text(
                      'تحكم في تنعيم الإشارة وتقليل التشويش.',
                      textAlign:
                          TextAlign.center,
                      style: TextStyle(
                        color: Colors.white60,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(
                      height: 20,
                    ),

                    Text(
                      '${dialogFilter.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 34,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    Slider(
                      value: dialogFilter,
                      min: 0,
                      max: 100,
                      divisions: 20,
                      activeColor:
                          Colors.cyanAccent,
                      inactiveColor:
                          Colors.white12,
                      onChanged: (value) {
                        setDialogState(() {
                          dialogFilter = value;
                        });
                      },
                    ),

                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment
                              .spaceBetween,
                      children: const [
                        Text(
                          'سريعة',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'متوازنة',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'قوية',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(
                        dialogContext,
                      );
                    },
                    child: const Text(
                      'إلغاء',
                      style: TextStyle(
                        color: Colors.white60,
                      ),
                    ),
                  ),

                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        filterStrength =
                            dialogFilter;
                      });

                      Navigator.pop(
                     
