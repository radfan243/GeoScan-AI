import 'dart:async';
import 'dart:convert';
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
  // ============================================================
  // GeoScan AI
  // شاشة المسح الرئيسية
  //
  // البيانات تأتي من ESP32 عبر BluetoothService الحقيقي.
  // لا توجد إشارات تجريبية أو أرقام مولدة من التطبيق.
  // ============================================================

  final BluetoothService _bluetooth = BluetoothService();

  StreamSubscription<String>? _dataSubscription;
  StreamSubscription<double>? _signalSubscription;
  StreamSubscription<bool>? _connectionSubscription;

  final List<double> signalHistory = [];

  double signal = 0.0;
  double rawSignal = 0.0;
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

  DateTime? _lastSignalTime;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _listenToBluetooth();

    if (_bluetooth.isConnected) {
      connected = true;
      deviceStatus = 'متصل';
    }
  }

  // ============================================================
  // BLUETOOTH LISTENERS
  // ============================================================

  void _listenToBluetooth() {
    _dataSubscription = _bluetooth.dataStream.listen(
      _handleDeviceData,
      onError: (error) {
        debugPrint(
          'GeoScan AI data error: $error',
        );
      },
    );

    _signalSubscription = _bluetooth.signalStream.listen(
      (value) {
        if (!mounted) return;

        _updateSignal(value);
      },
      onError: (error) {
        debugPrint(
          'GeoScan AI signal error: $error',
        );
      },
    );

    _connectionSubscription =
        _bluetooth.connectionStream.listen(
      _handleConnectionState,
      onError: (error) {
        debugPrint(
          'GeoScan AI connection error: $error',
        );
      },
    );
  }

  // ============================================================
  // ESP32 DATA
  // ============================================================

  void _handleDeviceData(String rawData) {
    if (!mounted || rawData.trim().isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(rawData);

      if (decoded is! Map) {
        return;
      }

      final data =
          Map<String, dynamic>.from(decoded);

      final incomingSignal =
          data.containsKey('signal')
              ? _toDouble(data['signal'])
              : signal;

      final incomingRaw =
          data.containsKey('raw')
              ? _toDouble(data['raw'])
              : incomingSignal;

      final incomingStability =
          data.containsKey('stability')
              ? _toDouble(data['stability'])
              : stability;

      final incomingDepth =
          data.containsKey('depth')
              ? _toDouble(data['depth'])
              : depth;

      final incomingStatus =
          data.containsKey('status')
              ? data['status'].toString()
              : deviceStatus;

      final incomingTarget =
          data.containsKey('target')
              ? data['target'].toString()
              : targetType;

      bool incomingScanning = scanning;

      if (data.containsKey('scanning')) {
        final value = data['scanning'];

        if (value is bool) {
          incomingScanning = value;
        } else {
          final text =
              value.toString().toLowerCase();

          incomingScanning =
              text == 'true' ||
              text == '1' ||
              text == 'scan' ||
              text == 'scanning';
        }
      }

      final safeSignal =
          incomingSignal
              .clamp(0.0, 100.0)
              .toDouble();

      final safeRaw =
          incomingRaw
              .clamp(0.0, 100.0)
              .toDouble();

      final safeStability =
          incomingStability
              .clamp(0.0, 100.0)
              .toDouble();

      final safeDepth =
          incomingDepth < 0
              ? 0.0
              : incomingDepth.toDouble();

      setState(() {
        signal = signal == 0.0
            ? safeSignal
            : ((signal * 0.72) +
                    (safeSignal * 0.28))
                .clamp(0.0, 100.0)
                .toDouble();

        rawSignal = safeRaw;
        stability = safeStability;
        depth = safeDepth;

        scanning = incomingScanning;
        deviceStatus = incomingStatus;

        if (incomingTarget.isNotEmpty) {
          targetType = incomingTarget;
        }

        signalHistory.add(signal);

        if (signalHistory.length > 80) {
          signalHistory.removeAt(0);
        }

        _lastSignalTime =
            DateTime.now();
      });

      _updatePulse();
    } catch (_) {
      // بعض إصدارات ESP32 قد ترسل قيمة رقمية فقط.
      final match = RegExp(
        r'[-+]?\d*\.?\d+',
      ).firstMatch(rawData);

      if (match != null) {
        final value = double.tryParse(
          match.group(0)!,
        );

        if (value != null) {
          _updateSignal(value);
        }
      }
    }
  }

  void _updateSignal(double value) {
    if (!mounted) return;

    final safe =
        value.clamp(0.0, 100.0).toDouble();

    final smoothed = signal == 0.0
        ? safe
        : ((signal * 0.72) +
                (safe * 0.28))
            .clamp(0.0, 100.0)
            .toDouble();

    setState(() {
      rawSignal = safe;
      signal = smoothed;

      signalHistory.add(smoothed);

      if (signalHistory.length > 80) {
        signalHistory.removeAt(0);
      }

      _lastSignalTime =
          DateTime.now();
    });

    _updatePulse();
  }

  void _updatePulse() {
    if (scanning && connected) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(
          reverse: true,
        );
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
      }
    }
  }

  void _handleConnectionState(bool value) {
    if (!mounted) return;

    setState(() {
      connected = value;

      if (!connected) {
        scanning = false;
        calibrating = false;

        deviceStatus = 'غير متصل';

        signal = 0.0;
        rawSignal = 0.0;
        stability = 0.0;
        depth = 0.0;

        signalHistory.clear();
      } else {
        deviceStatus = 'متصل';
      }
    });

    _updatePulse();
  }

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value
              .toString()
              .replaceAll(',', '.'),
        ) ??
        0.0;
  }

  // ============================================================
  // COMMANDS
  // ============================================================

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

    final success =
        await _bluetooth.startScanning();

    if (!mounted) return;

    if (!success) {
      _showMessage(
        'تعذر بدء المسح من ESP32',
      );
      return;
    }

    setState(() {
      scanning = true;
      deviceStatus = 'يمسح الآن';
      signalHistory.clear();
    });

    _updatePulse();
  }

  Future<void> stopScan() async {
    if (!connected) return;

    final success =
        await _bluetooth.stopScanning();

    if (!mounted) return;

    if (!success) {
      _showMessage(
        'تعذر إيقاف المسح من ESP32',
      );
      return;
    }

    setState(() {
      scanning = false;
      deviceStatus = 'متوقف';
    });

    _updatePulse();
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
      deviceStatus = 'جاري المعايرة';
      signalHistory.clear();
    });

    final success =
        await _bluetooth.calibrate();

    if (!mounted) return;

    setState(() {
      calibrating = false;
      deviceStatus =
          success ? 'جاهز' : 'متصل';
    });

    _showMessage(
      success
          ? 'تم إرسال أمر المعايرة إلى ESP32'
          : 'تعذر إرسال أمر المعايرة',
    );
  }

  Future<void> changeSensitivity(
    double value,
  ) async {
    if (!connected) {
      _showMessage(
        'الجهاز غير متصل',
      );
      return;
    }

    final safe =
        value.clamp(0.0, 100.0).toDouble();

    final success =
        await _bluetooth.setSensitivity(
      safe,
    );

    if (!mounted) return;

    if (success) {
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
    if (!connected) {
      _showMessage(
        'الجهاز غير متصل',
      );
      return;
    }

    final success =
        await _bluetooth.setFilter(
      value,
    );

    if (!mounted) return;

    if (success) {
      setState(() {
        filter = value;
      });
    } else {
      _showMessage(
        'تعذر تغيير الفلترة',
      );
    }
  }

  Future<void> toggleAudio() async {
    if (!connected) {
      _showMessage(
        'الجهاز غير متصل',
      );
      return;
    }

    final newValue = !audioEnabled;

    final success =
        await _bluetooth.setAudio(
      newValue,
    );

    if (!mounted) return;

    if (success) {
      setState(() {
        audioEnabled = newValue;
      });
    } else {
      _showMessage(
        'تعذر تغيير الصوت',
      );
    }
  }

  Future<void> toggleVibration() async {
    if (!connected) {
      _showMessage(
        'الجهاز غير متصل',
      );
      return;
    }

    final newValue =
        !vibrationEnabled;

    final success =
        await _bluetooth.setVibration(
      newValue,
    );

    if (!mounted) return;

    if (success) {
      setState(() {
        vibrationEnabled =
            newValue;
      });
    } else {
      _showMessage(
        'تعذر تغيير الاهتزاز',
      );
    }
  }

  // ============================================================
  // STATUS
  // ============================================================

  Color get signalColor {
    if (!connected) {
      return Colors.grey;
    }

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

  String get signalText {
    if (!connected) {
      return 'غير متصل';
    }

    if (calibrating) {
      return 'جاري المعايرة';
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
      return 'لا توجد قراءة';
    }

    if (!scanning) {
      return 'في انتظار المسح';
    }

    if (signal < 20) {
      return 'لا يوجد تغير واضح';
    }

    if (signal < 40) {
      return 'تغير ضعيف في الإشارة';
    }

    if (signal < 65) {
      return 'تغير يحتاج إلى فحص';
    }

    return 'تغير قوي - تحقق ميدانيًا';
  }

  String get lastUpdateText {
    if (_lastSignalTime == null) {
      return 'لم تصل قراءة بعد';
    }

    final seconds =
        DateTime.now()
            .difference(
              _lastSignalTime!,
            )
            .inSeconds;

    if (seconds <= 1) {
      return 'بيانات مباشرة';
    }

    return 'آخر قراءة منذ ${seconds}s';
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final color = signalColor;

    return Scaffold(
      backgroundColor:
          const Color(0xFF050A14),

      body: SafeArea(
        child: Directionality(
          textDirection:
              TextDirection.rtl,

          child: Column(
            children: [
              _topBar(),

              Expanded(
                child:
                    SingleChildScrollView(
                  physics:
                      const BouncingScrollPhysics(),

                  padding:
                      const EdgeInsets.fromLTRB(
                    14,
                    4,
                    14,
                    28,
                  ),

                  child: Column(
                    children: [
                      _mainGauge(color),

                      const SizedBox(
                        height: 12,
                      ),

                      _quickStatus(color),

                      const SizedBox(
                        height: 12,
                      ),

                      _metrics(),

                      const SizedBox(
                        height: 12,
                      ),

                      _signalMeter(),

                      const SizedBox(
                        height: 12,
                      ),

                      _signalGraph(),

                      const SizedBox(
                        height: 12,
                      ),

                      _targetCard(color),

                      const SizedBox(
                        height: 12,
                      ),

                      _controlsCard(),

                      const SizedBox(
                        height: 14,
                      ),

                      _mainButtons(),

                      const SizedBox(
                        height: 10,
                      ),

                      _calibrationButton(),

                      const SizedBox(
                        height: 14,
                      ),

                      _scientificNotice(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // TOP BAR
  // ============================================================

  Widget _topBar() {
    return Container(
      height: 72,

      padding:
          const EdgeInsets.symmetric(
        horizontal: 16,
      ),

      decoration:
          const BoxDecoration(
        color: Color(0xFF050A14),
      ),

      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,

            decoration:
                BoxDecoration(
              color: const Color(
                0xFF101A2B,
              ),

              borderRadius:
                  BorderRadius.circular(
                14,
              ),
            ),

            child: const Icon(
              Icons.radar,
              color: Colors.cyanAccent,
            ),
          ),

          const SizedBox(
            width: 11,
          ),

          const Expanded(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,

              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [
                Text(
                  'GeoScan AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                Text(
                  'المسح المباشر',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 7,
            ),

            decoration:
                BoxDecoration(
              color: connected
                  ? Colors.greenAccent
                      .withOpacity(0.10)
                  : Colors.redAccent
                      .withOpacity(0.10),

              borderRadius:
                  BorderRadius.circular(
                12,
              ),

              border: Border.all(
                color: connected
                    ? Colors.greenAccent
                        .withOpacity(
                        0.35,
                      )
                    : Colors.redAccent
                        .withOpacity(
                        0.35,
                      ),
              ),
            ),

            child: Row(
              children: [
                Icon(
                  connected
                      ? Icons
                          .bluetooth_connected
                      : Icons
                          .bluetooth_disabled,

                  size: 17,

                  color: connected
                      ? Colors.greenAccent
                      : Colors.redAccent,
                ),

                const SizedBox(
                  width: 5,
                ),

                Text(
                  connected
                      ? 'متصل'
                      : 'غير متصل',

                  style: TextStyle(
                    color: connected
                        ? Colors.greenAccent
                        : Colors.redAccent,

                    fontSize: 11,

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

  // ============================================================
  // MAIN GAUGE
  // ============================================================

  Widget _mainGauge(Color color) {
    return AnimatedBuilder(
      animation: _pulseController,

      builder:
          (context, child) {
        final pulse =
            scanning
                ? 0.92 +
                    (_pulseController
                            .value *
                        0.08)
                : 1.0;

        return Container(
          height: 300,
          width: double.infinity,

          decoration:
              BoxDecoration(
            color: const Color(
              0xFF091322,
            ),

            borderRadius:
                BorderRadius.circular(
              26,
            ),

            border: Border.all(
              color: color
                  .withOpacity(
                0.25,
              ),
            ),

            boxShadow: [
              BoxShadow(
                color: color
                    .withOpacity(
                  scanning ? 0.10 : 0.03,
                ),

                blurRadius: 28,

                spreadRadius:
                    scanning ? 2 : 0,
              ),
            ],
          ),

          child: Stack(
            alignment: Alignment.center,

            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter:
                      GaugePainter(
                    value: signal,
                    color: color,
                    scanning: scanning,
                  ),
                ),
              ),

              Transform.scale(
                scale: pulse,

                child: Column(
                  mainAxisAlignment:
                      MainAxisAlignment.center,

                  children: [
                    Text(
                      scanning
                          ? 'LIVE SCAN'
                          : 'GEO SCAN',

                      style:
                          const TextStyle(
                        color:
                            Colors.white70,

                        fontSize: 13,

                        fontWeight:
                            FontWeight.bold,

                        letterSpacing: 2.5,
                      ),
                    ),

                    const SizedBox(
                      height: 5,
                    ),

                    Text(
                      '${signal.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: color,
                        fontSize: 58,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),

                    Text(
                      signalText,
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    Text(
                      lastUpdateText,
                      style:
                          const TextStyle(
                        color:
                            Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // QUICK STATUS
  // ============================================================

  Widget _quickStatus(Color color) {
    return Container(
      width: double.infinity,

      padding:
          const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 13,
      ),

      decoration:
          BoxDecoration(
        color: color.withOpacity(0.06),

        borderRadius:
            BorderRadius.circular(
          16,
        ),

        border: Border.all(
          color: color.withOpacity(
            0.18,
          ),
        ),
      ),

      child: Row(
        children: [
          Icon(
            scanning
                ? Icons.radar
                : Icons.radar_outlined,

            color: color,

            size: 26,
          ),

          const SizedBox(
            width: 10,
          ),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [
                const Text(
                  'حالة المسح',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),

                const SizedBox(
                  height: 2,
                ),

                Text(
                  scanning
                      ? 'المستشعر يرسل البيانات الآن'
                      : deviceStatus,

                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          if (scanning)
            Container(
              width: 9,
              height: 9,

              decoration:
                  const BoxDecoration(
                color:
                    Colors.greenAccent,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // METRICS
  // ============================================================

  Widget _metrics() {
    return Row(
      children: [
        Expanded(
          child: _metricCard(
            'الإشارة',
            '${signal.toStringAsFixed(1)}%',
            Icons
                .signal_cellular_alt,
            signalColor,
          ),
        ),

        const SizedBox(
          width: 8,
        ),

        Expanded(
          child: _metricCard(
            'الاستقرار',
            '${stability.toStringAsFixed(0)}%',
            Icons.graphic_eq,
            Colors.cyanAccent,
          ),
        ),

        const SizedBox(
          width: 8,
        ),

        Expanded(
          child: _metricCard(
            'العمق',
            depth > 0
                ? '${depth.toStringAsFixed(2)}m'
                : '--',
            Icons
                .vertical_align_bottom,
            Colors.greenAccent,
          ),
        ),
      ],
    );
  }

  Widget _metricCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding:
          const EdgeInsets.all(12),

      decoration:
          BoxDecoration(
        color: const Color(
          0xFF0B1525,
        ),

        borderRadius:
            BorderRadius.circular(
          17,
        ),

        border: Border.all(
          color: Colors.white
              .withOpacity(
            0.06,
          ),
        ),
      ),

      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 21,
          ),

          const SizedBox(
            height: 7,
          ),

          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 17,
              fontWeight:
                  FontWeight.bold,
            ),
          ),

          const SizedBox(
            height: 2,
          ),

          Text(
            title,
            style:
                const TextStyle(
              color: Colors.white54,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SIGNAL METER
  // ============================================================

  Widget _signalMeter() {
    return _section(
      title: 'مستوى الإشارة',
      icon: Icons.bar_chart,

      child: Column(
        children: [
          SizedBox(
            height: 32,

            child: Row(
              children:
                  List.generate(
                36,
                (index) {
                  final level =
                      ((index + 1) /
                              36) *
                          100;

                  final active =
                      signal >= level;

                  final barColor =
                      _meterColor(
                    index,
                  );

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
                                0.06,
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

          const SizedBox(
            height: 8,
          ),

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
                  fontSize: 10,
                ),
              ),

              Text(
                'متوسطة',
                style: TextStyle(
                  color:
                      Colors.amberAccent,
                  fontSize: 10,
                ),
              ),

              Text(
                'قوية',
                style: TextStyle(
                  color:
                      Colors.greenAccent,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _meterColor(int index) {
    if (index < 9) {
      return Colors.redAccent;
    }

    if (index < 18) {
      return Colors.orangeAccent;
    }

    if (index < 27) {
      return Colors.amberAccent;
    }

    return Colors.greenAccent;
  }

  // ============================================================
  // GRAPH
  // ============================================================

  Widget _signalGraph() {
    return _section(
      title: 'الإشارة الحية',
      icon: Icons.show_chart,

      trailing: Text(
        '${signalHistory.length} نقطة',
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 10,
        ),
      ),

      child: SizedBox(
        height: 170,

        child: CustomPaint(
          painter: SignalPainter(
            values: signalHistory,
            color: signalColor,
          ),

          child:
              const SizedBox.expand(),
        ),
      ),
    );
  }

  // ============================================================
  // TARGET
  // ============================================================

  Widget _targetCard(Color color) {
    return _section(
      title: 'تحليل الهدف',
      icon: Icons.radar,

      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,

            decoration:
                BoxDecoration(
              color: color
                  .withOpacity(
                0.10,
              ),

              shape: BoxShape.circle,

              border: Border.all(
                color: color
                    .withOpacity(
                  0.25,
                ),
              ),
            ),

            child: Icon(
              signal >= 65
                  ? Icons
                      .priority_high
                  : Icons.radar,
              color: color,
              size: 27,
            ),
          ),

          const SizedBox(
            width: 12,
          ),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,

              children: [
                Text(
                  targetType == 'غير محدد'
                      ? 'نوع الهدف'
                      : targetType,

                  style:
                      const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 4,
                ),

                Text(
                  targetAnalysis,

                  style: TextStyle(
                    color: color,
                    fontSize: 12,
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

  // ============================================================
  // CONTROLS
  // ============================================================

  Widget _controlsCard() {
    return _section(
      title: 'إعدادات الجهاز',
      icon: Icons.tune,

      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.speed,
                color:
                    Colors.cyanAccent,
                size: 21,
              ),

              const SizedBox(
                width: 9,
              ),

              const Expanded(
                child: Text(
                  'الحساسية',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),

              Text(
                sensitivity
                    .toStringAsFixed(0),
                style:
                    const TextStyle(
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
            divisions: 20,

            activeColor:
                Colors.cyanAccent,

            inactiveColor:
                Colors.white12,

            onChanged:
                connected
                    ? (value) {
                        setState(() {
                          sensitivity =
                              value;
                        });
                      }
                    : null,

            onChangeEnd:
                connected
                    ? changeSensitivity
                    : null,
          ),

          const Divider(
            color: Colors.white10,
          ),

          Row(
            children: [
              const Icon(
                Icons.filter_alt,
                color:
                    Colors.amberAccent,
                size: 21,
              ),

              const SizedBox(
                width: 9,
              ),

              const Expanded(
                child: Text(
                  'الفلترة',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),

              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: filter,

                  dropdownColor:
                      const Color(
                    0xFF101B2D,
                  ),

                  style:
                      const TextStyle(
                    color: Colors.white,
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
                          ? (value) {
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
            ],
          ),

          const Divider(
            color: Colors.white10,
          ),

          Row(
            children: [
              Expanded(
                child: _toggleButton(
                  title: 'الصوت',
                  icon: audioEnabled
                      ? Icons.volume_up
                      : Icons.volume_off,
                  enabled:
                      audioEnabled,
                  onTap:
                      toggleAudio,
                ),
              ),

              const SizedBox(
                width: 8,
              ),

              Expanded(
                child: _toggleButton(
                  title: 'الاهتزاز',
                  icon: vibrationEnabled
                      ? Icons.vibration
                      : Icons
                          .mobile_off,
                  enabled:
                      vibrationEnabled,
                  onTap:
                      toggleVibration,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toggleButton({
    required String title,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: enabled
          ? Colors.greenAccent
              .withOpacity(0.08)
          : Colors.white
              .withOpacity(0.04),

      borderRadius:
          BorderRadius.circular(
        13,
      ),

      child: InkWell(
        borderRadius:
            BorderRadius.circular(
          13,
        ),

        onTap:
            connected ? onTap : null,

        child: Padding(
          padding:
              const EdgeInsets.symmetric(
            vertical: 12,
          ),

          child: Row(
            mainAxisAlignment:
                MainAxisAlignment
                    .center,

            children: [
              Icon(
                icon,

                size: 19,

                color: connected
                    ? (enabled
                        ? Colors
                            .greenAccent
                        : Colors.white38)
                    : Colors.white24,
              ),

              const SizedBox(
                width: 6,
              ),

              Text(
                title,

                style: TextStyle(
                  color: connected
                      ? Colors.white70
                      : Colors.white24,

                  fontSize: 12,

                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // MAIN BUTTONS
  // ============================================================

  Widget _mainButtons() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 58,

            child: ElevatedButton.icon(
              onPressed:
                  connected && !scanning
                      ? startScan
                      : null,

              icon: const Icon(
                Icons.play_arrow,
                size: 25,
              ),

              label: const Text(
                'بدء المسح',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              style:
                  ElevatedButton.styleFrom(
                backgroundColor:
                    Colors.greenAccent,

                foregroundColor:
                    Colors.black,

                disabledBackgroundColor:
                    Colors.white10,

                disabledForegroundColor:
                    Colors.white24,

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

        const SizedBox(
          width: 9,
        ),

        Expanded(
          child: SizedBox(
            height: 58,

            child: ElevatedButton.icon(
              onPressed:
                  connected && scanning
                      ? stopScan
                      : null,

              icon: const Icon(
                Icons.stop,
                size: 23,
              ),

              label: const Text(
                'إيقاف',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              style:
                  ElevatedButton.styleFrom(
                backgroundColor:
                    Colors.redAccent,

                foregroundColor:
                    Colors.white,

                disabledBackgroundColor:
                    Colors.white10,

                disabledForegroundColor:
                    Colors.white24,

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
    );
  }

  // ============================================================
  // CALIBRATION
  // ============================================================

  Widget _calibrationButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,

      child: OutlinedButton.icon(
        onPressed:
            connected &&
                    !scanning &&
                    !calibrating
                ? calibrate
                : null,

        icon: calibrating
            ? const SizedBox(
                width: 18,
                height: 18,

                child:
                    CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
            : const Icon(
                Icons
                    .center_focus_strong,
              ),

        label: Text(
          calibrating
              ? 'جاري المعايرة...'
              : 'معايرة الحساس',
        ),

        style:
            OutlinedButton.styleFrom(
          foregroundColor:
              Colors.cyanAccent,

          side: BorderSide(
            color: connected
                ? Colors.cyanAccent
                    .withOpacity(
                    0.45,
                  )
                : Colors.white10,
          ),

          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              15,
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // SCIENTIFIC NOTICE
  // ============================================================

  Widget _scientificNotice() {
    return Container(
      width: double.infinity,

      padding:
          const EdgeInsets.all(14),

      decoration:
          BoxDecoration(
        color: Colors.blueAccent
            .withOpacity(
          0.05,
        ),

        borderRadius:
            BorderRadius.circular(
          15,
        ),

        border: Border.all(
          color: Colors.blueAccent
              .withOpacity(
            0.14,
          ),
        ),
      ),

      child: const Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [
          Icon(
            Icons.info_outline,
            color: Colors.blueAccent,
            size: 20,
          ),

          SizedBox(
            width: 9,
          ),

          Expanded(
            child: Text(
              'القراءات المعروضة هي بيانات المستشعر القادمة من ESP32. ارتفاع الإشارة وحده لا يثبت وجود ذهب أو معدن محدد، كما أن تحديد العمق الحقيقي يحتاج إلى معايرة وحساس ودائرة قياس مناسبة.',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SECTION
  // ============================================================

  Widget _section({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,

      padding:
          const EdgeInsets.all(15),

      decoration:
          BoxDecoration(
        color: const Color(
          0xFF0A1423,
        ),

        borderRadius:
            BorderRadius.circular(
          19,
        ),

        border: Border.all(
          color: Colors.white
              .withOpacity(
            0.055,
          ),
        ),
      ),

      child: Column(
        children: [
          Row(
            children: [
              Icon(
                icon,
                color:
                    Colors.cyanAccent,
                size: 19,
              ),

              const SizedBox(
                width: 7,
              ),

              Expanded(
                child: Text(
                  title,

                  style:
                      const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),

              if (trailing != null)
                trailing,
            ],
          ),

          const SizedBox(
            height: 13,
          ),

          child,
        ],
      ),
    );
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(
    String message,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          message,
          textDirection:
              TextDirection.rtl,
        ),

        behavior:
            SnackBarBehavior.floating,
      ),
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _signalSubscription?.cancel();
    _connectionSubscription?.cancel();

    _pulseController.dispose();

    // لا نعمل:
    // _bluetooth.dispose();
    //
    // لأن BluetoothService مشترك
    // مع بقية التطبيق.

    super.dispose();
  }
}

// ==================================================================
// GAUGE PAINTER
// ==================================================================

class GaugePainter extends CustomPainter {
  final double value;
  final Color color;
  final bool scanning;

  GaugePainter({
    required this.value,
    required this.color,
    required this.scanning,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final center =
        Offset(
      size.width / 2,
      size.height / 2,
    );

    final radius =
        math.min(
          size.width,
          size.height,
        ) *
        0.37;

    final backgroundPaint =
        Paint()
          ..style =
              PaintingStyle.stroke
          ..strokeWidth = 17
          ..strokeCap =
              StrokeCap.round
          ..color = Colors.white
              .withOpacity(
            0.07,
          );

    canvas.drawArc(
      Rect.fromCircle(
        center: center,
        radius: radius,
      ),

      math.pi * 0.75,
      math.pi * 1.5,

      false,
      backgroundPaint,
    );

    final progress =
        (value.clamp(0.0, 100.0) /
                100.0) *
            (math.pi * 1.5);

    final progressPaint =
        Paint()
          ..style =
              PaintingStyle.stroke
          ..strokeWidth = 17
          ..strokeCap =
              StrokeCap.round
          ..color = color;

    canvas.drawArc(
      Rect.fromCircle(
        center: center,
        radius: radius,
      ),

      math.pi * 0.75,
      progress,

      false,
      progressPaint,
    );

    // نقاط التدريج
    final tickPaint =
        Paint()
          ..strokeWidth = 2
          ..strokeCap =
              StrokeCap.round
          ..color = Colors.white
              .withOpacity(
            0.18,
          );

    for (int i = 0; i <= 20; i++) {
      final angle =
          math.pi * 0.75 +
              (math.pi * 1.5) *
                  (i / 20);

      final outer = Offset(
        center.dx +
            math.cos(angle) *
                (radius + 17),

        center.dy +
            math.sin(angle) *
                (radius + 17),
      );

      final inner = Offset(
        center.dx +
            math.cos(angle) *
                (radius + 24),

        center.dy +
            math.sin(angle) *
                (radius + 24),
      );

      canvas.drawLine(
        outer,
        inner,
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant GaugePainter oldDelegate,
  ) {
    return oldDelegate.value != value ||
        oldDelegate.color != color ||
        oldDelegate.scanning != scanning;
  }
}

// ==================================================================
// SIGNAL PAINTER
// ==================================================================

class SignalPainter extends CustomPainter {
  final List<double> values;
  final Color color;

  SignalPainter({
    required this.values,
    required this.color,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final gridPaint =
        Paint()
          ..color = Colors
