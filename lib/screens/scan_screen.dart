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

  late AnimationController _animationController;

  final List<double> signalHistory = [];

  double signal = 0.0;
  double rawSignal = 0.0;
  double stability = 0.0;
  double depth = 0.0;
  double baseline = 0.0;
  double sensitivity = 75.0;

  bool connected = false;
  bool scanning = false;
  bool calibrating = false;
  bool audioEnabled = true;
  bool vibrationEnabled = true;

  String filter = 'متوسطة';
  String deviceStatus = 'غير متصل';
  String targetType = 'غير محدد';

  DateTime? _lastSignalTime;

  int receivedPackets = 0;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _listenToBluetooth();
  }

  // ============================================================
  // BLUETOOTH
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

    _connectionSubscription =
        _bluetooth.connectionStream.listen(
      _handleConnectionState,
      onError: (error) {
        debugPrint(
          'GeoScan AI connection error: $error',
        );
      },
    );

    connected = _bluetooth.isConnected;

    if (connected) {
      deviceStatus = 'متصل';
    }
  }

  void _handleDeviceData(String rawData) {
    if (!mounted || rawData.trim().isEmpty) {
      return;
    }

    try {
      debugPrint(
        'GeoScan AI <- ESP32: $rawData',
      );

      receivedPackets++;

      dynamic decoded;

      try {
        decoded = jsonDecode(rawData);
      } catch (_) {
        final match = RegExp(
          r'[-+]?\d*\.?\d+',
        ).firstMatch(rawData);

        if (match != null) {
          final value = double.tryParse(
            match.group(0)!,
          );

          if (value != null) {
            _updateSignalOnly(value);
          }
        }

        return;
      }

      if (decoded is! Map) {
        return;
      }

      final data =
          Map<String, dynamic>.from(decoded);

      final incomingSignal =
          data.containsKey('signal')
              ? _toDouble(data['signal'])
              : data.containsKey('value')
                  ? _toDouble(data['value'])
                  : data.containsKey('strength')
                      ? _toDouble(
                          data['strength'],
                        )
                      : signal;

      final incomingRaw =
          data.containsKey('raw')
              ? _toDouble(data['raw'])
              : incomingSignal;

      final incomingStability =
          data.containsKey('stability')
              ? _toDouble(
                  data['stability'],
                )
              : stability;

      final incomingDepth =
          data.containsKey('depth')
              ? _toDouble(data['depth'])
              : depth;

      final incomingBaseline =
          data.containsKey('baseline')
              ? _toDouble(
                  data['baseline'],
                )
              : baseline;

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
              text == 'scanning' ||
              text == 'start';
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
              : incomingDepth;

      final smoothed =
          signal == 0.0
              ? safeSignal
              : (signal * 0.72) +
                  (safeSignal * 0.28);

      final finalSignal =
          smoothed
              .clamp(0.0, 100.0)
              .toDouble();

      setState(() {
        signal = finalSignal;
        rawSignal = safeRaw;
        stability = safeStability;
        depth = safeDepth;
        baseline = incomingBaseline;

        deviceStatus =
            incomingStatus.isEmpty
                ? (incomingScanning
                    ? 'يمسح'
                    : 'متصل')
                : incomingStatus;

        scanning = incomingScanning;

        if (incomingTarget.isNotEmpty) {
          targetType = incomingTarget;
        }

        signalHistory.add(
          finalSignal,
        );

        if (signalHistory.length > 80) {
          signalHistory.removeAt(0);
        }

        _lastSignalTime =
            DateTime.now();
      });
    } catch (e) {
      debugPrint(
        'GeoScan AI parsing error: $e',
      );
    }
  }

  void _updateSignalOnly(double value) {
    if (!mounted) return;

    final safe =
        value.clamp(0.0, 100.0).toDouble();

    final smoothed =
        signal == 0.0
            ? safe
            : (signal * 0.72) +
                (safe * 0.28);

    final finalSignal =
        smoothed
            .clamp(0.0, 100.0)
            .toDouble();

    setState(() {
      rawSignal = safe;
      signal = finalSignal;

      signalHistory.add(
        finalSignal,
      );

      if (signalHistory.length > 80) {
        signalHistory.removeAt(0);
      }

      _lastSignalTime =
          DateTime.now();
    });
  }

  void _handleConnectionState(
    bool value,
  ) {
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
        baseline = 0.0;

        signalHistory.clear();
        receivedPackets = 0;
        _lastSignalTime = null;
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
          value
              .toString()
              .replaceAll(',', '.')
              .trim(),
        ) ??
        0.0;
  }

  // ============================================================
  // SCAN CONTROLS
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
      deviceStatus = 'يمسح';
      signalHistory.clear();
    });

    _showMessage(
      'بدأ المسح الحقيقي من ESP32',
    );
  }

  Future<void> stopScan() async {
    if (!connected) {
      return;
    }

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

    _showMessage(
      'تم إيقاف المسح',
    );
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
      signalHistory.clear();
    });

    final success =
        await _bluetooth.calibrate();

    if (!mounted) return;

    setState(() {
      calibrating = false;
      deviceStatus =
          success ? 'جاهز' : 'متصل';

      if (success) {
        signal = 0.0;
        rawSignal = 0.0;
        baseline = 0.0;
        stability = 0.0;
        depth = 0.0;
      }
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
    if (!connected || calibrating) {
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
    if (!connected || calibrating) {
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

  Future<void> toggleAudio(
    bool value,
  ) async {
    if (!connected) return;

    final success =
        await _bluetooth.setAudio(
      value,
    );

    if (!mounted) return;

    if (success) {
      setState(() {
        audioEnabled = value;
      });
    }
  }

  Future<void> toggleVibration(
    bool value,
  ) async {
    if (!connected) return;

    final success =
        await _bluetooth.setVibration(
      value,
    );

    if (!mounted) return;

    if (success) {
      setState(() {
        vibrationEnabled = value;
      });
    }
  }

  // ============================================================
  // SAVE
  // ============================================================

  void saveCurrentReading() {
    if (!connected) {
      _showMessage(
        'الجهاز غير متصل',
      );
      return;
    }

    if (_lastSignalTime == null) {
      _showMessage(
        'لا توجد قراءة مستلمة من ESP32',
      );
      return;
    }

    HapticFeedback.mediumImpact();

    _showMessage(
      'تم حفظ القراءة الحالية',
    );
  }

  void resetReading() {
    setState(() {
      signal = 0.0;
      rawSignal = 0.0;
      stability = 0.0;
      depth = 0.0;
      baseline = 0.0;
      signalHistory.clear();
    });

    _showMessage(
      'تم تصفير العرض',
    );
  }

  // ============================================================
  // STATUS
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
    if (!connected) {
      return 'غير متصل';
    }

    if (calibrating) {
      return 'جاري المعايرة';
    }

    if (!scanning) {
      return 'جاهز للمسح';
    }

    if (_lastSignalTime == null) {
      return 'بانتظار البيانات';
    }

    final age =
        DateTime.now()
            .difference(
              _lastSignalTime!,
            )
            .inMilliseconds;

    if (age > 2500) {
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
  // UI
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Directionality(
      textDirection:
          TextDirection.rtl,
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
                _buildScanner(),

                const SizedBox(
                  height: 10,
                ),

                _buildMetrics(),

                const SizedBox(
                  height: 10,
                ),

                _buildSignalMeter(),

                const SizedBox(
                  height: 10,
                ),

                _buildGraph(),

                const SizedBox(
                  height: 10,
                ),

                _buildTarget(),

                const SizedBox(
                  height: 10,
                ),

                _buildStatusCards(),

                const SizedBox(
                  height: 10,
                ),

                _buildSettings(),

                const SizedBox(
                  height: 10,
                ),

                _buildControls(),

                const SizedBox(
                  height: 10,
                ),

                _buildTechnicalData(),

                const SizedBox(
                  height: 10,
                ),

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
      backgroundColor:
          const Color(0xFF030712),
      elevation: 0,
      centerTitle: true,
      title: Column(
        children: [
          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 22,
                fontWeight:
                    FontWeight.w900,
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
                    color:
                        Colors.cyanAccent,
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
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding:
              const EdgeInsets.only(
            left: 12,
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(
                  color: connected
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  shape:
                      BoxShape.circle,
                ),
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
                  fontSize: 10,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CIRCULAR SCANNER
  // ============================================================

  Widget _buildScanner() {
    return Container(
      height: 350,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(28),
        gradient:
            const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF091526),
            Color(0xFF050B15),
          ],
        ),
        border: Border.all(
          color:
              Colors.white.withOpacity(
            .07,
          ),
        ),
      ),
      child: AnimatedBuilder(
        animation:
            _animationController,
        builder: (
          context,
          child,
        ) {
          return Stack(
            alignment:
                Alignment.center,
            children: [
              CustomPaint(
                size:
                    const Size(
                  double.infinity,
                  350,
                ),
                painter:
                    GeoScannerPainter(
                  signal: signal,
                  pulse:
                      _animationController
                          .value,
                  scanning: scanning,
                ),
              ),

              Column(
                mainAxisAlignment:
                    MainAxisAlignment
                        .center,
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
                                  .only(
                            left: 7,
                          ),
                          decoration:
                              BoxDecoration(
                            color:
                                signalColor,
                            shape:
                                BoxShape
                                    .circle,
                          ),
                        ),
                      const Text(
                        'LIVE SCAN',
                        style:
                            TextStyle(
                          color:
                              Colors.white,
                          fontSize: 17,
                          fontWeight:
                              FontWeight
                                  .w900,
                          letterSpacing:
                              2,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 5,
                  ),

                  Text(
                    '${signal.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color:
                          signalColor,
                      fontSize: 57,
                      height: .95,
                      fontWeight:
                          FontWeight
                              .w900,
                    ),
                  ),

                  const SizedBox(
                    height: 8,
                  ),

                  Container(
                    padding:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 15,
                      vertical: 6,
                    ),
                    decoration:
                        BoxDecoration(
                      color: signalColor
                          .withOpacity(
                        .08,
                      ),
                      borderRadius:
                          BorderRadius
                              .circular(
                        30,
                      ),
                      border:
                          Border.all(
                        color: signalColor
                            .withOpacity(
                          .3,
                        ),
                      ),
                    ),
                    child: Text(
                      signalStatus,
                      style:
                          TextStyle(
                        color:
                            signalColor,
                        fontSize: 12,
                        fontWeight:
                            FontWeight
                                .bold,
                      ),
                    ),
                  ),
                ],
              ),

              Positioned(
                top: 16,
                right: 18,
                child:
                    _connectionBadge(),
              ),

              Positioned(
                bottom: 15,
                left: 18,
                child: Text(
                  scanning
                      ? 'استقبال مباشر من ESP32'
                      : 'جاهز للمسح',
                  style:
                      const TextStyle(
                    color:
                        Colors.white38,
                    fontSize: 9,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _connectionBadge() {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration:
          BoxDecoration(
        color:
            Colors.black.withOpacity(
          .25,
        ),
        borderRadius:
            BorderRadius.circular(
          20,
        ),
        border: Border.all(
          color:
              Colors.white12,
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
            color: connected
                ? Colors.greenAccent
                : Colors.redAccent,
            size: 14,
          ),
          const SizedBox(
            width: 5,
          ),
          Text(
            connected
                ? 'ESP32'
                : 'OFFLINE',
            style: TextStyle(
              color: connected
                  ? Colors.greenAccent
                  : Colors.redAccent,
              fontSize: 9,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // METRICS
  // ============================================================

  Widget _buildMetrics() {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: _metricCard(
            height: 158,
            title: 'شدة الإشارة',
            value:
                '${signal.toStringAsFixed(1)}%',
            subtitle:
                signalStatus,
            icon: Icons
                .signal_cellular_alt_rounded,
            color:
                signalColor,
          ),
        ),
        const SizedBox(
          width: 8,
        ),
        Expanded(
          flex: 4,
          child: Column(
            children: [
              _metricCard(
                height: 75,
                title:
                    'العمق التقريبي',
                value:
                    depthText,
                subtitle: '',
                icon:
                    Icons.layers_rounded,
                color:
                    Colors.greenAccent,
                horizontal: true,
              ),
              const SizedBox(
                height: 8,
              ),
              _metricCard(
                height: 75,
                title:
                    'استقرار الإشارة',
                value:
                    '${stability.toStringAsFixed(0)}%',
                subtitle: '',
                icon: Icons
                    .graphic_eq_rounded,
                color:
                    Colors.cyanAccent,
                horizontal: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricCard({
    required double height,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    bool horizontal = false,
  }) {
    return _card(
      height: height,
      child: horizontal
          ? Row(
              children: [
                Icon(
                  icon,
                  color: color,
                  size: 24,
                ),
                const SizedBox(
                  width: 8,
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment:
                        MainAxisAlignment
                            .center,
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
                      Text(
                        value,
                        style:
                            TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight:
                              FontWeight
                                  .w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              mainAxisAlignment:
                  MainAxisAlignment
                      .center,
              children: [
                Icon(
                  icon,
                  color: color,
                  size: 28,
                ),
                const SizedBox(
                  height: 4,
                ),
                Text(
                  title,
                  style:
                      const TextStyle(
                    color:
                        Colors.white54,
                    fontSize: 11,
                  ),
                ),
                Text(
                  value,
                  style:
                      TextStyle(
                    color: color,
                    fontSize: 25,
                    fontWeight:
                        FontWeight
                            .w900,
                  ),
                ),
                Text(
                  subtitle,
                  style:
                      TextStyle(
                    color: color,
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

  Widget _buildSignalMeter() {
    return _card(
      child: Column(
        children: [
          _header(
            'مستوى الإشارة',
            Icons
                .bar_chart_rounded,
          ),
          const SizedBox(
            height: 12,
          ),
          SizedBox(
            height: 35,
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
                      signal >=
                          level;

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
                        horizontal:
                            1,
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
          const SizedBox(
            height: 6,
          ),
          const Row(
            mainAxisAlignment:
                MainAxisAlignment
                    .spaceBetween,
            children: [
              Text(
                'ضعيفة',
                style:
                    TextStyle(
                  color:
                      Colors.redAccent,
                  fontSize: 9,
                ),
              ),
              Text(
                'متوسطة',
                style:
                    TextStyle(
                  color:
                      Colors.orangeAccent,
                  fontSize: 9,
                ),
              ),
              Text(
                'جيدة',
                style:
                    TextStyle(
                  color:
                      Colors.amberAccent,
                  fontSize: 9,
                ),
              ),
              Text(
                'قوية',
                style:
                    TextStyle(
                  color:
                      Colors.greenAccent,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _meterColor(
    int index,
  ) {
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

  // ============================================================
  // GRAPH
  // ============================================================

  Widget _buildGraph() {
    return _card(
      height: 205,
      child: Column(
        children: [
          _header(
            'حركة الإشارة',
            Icons
                .show_chart_rounded,
          ),
          const SizedBox(
            height: 8,
          ),
          Expanded(
            child: CustomPaint(
              painter:
                  SignalGraphPainter(
                values:
                    signalHistory,
                color:
                    signalColor,
              ),
              child:
                  const SizedBox
                      .expand(),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TARGET
  // ============================================================

  Widget _buildTarget() {
    return _card(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment
                .stretch,
        children: [
          _header(
            'تحليل الهدف',
            Icons.radar_rounded,
          ),
          const SizedBox(
            height: 10,
          ),
          Container(
            padding:
                const EdgeInsets.all(
              13,
            ),
            decoration:
                BoxDecoration(
              color: signalColor
                  .withOpacity(
                .06,
              ),
              borderRadius:
                  BorderRadius.circular(
                18,
              ),
              border:
                  Border.all(
                color: signalColor
                    .withOpacity(
                  .2,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration:
                      BoxDecoration(
                    shape:
                        BoxShape.circle,
                    color: signalColor
                        .withOpacity(
                      .08,
                    ),
                    border:
                        Border.all(
                      color:
                          signalColor
                              .withOpacity(
                        .3,
                      ),
                    ),
                  ),
                  child: Icon(
                    Icons.radar_rounded,
                    color:
                        signalColor,
                    size: 30,
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
                      const Text(
                        'النوع المحتمل',
                        style:
                            TextStyle(
                          color:
                              Colors.white54,
                          fontSize: 9,
                        ),
                      ),
                      const SizedBox(
                        height: 2,
                      ),
                      Text(
                        targetType.isEmpty
                            ? 'غير محدد'
                            : targetType,
                        maxLines: 1,
                        overflow:
                            TextOverflow
                                .ellipsis,
                        style:
                            TextStyle(
                          color:
                              signalColor,
                          fontSize: 21,
                          fontWeight:
                              FontWeight
                                  .w900,
                        ),
                      ),
                      Text(
                        targetStatus,
                        style:
                            const TextStyle(
                          color:
                              Colors.white60,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(
            height: 9,
          ),
          _analysisBar(
            'قوة الإشارة',
            signal,
            signalColor,
            Icons.bolt_rounded,
          ),
          const SizedBox(
            height: 7,
          ),
          _analysisBar(
            'الاستقرار',
            stability,
            Colors.cyanAccent,
            Icons
                .graphic_eq_rounded,
          ),
          const SizedBox(
            height: 7,
          ),
          _analysisBar(
            'الإشارة الخام',
            rawSignal,
            Colors.orangeAccent,
            Icons.memory_rounded,
          ),
          const SizedBox(
            height: 8,
          ),
          const Text(
            'التصنيف احتمالي ويعتمد على البيانات القادمة من ESP32.',
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              color:
                  Colors.white38,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _analysisBar(
    String title,
    double value,
    Color color,
    IconData icon,
  ) {
    final safe =
        value.clamp(
      0.0,
      100.0,
    );

    return Container(
      padding:
          const EdgeInsets.all(
        8,
      ),
      decoration:
          BoxDecoration(
        color:
            Colors.black.withOpacity(
          .12,
        ),
        borderRadius:
            BorderRadius.circular(
          13,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: color,
                size: 17,
              ),
              const SizedBox(
                width: 7,
              ),
              Expanded(
                child: Text(
                  title,
                  style:
                      const TextStyle(
                    color:
                        Colors.white70,
                    fontSize: 10,
                  ),
                ),
              ),
              Text(
                '${safe.toStringAsFixed(0)}%',
                style:
                    TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 5,
          ),
          ClipRRect(
            borderRadius:
                BorderRadius.circular(
              8,
            ),
            child:
                LinearProgressIndicator(
              value:
                  safe / 100,
              minHeight: 5,
              backgroundColor:
                  Colors.white
                      .withOpacity(
                .06,
              ),
              valueColor:
                  AlwaysStoppedAnimation<
                      Color>(
                color,
              ),
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
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 2.3,
      shrinkWrap: true,
      physics:
          const NeverScrollableScrollPhysics(),
      children: [
        _statusCard(
          'حالة الجهاز',
          connected
              ? (scanning
                  ? 'يمسح'
                  : 'متصل')
              : 'غير متصل',
          Icons.memory_rounded,
          connected
              ? Colors.greenAccent
              : Colors.redAccent,
        ),
        _statusCard(
          'الحساسية',
          '${sensitivity.toStringAsFixed(0)}%',
          Icons.tune_rounded,
          Colors.cyanAccent,
        ),
        _statusCard(
          'الفلترة',
          filter,
          Icons.filter_alt_rounded,
          Colors.cyanAccent,
        ),
        _statusCard(
          'التنبيه',
          audioEnabled
              ? 'يعمل'
              : 'متوقف',
          Icons.volume_up_rounded,
          audioEnabled
              ? Colors.greenAccent
              : Colors.white38,
        ),
        _statusCard(
          'الاهتزاز',
          vibrationEnabled
              ? 'يعمل'
              : 'متوقف',
          Icons.vibration_rounded,
          vibrationEnabled
              ? Colors.greenAccent
              : Colors.white38,
        ),
        _statusCard(
          'البيانات',
          '$receivedPackets',
          Icons.sync_rounded,
          Colors.amberAccent,
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
      padding:
          const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: color,
            size: 23,
          ),
          const SizedBox(
            width: 7,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment
                      .center,
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
                    fontSize: 8,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow:
                      TextOverflow
                          .ellipsis,
                  style:
                      TextStyle(
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
  // SETTINGS
  // ============================================================

  Widget _buildSettings() {
    return _card(
      child: Column(
        children: [
          _header(
            'إعدادات المسح',
            Icons.settings_rounded,
          ),
          const SizedBox(
            height: 10,
          ),
          Row(
            children: [
              const Icon(
                Icons.tune_rounded,
                color:
                    Colors.cyanAccent,
              ),
              const SizedBox(
                width: 8,
              ),
              const Text(
                'الحساسية',
                style:
                    TextStyle(
                  color:
                      Colors.white,
                  fontSize: 13,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${sensitivity.toStringAsFixed(0)}%',
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
            color:
                Colors.white10,
          ),
          Row(
            children: [
              const Icon(
                Icons.filter_alt_rounded,
                color:
                    Colors.cyanAccent,
              ),
              const SizedBox(
                width: 8,
              ),
              const Text(
                'الفلترة',
                style:
                    TextStyle(
                  color:
                      Colors.white,
                  fontSize: 13,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              const Spacer(),
              DropdownButton<String>(
                value: filter,
                dropdownColor:
                    const Color(
                  0xFF071321,
                ),
                underline:
                    const SizedBox(),
                style:
                    const TextStyle(
                  color:
                      Colors.white,
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
                    connected &&
                            !calibrating
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
            ],
          ),
          const Divider(
            color:
                Colors.white10,
          ),
          SwitchListTile(
            contentPadding:
                EdgeInsets.zero,
            title: const Text(
              'التنبيه الصوتي',
              style:
                  TextStyle(
                color:
                    Colors.white,
                fontSize: 13,
              ),
            ),
            subtitle:
                const Text(
              'إرسال الإعداد إلى ESP32',
              style:
                  TextStyle(
                color:
                    Colors.white38,
                fontSize: 9,
              ),
            ),
            secondary:
                const Icon(
              Icons
                  .volume_up_rounded,
              color:
                  Colors.cyanAccent,
            ),
            value:
                audioEnabled,
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
              style:
                  TextStyle(
                color:
                    Colors.white,
                fontSize: 13,
              ),
            ),
            secondary:
                const Icon(
              Icons
                  .vibration_rounded,
              color:
                  Colors.cyanAccent,
            ),
            value:
                vibrationEnabled,
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
  // BUTTONS
  // ============================================================

  Widget _buildControls() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 55,
                child:
                    FilledButton.icon(
                  onPressed:
                      connected &&
                              !scanning &&
                              !calibrating
                          ? startScan
                          : null,
                  icon: const Icon(
                    Icons
                        .play_arrow_rounded,
                  ),
                  label: const Text(
                    'بدء المسح',
                    style:
                        TextStyle(
                      fontWeight:
                          FontWeight
                              .bold,
                    ),
                  ),
                  style:
                      FilledButton
                          .styleFrom(
                    backgroundColor:
                        Colors
                            .greenAccent
                            .withOpacity(
                      .12,
                    ),
                    foregroundColor:
                     
