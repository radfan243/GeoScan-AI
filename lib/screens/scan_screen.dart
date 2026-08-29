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

  late AnimationController _radarController;

  final List<double> signalHistory = <double>[];
  final List<Map<String, dynamic>> savedReadings =
      <Map<String, dynamic>>[];

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

  int receivedPackets = 0;
  DateTime? lastReceivedAt;

  @override
  void initState() {
    super.initState();

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _listenToBluetooth();

    connected = _bluetooth.isConnected;
    if (connected) {
      deviceStatus = 'متصل';
    }
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _connectionSubscription?.cancel();
    _radarController.dispose();
    super.dispose();
  }

  // ============================================================
  // Bluetooth
  // ============================================================

  void _listenToBluetooth() {
    _dataSubscription = _bluetooth.dataStream.listen(
      _handleDeviceData,
      onError: (Object error) {
        debugPrint('GeoScan AI data error: $error');
      },
    );

    _connectionSubscription =
        _bluetooth.connectionStream.listen(
      _handleConnectionState,
      onError: (Object error) {
        debugPrint('GeoScan AI connection error: $error');
      },
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

        signal = 0.0;
        rawSignal = 0.0;
        stability = 0.0;
        depth = 0.0;

        signalHistory.clear();
        receivedPackets = 0;
        lastReceivedAt = null;
      } else {
        deviceStatus = 'متصل';
      }
    });
  }

  void _handleDeviceData(String rawData) {
    if (!mounted) return;

    final text = rawData.trim();

    if (text.isEmpty) return;

    debugPrint('GeoScan AI <- ESP32: $text');

    receivedPackets++;
    lastReceivedAt = DateTime.now();

    dynamic decoded;

    try {
      decoded = jsonDecode(text);
    } catch (_) {
      final match = RegExp(
        r'[-+]?\d*\.?\d+',
      ).firstMatch(text);

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

    final data = Map<String, dynamic>.from(decoded);

    final incomingSignal = data.containsKey('signal')
        ? _toDouble(data['signal'])
        : data.containsKey('value')
            ? _toDouble(data['value'])
            : data.containsKey('strength')
                ? _toDouble(data['strength'])
                : signal;

    final incomingRaw = data.containsKey('raw')
        ? _toDouble(data['raw'])
        : incomingSignal;

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

    bool incomingScanning = scanning;

    if (data.containsKey('scanning')) {
      final value = data['scanning'];

      if (value is bool) {
        incomingScanning = value;
      } else {
        final valueText = value.toString().toLowerCase();

        incomingScanning =
            valueText == 'true' ||
            valueText == '1' ||
            valueText == 'scan' ||
            valueText == 'scanning' ||
            valueText == 'يمسح' ||
            valueText == 'مسح';
      }
    } else {
      final status = incomingStatus.toLowerCase();

      if (status == 'scanning' ||
          status == 'scan' ||
          incomingStatus == 'يمسح' ||
          incomingStatus == 'مسح') {
        incomingScanning = true;
      }
    }

    final safeSignal =
        incomingSignal.clamp(0.0, 100.0).toDouble();

    final safeRaw =
        incomingRaw.clamp(0.0, 100.0).toDouble();

    final safeStability =
        incomingStability.clamp(0.0, 100.0).toDouble();

    final safeDepth =
        incomingDepth.isFinite && incomingDepth >= 0
            ? incomingDepth
            : 0.0;

    final displayedSignal = signal == 0.0
        ? safeSignal
        : (signal * 0.72) + (safeSignal * 0.28);

    final finalSignal =
        displayedSignal.clamp(0.0, 100.0).toDouble();

    if (!mounted) return;

    setState(() {
      signal = finalSignal;
      rawSignal = safeRaw;
      stability = safeStability;
      depth = safeDepth;

      deviceStatus = incomingStatus.isEmpty
          ? (incomingScanning ? 'يمسح' : 'متصل')
          : incomingStatus;

      scanning = incomingScanning;

      if (incomingTarget.isNotEmpty) {
        targetType = incomingTarget;
      }

      if (signalHistory.length >= 80) {
        signalHistory.removeAt(0);
      }

      signalHistory.add(finalSignal);
    });
  }

  void _updateSignalOnly(double value) {
    if (!mounted) return;

    final safe = value.clamp(0.0, 100.0).toDouble();

    final displayed = signal == 0.0
        ? safe
        : (signal * 0.72) + (safe * 0.28);

    final finalSignal =
        displayed.clamp(0.0, 100.0).toDouble();

    setState(() {
      rawSignal = safe;
      signal = finalSignal;

      if (signalHistory.length >= 80) {
        signalHistory.removeAt(0);
      }

      signalHistory.add(finalSignal);
    });
  }

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value.toString().replaceAll(',', '.').trim(),
        ) ??
        0.0;
  }

  // ============================================================
  // Real commands
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

    if (scanning) {
      return;
    }

    try {
      final success =
          await _bluetooth.startScanning();

      if (!mounted) return;

      if (!success) {
        _showMessage(
          'تعذر إرسال أمر بدء المسح إلى ESP32',
        );
        return;
      }

      setState(() {
        scanning = true;
        deviceStatus = 'يمسح';
        signalHistory.clear();
      });

      _showMessage('بدأ المسح الحقيقي');
    } catch (e) {
      debugPrint('Start scan error: $e');
      _showMessage('حدث خطأ أثناء بدء المسح');
    }
  }

  Future<void> stopScan() async {
    if (!connected) {
      return;
    }

    try {
      final success =
          await _bluetooth.stopScanning();

      if (!mounted) return;

      if (!success) {
        _showMessage(
          'تعذر إرسال أمر إيقاف المسح إلى ESP32',
        );
        return;
      }

      setState(() {
        scanning = false;
        deviceStatus = 'متوقف';
      });

      _showMessage('تم إيقاف المسح');
    } catch (e) {
      debugPrint('Stop scan error: $e');
      _showMessage('حدث خطأ أثناء إيقاف المسح');
    }
  }

  Future<void> calibrate() async {
    if (!connected) {
      _showMessage('يجب الاتصال بجهاز ESP32 أولًا');
      return;
    }

    if (scanning) {
      _showMessage(
        'أوقف المسح أولًا ثم قم بالمعايرة',
      );
      return;
    }

    setState(() {
      calibrating = true;
      deviceStatus = 'معايرة';
      signalHistory.clear();
      signal = 0.0;
      rawSignal = 0.0;
      depth = 0.0;
    });

    try {
      final success =
          await _bluetooth.sendCommand(
        'CALIBRATE',
      );

      if (!mounted) return;

      setState(() {
        calibrating = false;
        deviceStatus =
            success ? 'جاهز' : 'متصل';

        if (success) {
          stability = 100.0;
        }
      });

      _showMessage(
        success
            ? 'تم إرسال أمر المعايرة إلى ESP32'
            : 'تعذر إرسال أمر المعايرة',
      );
    } catch (e) {
      debugPrint('Calibration error: $e');

      if (!mounted) return;

      setState(() {
        calibrating = false;
        deviceStatus =
            connected ? 'متصل' : 'غير متصل';
      });

      _showMessage('تعذر تنفيذ المعايرة');
    }
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
        await _bluetooth.setSensitivity(safe);

    if (!mounted) return;

    if (success) {
      setState(() {
        sensitivity = safe;
      });
    } else {
      _showMessage('تعذر تغيير الحساسية');
    }
  }

  Future<void> changeFilter(
    String value,
  ) async {
    if (!connected || calibrating) {
      return;
    }

    final success =
        await _bluetooth.setFilter(value);

    if (!mounted) return;

    if (success) {
      setState(() {
        filter = value;
      });
    } else {
      _showMessage('تعذر تغيير الفلترة');
    }
  }

  Future<void> toggleAudio(
    bool value,
  ) async {
    if (!connected) {
      return;
    }

    final success =
        await _bluetooth.setAudio(value);

    if (!mounted) return;

    if (success) {
      setState(() {
        audioEnabled = value;
      });
    } else {
      _showMessage('تعذر تغيير التنبيه الصوتي');
    }
  }

  Future<void> toggleVibration(
    bool value,
  ) async {
    if (!connected) {
      return;
    }

    final success =
        await _bluetooth.setVibration(value);

    if (!mounted) return;

    if (success) {
      setState(() {
        vibrationEnabled = value;
      });

      if (value) {
        HapticFeedback.mediumImpact();
      }
    } else {
      _showMessage('تعذر تغيير الاهتزاز');
    }
  }

  // ============================================================
  // Local save
  // ============================================================

  void saveReading() {
    if (!connected) {
      _showMessage(
        'لا يمكن حفظ قراءة والجهاز غير متصل',
      );
      return;
    }

    if (lastReceivedAt == null) {
      _showMessage(
        'لا توجد بيانات مستلمة من ESP32 بعد',
      );
      return;
    }

    setState(() {
      savedReadings.add({
        'signal': signal,
        'raw': rawSignal,
        'stability': stability,
        'depth': depth,
        'target': targetType,
        'status': deviceStatus,
        'sensitivity': sensitivity,
        'filter': filter,
        'time': DateTime.now(),
      });
    });

    HapticFeedback.mediumImpact();

    _showMessage(
      'تم حفظ القراءة رقم ${savedReadings.length}',
    );
  }

  void resetReading() {
    setState(() {
      signal = 0.0;
      rawSignal = 0.0;
      stability = 0.0;
      depth = 0.0;
      signalHistory.clear();
    });

    _showMessage('تم تصفير العرض');
  }

  // ============================================================
  // UI helpers
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
    if (!connected) {
      return 'غير متصل';
    }

    if (calibrating) {
      return 'معايرة';
    }

    if (!scanning) {
      return 'جاهز';
    }

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

  String get targetStatus {
    if (!connected) {
      return 'لا توجد بيانات';
    }

    if (lastReceivedAt == null) {
      return 'بانتظار ESP32';
    }

    if (signal < 25) {
      return 'لا توجد إشارة واضحة';
    }

    if (signal < 50) {
      return 'تغير يحتاج إلى فحص';
    }

    if (signal < 75) {
      return 'تغير ملحوظ';
    }

    return 'تغير قوي - تحقق ميدانيًا';
  }

  String get dataAge {
    if (lastReceivedAt == null) {
      return '--';
    }

    final age =
        DateTime.now().difference(lastReceivedAt!);

    return '${age.inMilliseconds} ms';
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
        ),
      );
  }

  // ============================================================
  // Main build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF020711),
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),

              Expanded(
                child: SingleChildScrollView(
                  physics:
                      const BouncingScrollPhysics(),
                  padding:
                      const EdgeInsets.fromLTRB(
                    14,
                    8,
                    14,
                    20,
                  ),
                  child: Column(
                    children: [
                      _buildScanner(),

                      const SizedBox(height: 10),

                      _buildMeter(),

                      const SizedBox(height: 12),

                      _buildAnalysis(),

                      const SizedBox(height: 12),

                      _buildLikelyTarget(),

                      const SizedBox(height: 12),

                      _buildStatusCards(),

                      const SizedBox(height: 12),

                      _buildSettings(),

                      const SizedBox(height: 12),

                      _buildControls(),

                      const SizedBox(height: 12),

                      _buildTechnicalData(),

                      const SizedBox(height: 12),

                      _buildScientificNotice(),
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
  // Header
  // ============================================================

  Widget _buildHeader() {
    return Container(
      height: 76,
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
              size: 30,
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
                        Color(0xFF75D9FF),
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
                const SizedBox(height: 2),
                const Text(
                  'المسح المباشر',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                connected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                color: connected
                    ? Colors.greenAccent
                    : Colors.redAccent,
                size: 25,
              ),
              const SizedBox(width: 4),
              Text(
                connected ? 'متصل' : 'غير متصل',
                style: TextStyle(
                  color: connected
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),

          IconButton(
            onPressed: _openMore,
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
  // Main scanner
  // ============================================================

  Widget _buildScanner() {
    return SizedBox(
      height: 360,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _radarController,
            builder: (context, child) {
              return CustomPaint(
                size: const Size(
                  double.infinity,
                  360,
                ),
                painter: RadarBackgroundPainter(
                  progress:
                      _radarController.value,
                ),
              );
            },
          ),

          CustomPaint(
            size: const Size(
              double.infinity,
              360,
            ),
            painter: MainScannerPainter(
              value: signal,
              color: signalColor,
            ),
          ),

          Positioned(
            top: 112,
            child: Column(
              children: [
                const Text(
                  'LIVE SCAN',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  '${signal.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: signalColor,
                    fontSize: 58,
                    fontWeight: FontWeight.w300,
                    height: 1,
                  ),
                ),

                const SizedBox(height: 6),

                Row(
                  children: [
                    Icon(
                      scanning
                          ? Icons.radar
                          : Icons.pause_circle_outline,
                      color: signalColor,
                      size: 19,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      scanning
                          ? 'إشارة $signalStatus'
                          : signalStatus,
                      style: TextStyle(
                        color: signalColor,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Positioned(
            left: 0,
            top: 28,
            child: _buildSignalCard(),
          ),

          Positioned(
            right: 0,
            top: 28,
            child: _buildDepthCard(),
          ),

          Positioned(
            right: 0,
            top: 180,
            child: _buildStabilityCard(),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalCard() {
    return _glassCard(
      width: 150,
      height: 145,
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          const Text(
            'شدة الإشارة',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          SizedBox(
            height: 44,
            child: Row(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              crossAxisAlignment:
                  CrossAxisAlignment.end,
              children:
                  List.generate(5, (index) {
                final threshold =
                    (index + 1) * 20;
                final active =
                    signal >= threshold;

                return AnimatedContainer(
                  duration:
                      const Duration(
                    milliseconds: 180,
                  ),
                  width: 8,
                  height:
                      14.0 + (index * 7),
                  margin:
                      const EdgeInsets.symmetric(
                    horizontal: 3,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? signalColor
                        : Colors.white12,
                    borderRadius:
                        BorderRadius.circular(5),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 5),

          Text(
            '${signal.toStringAsFixed(1)}%',
            style: TextStyle(
              color: signalColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),

          Text(
            signalStatus,
            style: TextStyle(
              color: signalColor,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepthCard() {
    return _glassCard(
      width: 150,
      height: 92,
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          const Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              Icon(
                Icons.gps_fixed,
                color: Colors.white,
                size: 20,
              ),
              SizedBox(width: 5),
              Text(
                'العمق التقريبي',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            depth > 0
                ? '${depth.toStringAsFixed(2)} m'
                : '-- m',
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 23,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStabilityCard() {
    return _glassCard(
      width: 150,
      height: 92,
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          const Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              Icon(
                Icons.graphic_eq,
                color: Colors.white,
                size: 20,
              ),
              SizedBox(width: 5),
              Text(
                'استقرار الإشارة',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${stability.toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 23,
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF07121F)
            .withOpacity(0.94),
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color:
              Colors.cyanAccent.withOpacity(0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(0.35),
            blurRadius: 15,
          ),
        ],
      ),
      child: child,
    );
  }

  // ============================================================
  // Meter
  // ============================================================

  Widget _buildMeter() {
    return _panel(
      child: Column(
        children: [
          const Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '0',
                style:
                    TextStyle(color: Colors.white54),
              ),
              Text(
                '20',
                style:
                    TextStyle(color: Colors.white54),
              ),
              Text(
                '40',
                style:
                    TextStyle(color: Colors.white54),
              ),
              Text(
                '60',
                style:
                    TextStyle(color: Colors.white54),
              ),
              Text(
                '80',
                style:
                    TextStyle(color: Colors.white54),
              ),
              Text(
                '100',
                style:
                    TextStyle(color: Colors.white54),
              ),
            ],
          ),

          const SizedBox(height: 6),

          SizedBox(
            height: 28,
            child: Row(
              children:
                  List.generate(40, (index) {
                final value =
                    index * 2.5;

                final Color barColor =
                    value < 25
                        ? Colors.redAccent
                        : value < 50
                            ? Colors.orangeAccent
                            : value < 75
                                ? Colors.amberAccent
                                : Colors.greenAccent;

                final active =
                    signal >= value;

                return Expanded(
                  child: AnimatedContainer(
                    duration:
                        const Duration(
                      milliseconds: 100,
                    ),
                    margin:
                        const EdgeInsets.symmetric(
                      horizontal: 1,
                    ),
                    decoration:
                        BoxDecoration(
                      color: active
                          ? barColor
                          : barColor.withOpacity(
                              0.10,
                            ),
                      borderRadius:
                          BorderRadius.circular(3),
                    ),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 6),

          const Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceAround,
            children: [
              Text(
                'ضعيفة',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              Text(
                'متوسطة',
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              Text(
                'قوية',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Analysis
  // ============================================================

  Widget _buildAnalysis() {
    return Column(
      children: [
        _buildGraph(),

        const SizedBox(height: 10),

        _buildTargetAnalysis(),
      ],
    );
  }

  Widget _buildGraph() {
    return _panel(
      height: 240,
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(
            'حركة الإشارة',
            Icons.show_chart,
          ),

          const SizedBox(height: 10),

          Expanded(
            child: CustomPaint(
              painter: SignalGraphPainter(
                values: signalHistory,
              ),
              child:
                  const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetAnalysis() {
    final targetSignal =
        signal.clamp(0.0, 100.0).toDouble();

    return _panel(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(
            'تحليل الهدف',
            Icons.radar,
          ),

          const SizedBox(height: 10),

          _targetRow(
            title: targetType.isEmpty
                ? 'الهدف'
                : targetType,
            value: targetSignal,
            color: signalColor,
            icon: Icons.radar,
          ),

          const SizedBox(height: 8),

          _targetRow(
            title: 'استقرار الإشارة',
            value: stability,
            color: Colors.cyanAccent,
            icon: Icons.graphic_eq,
          ),

          const SizedBox(height: 8),

          _targetRow(
            title: 'الإشارة الخام',
            value: rawSignal,
            color: Colors.orangeAccent,
            icon: Icons.memory,
          ),

          const SizedBox(height: 10),

          Text(
            targetStatus,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: signalColor,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetRow({
    required String title,
    required double value,
    required Color color,
    required IconData icon,
  }) {
    final safe =
        value.clamp(0.0, 100.0).toDouble();

    return Container(
      padding:
          const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color:
            Colors.black.withOpacity(0.14),
        borderRadius:
            BorderRadius.circular(13),
        border: Border.all(
          color:
              Colors.white.withOpacity(0.06),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: color,
                size: 21,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                '${safe.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: color,
                  fontWeight:
                      FontWeight.bold,
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
              minHeight: 7,
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
    );
  }

  // ============================================================
  // Likely target
  // ============================================================

  Widget _buildLikelyTarget() {
    final color = signalColor;

    final title =
        targetType.isEmpty ||
                targetType == 'غير محدد'
            ? 'غير محدد'
            : targetType;

    return _panel(
      child: Row(
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  color.withOpacity(0.07),
              border: Border.all(
                color:
                    color.withOpacity(0.25),
              ),
            ),
            child: Icon(
              Icons.radar,
              color: color,
              size: 50,
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
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 23,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  '${signal.toStringAsFixed(0)}% مؤشر الإشارة',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                  ),
                ),

                const SizedBox(height: 4),

                const Text(
                  'هذه قراءة إشارة وليست إثباتًا لنوع المادة.',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
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
  // Status cards
  // ============================================================

  Widget _buildStatusCards() {
    return SizedBox(
      height: 108,
      child: Row(
        children: [
          Expanded(
            child: _statusCard(
              icon: Icons.monitor_heart,
              title: 'الجهاز',
              value: connected
                  ? 'متصل'
                  : 'غير متصل',
              color: connected
                  ? Colors.greenAccent
                  : Colors.redAccent,
            ),
          ),

          const SizedBox(width: 5),

          Expanded(
            child: _statusCard(
              icon: Icons.tune,
              title: 'الحساسية',
              value:
                  '${sensitivity.toStringAsFixed(0)}%',
              color: Colors.cyanAccent,
            ),
          ),

          const SizedBox(width: 5),

          Expanded(
            child: _statusCard(
              icon: Icons.filter_alt,
              title: 'الفلترة',
              value: filter,
              color: Colors.cyanAccent,
              onTap: _showFilterDialog,
            ),
          ),

          const SizedBox(width: 5),

          Expanded(
            child: _statusCard(
              icon: Icons.volume_up,
              title: 'التنبيه',
              value: audioEnabled
                  ? 'يعمل'
                  : 'متوقف',
              color: audioEnabled
                  ? Colors.greenAccent
                  : Colors.white38,
              onTap: () {
                toggleAudio(
                  !audioEnabled,
                );
              },
            ),
          ),

          const SizedBox(width: 5),

          Expanded(
            child: _statusCard(
              icon: Icons.vibration,
              title: 'الاهتزاز',
              value: vibrationEnabled
                  ? 'يعمل'
                  : 'متوقف',
              color: vibrationEnabled
                  ? Colors.greenAccent
                  : Colors.white38,
              onTap: () {
                toggleVibration(
                  !vibrationEnabled,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius:
          BorderRadius.circular(15),
      child: Container(
        padding:
            const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color:
              const Color(0xFF07121F),
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
              size: 24,
            ),

            const SizedBox(height: 4),

            Text(
              title,
              maxLines: 1,
              overflow:
                  TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 9,
              ),
            ),

            const SizedBox(height: 3),

            Text(
              value,
              maxLines: 1,
              overflow:
                  TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Settings
  // ============================================================

  Widget _buildSettings() {
    return _panel(
      child: Column(
        children: [
          _sectionTitle(
            'إعدادات المسح',
            Icons.settings,
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              const Icon(
                Icons.tune,
                color: Colors.cyanAccent,
              ),

              const SizedBox(width: 8),

              const Text(
                'الحساسية',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight:
                      FontWeight.bold,
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
            onChanged:
                connected && !calibrating
                    ? changeSensitivity
                    : null,
          ),

          const Divider(
            color: Colors.white12,
          ),

          Row(
            children: [
              const Icon(
                Icons.filter_alt,
                color: Colors.cyanAccent,
              ),

              const SizedBox(width: 8),

              const Text(
                'الفلترة',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const Spacer(),

              DropdownButton<String>(
                value: filter,
                dropdownColor:
                    const Color(0xFF07121F),
                underline:
                    const SizedBox(),
                style: const TextStyle(
                  color: Colors.white,
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
                    connected && !calibrating
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
            color: Colors.white12,
          ),

          SwitchListTile(
            contentPadding:
                EdgeInsets.zero,
            title: const Text(
              'التنبيه الصوتي',
              style: TextStyle(
                color: Colors.white,
              ),
            ),
            secondary: const Icon(
              Icons.volume_up,
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
              ),
            ),
            secondary: const Icon(
              Icons.vibration,
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
                height: 58,
                child: FilledButton.icon(
                  onPressed:
                      connected &&
                              !scanning &&
                              !calibrating
                          ? startScan
                          : null,
                  icon: const Icon(
                    Icons.play_arrow,
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
                      FilledButton.styleFrom(
                    backgroundColor:
                        Colors.greenAccent
                            .withOpacity(
                      0.12,
                    ),
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
                        15,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 7),

            Expanded(
              child: SizedBox(
                height: 58,
                child: OutlinedButton.icon(
                  onPressed:
                      scanning
                          ? stopScan
                          : null,
                  icon: const Icon(
                    Icons.stop,
                  ),
                  label: const Text(
                    'إيقاف المسح',
                    style: TextStyle(
                      fontSize: 15,
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
                        15,
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
                        Icons.refresh,
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
                  side:
                      const BorderSide(
                    color:
                        Colors.cyanAccent,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    connected
                        ? saveReading
                        : null,
                icon: const Icon(
                  Icons.save,
                ),
                label: const Text(
                  'حفظ القراءة',
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
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        SizedBox(
          width: double.infinity,
          height: 50,
          child: TextButton.icon(
            onPressed: resetReading,
            icon: const Icon(
              Icons.restart_alt,
            ),
            label: const Text(
              'تصفير العرض',
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // Technical data
  // ============================================================

  Widget _buildTechnicalData() {
    return _panel(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(
            'بيانات 
