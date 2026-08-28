import 'dart:async';
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
  // ============================================================
  // GeoScan AI - Premium Live Scan Screen
  //
  // IMPORTANT:
  // لا توجد قراءة وهمية.
  // جميع البيانات تأتي من BluetoothService <- ESP32.
  // ============================================================

  final BluetoothService _bluetooth = BluetoothService();

  StreamSubscription<Map<String, dynamic>>? _dataSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  Timer? _watchdogTimer;

  late AnimationController _pulseController;

  final List<double> signalHistory = [];
  final List<Map<String, dynamic>> savedReadings = [];

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

  int receivedPackets = 0;
  int? lastSequence;
  int? _lastReceivedAt;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);

    _listenToBluetooth();

    _watchdogTimer = Timer.periodic(
      const Duration(milliseconds: 700),
      (_) {
        if (!mounted) return;

        if (scanning && !_bluetooth.hasRecentData) {
          setState(() {
            scanning = false;
            deviceStatus = connected
                ? 'لا توجد بيانات حديثة'
                : 'غير متصل';
          });
        }
      },
    );
  }

  // ============================================================
  // Bluetooth
  // ============================================================

  void _listenToBluetooth() {
    _dataSubscription = _bluetooth.dataStream.listen(
      _handleDeviceData,
      onError: (_) {},
    );

    _connectionSubscription =
        _bluetooth.connectionStream.listen(
      _handleConnectionState,
      onError: (_) {},
    );

    connected = _bluetooth.isConnected;

    if (connected) {
      deviceStatus = 'متصل';
    }
  }

  void _handleDeviceData(
    Map<String, dynamic> data,
  ) {
    if (!mounted) return;

    final incomingSignal = data.containsKey('signal')
        ? _toDouble(data['signal'])
        : signal;

    final incomingRaw = data.containsKey('raw')
        ? _toDouble(data['raw'])
        : rawSignal;

    final incomingBaseline = data.containsKey('baseline')
        ? _toDouble(data['baseline'])
        : baseline;

    final incomingStability = data.containsKey('stability')
        ? _toDouble(data['stability'])
        : stability;

    final incomingDepth = data.containsKey('depth')
        ? _toDouble(data['depth'])
        : depth;

    final incomingStatus = data.containsKey('status')
        ? data['status'].toString().trim()
        : deviceStatus;

    final incomingTarget = data.containsKey('target')
        ? data['target'].toString().trim()
        : targetType;

    final safeSignal =
        incomingSignal.clamp(0.0, 100.0).toDouble();

    final safeStability =
        incomingStability.clamp(0.0, 100.0).toDouble();

    final safeDepth =
        incomingDepth.isFinite && incomingDepth >= 0
            ? incomingDepth
            : 0.0;

    // تنعيم للعرض فقط.
    // لا يتم تعديل rawSignal.
    final displayedSignal = signal == 0
        ? safeSignal
        : (signal * 0.72) + (safeSignal * 0.28);

    final safeDisplayedSignal =
        displayedSignal.clamp(0.0, 100.0).toDouble();

    final statusLower = incomingStatus.toLowerCase();

    final isScanning =
        incomingStatus == 'يمسح' ||
        incomingStatus == 'مسح' ||
        incomingStatus == 'SCANNING' ||
        statusLower == 'scanning' ||
        statusLower == 'scan' ||
        data['scanning'] == true;

    final sequence = data.containsKey('sequence')
        ? _toInt(data['sequence'])
        : lastSequence;

    final receivedAt = data.containsKey('receivedAt')
        ? _toInt(data['receivedAt'])
        : DateTime.now().millisecondsSinceEpoch;

    setState(() {
      signal = safeDisplayedSignal;
      rawSignal = incomingRaw;
      baseline = incomingBaseline;
      stability = safeStability;
      depth = safeDepth;

      deviceStatus = incomingStatus.isEmpty
          ? (isScanning ? 'يمسح' : 'متصل')
          : incomingStatus;

      if (incomingTarget.isNotEmpty) {
        targetType = incomingTarget;
      }

      scanning = isScanning;
      receivedPackets = _bluetooth.receivedPackets;
      lastSequence = sequence;
      _lastReceivedAt = receivedAt;

      if (signalHistory.length >= 100) {
        signalHistory.removeAt(0);
      }

      signalHistory.add(safeDisplayedSignal);
    });
  }

  void _handleConnectionState(bool isConnected) {
    if (!mounted) return;

    setState(() {
      connected = isConnected;

      if (!isConnected) {
        scanning = false;
        calibrating = false;
        deviceStatus = 'غير متصل';

        signal = 0;
        rawSignal = 0;
        baseline = 0;
        stability = 0;
        depth = 0;

        signalHistory.clear();

        receivedPackets = 0;
        lastSequence = null;
        _lastReceivedAt = null;
      } else {
        deviceStatus = 'متصل';
      }
    });
  }

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value.toString().replaceAll(',', '.').trim(),
        ) ??
        0;
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;

    if (value is num) {
      final number = value.toDouble();

      if (!number.isFinite) {
        return null;
      }

      return number.round();
    }

    return int.tryParse(value.toString().trim());
  }

  // ============================================================
  // Start Scan
  // ============================================================

  Future<void> startScan() async {
    if (!connected) {
      _showMessage('يجب الاتصال بجهاز ESP32 أولًا');
      return;
    }

    if (calibrating) {
      _showMessage('انتظر حتى تنتهي المعايرة');
      return;
    }

    try {
      await _bluetooth.startScan();

      if (!mounted) return;

      setState(() {
        scanning = true;
        deviceStatus = 'يمسح';
        signalHistory.clear();
      });

      _showMessage('بدأ المسح الحقيقي من ESP32');
    } catch (_) {
      _showMessage('تعذر بدء المسح');
    }
  }

  // ============================================================
  // Stop Scan
  // ============================================================

  Future<void> stopScan() async {
    if (!connected) return;

    try {
      await _bluetooth.stopScan();

      if (!mounted) return;

      setState(() {
        scanning = false;
        deviceStatus = 'متوقف';
      });

      _showMessage('تم إيقاف المسح');
    } catch (_) {
      _showMessage('تعذر إيقاف المسح');
    }
  }

  // ============================================================
  // Calibration
  // ============================================================

  Future<void> calibrate() async {
    if (!connected) {
      _showMessage('يجب الاتصال بجهاز ESP32 أولًا');
      return;
    }

    if (scanning) {
      _showMessage('أوقف المسح أولًا ثم قم بالمعايرة');
      return;
    }

    setState(() {
      calibrating = true;
      deviceStatus = 'معايرة';
      signalHistory.clear();
    });

    try {
      await _bluetooth.calibrate();

      if (!mounted) return;

      setState(() {
        calibrating = false;
        deviceStatus = 'جاهز';

        signal = 0;
        rawSignal = 0;
        baseline = 0;
        stability = 0;
        depth = 0;
      });

      _showMessage('تم إرسال أمر المعايرة إلى ESP32');
    } catch (_) {
      if (!mounted) return;

      setState(() {
        calibrating = false;
        deviceStatus =
            connected ? 'متصل' : 'غير متصل';
      });

      _showMessage('تعذر تنفيذ المعايرة');
    }
  }

  // ============================================================
  // Sensitivity
  // ============================================================

  Future<void> changeSensitivity(
    double value,
  ) async {
    if (!connected || calibrating) return;

    final safeValue =
        value.clamp(0.0, 100.0).toDouble();

    try {
      await _bluetooth.setSensitivity(safeValue);

      if (!mounted) return;

      setState(() {
        sensitivity = safeValue;
      });
    } catch (_) {
      _showMessage('تعذر تغيير الحساسية');
    }
  }

  // ============================================================
  // Filter
  // ============================================================

  Future<void> changeFilter(
    String value,
  ) async {
    if (!connected || calibrating) return;

    try {
      await _bluetooth.setFilter(value);

      if (!mounted) return;

      setState(() {
        filter = value;
      });
    } catch (_) {
      _showMessage('تعذر تغيير الفلترة');
    }
  }

  // ============================================================
  // Audio
  // ============================================================

  Future<void> toggleAudio(
    bool value,
  ) async {
    if (!connected) return;

    try {
      await _bluetooth.setAudio(value);

      if (!mounted) return;

      setState(() {
        audioEnabled = value;
      });
    } catch (_) {
      _showMessage('تعذر تغيير الصوت');
    }
  }

  // ============================================================
  // Vibration
  // ============================================================

  Future<void> toggleVibration(
    bool value,
  ) async {
    if (!connected) return;

    try {
      await _bluetooth.setVibration(value);

      if (!mounted) return;

      setState(() {
        vibrationEnabled = value;
      });
    } catch (_) {
      _showMessage('تعذر تغيير الاهتزاز');
    }
  }

  // ============================================================
  // Save
  // ============================================================

  void saveCurrentReading() {
    if (!connected) {
      _showMessage(
        'لا يمكن حفظ قراءة والجهاز غير متصل',
      );
      return;
    }

    if (_lastReceivedAt == null) {
      _showMessage(
        'لا توجد قراءة مستلمة من ESP32 بعد',
      );
      return;
    }

    final reading = <String, dynamic>{
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

  // ============================================================
  // Reset
  // ============================================================

  void resetReading() {
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

  // ============================================================
  // Helpers
  // ============================================================

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
    if (!connected) return 'غير متصل';
    if (calibrating) return 'جاري المعايرة';
    if (!scanning) return 'جاهز للمسح';

    if (!_bluetooth.hasRecentData) {
      return 'بانتظار البيانات';
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

  String get targetStatus {
    if (!connected) {
      return 'لا توجد قراءة';
    }

    if (!_bluetooth.hasRecentData && scanning) {
      return 'لا توجد بيانات حديثة';
    }

    if (!scanning) {
      return 'في انتظار المسح';
    }

    if (signal < 20) {
      return 'لا توجد إشارة واضحة';
    }

    if (signal < 40) {
      return 'تغير ضعيف يحتاج فحص';
    }

    if (signal < 65) {
      return 'تغير يحتاج إلى فحص';
    }

    return 'تغير قوي - تحقق ميدانيًا';
  }

  String get depthText {
    if (depth <= 0) {
      return '--';
    }

    return '${depth.toStringAsFixed(2)} m';
  }

  // ============================================================
  // Messages
  // ============================================================

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
          duration:
              const Duration(seconds: 2),
        ),
      );
  }

  // ============================================================
  // Main UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor:
            const Color(0xFF030712),

        appBar: _buildAppBar(),

        body: SafeArea(
          child: SingleChildScrollView(
            physics:
                const BouncingScrollPhysics(),
            padding:
                const EdgeInsets.fromLTRB(
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

                _buildTechnicalInfo(),

                const SizedBox(height: 10),

                _buildScientificNotice(),
              ],
            ),
          ),
        ),

        bottomNavigationBar:
            _buildBottomNavigation(),
      ),
    );
  }

  // ============================================================
  // AppBar
  // ============================================================

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor:
          const Color(0xFF030712),
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
              const EdgeInsets.only(left: 10),
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
                  boxShadow: [
                    if (connected)
                      BoxShadow(
                        color: Colors.greenAccent
                            .withOpacity(.7),
                        blurRadius: 8,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Text(
                connected ? 'متصل' : 'غير متصل',
                style: TextStyle(
                  color: connected
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // Hero Scanner
  // ============================================================

  Widget _buildHeroScanner() {
    final color = signalColor;

    return Container(
      height: 350,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(28),
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
            color: color.withOpacity(.06),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (_, __) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: PremiumScannerPainter(
                    value: signal,
                    pulse:
                        _pulseController.value,
                    scanning: scanning,
                  ),
                ),
              ),

              Column(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      if (scanning)
                        Container(
                          width: 8,
                          height: 8,
                          margin:
                              const EdgeInsets
                                  .only(left: 7),
                          decoration:
                              BoxDecoration(
                            color: color,
                            shape:
                                BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: color
                                    .withOpacity(
                                        .8),
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
                          fontWeight:
                              FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 3),

                  Text(
                    '${signal.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: color,
                      fontSize: 58,
                      height: .95,
                      fontWeight:
                          FontWeight.w900,
                      shadows: [
                        Shadow(
                          color:
                              color.withOpacity(.35),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 6,
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
                        fontSize: 13,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              Positioned(
                top: 16,
                right: 18,
                child: _liveBadge(),
              ),

              Positioned(
                bottom: 15,
                left: 20,
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
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.28),
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white12,
        ),
      ),
      child: Row(
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

  // ============================================================
  // Main Metrics
  // ============================================================

  Widget _buildMainMetrics() {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
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
                icon:
                    Icons.graphic_eq_rounded,
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
    return _glassCard(
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
          const SizedBox(height: 4),
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
            style: TextStyle(
              color: color,
              fontSize: 11,
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
    return _glassCard(
      height: 75,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 11,
      ),
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
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 19,
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

  // ============================================================
  // Signal Level
  // ============================================================

  Widget _buildSignalLevel() {
    return _glassCard(
      child: Column(
        children: [
          _sectionHeader(
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
                  final level =
                      ((index + 1) / 40) *
                          100;

                  final active =
                      signal >= level;

                  final barColor =
                      _meterColor(index);

                  return Expanded(
                    child: AnimatedContainer(
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
                            ? barColor
                            : Colors.white
                                .withOpacity(
                                    .065),
                        borderRadius:
                            BorderRadius
                                .circular(4),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: barColor
                                      .withOpacity(
                                          .25),
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

          const SizedBox(height: 6),

          const Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
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
                  color: Colors.orangeAccent,
                  fontSize: 10,
                ),
              ),
              Text(
                'جيدة',
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

  Color _meterColor(int index) {
    if (index < 9) {
      return Colors.redAccent;
    }

    if (index < 19) {
      return Colors.orangeAccent;
    }

    if (index < 29) {
      return Colors.amberAccent;
    }

    return Colors.greenAccent;
  }

  // ============================================================
  // Signal Graph
  // ============================================================

  Widget _buildSignalGraph() {
    return _glassCard(
      height: 210,
      child: Column(
        children: [
          _sectionHeader(
            'حركة الإشارة',
            Icons.show_chart_rounded,
          ),

          const SizedBox(height: 8),

          Expanded(
            child: CustomPaint(
              painter: PremiumSignalPainter(
                values: signalHistory,
                color: signalColor,
              ),
              child:
                  const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Target Analysis
  // ============================================================

  Widget _buildTargetAnalysis() {
    return _glassCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          _sectionHeader(
            'تحليل الهدف',
            Icons.radar_rounded,
          ),

          const SizedBox(height: 10),

          Container(
            padding:
                const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [
                  signalColor
                      .withOpacity(.10),
                  Colors.black
                      .withOpacity(.12),
                ],
              ),
              border: Border.all(
                color: signalColor
                    .withOpacity(.18),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: signalColor
                        .withOpacity(.08),
                    border: Border.all(
                      color: signalColor
                          .withOpacity(.30),
                    ),
                  ),
                  child: Icon(
                    Icons.radar_rounded,
                    color: signalColor,
                    size: 32,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'النوع المحتمل',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),

                      const SizedBox(height: 2),

                      Text(
                        targetType.isEmpty
                            ? 'غير محدد'
                            : targetType,
                        maxLines: 1,
                        overflow:
                            TextOverflow.ellipsis,
                        style: TextStyle(
                          color: signalColor,
                          fontSize: 22,
                          fontWeight:
                              FontWeight.w900,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        targetStatus,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 9),

          _analysisRow(
            'قوة الإشارة',
            signal,
            signalColor,
            Icons.bolt_rounded,
          ),

          const SizedBox(height: 7),

          _analysisRow(
            'الاستقرار',
            stability,
            Colors.cyanAccent,
            Icons.graphic_eq_rounded,
          ),

          const SizedBox(height: 7),

          _analysisRow(
            'الإشارة الخام',
            rawSignal > 100
                ? 100
                : rawSignal
                    .clamp(0.0, 100.0)
                    .toDouble(),
            Colors.orangeAccent,
            Icons.memory_rounded,
          ),

          const SizedBox(height: 9),

          const Text(
            'التصنيف احتمالي ويعتمد على البيانات القادمة من ESP32.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white38,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _analysisRow(
    String title,
    double value,
    Color color,
    IconData icon,
  ) {
    final safe =
        value.clamp(0.0, 100.0).toDouble();

    return Container(
      padding:
          const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.black
            .withOpacity(.13),
        borderRadius:
            BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ),
              Text(
                '${safe.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: color,
                  fontWeight:
                      FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius:
                BorderRadius.circular(8),
            child:
                LinearProgressIndicator(
              value: safe / 100,
              minHeight: 5,
              backgroundColor:
                  Colors.white
                      .withOpacity(.07),
              valueColor:
                  AlwaysStoppedAnimation(
                color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Status Cards
  // ============================================================

  Widget _buildStatusCards() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 2.25,
      shrinkWrap: true,
      physics:
          const NeverScrollableScrollPhysics(),
      children: [
        _statusCard(
          title: 'حالة الجهاز',
          value: connected
              ? (scanning ? 'يمسح' : 'متصل')
              : 'غير متصل',
          icon: Icons.memory_rounded,
          color: connected
              ? Colors.greenAccent
              : Colors.redAccent,
        ),

        _statusCard(
          title: 'الحساسية',
          value:
              '${sensitivity.toStringAsFixed(0)}%',
          icon: Icons.tune_rounded,
          color: Colors.cyanAccent,
        ),

        _statusCard(
          title: 'الفلترة',
          value: filter,
          icon:
              Icons.filter_alt_rounded,
          color: Colors.cyanAccent,
        ),

        _statusCard(
          title: 'التنبيه',
          value:
              audioEnabled ? 'يعمل' : 'متوقف',
          icon:
              Icons.volume_up_rounded,
          color: audioEnabled
              ? Colors.greenAccent
              : Colors.white38,
        ),

        _statusCard(
          title: 'الاهتزاز',
          value: vibrationEnabled
              ? 'يعمل'
              : 'متوقف',
          icon:
              Icons.vibration_rounded,
          color: vibrationEnabled
              ? Colors.greenAccent
              : Colors.white38,
        ),

        _statusCard(
          title: 'الحزم',
          value:
              '$receivedPackets',
          icon:
              Icons.sync_rounded,
          color: Colors.amberAccent,
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
    return _glassCard(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 6,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: color,
            size: 24,
          ),
          const SizedBox(width: 7),
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
                    color: Colors.white45,
                    fontSize: 9,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
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
  // Settings
  // ============================================================

  Widget _buildSettings() {
    return _glassCard(
      child: Column(
        children: [
          _sectionHeader(
            'إعدادات المسح',
            Icons.settings_rounded,
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              const Icon(
                Icons.tune_rounded,
                color: Colors.cyanAccent,
              ),
              const SizedBox(width: 9),
              const Text(
                'الحساسية',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight:
                      FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                '${sensitivity.toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Colors.cyanAccent,
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
            inactiveColor:
                Colors.white12,
            onChanged:
                connected && !calibrating
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
                color: Colors.cyanAccent,
              ),
              const SizedBox(width: 9),
              const Text(
                'الفلترة',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight:
                      FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Spacer(),

              DropdownButton<String>(
                value: filter,
                dropdownColor:
                    const Color(0xFF071321),
                underline:
                    const SizedBox(),
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
                onChanged:
                    connected &&
                            !calibrating
                        ? (value) {
                            if (value != null) {
                              changeFilter(
                                value,
                              );
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
            contentPadding:
                EdgeInsets.zero,
            title: const Text(
              'التنبيه الصوتي',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
            subtitle: const Text(
              'يتم إرسال الإعداد إلى ESP32',
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
                connected
                    ? toggleAudio
                    : null,
          ),

          SwitchListTile(
            contentPadding:
                EdgeInsets.zero,
            title: const Text(
              'الاهتزاز',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
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

  // ============================================================
  // Controls
  // ============================================================

  Widget _buildControls() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 56,
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
                            .withOpacity(
                                .12),
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
                              16),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            Expanded(
              child: SizedBox(
                height: 56,
                child:
                    OutlinedButton.icon(
                  onPressed:
                      scanning
                          ? stopScan
                          : null,
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
                              16),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            Expanded(
              child: SizedBox(
                height: 56,
                child:
                    OutlinedButton.icon(
                  onPressed:
                      connected &&
                              !scanning &&
                              !calibrating
                          ? saveCurrentReading
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
            
