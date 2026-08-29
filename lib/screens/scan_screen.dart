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

  double signal = 0.0;
  double rawSignal = 0.0;
  double baseline = 0.0;
  double stability = 0.0;
  double depth = 0.0;
  double sensitivity = 75.0;

  bool scanning = false;
  bool connected = false;
  bool calibrating = false;
  bool audioEnabled = true;
  bool vibrationEnabled = true;

  String filter = 'متوسطة';
  String deviceStatus = 'غير متصل';
  String targetType = 'غير محدد';

  int? lastSequence;
  DateTime? lastDataTime;

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

    _listenToBluetooth();

    connected = _bluetooth.isConnected;

    if (connected) {
      deviceStatus = 'متصل';
    }
  }

  void _listenToBluetooth() {
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

    if (cleaned.isEmpty) {
      return;
    }

    Map<String, dynamic> data = <String, dynamic>{};

    try {
      final dynamic decoded = jsonDecode(cleaned);

      if (decoded is Map) {
        data = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // قد تصل قراءة رقمية مباشرة بدل JSON.
      final double? directValue = double.tryParse(
        cleaned.replaceAll(',', '.'),
      );

      if (directValue != null) {
        data['signal'] = directValue;
      }
    }

    if (data.isEmpty) {
      return;
    }

    final double incomingSignal = _readDouble(
      data,
      const [
        'signal',
        'value',
        'strength',
        'reading',
      ],
      signal,
    );

    final double incomingRaw = _readDouble(
      data,
      const [
        'raw',
        'rawSignal',
      ],
      rawSignal,
    );

    final double incomingBaseline = _readDouble(
      data,
      const [
        'baseline',
        'base',
      ],
      baseline,
    );

    final double incomingStability = _readDouble(
      data,
      const [
        'stability',
        'stable',
      ],
      stability,
    );

    final double incomingDepth = _readDouble(
      data,
      const [
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
            : 0.0;

    final dynamic statusValue = data['status'];

    final String incomingStatus =
        statusValue?.toString().trim() ?? '';

    final dynamic targetValue = data['target'];

    final String incomingTarget =
        targetValue?.toString().trim() ?? '';

    final dynamic scanningValue = data['scanning'];

    final bool incomingScanning =
        scanningValue == true ||
        incomingStatus.toLowerCase() == 'scanning' ||
        incomingStatus.toLowerCase() == 'scan' ||
        incomingStatus == 'يمسح' ||
        incomingStatus == 'مسح';

    final int? sequence = _readInt(
      data,
      const [
        'sequence',
        'seq',
      ],
    );

    final double displayedSignal = signal == 0
        ? safeSignal
        : (signal * 0.70) + (safeSignal * 0.30);

    final double safeDisplayedSignal =
        displayedSignal.clamp(0.0, 100.0).toDouble();

    setState(() {
      signal = safeDisplayedSignal;
      rawSignal = incomingRaw;
      baseline = incomingBaseline;
      stability = safeStability;
      depth = safeDepth;

      if (incomingStatus.isNotEmpty) {
        deviceStatus = incomingStatus;
      } else {
        deviceStatus =
            incomingScanning ? 'يمسح' : 'متصل';
      }

      if (incomingTarget.isNotEmpty) {
        targetType = incomingTarget;
      }

      scanning = incomingScanning;
      lastSequence = sequence;
      lastDataTime = DateTime.now();

      if (signalHistory.length >= 80) {
        signalHistory.removeAt(0);
      }

      signalHistory.add(safeDisplayedSignal);
    });
  }

  double _readDouble(
    Map<String, dynamic> data,
    List<String> keys,
    double fallback,
  ) {
    for (final String key in keys) {
      if (!data.containsKey(key)) {
        continue;
      }

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
      if (!data.containsKey(key)) {
        continue;
      }

      final dynamic value = data[key];

      if (value is int) {
        return value;
      }

      if (value is num) {
        return value.round();
      }

      return int.tryParse(value.toString().trim());
    }

    return null;
  }

  bool get hasRecentData {
    if (lastDataTime == null) {
      return false;
    }

    return DateTime.now()
            .difference(lastDataTime!)
            .inSeconds <
        3;
  }

  Color get signalColor {
    if (signal < 20) {
      return Colors.redAccent;
    }

    if (signal < 40) {
      return Colors.orangeAccent;
    }

    if (signal < 65) {
      return Colors.amberAccent;
    }

    return Colors.greenAccent;
  }

  String get signalStatus {
    if (!connected) {
      return 'غير متصل';
    }

    if (calibrating) {
      return 'جاري المعايرة';
    }

    if (!hasRecentData && scanning) {
      return 'بانتظار البيانات';
    }

    if (!scanning) {
      return 'جاهز للمسح';
    }

    if (signal < 20) {
      return 'إشارة ضعيفة';
    }

    if (signal < 40) {
      return 'إشارة متوسطة';
    }

    if (signal < 65) {
      return 'إشارة جيدة';
    }

    if (signal < 85) {
      return 'إشارة قوية';
    }

    return 'إشارة قوية جدًا';
  }

  String get targetAnalysis {
    if (!connected) {
      return 'الجهاز غير متصل';
    }

    if (!hasRecentData && scanning) {
      return 'بانتظار قراءة ESP32';
    }

    if (signal < 20) {
      return 'لا توجد إشارة واضحة';
    }

    if (signal < 40) {
      return 'تغير ضعيف يحتاج فحصًا';
    }

    if (signal < 65) {
      return 'تغير متوسط يحتاج تحققًا ميدانيًا';
    }

    if (signal < 85) {
      return 'إشارة قوية - افحص الموقع';
    }

    return 'إشارة قوية جدًا - تحقق ميدانيًا';
  }

  String get depthText {
    if (depth <= 0) {
      return '--';
    }

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

    final bool result = await _bluetooth.startScan();

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

    final bool result = await _bluetooth.stopScan();

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

    final bool result = await _bluetooth.calibrate();

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
    if (!connected || calibrating) {
      return;
    }

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
    if (!connected || calibrating) {
      return;
    }

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
    if (!connected) {
      return;
    }

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
    if (!connected) {
      return;
    }

    final bool result =
        await _bluetooth.setVibration(value);

    if (!mounted) return;

    if (result) {
      setState(() {
        vibrationEnabled = value;
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

    final Map<String, dynamic> reading =
        <String, dynamic>{
      'signal': signal,
      'raw': rawSignal,
      'baseline': baseline,
      'stability': stability,
      'depth': depth,
      'target': targetType,
      'status': deviceStatus,
      'sensitivity': sensitivity,
      'filter': filter,
      'sequence': lastSequence,
      'savedAt':
          DateTime.now().millisecondsSinceEpoch,
    };

    setState(() {
      savedReadings.add(reading);
    });

    HapticFeedback.mediumImpact();

    _showMessage(
      'تم حفظ القراءة رقم ${savedReadings.length}',
    );
  }

  void resetDisplay() {
    setState(() {
      signal = 0;
      rawSignal = 0;
      baseline = 0;
      stability = 0;
      depth = 0;
      signalHistory.clear();
    });

    _showMessage('تم تصفير العرض');
  }

  void selectTarget(String value) {
    setState(() {
      targetType = value;
    });

    _showMessage('نوع الفحص: $value');
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            textDirection: TextDirection.rtl,
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF030712),
        appBar: _buildAppBar(),
        body: SafeArea(
          child: SingleChildScrollView(
            physics:
                const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              12,
              8,
              12,
              24,
            ),
            child: Column(
              children: [
                _buildHeroScanner(),
                const SizedBox(height: 10),
                _buildMainMetrics(),
                const SizedBox(height: 10),
                _buildSignalLevel(),
                const SizedBox(height: 10),
                _buildSignalGraph(),
                const SizedBox(height: 10),
                _buildTargetAnalysis(),
                const SizedBox(height: 10),
                _buildStatusCards(),
                const SizedBox(height: 10),
                _buildSettings(),
                const SizedBox(height: 10),
                _buildControls(),
                const SizedBox(height: 10),
                _buildTechnicalData(),
                const SizedBox(height: 10),
                _buildNotice(),
              ],
            ),
          ),
        ),
        bottomNavigationBar:
            _buildBottomNavigation(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF030712),
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        tooltip: 'خيارات المسح',
        icon: const Icon(
          Icons.tune_rounded,
          color: Colors.white,
        ),
        onPressed: _openQuickMenu,
      ),
      title: Column(
        children: [
          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
              children: [
                TextSpan(
                  text: 'Geo',
                  style: TextStyle(
                    color: Colors.white,
                  ),
                ),
                TextSpan(
                  text: 'Scan',
                  style: TextStyle(
                    color: Colors.cyanAccent,
                  ),
                ),
                TextSpan(
                  text: ' AI',
                  style: TextStyle(
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const Text(
            'LIVE DETECTION',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 9,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding:
              const EdgeInsets.only(left: 12),
          child: Row(
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
              const SizedBox(width: 5),
              Text(
                connected ? 'متصل' : 'غير متصل',
                style: TextStyle(
                  color: connected
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroScanner() {
    final Color color = signalColor;

    return Container(
      height: 350,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF091526),
            Color(0xFF050C17),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(.08),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(.07),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: GeoScannerPainter(
                    value: signal,
                    pulse: _pulseController.value,
                    scanning: scanning,
                  ),
                ),
              ),
              Column(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (scanning)
                        Container(
                          width: 8,
                          height: 8,
                          margin:
                              const EdgeInsets.only(
                            left: 7,
                          ),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    color.withOpacity(
                                  .8,
                                ),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      const Text(
                        'LIVE SCAN',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${signal.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: color,
                      fontSize: 58,
                      height: .95,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(
                          color:
                              color.withOpacity(.4),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color:
                          color.withOpacity(.08),
                      borderRadius:
                          BorderRadius.circular(30),
                      border: Border.all(
                        color:
                            color.withOpacity(.25),
                      ),
                    ),
                    child: Text(
                      signalStatus,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 16,
                right: 16,
                child: _liveBadge(),
              ),
              Positioned(
                bottom: 14,
                left: 18,
                child: Text(
                  scanning
                      ? 'استقبال مباشر من ESP32'
                      : 'جاهز لاستقبال البيانات',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _liveBadge() {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white12,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            connected
                ? Icons.bluetooth_connected
                : Icons.bluetooth_disabled,
            size: 14,
            color: connected
                ? Colors.greenAccent
                : Colors.redAccent,
          ),
          const SizedBox(width: 5),
          Text(
            connected ? 'ESP32' : 'OFFLINE',
            style: TextStyle(
              color: connected
                  ? Colors.greenAccent
                  : Colors.redAccent,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainMetrics() {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: _largeMetric(
            title: 'شدة الإشارة',
            value:
                '${signal.toStringAsFixed(1)}%',
            subtitle: signalStatus,
            icon:
                Icons.signal_cellular_alt_rounded,
            color: signalColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: Column(
            children: [
              _smallMetric(
                title: 'العمق التقريبي',
                value: depthText,
                icon: Icons.layers_rounded,
                color: Colors.greenAccent,
              ),
              const SizedBox(height: 8),
              _smallMetric(
                title: 'استقرار الإشارة',
                value:
                    '${stability.toStringAsFixed(0)}%',
                icon: Icons.graphic_eq_rounded,
                color: Colors.cyanAccent,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _largeMetric({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return _card(
      height: 158,
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
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
              color: Colors.white60,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallMetric({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return _card(
      height: 75,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: color,
            size: 24,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 9,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),
              ],
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
            height: 36,
            child: Row(
              children: List.generate(
                40,
                (index) {
                  final double level =
                      ((index + 1) / 40) * 100;

                  final bool active =
                      signal >= level;

                  final Color barColor =
                      _meterColor(index);

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
                            ? barColor
                            : Colors.white
                                .withOpacity(.06),
                        borderRadius:
                            BorderRadius.circular(4),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: barColor
                                      .withOpacity(
                                    .25,
                                  ),
                                  blurRadius: 5,
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
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: const [
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
    if (index < 10) {
      return Colors.redAccent;
    }

    if (index < 20) {
      return Colors.orangeAccent;
    }

    if (index < 30) {
      return Colors.amberAccent;
    }

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
            height: 130,
            width: double.infinity,
            child: CustomPaint(
              painter: SignalGraphPainter(
                values:
                    List<double>.from(signalHistory),
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
            padding:
                const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(18),
              color:
                  signalColor.withOpacity(.07),
              border: Border.all(
                color:
                    signalColor.withOpacity(.18),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        signalColor.withOpacity(.12),
                  ),
                  child: Icon(
                    Icons.radar_rounded,
                    color: signalColor,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'النتيجة الحالية',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        targetAnalysis,
                        style: TextStyle(
                          color: signalColor,
                          fontWeight:
                              FontWeight.bold,
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
                      Colors.cyanAccent
                          .withOpacity(.16),
                  backgroundColor:
                      Colors.white
                          .withOpacity(.04),
                  labelStyle: TextStyle(
                    color: selected
                        ? Colors.cyanAccent
                        : Colors.white70,
                    fontSize: 10,
                  ),
                  side: BorderSide(
                    color: selected
                        ? Colors.cyanAccent
                        : Colors.white12,
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
      height: 105,
      padding:
          const EdgeInsets.all(9),
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: color,
            size: 21,
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
          const SizedBox(height: 8),
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
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
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
            inactiveColor:
                Colors.white12,
            onChanged: connected
                ? (double value) {
                    setState(() {
                      sensitivity = value;
                    });
                  }
                : null,
            onChangeEnd: connected
                ? changeSensitivity
                : null,
          ),
          const Divider(
            color: Colors.white10,
          ),
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
                dropdownColor:
                    const Color(0xFF101A2B),
                underline: const SizedBox(),
                iconEnabledColor:
                    Colors.amberAccent,
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
          const Divider(
            color: Colors.white10,
          ),
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
            secondary: const Icon(
              Icons.volume_up_rounded,
              color: Colors.cyanAccent,
            ),
            value: audioEnabled,
            onChanged:
                connected ? toggleAudio : null,
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
              'إرسال الإعداد إلى ESP32',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 9,
              ),
            ),
            secondary: const Icon(
              Icons.vibration_rounded,
              color: Colors.cyanAccent,
            ),
            value: vibrationEnabled,
            onChanged:
                connected
                    ? toggleVibration
                    : null,
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 55,
                child: FilledButton.icon(
                  onPressed:
                      connected &&
                              !scanning &&
                              !calibrating
                          ? startScan
                          : null,
                  icon: const Icon(
                    Icons.play_arrow_rounded,
                  ),
                  label: const Text(
                    'بدء المسح',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  style:
                      FilledButton.styleFrom(
                    backgroundColor:
                        Colors.greenAccent
                            .withOpacity(.12),
                    foregroundColor:
                        Colors.greenAccent,
                    side:
                        const BorderSide(
                      color:
                          Colors.greenAccent,
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
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 55,
                child: OutlinedButton.icon(
                  onPressed:
                      scanning ? stopScan : null,
                  icon: const Icon(
                    Icons.stop_rounded,
                  ),
                  label: const Text(
                    'إيقاف',
                    style: TextStyle(
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
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 55,
                child: OutlinedButton.icon(
                  onPressed:
                      connected
                          ? saveReading
                          : null,
                  icon: const Icon(
                    Icons.save_rounded,
                  ),
                  label: const Text(
                    'حفظ',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  style:
                      OutlinedButton.styleFrom(
                    foregroundColor:
                        Colors.amberAccent,
                    side:
                        const BorderSide(
                      color:
                          Colors.amberAccent,
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
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    connected &&
                            !scanning &&
                            !calibrating
                        ? calibrate
                        : null,
                icon: const Icon(
                  Icons.sync_rounded,
                  size: 18,
                ),
                label: const Text(
                  'معايرة الجهاز',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: resetDisplay,
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 18,
                ),
                label: const Text(
                  'تصفير العرض',
                ),
              ),
            ),
          ],
        ),
      ],
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
      padding:
          const EdgeInsets.symmetric(
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
        color: Colors.amberAccent
            .withOpacity(.05),
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color: Colors.amberAccent
              .withOpacity(.14),
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
        borderRadius:
            BorderRadius.circular(20),
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
                () => _showMessage(
                  'الرئيسية',
                ),
              ),
              _navItem(
                Icons.history_rounded,
                'السجل
