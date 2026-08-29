import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/bluetooth_service.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  final BluetoothService _bluetooth = BluetoothService();

  StreamSubscription<double>? _signalSubscription;
  StreamSubscription<String>? _dataSubscription;
  StreamSubscription<bool>? _connectionSubscription;

  late AnimationController _animationController;

  double signal = 0;
  double smoothedSignal = 0;
  double sensitivity = 75;

  bool scanning = false;
  bool connected = false;
  bool audioEnabled = true;
  bool vibrationEnabled = true;

  String filter = 'متوسطة';
  String selectedTarget = 'تلقائي';
  String deviceName = 'غير متصل';

  String lastRawData = '';
  String targetType = 'لا توجد قراءة';
  String targetAnalysis = 'ابدأ المسح للحصول على تحليل';

  int receivedPackets = 0;
  DateTime? lastPacketTime;

  final List<double> signalHistory = <double>[];

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _listenBluetooth();
    _loadSettings();

    connected = _bluetooth.isConnected;
    deviceName = _bluetooth.deviceName;
  }

  void _listenBluetooth() {
    _signalSubscription = _bluetooth.signalStream.listen(
      (value) {
        if (!mounted) return;

        final safe = value.clamp(0.0, 100.0).toDouble();

        setState(() {
          signal = safe;

          if (smoothedSignal == 0) {
            smoothedSignal = safe;
          } else {
            smoothedSignal =
                (smoothedSignal * 0.72) + (safe * 0.28);
          }

          signalHistory.add(smoothedSignal);

          if (signalHistory.length > 80) {
            signalHistory.removeAt(0);
          }

          receivedPackets++;
          lastPacketTime = DateTime.now();

          _updateAnalysis();
        });
      },
    );

    _dataSubscription = _bluetooth.dataStream.listen(
      (raw) {
        if (!mounted) return;

        setState(() {
          lastRawData = raw;
          receivedPackets++;
          lastPacketTime = DateTime.now();
          _parseIncomingData(raw);
        });
      },
    );

    _connectionSubscription =
        _bluetooth.connectionStream.listen(
      (value) {
        if (!mounted) return;

        setState(() {
          connected = value;
          deviceName =
              value ? _bluetooth.deviceName : 'غير متصل';

          if (!value) {
            scanning = false;
          }
        });
      },
    );
  }

  void _parseIncomingData(String raw) {
    final text = raw.trim();

    if (text.isEmpty) return;

    try {
      final decoded = jsonDecode(text);

      if (decoded is Map) {
        final dynamic incoming =
            decoded['target'] ??
                decoded['type'] ??
                decoded['material'];

        if (incoming != null) {
          targetType = incoming.toString();
        }

        final dynamic status = decoded['status'];

        if (status != null &&
            status.toString().isNotEmpty) {
          targetAnalysis = status.toString();
        }

        return;
      }
    } catch (_) {}

    final lower = text.toLowerCase();

    if (lower.contains('gold') ||
        text.contains('ذهب')) {
      targetType = 'ذهب محتمل';
    } else if (lower.contains('silver') ||
        text.contains('فضة')) {
      targetType = 'فضة محتملة';
    } else if (lower.contains('copper') ||
        text.contains('نحاس')) {
      targetType = 'نحاس محتمل';
    } else if (lower.contains('water') ||
        text.contains('ماء')) {
      targetType = 'ماء محتمل';
    }
  }

  void _updateAnalysis() {
    if (smoothedSignal < 20) {
      targetType = 'إشارة ضعيفة';
      targetAnalysis = 'لا توجد إشارة هدف واضحة';
    } else if (smoothedSignal < 40) {
      targetType = 'إشارة منخفضة';
      targetAnalysis = 'قد تكون ضوضاء أو هدف بعيد';
    } else if (smoothedSignal < 60) {
      targetType = 'هدف محتمل';
      targetAnalysis = 'توجد إشارة قابلة للتحليل';
    } else if (smoothedSignal < 80) {
      targetType = 'هدف معدني محتمل';
      targetAnalysis = 'إشارة قوية نسبيًا';
    } else {
      targetType = 'هدف قوي محتمل';
      targetAnalysis = 'إشارة قوية جدًا - افحص المنطقة';
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      sensitivity =
          prefs.getDouble('geoscan_sensitivity') ?? 75;
      filter =
          prefs.getString('geoscan_filter') ?? 'متوسطة';
      audioEnabled =
          prefs.getBool('geoscan_audio') ?? true;
      vibrationEnabled =
          prefs.getBool('geoscan_vibration') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setDouble(
      'geoscan_sensitivity',
      sensitivity,
    );

    await prefs.setString(
      'geoscan_filter',
      filter,
    );

    await prefs.setBool(
      'geoscan_audio',
      audioEnabled,
    );

    await prefs.setBool(
      'geoscan_vibration',
      vibrationEnabled,
    );
  }

  Color get signalColor {
    if (smoothedSignal < 25) {
      return Colors.redAccent;
    }

    if (smoothedSignal < 50) {
      return Colors.orangeAccent;
    }

    if (smoothedSignal < 75) {
      return Colors.amberAccent;
    }

    return Colors.greenAccent;
  }

  String get signalStatus {
    if (!connected) return 'غير متصل';
    if (!scanning) return 'جاهز للمسح';

    if (smoothedSignal < 25) {
      return 'إشارة ضعيفة';
    }

    if (smoothedSignal < 50) {
      return 'إشارة منخفضة';
    }

    if (smoothedSignal < 75) {
      return 'إشارة جيدة';
    }

    return 'إشارة قوية';
  }

  double get approximateDepth {
    if (smoothedSignal < 10) return 0;
    if (smoothedSignal < 25) return 0.3;
    if (smoothedSignal < 45) return 0.6;
    if (smoothedSignal < 65) return 1.0;
    if (smoothedSignal < 85) return 1.5;
    return 2.0;
  }

  String get stabilityText {
    if (signalHistory.length < 5) {
      return '--';
    }

    final recent = signalHistory.length > 15
        ? signalHistory.sublist(
            signalHistory.length - 15,
          )
        : signalHistory;

    final avg =
        recent.reduce((a, b) => a + b) /
            recent.length;

    double variance = 0;

    for (final value in recent) {
      variance += math.pow(value - avg, 2);
    }

    variance /= recent.length;

    final deviation = math.sqrt(variance);

    if (deviation < 3) return 'ممتاز';
    if (deviation < 7) return 'جيد';
    if (deviation < 12) return 'متوسط';

    return 'ضعيف';
  }

  Future<void> _startScanning() async {
    if (!connected) {
      _showMessage('يجب الاتصال بجهاز ESP32 أولاً');
      return;
    }

    final result = await _bluetooth.startScanning();

    if (!mounted) return;

    if (result) {
      setState(() {
        scanning = true;
        receivedPackets = 0;
        lastRawData = '';
      });

      if (vibrationEnabled) {
        HapticFeedback.mediumImpact();
      }

      _showMessage('تم بدء المسح الحقيقي');
    } else {
      _showMessage('تعذر إرسال أمر START إلى ESP32');
    }
  }

  Future<void> _stopScanning() async {
    if (!connected) return;

    final result = await _bluetooth.stopScanning();

    if (!mounted) return;

    setState(() {
      scanning = false;
    });

    if (result) {
      _showMessage('تم إيقاف المسح');
    } else {
      _showMessage('تعذر إرسال أمر STOP');
    }
  }

  Future<void> _calibrate() async {
    if (!connected) {
      _showMessage('الجهاز غير متصل');
      return;
    }

    final result = await _bluetooth.calibrate();

    if (!mounted) return;

    if (result) {
      setState(() {
        signal = 0;
        smoothedSignal = 0;
        signalHistory.clear();
      });

      _showMessage('تم إرسال أمر المعايرة إلى ESP32');

      if (vibrationEnabled) {
        HapticFeedback.mediumImpact();
      }
    } else {
      _showMessage('فشل إرسال المعايرة');
    }
  }

  Future<void> _changeSensitivity(double value) async {
    setState(() {
      sensitivity = value;
    });

    await _bluetooth.setSensitivity(value);
    await _saveSettings();
  }

  Future<void> _changeFilter(String value) async {
    setState(() {
      filter = value;
    });

    await _bluetooth.setFilter(value);
    await _saveSettings();
  }

  Future<void> _toggleAudio(bool value) async {
    setState(() {
      audioEnabled = value;
    });

    await _bluetooth.setAudio(value);
    await _saveSettings();

    if (value) {
      SystemSound.play(SystemSoundType.click);
    }
  }

  Future<void> _toggleVibration(bool value) async {
    setState(() {
      vibrationEnabled = value;
    });

    await _bluetooth.setVibration(value);
    await _saveSettings();

    if (value) {
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _saveReading() async {
    final prefs = await SharedPreferences.getInstance();

    final readings =
        prefs.getStringList('geoscan_readings') ?? [];

    final reading = jsonEncode({
      'time': DateTime.now().toIso8601String(),
      'signal': smoothedSignal,
      'target': targetType,
      'analysis': targetAnalysis,
      'depth': approximateDepth,
      'stability': stabilityText,
      'device': deviceName,
    });

    readings.add(reading);

    if (readings.length > 100) {
      readings.removeAt(0);
    }

    await prefs.setStringList(
      'geoscan_readings',
      readings,
    );

    if (!mounted) return;

    if (vibrationEnabled) {
      HapticFeedback.lightImpact();
    }

    _showMessage('تم حفظ القراءة بنجاح');
  }

  void _openQuickMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF10182B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
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
                const SizedBox(height: 22),
                const Text(
                  'التحكم السريع',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 18),
                _quickAction(
                  icon: Icons.tune_rounded,
                  title: 'المعايرة',
                  subtitle: 'معايرة الحساس',
                  onTap: () {
                    Navigator.pop(context);
                    _calibrate();
                  },
                ),
                _quickAction(
                  icon: Icons.save_rounded,
                  title: 'حفظ القراءة',
                  subtitle: 'حفظ البيانات الحالية',
                  onTap: () {
                    Navigator.pop(context);
                    _saveReading();
                  },
                ),
                _quickAction(
                  icon: Icons.refresh_rounded,
                  title: 'طلب الحالة',
                  subtitle: 'قراءة حالة ESP32',
                  onTap: () async {
                    Navigator.pop(context);
                    await _bluetooth.getStatus();
                    _showMessage(
                      'تم طلب حالة الجهاز',
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: signalColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          icon,
          color: signalColor,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: Colors.white54,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_left_rounded,
        color: Colors.white38,
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            textAlign: TextAlign.center,
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF182238),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  @override
  void dispose() {
    _signalSubscription?.cancel();
    _dataSubscription?.cancel();
    _connectionSubscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060B18),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                physics:
                    const BouncingScrollPhysics(),
                padding:
                    const EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  24,
                ),
                child: Column(
                  children: [
                    _buildScanner(),
                    const SizedBox(height: 18),
                    _buildSignalCards(),
                    const SizedBox(height: 18),
                    _buildSignalBar(),
                    const SizedBox(height: 18),
                    _buildGraphCard(),
                    const SizedBox(height: 18),
                    _buildAnalysisCard(),
                    const SizedBox(height: 18),
                    _buildControlsCard(),
                    const SizedBox(height: 18),
                    _buildDeviceCard(),
                    const SizedBox(height: 18),
                    _buildTechnicalData(),
                    const SizedBox(height: 18),
                    _buildNotice(),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar:
          _buildBottomNavigation(),
      floatingActionButton: FloatingActionButton(
        onPressed: _openQuickMenu,
        backgroundColor: signalColor,
        child: const Icon(
          Icons.bolt_rounded,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        18,
        10,
        18,
        8,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF1DDB83),
                  Color(0xFF00AEEF),
                ],
              ),
              borderRadius:
                  BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.radar_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'GeoScan AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'نظام المسح الذكي',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          _connectionBadge(),
        ],
      ),
    );
  }

  Widget _connectionBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: connected
            ? Colors.greenAccent.withValues(
                alpha: 0.10,
              )
            : Colors.redAccent.withValues(
                alpha: 0.10,
              ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: connected
              ? Colors.greenAccent.withValues(
                  alpha: 0.30,
                )
              : Colors.redAccent.withValues(
                  alpha: 0.30,
                ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: connected
                  ? Colors.greenAccent
                  : Colors.redAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            connected ? 'متصل' : 'غير متصل',
            style: TextStyle(
              color: connected
                  ? Colors.greenAccent
                  : Colors.redAccent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: 20,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1324),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: Colors.white.withValues(
            alpha: 0.06,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: signalColor.withValues(
              alpha: 0.07,
            ),
            blurRadius: 30,
            spreadRadius: 3,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              Icon(
                scanning
                    ? Icons.sensors_rounded
                    : Icons.sensors_off_rounded,
                color: scanning
                    ? signalColor
                    : Colors.white38,
                size: 18,
              ),
              const SizedBox(width: 7),
              Text(
                scanning
                    ? 'LIVE SCAN'
                    : 'READY TO SCAN',
                style: TextStyle(
                  color: scanning
                      ? signalColor
                      : Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 290,
            height: 290,
            child: AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return CustomPaint(
                  painter: GeoScannerPainter(
                    signal: smoothedSignal,
                    scanning: scanning,
                    pulse:
                        _animationController.value,
                    color: signalColor,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Text(
                          smoothedSignal
                              .toStringAsFixed(0),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 62,
                            fontWeight:
                                FontWeight.w900,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          signalStatus,
                          style: TextStyle(
                            color: signalColor,
                            fontSize: 15,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          selectedTarget,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 5),
          Text(
            scanning
                ? 'يتم استقبال بيانات ESP32 لحظيًا'
                : connected
                    ? 'اضغط بدء المسح للبدء'
                    : 'اتصل بجهاز ESP32 أولًا',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalCards() {
    return Row(
      children: [
        Expanded(
          child: _infoCard(
            icon: Icons.bolt_rounded,
            title: 'شدة الإشارة',
            value:
                '${smoothedSignal.toStringAsFixed(0)}%',
            color: signalColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _infoCard(
            icon: Icons.height_rounded,
            title: 'العمق التقريبي',
            value:
                '${approximateDepth.toStringAsFixed(1)} m',
            color: Colors.cyanAccent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _infoCard(
            icon: Icons.graphic_eq_rounded,
            title: 'الاستقرار',
            value: stabilityText,
            color: Colors.amberAccent,
          ),
        ),
      ],
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return _card(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: color,
            size: 21,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalBar() {
    return _card(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          _header(
            'مؤشر الإشارة',
            Icons.bar_chart_rounded,
          ),
          const SizedBox(height: 15),
          SizedBox(
            height: 34,
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.end,
              children: List.generate(
                30,
                (index) {
                  final level =
                      (index + 1) * 100 / 30;
                  final active =
                      smoothedSignal >= level;

                  final barColor =
                      index < 8
                          ? Colors.redAccent
                          : index < 16
                              ? Colors.orangeAccent
                              : index < 23
                                  ? Colors.amberAccent
                                  : Colors.greenAccent;

                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(
                        milliseconds: 150,
                      ),
                      margin:
                          const EdgeInsets.symmetric(
                        horizontal: 1.5,
                      ),
                      height:
                          8 + (index % 5) * 5,
                      decoration: BoxDecoration(
                        color: active
                            ? barColor
                            : Colors.white
                                .withValues(
                                alpha: 0.07,
                              ),
                        borderRadius:
                            BorderRadius.circular(
                          3,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'ضعيفة',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 10,
                ),
              ),
              Text(
                'متوسطة',
                style: TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 10,
                ),
              ),
              Text(
                'قوية',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGraphCard() {
    return _card(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          _header(
            'حركة الإشارة',
            Icons.show_chart_rounded,
          ),
          const SizedBox(height: 15),
          SizedBox(
            height: 145,
            width: double.infinity,
            child: CustomPaint(
              painter: SignalGraphPainter(
                values: signalHistory,
                color: signalColor,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'آخر القراءات',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                ),
              ),
              Text(
                '$receivedPackets حزمة',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisCard() {
    return _card(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          _header(
            'تحليل الهدف',
            Icons.auto_awesome_rounded,
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: signalColor.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius:
                      BorderRadius.circular(18),
                  border: Border.all(
                    color: signalColor.withValues(
                      alpha: 0.25,
                    ),
                  ),
                ),
                child: Icon(
                  Icons.search_rounded,
                  color: signalColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'نوع الهدف المحتمل',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      targetType,
                      style: TextStyle(
                        color: signalColor,
                        fontSize: 18,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: 0.035,
              ),
              borderRadius:
                  BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.analytics_outlined,
                  color: Colors.white54,
                  size: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    targetAnalysis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _targetSelector(),
        ],
      ),
    );
  }

  Widget _targetSelector() {
    const targets = [
      'تلقائي',
      'ذهب',
      'فضة',
      'نحاس',
      'معدن',
      'ماء',
    ];

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: targets.map((target) {
        final selected =
            selectedTarget == target;

        return ChoiceChip(
          label: Text(target),
          selected: selected,
          onSelected: (_) {
            setState(() {
              selectedTarget = target;
            });

            _bluetooth.setTarget(target);
          },
          selectedColor:
              signalColor.withValues(
            alpha: 0.20,
          ),
          backgroundColor:
              const Color(0xFF111A2D),
          side: BorderSide(
            color: selected
                ? signalColor.withValues(
                    alpha: 0.45,
                  )
                : Colors.white12,
          ),
          labelStyle: TextStyle(
            color: selected
                ? signalColor
                : Colors.white60,
            fontSize: 11,
            fontWeight: selected
                ? FontWeight.bold
                : FontWeight.normal,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildControlsCard() {
    return _card(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          _header(
            'التحكم بالمسح',
            Icons.tune_rounded,
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: scanning
                        ? null
                        : _startScanning,
                    icon: const Icon(
                      Icons.play_arrow_rounded,
                    ),
                    label: const Text(
                      'بدء المسح',
                    ),
                    style:
                        FilledButton.styleFrom(
                      backgroundColor:
                          Colors.greenAccent,
                      foregroundColor:
                          Colors.black,
                      disabledBackgroundColor:
                          Colors.white10,
                      disabledForegroundColor:
                          Colors.white30,
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(
                          16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: scanning
                        ? _stopScanning
                        : null,
                    icon: const Icon(
                      Icons.stop_rounded,
                    ),
                    label: const Text(
                      'إيقاف',
                    ),
                    style:
                        OutlinedButton.styleFrom(
                      foregroundColor:
                          Colors.redAccent,
                      disabledForegroundColor:
                          Colors.white24,
                      side: const BorderSide(
                        color: Colors.redAccent,
                      ),
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(
                          16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _saveReading,
              icon: const Icon(
                Icons.save_rounded,
              ),
              label: const Text(
                'حفظ القراءة الحالية',
              ),
              style:
                  OutlinedButton.styleFrom(
                foregroundColor:
                    Colors.cyanAccent,
                side: BorderSide(
                  color: Colors.cyanAccent
                      .withValues(alpha: 0.35),
                ),
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(15),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'الحساسية',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          Slider(
            value: sensitivity,
            min: 0,
            max: 100,
            divisions: 20,
            activeColor: signalColor,
            inactiveColor: Colors.white12,
            label:
                sensitivity.toStringAsFixed(0),
            onChanged: _changeSensitivity,
          ),
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'منخفضة',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                ),
              ),
              Text(
                '${sensitivity.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: signalColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'عالية',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _settingRow(
            icon: Icons.filter_alt_rounded,
            title: 'الفلترة',
            trailing: DropdownButton<String>(
              value: filter,
              dropdownColor:
                  const Color(0xFF111A2D),
              underline: const SizedBox(),
              iconEnabledColor: signalColor,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'منخفضة',
                  child: Text('منخفضة'),
                ),
                DropdownMenuItem(
                  value: 'متوسطة',
                  child: Text('متوسطة'),
                ),
                DropdownMenuItem(
                  value: 'عالية',
                  child: Text('عالية'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  _changeFilter(value);
                }
              },
            ),
          ),
          _settingRow(
            icon: Icons.volume_up_rounded,
            title: 'التنبيه الصوتي',
            trailing: Switch(
              value: audioEnabled,
              activeColor: signalColor,
              onChanged: _toggleAudio,
            ),
          ),
          _settingRow(
            icon: Icons.vibration_rounded,
            title: 'الاهتزاز',
            trailing: Switch(
              value: vibrationEnabled,
              activeColor: signalColor,
              onChanged: _toggleVibration,
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingRow({
    required IconData icon,
    required String title,
    required Widget trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(
          alpha: 0.025,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: Colors.white54,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _buildDeviceCard() {
    return _card(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          _header(
            'حالة الجهاز',
            Icons.memory_rounded,
          ),
          const SizedBox(height: 15),
          _dataRow(
            'الجهاز',
            deviceName,
            connected
                ? Colors.greenAccent
                : Colors.redAccent,
          ),
          _dataRow(
            'الاتصال',
            connected ? 'Bluetooth BLE' : 'غير متصل',
            connected
                ? Colors.greenAccent
                : Colors.redAccent,
          ),
          _dataRow(
            'حالة المسح',
            scanning ? 'نشط' : 'متوقف',
            scanning
                ? Colors.amberAccent
                : Colors.white54,
          ),
          _dataRow(
            'الحزم المستلمة',
            '$receivedPackets',
            Colors.cyanAccent,
          ),
          _dataRow(
            'آخر بيانات',
            lastPacketTime == null
                ? '--'
                : _formatTime(
                    lastPacketTime!,
                  ),
            Colors.white70,
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final h = time.hour
        .toString()
        .padLeft(2, '0');
    final m = time.minute
        .toString()
        .padLeft(2, '0');
    final s = time.second
        .toString()
        .padLeft(2, '0');

    return '$h:$m:$s';
  }

  Widget _buildTechnicalData() {
    return _card(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          _header(
            'البيانات التقنية',
            Icons.code_rounded,
          ),
          const SizedBox(height: 14),
          _dataRow(
            'Signal',
            smoothedSignal.toStringAsFixed(2),
            signalColor,
          ),
          _dataRow(
            'Sensitivity',
            sensitivity.toStringAsFixed(0),
            Colors.cyanAccent,
          ),
          _dataRow(
            'Filter',
            filter,
            Colors.amberAccent,
          ),
          _dataRow(
            'Target',
            selectedTarget,
            Colors.purpleAccent,
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(
                alpha: 0.18,
              ),
              borderRadius:
                  BorderRadius.circular(12),
            ),
            child: Text(
              lastRawData.isEmpty
                  ? 'لا توجد بيانات خام بعد'
                  : lastRawData,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataRow(
    String title,
    String value,
    Color color,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white45,
                fontSize: 11,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amberAccent.withValues(
          alpha: 0.05,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.amberAccent.withValues(
            alpha: 0.14,
          ),
        ),
      ),
      child: const Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: Colors.amberAccent,
            size: 19,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'النتائج المعروضة هي تحليل للإشارة القادمة من الحساس. تحديد نوع المادة والعمق بشكل مؤكد يحتاج إلى اختبار ومعايرة فعلية للجهاز.',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required Widget child,
    EdgeInsetsGeometry padding =
        const EdgeInsets.all(16),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF0C1324),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(
            alpha: 0.055,
          ),
        ),
      ),
      child: child,
    );
  }

  Widget _header(
    String title,
    IconData icon,
  ) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: signalColor.withValues(
              alpha: 0.09,
            ),
            borderRadius:
                BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: signalColor,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF080E1C),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(
              alpha: 0.06,
            ),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 67,
          child: Row(
            children: [
              _navItem(
                Icons.home_rounded,
                'الرئيسية',
                false,
              ),
              _navItem(
                Icons.history_rounded,
                'السجل',
                false,
              ),
              _navItem(
                Icons.radar_rounded,
                'المسح',
                true,
              ),
              _navItem(
                Icons.analytics_rounded,
                'التحليل',
                false,
              ),
              _navItem(
                Icons.settings_rounded,
                'الإعدادات',
                false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(
    IconData icon,
    String label,
    bool active,
  ) {
    final color = active
        ? signalColor
        : Colors.white38;

    return Expanded(
      child: InkWell(
        onTap: () {
          if (active) return;

          _showMessage(
            '$label — التنقل متاح من الشاشة الرئيسية',
          );
        },
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: color,
              size: 21,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: active
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GeoScannerPainter extends CustomPainter {
  final double signal;
  final bool scanning;
  final double pulse;
  final Color color;

  GeoScannerPainter({
    required this.signal,
    required this.scanning,
    required this.pulse,
    required this.color,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final center = Offset(
      size.width / 2,
      size.height / 2,
    );

    final radius =
        math.min(size.width, size.height) / 2 -
            12;

    final backgroundPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF07101F);

    canvas.drawCircle(
      center,
      radius,
      backgroundPaint,
    );

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final rect = Rect.fromCircle(
      center: center,
      radius: radius,
    );

    final colors = [
      Colors.greenAccent,
      Colors.amberAccent,
      Colors.orangeAccent,
      Colors.redAccent,
    ];

    final sweep = math.pi * 2;

    for (int i = 0; i < 4; i++) {
      ringPaint.color = colors[i]
          .withValues(alpha: 0.75);

      canvas.drawArc(
        rect,
        -math.pi / 2 +
            (sweep * i / 4),
        sweep / 4 - 0.035,
        false,
        ringPaint,
      );
    }

    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(
        
