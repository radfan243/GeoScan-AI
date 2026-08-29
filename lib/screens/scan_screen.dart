import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/bluetooth_service.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  final BluetoothService _bluetooth = BluetoothService();

  StreamSubscription<String>? _dataSubscription;
  StreamSubscription<bool>? _connectionSubscription;

  late final AnimationController _pulseController;

  final List<double> signalHistory = <double>[];
  final List<Map<String, dynamic>> savedReadings =
      <Map<String, dynamic>>[];

  double signal = 0;
  double rawSignal = 0;
  double baseline = 0;
  double stability = 0;
  double depth = 0;
  double sensitivity = 75;

  bool scanning = false;
  bool connected = false;
  bool calibrating = false;
  bool audioEnabled = true;
  bool vibrationEnabled = true;

  String filter = 'متوسطة';
  String deviceStatus = 'غير متصل';
  String targetType = 'غير محدد';

  DateTime? lastDataTime;
  int? lastSequence;

  final List<String> targets = <String>[
    'ذهب',
    'معدن',
    'فضة',
    'نحاس',
    'ألماس',
    'ماء',
  ];

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    connected = _bluetooth.isConnected;
    deviceStatus = connected ? 'متصل' : 'غير متصل';

    _dataSubscription = _bluetooth.dataStream.listen(
      _handleIncomingData,
      onError: (_) {},
    );

    _connectionSubscription =
        _bluetooth.connectionStream.listen(
      _handleConnectionState,
      onError: (_) {},
    );
  }

  void _handleConnectionState(bool value) {
    if (!mounted) return;

    setState(() {
      connected = value;

      if (!value) {
        scanning = false;
        calibrating = false;
        deviceStatus = 'غير متصل';
        signal = 0;
        rawSignal = 0;
        baseline = 0;
        stability = 0;
        depth = 0;
        signalHistory.clear();
      } else {
        deviceStatus = 'متصل';
      }
    });
  }

  void _handleIncomingData(String text) {
    if (!mounted) return;

    final String cleaned = text.trim();
    if (cleaned.isEmpty) return;

    Map<String, dynamic> data = <String, dynamic>{};

    try {
      final dynamic decoded = jsonDecode(cleaned);

      if (decoded is Map) {
        data = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      final double? direct =
          double.tryParse(cleaned.replaceAll(',', '.'));

      if (direct != null) {
        data['signal'] = direct;
      }
    }

    if (data.isEmpty) return;

    final double incomingSignal = _readDouble(
      data,
      <String>[
        'signal',
        'value',
        'strength',
        'reading',
      ],
      signal,
    );

    final double incomingRaw = _readDouble(
      data,
      <String>[
        'raw',
        'rawSignal',
      ],
      rawSignal,
    );

    final double incomingBaseline = _readDouble(
      data,
      <String>[
        'baseline',
        'base',
      ],
      baseline,
    );

    final double incomingStability = _readDouble(
      data,
      <String>[
        'stability',
        'stable',
      ],
      stability,
    );

    final double incomingDepth = _readDouble(
      data,
      <String>[
        'depth',
        'distance',
      ],
      depth,
    );

    final double safeSignal =
        incomingSignal.clamp(0.0, 100.0).toDouble();

    final double safeStability =
        incomingStability.clamp(0.0, 100.0).toDouble();

    final double safeDepth =
        incomingDepth.isFinite && incomingDepth >= 0
            ? incomingDepth
            : 0;

    final String status =
        data['status']?.toString().trim() ?? '';

    final String target =
        data['target']?.toString().trim() ?? '';

    final dynamic scanningValue = data['scanning'];

    final bool incomingScanning =
        scanningValue == true ||
        status.toLowerCase() == 'scanning' ||
        status.toLowerCase() == 'scan' ||
        status == 'يمسح' ||
        status == 'مسح';

    final int? sequence = _readInt(
      data,
      <String>[
        'sequence',
        'seq',
      ],
    );

    final double displayedSignal =
        signal == 0
            ? safeSignal
            : signal * 0.70 + safeSignal * 0.30;

    final double finalSignal =
        displayedSignal.clamp(0.0, 100.0).toDouble();

    setState(() {
      signal = finalSignal;
      rawSignal = incomingRaw;
      baseline = incomingBaseline;
      stability = safeStability;
      depth = safeDepth;

      if (status.isNotEmpty) {
        deviceStatus = status;
      } else {
        deviceStatus =
            incomingScanning ? 'يمسح' : 'متصل';
      }

      if (target.isNotEmpty) {
        targetType = target;
      }

      scanning = incomingScanning;
      lastSequence = sequence;
      lastDataTime = DateTime.now();

      if (signalHistory.length >= 80) {
        signalHistory.removeAt(0);
      }

      signalHistory.add(finalSignal);
    });
  }

  double _readDouble(
    Map<String, dynamic> data,
    List<String> keys,
    double fallback,
  ) {
    for (final String key in keys) {
      if (!data.containsKey(key)) continue;

      final dynamic value = data[key];

      if (value is num) {
        return value.toDouble();
      }

      final double? parsed = double.tryParse(
        value.toString().replaceAll(',', '.').trim(),
      );

      if (parsed != null) {
        return parsed;
      }
    }

    return fallback;
  }

  int? _readInt(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final String key in keys) {
      if (!data.containsKey(key)) continue;

      final dynamic value = data[key];

      if (value is int) return value;

      if (value is num) {
        return value.round();
      }

      return int.tryParse(
        value.toString().trim(),
      );
    }

    return null;
  }

  bool get hasRecentData {
    if (lastDataTime == null) return false;

    return DateTime.now()
            .difference(lastDataTime!)
            .inSeconds <
        3;
  }

  Color get signalColor {
    if (signal < 20) return Colors.redAccent;
    if (signal < 40) return Colors.orangeAccent;
    if (signal < 65) return Colors.amberAccent;
    return Colors.greenAccent;
  }

  String get signalStatus {
    if (!connected) return 'غير متصل';
    if (calibrating) return 'جاري المعايرة';

    if (scanning && !hasRecentData) {
      return 'بانتظار البيانات';
    }

    if (!scanning) return 'جاهز للمسح';

    if (signal < 20) return 'إشارة ضعيفة';
    if (signal < 40) return 'إشارة متوسطة';
    if (signal < 65) return 'إشارة جيدة';
    if (signal < 85) return 'إشارة قوية';

    return 'إشارة قوية جدًا';
  }

  String get targetAnalysis {
    if (!connected) return 'الجهاز غير متصل';

    if (scanning && !hasRecentData) {
      return 'بانتظار قراءة ESP32';
    }

    if (signal < 20) return 'لا توجد إشارة واضحة';
    if (signal < 40) return 'تغير ضعيف يحتاج فحصًا';
    if (signal < 65) {
      return 'تغير متوسط يحتاج تحققًا ميدانيًا';
    }
    if (signal < 85) {
      return 'إشارة قوية - افحص الموقع';
    }

    return 'إشارة قوية جدًا - تحقق ميدانيًا';
  }

  String get depthText {
    if (depth <= 0) return '--';
    return '${depth.toStringAsFixed(2)} m';
  }

  Future<void> startScan() async {
    if (!connected) {
      _showMessage('يجب الاتصال بجهاز ESP32 أولًا');
      return;
    }

    if (calibrating) {
      _showMessage('انتظر حتى تنتهي المعايرة');
      return;
    }

    final bool result =
        await _bluetooth.startScan();

    if (!mounted) return;

    if (result) {
      setState(() {
        scanning = true;
        deviceStatus = 'يمسح';
        signalHistory.clear();
        lastDataTime = null;
      });

      _showMessage('بدأ المسح الحقيقي من ESP32');
    } else {
      _showMessage('تعذر إرسال أمر بدء المسح');
    }
  }

  Future<void> stopScan() async {
    if (!connected) {
      _showMessage('الجهاز غير متصل');
      return;
    }

    final bool result =
        await _bluetooth.stopScan();

    if (!mounted) return;

    if (result) {
      setState(() {
        scanning = false;
        deviceStatus = 'متوقف';
      });

      _showMessage('تم إيقاف المسح');
    } else {
      _showMessage('تعذر إرسال أمر الإيقاف');
    }
  }

  Future<void> calibrate() async {
    if (!connected) {
      _showMessage('يجب الاتصال بجهاز ESP32 أولًا');
      return;
    }

    if (scanning) {
      _showMessage('أوقف المسح أولًا');
      return;
    }

    setState(() {
      calibrating = true;
      deviceStatus = 'معايرة';
    });

    final bool result =
        await _bluetooth.calibrate();

    if (!mounted) return;

    setState(() {
      calibrating = false;
      deviceStatus = result ? 'جاهز' : 'متصل';
    });

    _showMessage(
      result
          ? 'تم إرسال أمر المعايرة إلى ESP32'
          : 'تعذر إرسال أمر المعايرة',
    );
  }

  Future<void> changeSensitivity(double value) async {
    if (!connected || calibrating) return;

    final double safe =
        value.clamp(0.0, 100.0).toDouble();

    final bool result =
        await _bluetooth.setSensitivity(safe);

    if (!mounted) return;

    if (result) {
      setState(() {
        sensitivity = safe;
      });
    } else {
      _showMessage('تعذر تغيير الحساسية');
    }
  }

  Future<void> changeFilter(String value) async {
    if (!connected || calibrating) return;

    final bool result =
        await _bluetooth.setFilter(value);

    if (!mounted) return;

    if (result) {
      setState(() {
        filter = value;
      });
    } else {
      _showMessage('تعذر تغيير الفلترة');
    }
  }

  Future<void> toggleAudio(bool value) async {
    if (!connected) return;

    final bool result =
        await _bluetooth.setAudio(value);

    if (!mounted) return;

    if (result) {
      setState(() {
        audioEnabled = value;
      });
    }
  }

  Future<void> toggleVibration(bool value) async {
    if (!connected) return;

    final bool result =
        await _bluetooth.setVibration(value);

    if (!mounted) return;

    if (result) {
      setState(() {
        vibrationEnabled = value;
      });

      if (value) {
        HapticFeedback.mediumImpact();
      }
    }
  }

  Future<void> selectTarget(String target) async {
    final bool result =
        await _bluetooth.setTarget(target);

    if (!mounted) return;

    if (result) {
      setState(() {
        targetType = target;
      });
    }
  }

  void saveReading() {
    if (!connected) {
      _showMessage('الجهاز غير متصل');
      return;
    }

    if (lastDataTime == null) {
      _showMessage('لا توجد قراءة مستلمة من ESP32');
      return;
    }

    savedReadings.add({
      'time': DateTime.now().toIso8601String(),
      'signal': signal,
      'raw': rawSignal,
      'baseline': baseline,
      'stability': stability,
      'depth': depth,
      'target': targetType,
      'status': deviceStatus,
      'sensitivity': sensitivity,
      'filter': filter,
    });

    HapticFeedback.mediumImpact();

    setState(() {});

    _showMessage('تم حفظ القراءة');
  }

  void resetDisplay() {
    setState(() {
      signal = 0;
      rawSignal = 0;
      baseline = 0;
      stability = 0;
      depth = 0;
      signalHistory.clear();
      lastDataTime = null;
    });

    _showMessage('تم تصفير العرض');
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
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF101B2C),
        ),
      );
  }

  void _openQuickMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF08111F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'GeoScan AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                ListTile(
                  leading: const Icon(
                    Icons.sync_rounded,
                    color: Colors.cyanAccent,
                  ),
                  title: const Text(
                    'معايرة الجهاز',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    calibrate();
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.refresh_rounded,
                    color: Colors.amberAccent,
                  ),
                  title: const Text(
                    'تصفير العرض',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    resetDisplay();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _connectionSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050A14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050A14),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'GeoScan AI',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        leading: IconButton(
          onPressed: _openQuickMenu,
          icon: const Icon(
            Icons.tune_rounded,
            color: Colors.cyanAccent,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
            ),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: connected
                      ? Colors.greenAccent.withOpacity(.10)
                      : Colors.redAccent.withOpacity(.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: connected
                        ? Colors.greenAccent.withOpacity(.35)
                        : Colors.redAccent.withOpacity(.35),
                  ),
                ),
                child: Text(
                  connected ? 'BLE' : 'OFF',
                  style: TextStyle(
                    color: connected
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            12,
            8,
            12,
            18,
          ),
          child: Column(
            children: [
              _buildScanner(),
              const SizedBox(height: 12),
              _buildMetrics(),
              const SizedBox(height: 12),
              _buildSignalLevel(),
              const SizedBox(height: 12),
              _buildSignalGraph(),
              const SizedBox(height: 12),
              _buildTargetAnalysis(),
              const SizedBox(height: 12),
              _buildStatusCards(),
              const SizedBox(height: 12),
              _buildSettings(),
              const SizedBox(height: 12),
              _buildControls(),
              const SizedBox(height: 12),
              _buildTechnicalData(),
              const SizedBox(height: 12),
              _buildNotice(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigation(),
    );
  }

  Widget _buildScanner() {
    return _card(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Text(
                    'المسح المباشر',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    signalStatus,
                    style: TextStyle(
                      color: signalColor,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              Icon(
                connected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                color: connected
                    ? Colors.greenAccent
                    : Colors.redAccent,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 330,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (
                    BuildContext context,
                    Widget? child,
                  ) {
                    return CustomPaint(
                      size: const Size(320, 320),
                      painter: GeoScannerPainter(
                        signal: signal,
                        scanning: scanning,
                        pulse: _pulseController.value,
                        color: signalColor,
                      ),
                    );
                  },
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      scanning ? 'LIVE SCAN' : 'READY',
                      style: TextStyle(
                        color: signalColor,
                        fontSize: 12,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      signal.toStringAsFixed(0),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 62,
                        height: .9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      '% SIGNAL',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      targetType,
                      style: TextStyle(
                        color: signalColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetrics() {
    return Row(
      children: [
        Expanded(
          child: _smallMetric(
            title: 'شدة الإشارة',
            value: '${signal.toStringAsFixed(0)}%',
            icon: Icons.signal_cellular_alt,
            color: signalColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _smallMetric(
            title: 'العمق التقريبي',
            value: depthText,
            icon: Icons.height_rounded,
            color: Colors.cyanAccent,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _smallMetric(
            title: 'استقرار الإشارة',
            value: '${stability.toStringAsFixed(0)}%',
            icon: Icons.speed_rounded,
            color: Colors.greenAccent,
          ),
        ),
      ],
    );
  }

  Widget _smallMetric({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return _card(
      height: 82,
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 8,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalLevel() {
    return _card(
      child: Column(
        children: [
          _header(
            'مستوى الإشارة',
            Icons.bar_chart_rounded,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 32,
            child: Row(
              children: List.generate(
                40,
                (int index) {
                  final double level =
                      ((index + 1) / 40) * 100;
                  final bool active = signal >= level;

                  return Expanded(
                    child: AnimatedContainer(
                      duration:
                          const Duration(milliseconds: 120),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 1,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? _meterColor(index)
                            : Colors.white.withOpacity(.06),
                        borderRadius:
                            BorderRadius.circular(4),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 7),
          const Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ضعيفة',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 9,
                ),
              ),
              Text(
                'متوسطة',
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 9,
                ),
              ),
              Text(
                'قوية',
                style: TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 9,
                ),
              ),
              Text(
                'قوية جدًا',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _meterColor(int index) {
    if (index < 10) return Colors.redAccent;
    if (index < 20) return Colors.orangeAccent;
    if (index < 30) return Colors.amberAccent;
    return Colors.greenAccent;
  }

  Widget _buildSignalGraph() {
    return _card(
      child: Column(
        children: [
          _header(
            'حركة الإشارة',
            Icons.show_chart_rounded,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 135,
            width: double.infinity,
            child: CustomPaint(
              painter: SignalGraphPainter(
                values: List<double>.from(signalHistory),
                lineColor: signalColor,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'الآن',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                ),
              ),
              Text(
                '${signalHistory.length} قراءة',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTargetAnalysis() {
    return _card(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          _header(
            'تحليل الهدف',
            Icons.analytics_rounded,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: signalColor.withOpacity(.07),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: signalColor.withOpacity(.18),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: signalColor.withOpacity(.10),
                    border: Border.all(
                      color: signalColor.withOpacity(.25),
                    ),
                  ),
                  child: Icon(
                    Icons.radar_rounded,
                    color: signalColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'التحليل الحالي',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        targetAnalysis,
                        style: TextStyle(
                          color: signalColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'نوع الهدف المحتمل',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: targets.map(
              (String item) {
                final bool selected =
                    targetType == item;

                return ChoiceChip(
                  label: Text(item),
                  selected: selected,
                  onSelected: (_) {
                    selectTarget(item);
                  },
                  selectedColor:
                      Colors.cyanAccent.withOpacity(.16),
                  backgroundColor:
                      Colors.white.withOpacity(.04),
                  labelStyle: TextStyle(
                    color: selected
                        ? Colors.cyanAccent
                        : Colors.white70,
                    fontSize: 10,
                  ),
                  side: BorderSide(
                    color: selected
                        ? Colors.cyanAccent
                        : Colors.white.withOpacity(.12),
                  ),
                );
              },
            ).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCards() {
    return Row(
      children: [
        Expanded(
          child: _statusCard(
            'حالة الجهاز',
            connected ? 'متصل' : 'غير متصل',
            connected
                ? Icons.bluetooth_connected
                : Icons.bluetooth_disabled,
            connected
                ? Colors.greenAccent
                : Colors.redAccent,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: _statusCard(
            'الحساسية',
            '${sensitivity.toStringAsFixed(0)}%',
            Icons.tune_rounded,
            Colors.cyanAccent,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: _statusCard(
            'الفلترة',
            filter,
            Icons.filter_alt_rounded,
            Colors.amberAccent,
          ),
        ),
      ],
    );
  }

  Widget _statusCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return _card(
      height: 100,
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettings() {
    return _card(
      child: Column(
        children: [
          _header(
            'إعدادات المسح',
            Icons.settings_input_component_rounded,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.tune_rounded,
                color: Colors.cyanAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'الحساسية',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                '${sensitivity.toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: sensitivity,
            min: 0,
            max: 100,
            divisions: 100,
            activeColor: Colors.cyanAccent,
            inactiveColor: Colors.white12,
            onChanged: connected
                ? (double value) {
                    setState(() {
                      sensitivity = value;
                    });
                  }
                : null,
            onChangeEnd:
                connected ? changeSensitivity : null,
          ),
          const Divider(color: Colors.white10),
          Row(
            children: [
              const Icon(
                Icons.filter_alt_rounded,
                color: Colors.amberAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'الفلترة',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              DropdownButton<String>(
                value: filter,
                dropdownColor: const Color(0xFF101A2B),
                underline: const SizedBox(),
                iconEnabledColor: Colors.amberAccent,
                style: const TextStyle(
                  color: Colors.amberAccent,
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
                onChanged: connected
                    ? (String? value) {
                        if (value != null) {
                          changeFilter(value);
                        }
                      }
                    : null,
              ),
            ],
          ),
          const Divider(color: Colors.white10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'التنبيه الصوتي',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
            subtitle: const Text(
              'إرسال الإعداد إلى ESP32',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 9,
              ),
            ),
            value: audioEnabled,
            activeColor: Colors.cyanAccent,
            onChanged: connected
                ? toggleAudio
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'الاهتزاز',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
            subtitle: const Text(
              'اهتزاز عند تغير الإشارة',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 9,
              ),
            ),
            value: vibrationEnabled,
            activeColor: Colors.cyanAccent,
            onChanged: connected
                ? toggleVibration
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return _card(
      child: Column(
        children: [
          _header(
            'التحكم',
            Icons.gamepad_rounded,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 55,
                  child: FilledButton.icon(
                    onPressed:
                        connected && !scanning
                            ? startScan
                            : null,
                    icon: const Icon(
                      Icons.play_arrow_rounded,
                    ),
                    label: const Text(
                      'بدء المسح',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          Colors.greenAccent.withOpacity(.12),
                      foregroundColor:
                          Colors.greenAccent,
                      side: const BorderSide(
                        color: Colors.greenAccent,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 55,
                  child: OutlinedButton.icon(
                    onPressed: scanning
                        ? stopScan
                        : null,
                    icon: const Icon(
                      Icons.stop_rounded,
                    ),
                    label: const Text(
                      'إيقاف',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          Colors.redAccent,
                      side: const BorderSide(
                        color: Colors.redAccent,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 55,
                  child: OutlinedButton.icon(
                    onPressed:
                        connected &&
                                lastDataTime != null
                            ? saveReading
                            : null,
                    icon: const Icon(
                      Icons.save_rounded,
                    ),
                    label: const Text(
                      'حفظ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          Colors.cyanAccent,
                      side: const BorderSide(
                        color: Colors.cyanAccent,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(16),
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
            height: 45,
            child: OutlinedButton.icon(
              onPressed:
                  connected && !scanning
                      ? calibrate
                      : null,
              icon: const Icon(
                Icons.sync_rounded,
                size: 19,
              ),
              label: const Text(
                'معايرة الجهاز',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    Colors.amberAccent,
                side: const BorderSide(
                  color: Colors.amberAccent,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTechnicalData() {
    return _card(
      child: Column(
        children: [
          _header(
            'بيانات الجهاز',
            Icons.memory_rounded,
          ),
          const SizedBox(height: 10),
          _infoRow(
            'الجهاز',
            _bluetooth.deviceName,
          ),
          _infoRow(
            'حالة الاتصال',
            connected ? 'متصل' : 'غير متصل',
          ),
          _infoRow(
            'الحالة',
            deviceStatus,
          ),
          _infoRow(
            'Raw Signal',
            rawSignal.toStringAsFixed(2),
          ),
          _infoRow(
            'Baseline',
            baseline.toStringAsFixed(2),
          ),
          _infoRow(
            'Sequence',
            lastSequence?.toString() ?? '--',
          ),
          _infoRow(
            'القراءات المحفوظة',
            savedReadings.length.toString(),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(
    String title,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 5,
      ),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.left,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
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
        color: Colors.amberAccent.withOpacity(.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.amberAccent.withOpacity(.14),
        ),
      ),
      child: const Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: Colors.amberAccent,
            size: 20,
          ),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'النتيجة المعروضة هي تحليل لإشارة الحساس القادمة من ESP32. تحديد نوع المادة وعمقها بدقة يحتاج إلى معايرة واختبارات ميدانية فعلية.',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required Widget child,
    double? height,
    EdgeInsetsGeometry padding =
        const EdgeInsets.all(14),
  }) {
    return Container(
      width: double.infinity,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF08111F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(.07),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
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
        Icon(
          icon,
          color: Colors.cyanAccent,
          size: 19,
        ),
        const SizedBox(width: 7),
        Text(
          title,
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
      decoration: const BoxDecoration(
        color: Color(0xFF050B15),
        border: Border(
          top: BorderSide(
            color: Colors.white10,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 65,
          child: Row(
            children: [
              _navItem(
                Icons.home_rounded,
                'الرئيسية',
                false,
                () => _showMessage('الرئيسية'),
              ),
              _navItem(
                Icons.history_rounded,
                'السجل',
                false,
                () => _showMessage(
                  'السجل - ${savedReadings.length} قراءة',
                ),
              ),
              _navItem(
                Icons.radar_rounded,
                'المسح',
                true,
                () {},
              ),
              _navItem(
                Icons.analytics_rounded,
                'التحليل',
                false,
                () => _showMessage('التحليل'),
              ),
              _navItem(
                Icons.settings_rounded,
                'الإعدادات',
                false,
                () => _showMessage('الإعدادات'),
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
    bool selected,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected
                  ? Colors.cyanAccent
                  : Colors.white38,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? Colors.cyanAccent
                    : Colors.white38,
                fontSize: 8,
                fontWeight: selected
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

// ============================================================
// الدائرة الرئيسية للماسح
// ============================================================

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
  void paint(Canvas canvas, Size size) {
    final Offset center =
        Offset(size.width / 2, size.height / 2);

    final double radius =
        math.min(size.width, size.height) * .43;

    final Paint backgroundPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF06101C);

    canvas.drawCircle(
      center,
      radius,
      backgroundPaint,
    );

    final Paint outerGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color.withOpacity(.20);

    canvas.drawCircle(
      center,
      radius + 7,
      outerGlow,
    );

    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final List<Color> colors = <Color>[
      Colors.redAccent,
      Colors.orangeAccent,
      Colors.amberAccent,
      Colors.greenAccent,
    ];

    for (int i = 0; i < 4; i++) {
      ring.color = colors[i].withOpacity(.75);

      final double start =
          -math.pi / 2 +
          i * (math.pi * 2 / 4);

      canvas.drawArc(
        Rect.fromCircle(
          center: center,
          radius: radius,
        ),
        start,
        math.pi * 2 / 4 - .08,
        false,
        ring,
      );
    }

    final Paint gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withOpacity(.07);

    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(
        center,
        radius * i / 3,
        gridPaint,
      );
    }

    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      gridPaint,
    );

    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      gridPaint,
    );

    if (scanning) {
      final double scanRadius =
          radius * (.25 + pulse * .65);

      final Paint scanPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withOpacity(
          .35 * (1 - pulse) + .10,
        );

      canvas.drawCircle(
        center,
        scanRadius,
        scanPaint,
      );
    }

    final Paint centerPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(.85);

    canvas.drawCircle(
      center,
      4,
      centerPaint,
    );

    final Paint needlePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;

    final double angle =
        -math.pi / 2 +
        (signal / 100) * math.pi * 2;

    canvas.drawLine(
      center,
      Offset(
        center.dx + math.cos(angle) * radius * .72,
        center.dy + math.sin(angle) * radius * .72,
      ),
      needlePaint,
    );
