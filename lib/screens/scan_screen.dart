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

      if (value) {
        deviceStatus = 'متصل';
      } else {
        scanning = false;
        calibrating = false;
        deviceStatus = 'غير متصل';
        signal = 0;
        rawSignal = 0;
        baseline = 0;
        stability = 0;
        depth = 0;
        signalHistory.clear();
        lastDataTime = null;
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
      final double? direct = double.tryParse(
        cleaned.replaceAll(',', '.'),
      );

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

    final dynamic scanValue = data['scanning'];

    final bool incomingScanning =
        scanValue == true ||
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

      if (value is int) {
        return value;
      }

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

    if (scanning && !hasRecentData) {
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

    if (scanning && !hasRecentData) {
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
      _showMessage(
        'يجب الاتصال بجهاز ESP32 أولًا',
      );
      return;
    }

    if (calibrating) {
      _showMessage(
        'انتظر حتى تنتهي المعايرة',
      );
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

      _showMessage(
        'بدأ المسح الحقيقي من ESP32',
      );
    } else {
      _showMessage(
        'تعذر إرسال أمر بدء المسح',
      );
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
      _showMessage(
        'تعذر إرسال أمر الإيقاف',
      );
    }
  }

  Future<void> calibrate() async {
    if (!connected) {
      _showMessage(
        'يجب الاتصال بجهاز ESP32 أولًا',
      );
      return;
    }

    if (scanning) {
      _showMessage(
        'أوقف المسح أولًا',
      );
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
      deviceStatus =
          result ? 'جاهز' : 'متصل';
    });

    _showMessage(
      result
          ? 'تم إرسال أمر المعايرة إلى ESP32'
          : 'تعذر إرسال أمر المعايرة',
    );
  }

  Future<void> changeSensitivity(
    double value,
  ) async {
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
      _showMessage(
        'تعذر تغيير الحساسية',
      );
    }
  }

  Future<void> changeFilter(
    String value,
  ) async {
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
      _showMessage(
        'تعذر تغيير الفلترة',
      );
    }
  }

  Future<void> toggleAudio(
    bool value,
  ) async {
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

  Future<void> toggleVibration(
    bool value,
  ) async {
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

  Future<void> selectTarget(
    String target,
  ) async {
    if (!connected) {
      _showMessage(
        'اتصل بجهاز ESP32 أولًا',
      );
      return;
    }

    final bool result =
        await _bluetooth.setTarget(target);

    if (!mounted) return;

    if (result) {
      setState(() {
        targetType = target;
      });

      _showMessage(
        'تم اختيار الهدف: $target',
      );
    } else {
      _showMessage(
        'تعذر إرسال نوع الهدف',
      );
    }
  }

  void saveReading() {
    if (!connected) {
      _showMessage(
        'الجهاز غير متصل',
      );
      return;
    }

    if (lastDataTime == null) {
      _showMessage(
        'لا توجد قراءة مستلمة من ESP32',
      );
      return;
    }

    savedReadings.add(
      <String, dynamic>{
        'time':
            DateTime.now().toIso8601String(),
        'signal': signal,
        'raw': rawSignal,
        'baseline': baseline,
        'stability': stability,
        'depth': depth,
        'target': targetType,
        'status': deviceStatus,
        'sensitivity': sensitivity,
        'filter': filter,
      },
    );

    HapticFeedback.mediumImpact();

    setState(() {});

    _showMessage(
      'تم حفظ القراءة',
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
      lastDataTime = null;
    });

    _showMessage(
      'تم تصفير العرض',
    );
  }

  void _showMessage(
    String message,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            textAlign: TextAlign.center,
          ),
          duration:
              const Duration(seconds: 2),
          behavior:
              SnackBarBehavior.floating,
          backgroundColor:
              const Color(0xFF101B2C),
        ),
      );
  }

  void _openQuickMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor:
          const Color(0xFF08111F),
      shape:
          const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.all(18),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                const Text(
                  'GeoScan AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 15,
                ),
                ListTile(
                  leading:
                      const Icon(
                    Icons.sync_rounded,
                    color:
                        Colors.cyanAccent,
                  ),
                  title:
                      const Text(
                    'معايرة الجهاز',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(
                      context,
                    );
                    calibrate();
                  },
                ),
                ListTile(
                  leading:
                      const Icon(
                    Icons.refresh_rounded,
                    color:
                        Colors.amberAccent,
                  ),
                  title:
                      const Text(
                    'تصفير العرض',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(
                      context,
                    );
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
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          const Color(0xFF050A14),
      appBar: AppBar(
        backgroundColor:
            const Color(0xFF050A14),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'GeoScan AI',
          style: TextStyle(
            color: Colors.white,
            fontWeight:
                FontWeight.w900,
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
            padding:
                const EdgeInsets.symmetric(
              horizontal: 12,
            ),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                decoration:
                    BoxDecoration(
                  color: connected
                      ? Colors.greenAccent
                          .withOpacity(.10)
                      : Colors.redAccent
                          .withOpacity(.10),
                  borderRadius:
                      BorderRadius.circular(
                    20,
                  ),
                  border:
                      Border.all(
                    color: connected
                        ? Colors.greenAccent
                            .withOpacity(.35)
                        : Colors.redAccent
                            .withOpacity(.35),
                  ),
                ),
                child: Text(
                  connected
                      ? 'BLE'
                      : 'OFF',
                  style: TextStyle(
                    color: connected
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    fontSize: 10,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics:
              const BouncingScrollPhysics(),
          padding:
              const EdgeInsets.fromLTRB(
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
      bottomNavigationBar:
          _buildBottomNavigation(),
    );
  }

  Widget _buildScanner() {
    return _card(
      padding:
          const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment
                    .spaceBetween,
            children: [
              Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  const Text(
                    'المسح المباشر',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 3,
                  ),
                  Text(
                    signalStatus,
                    style: TextStyle(
                      color:
                          signalColor,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              Icon(
                connected
                    ? Icons
                        .bluetooth_connected
                    : Icons
                        .bluetooth_disabled,
                color: connected
                    ? Colors.greenAccent
                    : Colors.redAccent,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 330,
            width: double.infinity,
            child: Stack(
              alignment:
                  Alignment.center,
              children: [
                AnimatedBuilder(
                  animation:
                      _pulseController,
                  builder:
                      (
                    BuildContext context,
                    Widget? child,
                  ) {
                    return CustomPaint(
                      size:
                          const Size(
                        320,
                        320,
                      ),
                      painter:
                          GeoScannerPainter(
                        signal: signal,
                        scanning:
                            scanning,
                        pulse:
                            _pulseController
                                .value,
                        color:
                            signalColor,
                      ),
                    );
                  },
                ),
                Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    Text(
                      scanning
                          ? 'LIVE SCAN'
                          : 'READY',
                      style:
                          TextStyle(
                        color:
                            signalColor,
                        fontSize: 12,
                        letterSpacing: 2,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Text(
                      signal
                          .toStringAsFixed(
                        0,
                      ),
                      style:
                          const TextStyle(
                        color:
                            Colors.white,
                        fontSize: 62,
                        height: .9,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),
                    const SizedBox(
                      height: 4,
                    ),
                    const Text(
                      '% SIGNAL',
                      style:
                          TextStyle(
                        color:
                            Colors.white38,
                        fontSize: 10,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    Text(
                      targetType,
                      style:
                          TextStyle(
                        color:
                            signalColor,
                        fontSize: 12,
                        fontWeight:
                            FontWeight.bold,
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
            value:
                '${signal.toStringAsFixed(0)}%',
            icon:
                Icons.signal_cellular_alt,
            color: signalColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _smallMetric(
            title: 'العمق التقريبي',
            value: depthText,
            icon:
                Icons.height_rounded,
            color:
                Colors.cyanAccent,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _smallMetric(
            title: 'استقرار الإشارة',
            value:
                '${stability.toStringAsFixed(0)}%',
            icon:
                Icons.speed_rounded,
            color:
                Colors.greenAccent,
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
      height: 84,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 5,
        vertical: 8,
      ),
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
            title,
            textAlign:
                TextAlign.center,
            style:
                const TextStyle(
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
              fontWeight:
                  FontWeight.w900,
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
              children:
                  List.generate(
                40,
                (int index) {
                  final double level =
                      ((index + 1) /
                              40) *
                          100;

                  final bool active =
                      signal >= level;

                  return Expanded(
                    child:
                        AnimatedContainer(
                      duration:
                          const Duration(
                        milliseconds: 120,
                      ),
                      margin:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 1,
                      ),
                      decoration:
                          BoxDecoration(
                        color: active
                            ? _meterColor(
                                index,
                              )
                            : Colors
                                .white
                                .withOpacity(
                                .06,
                              ),
                        borderRadius:
                            BorderRadius
                                .circular(
                          4,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _meterColor(int index) {
    if (index < 8) {
      return Colors.redAccent;
    }

    if (index < 18) {
      return Colors.orangeAccent;
    }

    if (index < 28) {
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
            height: 150,
            width: double.infinity,
            child: CustomPaint(
              painter:
                  SignalGraphPainter(
                values: signalHistory,
                lineColor:
                    signalColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetAnalysis() {
    return _card(
      child: Column(
        children: [
          _header(
            'تحليل الهدف',
            Icons.radar_rounded,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration:
                    BoxDecoration(
                  shape:
                      BoxShape.circle,
                  color: signalColor
                      .withOpacity(.10),
                  border:
                      Border.all(
                    color: signalColor
                        .withOpacity(
                      .35,
                    ),
                  ),
                ),
                child: Icon(
                  _targetIcon(
                    targetType,
                  ),
                  color:
                      signalColor,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      targetType,
                      style:
                          const TextStyle(
                        color:
                            Colors.white,
                        fontSize: 16,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 5,
                    ),
                    Text(
                      targetAnalysis,
                      style:
                          const TextStyle(
                        color:
                            Colors.white60,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children:
                targets.map(
              (String target) {
                final bool selected =
                    targetType ==
                        target;

                return ChoiceChip(
                  label:
                      Text(target),
                  selected:
                      selected,
                  onSelected:
                      (_) {
                    selectTarget(
                      target,
                    );
                  },
                  labelStyle:
                      TextStyle(
                    color: selected
                        ? Colors.black
                        : Colors.white70,
                    fontSize: 11,
                    fontWeight:
                        FontWeight.bold,
                  ),
                  selectedColor:
                      signalColor,
                  backgroundColor:
                      const Color(
                    0xFF101A2A,
                  ),
                  side:
                      BorderSide(
                    color: selected
                        ? signalColor
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

  IconData _targetIcon(
    String target,
  ) {
    switch (target) {
      case 'ذهب':
        return Icons.diamond;
      case 'فضة':
        return Icons.circle_outlined;
      case 'نحاس':
        return Icons.bolt;
      case 'ماء':
        return Icons.water_drop;
      case 'ألماس':
        return Icons.diamond_outlined;
      case 'معدن':
        return Icons.hardware;
      default:
        return Icons.search;
    }
  }

  Widget _buildStatusCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _statusCard(
                title: 'حالة الجهاز',
                value:
                    connected
                        ? 'متصل'
                        : 'غير متصل',
                icon:
                    Icons.memory_rounded,
                color:
                    connected
                        ? Colors.greenAccent
                        : Colors.redAccent,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statusCard(
                title: 'حالة المسح',
                value:
                    scanning
                        ? 'مباشر'
                        : 'متوقف',
                icon:
                    Icons.radar,
                color:
                    scanning
                        ? Colors.cyanAccent
                        : Colors.white54,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _statusCard(
                title: 'آخر حزمة',
                value:
                    lastSequence
                        ?.toString() ??
                    '--',
                icon:
                    Icons.numbers,
                color:
                    Colors.amberAccent,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statusCard(
                title: 'البيانات',
                value:
                    hasRecentData
                        ? 'LIVE'
                        : '--',
                icon:
                    Icons.data_usage,
                color:
                    hasRecentData
                        ? Colors.greenAccent
                        : Colors.white54,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statusCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return _card(
      height: 88,
      padding:
          const EdgeInsets.all(10),
      child: Row(
        children: [
          Icon(
            icon,
            color: color,
            size: 25,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                Text(
                  title,
                  style:
                      const TextStyle(
                    color:
                        Colors.white54,
                    fontSize: 9,
                  ),
                ),
                const SizedBox(
                  height: 4,
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow:
                      TextOverflow
                          .ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
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

  Widget _buildSettings() {
    return _card(
      child: Column(
        children: [
          _header(
            'إعدادات الجهاز',
            Icons.tune_rounded,
          ),
          const SizedBox(height: 8),
          _settingTile(
            icon:
                Icons.sensors_rounded,
            title: 'الحساسية',
            trailing: Text(
              '${sensitivity.toStringAsFixed(0)}%',
              style:
                  const TextStyle(
                color:
                    Colors.cyanAccent,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
          Slider(
            value: sensitivity,
            min: 0,
            max: 100,
            divisions: 100,
            activeColor:
                Colors.cyanAccent,
            inactiveColor:
                Colors.white12,
            onChanged:
                connected &&
                        !calibrating
                    ? changeSensitivity
                    : null,
          ),
          const Divider(
            color: Colors.white10,
            height: 10,
          ),
          _settingTile(
            icon:
                Icons.filter_alt_rounded,
            title: 'الفلترة',
            trailing:
                DropdownButton<String>(
              value: filter,
              dropdownColor:
                  const Color(
                0xFF101A2A,
              ),
              underline:
                  const SizedBox(),
              style:
                  const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'منخفضة',
                  child:
                      Text('منخفضة'),
                ),
                DropdownMenuItem(
                  value: 'متوسطة',
                  child:
                      Text('متوسطة'),
                ),
                DropdownMenuItem(
                  value: 'عالية',
                  child:
                      Text('عالية'),
                ),
              ],
              onChanged:
                  connected
                      ? (String? value) {
                          if (value !=
                              null) {
                            changeFilter(
                              value,
                            );
                          }
                        }
                      : null,
            ),
          ),
          const Divider(
            color: Colors.white10,
            height: 20,
          ),
          SwitchListTile(
            contentPadding:
                EdgeInsets.zero,
            secondary:
                const Icon(
              Icons.volume_up_rounded,
              color:
                  Colors.amberAccent,
            ),
            title:
                const Text(
              'التنبيه الصوتي',
              style:
                  TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
            value: audioEnabled,
            activeColor:
                Colors.amberAccent,
            onChanged:
                connected
                    ? toggleAudio
                    : null,
          ),
          SwitchListTile(
            contentPadding:
                EdgeInsets.zero,
            secondary:
                const Icon(
              Icons.vibration_rounded,
              color:
                  Colors.purpleAccent,
            ),
            title:
                const Text(
              'الاهتزاز',
              style:
                  TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
            value:
                vibrationEnabled,
            activeColor:
                Colors.purpleAccent,
            onChanged:
                connected
                    ? toggleVibration
                    : null,
          ),
        ],
      ),
    );
  }

  Widget _settingTile({
    required IconData icon,
    required String title,
    required Widget trailing,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color:
              Colors.white54,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style:
                const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ),
        trailing,
      ],
    );
  }

  Widget _buildControls() {
    return _card(
      child: Column(
        children: [
          _header(
            'التحكم بالمسح',
            Icons.play_circle_outline,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child:
                      FilledButton.icon(
                    onPressed:
                        scanning
                            ? null
                            : startScan,
                    icon:
                        const Icon(
                      Icons.play_arrow_rounded,
                    ),
                    label:
                        const Text(
                      'بدء المسح',
                    ),
                    style:
                        FilledButton
                            .styleFrom(
                      backgroundColor:
                          Colors.green,
                      disabledBackgroundColor:
                          Colors.white10,
                      foregroundColor:
                          Colors.white,
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius
                                .circular(
                          14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child:
                      FilledButton.icon(
                    onPressed:
                        scanning
                            ? stopScan
                            : null,
                    icon:
                        const Icon(
                      Icons.stop_rounded,
                    ),
                    label:
                        const Text(
                      'إيقاف',
                    ),
                    style:
                        FilledButton
                            .styleFrom(
                      backgroundColor:
                          Colors.redAccent,
                      disabledBackgroundColor:
                          Colors.white10,
                      foregroundColor:
                          Colors.white,
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius
                                .circular(
                          14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      connected
                          ? saveReading
                          : null,
                  icon:
                      const Icon(
                    Icons.save_rounded,
                  ),
                  label:
                      const Text(
                    'حفظ القراءة',
                  ),
                  style:
                      OutlinedButton
                          .styleFrom(
                    foregroundColor:
                        Colors.cyanAccent,
                    side:
                        const BorderSide(
                      color:
                          Colors.cyanAccent,
                    ),
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius
                              .circular(
                        14,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      resetDisplay,
                  icon:
                      const Icon(
                    Icons.refresh_rounded,
                  ),
                  label:
                      const Text(
                    'تصفير',
                  ),
                  style:
                      OutlinedButton
                          .styleFrom(
                    foregroundColor:
                        Colors.white70,
                    side:
                        const BorderSide(
                      color:
                          Colors.white24,
                    ),
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius
                              .circular(
                        14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
            'البيانات التقنية',
            Icons.memory_rounded,
          ),
          const SizedBox(height: 10),
          _technicalRow(
            'Raw Signal',
            rawSignal.toStringAsFixed(2),
          ),
          _technicalRow(
            'Baseline',
            baseline.toStringAsFixed(2),
          ),
          _technicalRow(
            'Stability',
            '${stability.toStringAsFixed(1)}%',
          ),
          _technicalRow(
            'Depth',
            depthText,
          ),
          _technicalRow(
            'Sensitivity',
            sensitivity
                .toStringAsFixed(0),
          ),
          _technicalRow(
            'Filter',
            filter,
          ),
          _technicalRow(
            'Target',
            targetType,
          ),
        ],
      ),
    );
  }

  Widget _technicalRow(
    String title,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 6,
      ),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment
                .spaceBetween,
        children: [
          Text(
            title,
            style:
                const TextStyle(
              color: Colors.white54,
              fontSize: 10,
            ),
          ),
          Text(
            value,
            style:
                const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotice() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(14),
      decoration:
          BoxDecoration(
        color:
            Colors.amberAccent
                .withOpacity(.06),
        borderRadius:
            BorderRadius.circular(
          14,
        ),
        border:
            Border.all(
          color:
              Colors.amberAccent
                  .withOpacity(.18),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color:
                Colors.amberAccent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'القراءة المعروضة تعتمد على البيانات الحقيقية القادمة من ESP32 عبر Bluetooth. تحديد نوع الهدف والعمق يحتاج إلى معايرة واختبارات ميدانية.',
              style:
                  const TextStyle(
                color:
                    Colors.white60,
                fontSize: 10,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      decoration:
          const BoxDecoration(
        color:
            Color(0xFF07101D),
        border:
            Border(
          top:
              BorderSide(
            color:
                Colors.white10,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              _navItem(
                Icons.home_rounded,
                'الرئيسية',
                false,
              ),
              _navItem(
                Icons.history_rounded,
                'السجلات',
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
    bool selected,
  ) {
    return Expanded(
      child: InkWell(
        onTap: () {
          if (selected) {
            return;
          }

          _showMessage(
            '$label - سيتم ربط الشاشة لاحقًا',
          );
        },
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center
