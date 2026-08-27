import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/bluetooth_service.dart';
import '../services/signal_processor.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  final BluetoothService _bluetoothService = BluetoothService();
  final SignalProcessor _signalProcessor = SignalProcessor();

  StreamSubscription<String>? _dataSubscription;
  StreamSubscription<bool>? _connectionSubscription;

  late AnimationController _pulseController;

  double signal = 0.0;
  double rawSignal = 0.0;
  double stability = 0.0;
  double peak = 0.0;

  int rawAdc = 0;

  bool scanning = false;
  bool soundEnabled = true;
  bool vibrationEnabled = true;

  String selectedTarget = 'ذهب';

  final List<double> history = [];

  final List<String> targets = const [
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

    _listenToEsp32Data();
    _listenToConnection();
  }

  void _listenToEsp32Data() {
    _dataSubscription = _bluetoothService.dataStream.listen(
      (data) {
        if (!mounted) return;

        try {
          final decoded = jsonDecode(data);

          if (decoded is! Map<String, dynamic>) {
            return;
          }

          final result = _signalProcessor.process(
            signal: decoded['signal'],
            raw: decoded['raw'],
            stability: decoded['stability'],
          );

          final processed =
              result.processedSignal.clamp(0.0, 100.0).toDouble();

          setState(() {
            signal = processed;
            rawSignal = result.rawSignal;
            stability = result.stability;
            rawAdc = result.rawAdc;
            peak = result.peak;

            history.add(processed);

            if (history.length > SignalProcessor.historySize) {
              history.removeAt(0);
            }
          });

          _handleAlert(result);
        } catch (_) {
          // تجاهل أي packet غير صالح.
        }
      },
      onError: (_) {},
    );
  }

  void _listenToConnection() {
    _connectionSubscription =
        _bluetoothService.connectionStream.listen((connected) {
      if (!mounted) return;

      if (!connected) {
        setState(() {
          scanning = false;
        });
      }
    });
  }

  void _handleAlert(SignalResult result) {
    if (!scanning) return;

    if (result.hasStrongChange) {
      if (soundEnabled) {
        SystemSound.play(SystemSoundType.alert);
      }

      if (vibrationEnabled) {
        HapticFeedback.mediumImpact();
      }
    }
  }

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

  String get targetStatus {
    if (signal >= 75 && stability >= 70) {
      return 'إشارة قوية ومستقرة';
    }

    if (signal >= 50) {
      return 'إشارة مرتفعة';
    }

    return 'لا توجد إشارة كافية';
  }

  Future<void> _startScan() async {
    if (scanning) return;

    if (!_bluetoothService.isConnected) {
      _showMessage('يجب الاتصال بجهاز ESP32 أولاً');
      return;
    }

    final success = await _bluetoothService.startScanning();

    if (!mounted) return;

    if (success) {
      _signalProcessor.reset();

      setState(() {
        scanning = true;
        signal = 0;
        rawSignal = 0;
        stability = 0;
        peak = 0;
        rawAdc = 0;
        history.clear();
      });

      _showMessage('بدأ المسح الحقيقي من ESP32');
    } else {
      _showMessage('تعذر إرسال أمر بدء المسح إلى ESP32');
    }
  }

  Future<void> _stopScan() async {
    if (!scanning) return;

    final success = await _bluetoothService.stopScanning();

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

  Future<void> _selectTarget(String target) async {
    setState(() {
      selectedTarget = target;
    });

    if (_bluetoothService.isConnected) {
      final success = await _bluetoothService.setTarget(target);

      if (!success && mounted) {
        _showMessage('تعذر إرسال الهدف إلى ESP32');
      }
    }
  }

  void _resetCalibrationView() {
    _signalProcessor.reset();

    setState(() {
      signal = 0;
      rawSignal = 0;
      stability = 0;
      peak = 0;
      rawAdc = 0;
      history.clear();
    });

    _showMessage('تم تصفير قراءة التطبيق');
  }

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

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _connectionSubscription?.cancel();

    _signalProcessor.reset();
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

                      const SizedBox(height: 14),

                      _buildRawDataCard(),
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

  Widget _buildTopBar() {
    final connected = _bluetoothService.isConnected;

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
            onPressed: () {
              _showMessage(
                'استخدم شاشة Bluetooth لإدارة اتصال ESP32',
              );
            },
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
            onPressed: _resetCalibrationView,
            icon: const Icon(
              Icons.refresh,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

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
              title: 'قوة الإشارة',
              value:
                  '${signal.toStringAsFixed(1)}%',
              icon: Icons.radar,
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
              color: signalColor,
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
                          ? signalColor
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
            style: TextStyle(
              color: signalColor,
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
              Text(
                '0',
                style:
                    TextStyle(color: Colors.white70),
              ),
              Text(
                '20',
                style:
                    TextStyle(color: Colors.white70),
              ),
              Text(
                '40',
                style:
                    TextStyle(color: Colors.white70),
              ),
              Text(
                '60',
                style:
                    TextStyle(color: Colors.white70),
              ),
              Text(
                '80',
                style:
                    TextStyle(color: Colors.white70),
              ),
              Text(
                '100',
                style:
                    TextStyle(color: Colors.white70),
              ),
            ],
          ),

          const SizedBox(height: 6),

          SizedBox(
            height: 24,
            child: Row(
              children: List.generate(
                40,
                (index) {
                  final value = index * 2.5;

                  final Color color;

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
          const Text(
            'اختيار الهدف',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          ...targets.map(
            (target) {
              return _targetButton(target);
            },
          ),
        ],
      ),
    );
  }

  Widget _targetButton(String target) {
    final selected = selectedTarget == target;

    final color = target == 'ذهب'
        ? Colors.amberAccent
        : target == 'نحاس'
            ? Colors.orange
            : target == 'فضة'
                ? Colors.lightBlueAccent
                : target == 'حديد'
                    ? Colors.redAccent
                    : Colors.cyanAccent;

    return Expanded(
      child: GestureDetector(
        onTap: () => _selectTarget(target),
        child: Container(
          margin:
              const EdgeInsets.only(bottom: 6),
          padding:
              const EdgeInsets.symmetric(
            horizontal: 8,
          ),
          decoration: BoxDecoration(
            color: selected
                ? color.withOpacity(.12)
                : const Color(0xFF091522),
            borderRadius:
                BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? color
                  : Colors.white10,
            ),
          ),
          child: Row(
            children: [
              Icon(
                target == 'ماء'
                    ? Icons.water_drop
                    : Icons.circle,
                size: 20,
                color: color,
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Text(
                  target,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),

              if (selected)
                Icon(
                  Icons.check_circle,
                  color: color,
                  size: 19,
                ),
            ],
          ),
        ),
      ),
    );
  }

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
            'حالة الهدف المحدد',
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
                  color:
                      Colors.amber.withOpacity(.08),
                ),
                child: Icon(
                  selectedTarget == 'ماء'
                      ? Icons.water_drop
                      : Icons.diamond,
                  size: 58,
                  color: selectedTarget == 'ماء'
                      ? Colors.cyanAccent
                      : Colors.amber,
                ),
              ),

              const SizedBox(width: 18),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedTarget,
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      targetStatus,
                      style: TextStyle(
                        color: signalColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      '${signal.toStringAsFixed(0)}% قوة الإشارة',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      '${stability.toStringAsFixed(0)}% استقرار',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(height: 5),

                    const Text(
                      'هذه قراءة إشارة وليست إثباتًا لنوع المعدن.',
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
        ],
      ),
    );
  }

  Widget _buildControlCards() {
    return Row(
      children: [
        Expanded(
          child: _controlCard(
            icon: Icons.monitor_heart,
            title: 'حالة الجهاز',
            value: _bluetoothService.isConnected
                ? 'متصل'
                : 'غير متصل',
            color: _bluetoothService.isConnected
                ? Colors.greenAccent
                : Colors.redAccent,
          ),
        ),

        const SizedBox(width: 7),

        Expanded(
          child: _controlCard(
            icon: Icons.speed,
            title: 'الإشارة',
            value:
                '${signal.toStringAsFixed(0)}%',
            color: signalColor,
          ),
        ),

        const SizedBox(width: 7),

        Expanded(
          child: _controlCard(
            icon: Icons.volume_up,
            title: 'الصوت',
            value:
                soundEnabled ? 'يعمل' : 'متوقف',
            color: soundEnabled
                ? Colors.greenAccent
                : Colors.white54,
            onTap: () {
              setState(() {
                soundEnabled = !soundEnabled;
              });
            },
          ),
        ),

        const SizedBox(width: 7),

        Expanded(
          child: _controlCard(
            icon: Icons.vibration,
            title: 'الاهتزاز',
            value:
                vibrationEnabled ? 'يعمل' : 'متوقف',
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
              style:
                  ElevatedButton.styleFrom(
                backgroundColor:
                    const Color(0xFF071B12),
                foregroundColor:
                    Colors.greenAccent,
                side: const BorderSide(
                  color: Colors.greenAccent,
                ),
                shape:
                    RoundedRectangleBorder(
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
              style:
                  ElevatedButton.styleFrom(
                backgroundColor:
                    const Color(0xFF241015),
                foregroundColor:
                    Colors.redAccent,
                side: const BorderSide(
                  color: Colors.redAccent,
                ),
                shape:
                    RoundedRectangleBorder(
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
              onPressed: _resetCalibrationView,
              icon: const Icon(
                Icons.refresh,
              ),
              label: const Text(
                'تصفير',
                style: TextStyle(
                  fontSize: 15,
                ),
              ),
              style:
                  OutlinedButton.styleFrom(
                foregroundColor:
                    Colors.white70,
                side: const BorderSide(
                  color: Colors.white24,
                ),
                shape:
                    RoundedRectangleBorder(
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

  Widget _buildRawDataCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF07121F),
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white10,
        ),
      ),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceAround,
        children: [
          _rawItem(
            'RAW ADC',
            rawAdc.toString(),
          ),
          _rawItem(
            'RAW',
            '${rawSignal.toStringAsFixed(1)}%',
          ),
          _rawItem(
            'PEAK',
            '${peak.toStringAsFixed(1)}%',
          ),
          _rawItem(
            'استقرار',
            '${stability.toStringAsFixed(0)}%',
          ),
        ],
      ),
    );
  }

  Widget _rawItem(
    String title,
    String value,
  ) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

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
    return GestureDetector(
      onTap: () {
        _showMessage(
          active
              ? 'أنت الآن في شاشة المسح'
              : 'سيتم ربط $title في المرحلة التالية',
        );
      },
      child: Column(
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
      ),
    );
  }
}

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
        math.min(
          size.width * .40,
          size.height * .55,
        );

    const startAngle = math.pi * 1.08;
    const sweepAngle = math.pi * .84;

    final rect = Rect.fromCircle(
      center: center,
      radius: radius,
    );

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

    const segments = 36;

    for (int i = 0;
        i < segments;
        i++) {
      final ratio = i / segments;

      final Color segmentColor;

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

    final valueRatio =
        value.clamp(0.0, 100.0) / 100;

    final angle =
        startAngle +
            sweepAngle * valueRatio;

    final needleLength =
        radius * .72;

    final needleEnd = Offset(
      center.dx +
          math.cos(angle) *
              needleLength,
      center.dy +
          math.sin(angle) *
              needleLength,
    );

    final needlePaint = Paint()
      ..color = color
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      center,
      needleEnd,
      needlePaint,
    );

    final centerPaint = Paint()
      ..color = Colors.white;

    canvas.drawCircle(
      center,
      10,
      centerPaint,
    );

    final innerPaint = Paint()
      ..color = color;

    canvas.drawCircle(
      center,
      5,
      innerPaint,
    );
  }

  @override
  bool shouldRepaint(
    _GaugePainter oldDelegate,
  ) {
    return oldDelegate.value != value ||
        oldDelegate.color != color;
  }
}

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

    for (int i = 1; i < 5; i++) {
      final y =
          size.height * i / 5;

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
          size.width *
              i /
              (values.length - 1);

      final normalized =
          values[i].clamp(0.0, 100.0) /
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

    final linePaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
      path,
      linePaint,
    );
  }

  @override
  bool shouldRepaint(
    _GraphPainter oldDelegate,
  ) {
    return true;
  }
}
