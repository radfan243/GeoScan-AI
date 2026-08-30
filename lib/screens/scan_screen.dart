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
  Map<String, double> materialScores = <String, double>{};

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
      duration: const Duration(milliseconds: 1400),
    )..repeat();

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
      const <String>[
        'signal',
        'value',
        'strength',
        'reading',
      ],
      signal,
    );

    final double incomingRaw = _readDouble(
      data,
      const <String>[
        'raw',
        'rawSignal',
      ],
      rawSignal,
    );

    final double incomingBaseline = _readDouble(
      data,
      const <String>[
        'baseline',
        'base',
      ],
      baseline,
    );

    final double incomingStability = _readDouble(
      data,
      const <String>[
        'stability',
        'stable',
      ],
      stability,
    );

    final double incomingDepth = _readDouble(
      data,
      const <String>[
        'depth',
        'distance',
      ],
      depth,
    );

    final Map<String, double> incomingMaterials = <String, double>{};

    final dynamic materialsRaw = data['materials'];

    if (materialsRaw is Map) {
      materialsRaw.forEach((dynamic key, dynamic value) {
        if (value is num) {
          incomingMaterials[key.toString()] =
              value.toDouble().clamp(0.0, 100.0);
        }
      });
    }

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
      const <String>[
        'sequence',
        'seq',
      ],
    );

    final double displayedSignal =
        signal == 0
            ? safeSignal
            : signal * .70 + safeSignal * .30;

    final double finalSignal =
        displayedSignal.clamp(0.0, 100.0).toDouble();

    setState(() {
      signal = finalSignal;
      rawSignal = incomingRaw;
      baseline = incomingBaseline;
      stability = safeStability;
      depth = safeDepth;

      if (incomingMaterials.isNotEmpty) {
        materialScores = incomingMaterials;
      }

      if (status.isNotEmpty) {
        deviceStatus = status;
      } else {
        deviceStatus = incomingScanning ? 'يمسح' : 'متصل';
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

      if (value is num) return value.round();

      return int.tryParse(value.toString().trim());
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
    if (!connected) {
      _showMessage('اتصل بجهاز ESP32 أولًا');
      return;
    }

    final bool result =
        await _bluetooth.setTarget(target);

    if (!mounted) return;

    if (result) {
      setState(() {
        targetType = target;
      });

      _showMessage('تم اختيار الهدف: $target');
    } else {
      _showMessage('تعذر إرسال نوع الهدف');
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

    savedReadings.add(
      <String, dynamic>{
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
      },
    );

    HapticFeedback.mediumImpact();

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
      backgroundColor: const Color(0xFF07111E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(26),
        ),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                18,
                18,
                18,
                24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 45,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius:
                          BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'GeoScan AI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF030912),
        appBar: _buildAppBar(),
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              14,
              8,
              14,
              20,
            ),
            child: Column(
              children: [
                _buildHeroScanner(),
                const SizedBox(height: 12),
                _buildSignalLevel(),
                const SizedBox(height: 12),
                _buildMainContent(),
                const SizedBox(height: 12),
                _buildStatusCards(),
                const SizedBox(height: 12),
                _buildControls(),
                const SizedBox(height: 12),
                _buildSettings(),
                const SizedBox(height: 12),
                _buildTechnicalData(),
                const SizedBox(height: 12),
                _buildNotice(),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _buildBottomNavigation(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF030912),
      elevation: 0,
      centerTitle: true,
      toolbarHeight: 82,
      leading: IconButton(
        onPressed: _openQuickMenu,
        icon: const Icon(
          Icons.menu_rounded,
          color: Colors.white,
          size: 34,
        ),
      ),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RichText(
            text: const TextSpan(
              children: [
                TextSpan(
                  text: 'Geo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(
                  text: 'Scan',
                  style: TextStyle(
                    color: Color(0xFF8BD7FF),
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(
                  text: ' AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const Text(
            'المسح المباشر',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(
            left: 4,
            right: 4,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                connected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                color: connected
                    ? Colors.cyanAccent
                    : Colors.redAccent,
                size: 27,
              ),
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
        IconButton(
          onPressed: _openQuickMenu,
          icon: const Icon(
            Icons.more_vert_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
      ],
    );
  }

  Widget _buildHeroScanner() {
    return LayoutBuilder(
      builder: (
        BuildContext context,
        BoxConstraints constraints,
      ) {
        final bool wide = constraints.maxWidth >= 700;

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildMetricCard(
                  'شدة الإشارة',
                  '${signal.toStringAsFixed(1)}%',
                  signalStatus,
                  Icons.signal_cellular_alt_rounded,
                  signalColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _buildGaugeCard(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  children: [
                    _buildMetricCard(
                      'العمق التقريبي',
                      depthText,
                      depth > 0
                          ? 'قراءة ESP32'
                          : 'لا توجد قراءة',
                      Icons.gps_fixed_rounded,
                      Colors.greenAccent,
                    ),
                    const SizedBox(height: 10),
                    _buildMetricCard(
                      'استقرار الإشارة',
                      '${stability.toStringAsFixed(0)}%',
                      'استقرار القراءة',
                      Icons.graphic_eq_rounded,
                      Colors.greenAccent,
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            _buildGaugeCard(),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    'شدة الإشارة',
                    '${signal.toStringAsFixed(1)}%',
                    signalStatus,
                    Icons.signal_cellular_alt_rounded,
                    signalColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricCard(
                    'العمق التقريبي',
                    depthText,
                    depth > 0
                        ? 'قراءة ESP32'
                        : 'لا توجد قراءة',
                    Icons.gps_fixed_rounded,
                    Colors.greenAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricCard(
                    'الاستقرار',
                    '${stability.toStringAsFixed(0)}%',
                    'الإشارة',
                    Icons.graphic_eq_rounded,
                    Colors.greenAccent,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildGaugeCard() {
    return _panel(
      padding: const EdgeInsets.fromLTRB(
        10,
        12,
        10,
        8,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    scanning
                        ? Icons.radar_rounded
                        : Icons.radar_outlined,
                    color: signalColor,
                    size: 20,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    scanning ? 'LIVE SCAN' : 'READY',
                    style: TextStyle(
                      color: signalColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              _liveBadge(),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 285,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (
                BuildContext context,
                BoxConstraints constraints,
              ) {
                final double size =
                    math.min(
                      constraints.maxWidth,
                      330,
                    );

                return Center(
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (
                        BuildContext context,
                        Widget? child,
                      ) {
                        return CustomPaint(
                          painter: GeoGaugePainter(
                            signal: signal,
                            scanning: scanning,
                            pulse:
                                _pulseController.value,
                          ),
                          child: Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.only(
                                top: 50,
                              ),
                              child: Column(
                                mainAxisSize:
                                    MainAxisSize.min,
                                children: [
                                  const Text(
                                    'LIVE SCAN',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 21,
                                      fontWeight:
                                          FontWeight.w800,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${signal.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      color: signalColor,
                                      fontSize: 52,
                                      height: .95,
                                      fontWeight:
                                          FontWeight.w900,
                                      shadows: [
                                        Shadow(
                                          color: signalColor
                                              .withOpacity(.35),
                                          blurRadius: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    signalStatus,
                                    style: TextStyle(
                                      color: signalColor,
                                      fontSize: 14,
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: connected
            ? Colors.greenAccent.withOpacity(.08)
            : Colors.redAccent.withOpacity(.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: connected
              ? Colors.greenAccent.withOpacity(.35)
              : Colors.redAccent.withOpacity(.35),
        ),
      ),
      child: Text(
        connected ? 'متصل' : 'OFF',
        style: TextStyle(
          color: connected
              ? Colors.greenAccent
              : Colors.redAccent,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return _panel(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: color,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              color: color.withOpacity(.8),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalLevel() {
    return _panel(
      child: Column(
        children: [
          _sectionTitle(
            'مستوى الإشارة',
            Icons.bar_chart_rounded,
          ),
          const SizedBox(height: 11),
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                '0',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                ),
              ),
              Text(
                '20',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                ),
              ),
              Text(
                '40',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                ),
              ),
              Text(
                '60',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                ),
              ),
              Text(
                '80',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                ),
              ),
              Text(
                '100',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 28,
            child: Row(
              children: List.generate(
                40,
                (int index) {
                  final double level =
                      ((index + 1) / 40) * 100;
                  final bool active =
                      signal >= level;

                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(
                        milliseconds: 130,
                      ),
                      margin:
                          const EdgeInsets.symmetric(
                        horizontal: 1,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? _meterColor(index)
                            : Colors.white
                                .withOpacity(.055),
                        borderRadius:
                            BorderRadius.circular(4),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'ضعيفة',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'متوسطة',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'قوية',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _meterColor(int index) {
    if (index < 8) return Colors.redAccent;
    if (index < 18) return Colors.orangeAccent;
    if (index < 28) return Colors.amberAccent;
    return Colors.greenAccent;
  }

  Widget _buildMainContent() {
    return LayoutBuilder(
      builder: (
        BuildContext context,
        BoxConstraints constraints,
      ) {
        final bool wide = constraints.maxWidth >= 700;

        if (wide) {
          return Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    _buildSignalGraph(),
                    const SizedBox(height: 12),
                    _buildPotentialTarget(),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildTargetAnalysis(),
              ),
            ],
          );
        }

        return Column(
          children: [
            _buildSignalGraph(),
            const SizedBox(height: 12),
            _buildTargetAnalysis(),
            const SizedBox(height: 12),
            _buildPotentialTarget(),
          ],
        );
      },
    );
  }

  Widget _buildSignalGraph() {
    return _panel(
      child: Column(
        children: [
          _sectionTitle(
            'حركة الإشارة',
            Icons.show_chart_rounded,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 175,
            width: double.infinity,
            child: CustomPaint(
              painter: SignalGraphPainter(
                values: signalHistory,
                lineColor: signalColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetAnalysis() {
    return _panel(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              _sectionTitle(
                'تحليل الهدف',
                Icons.radar_rounded,
              ),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white38,
                  ),
                ),
                child: const Center(
                  child: Text(
                    '?',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _targetRow(
            'ذهب',
            _targetScore('ذهب'),
            Icons.diamond,
            Colors.greenAccent,
          ),
          _targetRow(
            'نحاس',
            _targetScore('نحاس'),
            Icons.bolt,
            Colors.orangeAccent,
          ),
          _targetRow(
            'فضة',
            _targetScore('فضة'),
            Icons.circle_outlined,
            Colors.lightBlueAccent,
          ),
          _targetRow(
            'حديد',
            _targetScore('حديد'),
            Icons.hardware_rounded,
            Colors.redAccent,
          ),
          _targetRow(
            'ماء',
            _targetScore('ماء'),
            Icons.water_drop_rounded,
            Colors.cyanAccent,
          ),
          const SizedBox(height: 7),
          Text(
            'النسب تقديرية لعرض الإشارة وليست تعريفًا علميًا للمادة.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  int _targetScore(String target) {
    if (!connected || signal <= 0) return 0;

    if (materialScores.containsKey(target)) {
      return materialScores[target]!.round().clamp(0, 100);
    }

    return 0;
  }

  Widget _targetRow(
    String name,
    int percentage,
    IconData icon,
    Color color,
  ) {
    final bool selected = targetType == name;

    return GestureDetector(
      onTap: () => selectTarget(name),
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: selected
              ? color.withOpacity(.07)
              : const Color(0xFF07111D),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? color.withOpacity(.55)
                : Colors.white.withOpacity(.08),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(.09),
              ),
              child: Icon(
                icon,
                color: color,
                size: 21,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$percentage%',
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius:
                        BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      value: percentage / 100,
                      minHeight: 7,
                      backgroundColor:
                          Colors.white.withOpacity(.07),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(
                        color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPotentialTarget() {
    final String displayTarget =
        targetType == 'غير محدد'
            ? 'غير محدد'
            : targetType;

    final int score =
        _targetScore(displayTarget);

    final Color color =
        displayTarget == 'ذهب'
            ? Colors.amberAccent
            : signalColor;

    return _panel(
      child: Column(
        children: [
          _sectionTitle(
            'نوع الهدف المحتمل',
            Icons.search_rounded,
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(.14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withOpacity(.22),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withOpacity(.07),
                    border: Border.all(
                      color: color.withOpacity(.25),
                    ),
                  ),
                  child: Icon(
                    _targetIcon(displayTarget),
                    color: color,
                    size: 44,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayTarget == 'غير محدد'
                            ? 'لا يوجد هدف محدد'
                            : '$displayTarget محتمل',
                        style: TextStyle(
                          color: color,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$score%',
                        style: TextStyle(
                          color: signalColor,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'يرجى تأكيد النتيجة بالحفر والاختبار الميداني.',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _targetIcon(String target) {
    switch (target) {
      case 'ذهب':
        return Icons.diamond;
      case 'فضة':
        return Icons.circle_outlined;
      case 'نحاس':
        return Icons.bolt;
      case 'ماء':
        return Icons.water_drop;
      case 'حديد':
        return Icons.hardware_rounded;
      default:
        return Icons.search_rounded;
    }
  }

  Widget _buildStatusCards() {
    return LayoutBuilder(
      builder: (
        BuildContext context,
        BoxConstraints constraints,
      ) {
        final bool wide = constraints.maxWidth >= 700;

        final List<Widget> cards = [
          _statusCard(
            title: 'حالة الجهاز',
            value: connected ? 'مستقر' : 'غير متصل',
            icon: Icons.memory_rounded,
            color: connected
                ? Colors.greenAccent
                : Colors.redAccent,
          ),
          _statusCard(
            title: 'الحساسية',
            value:
                '${sensitivity.toStringAsFixed(0)}%',
            icon: Icons.gps_fixed_rounded,
            color: Colors.greenAccent,
          ),
          _statusCard(
            title: 'الفلترة',
            value: filter,
            icon: Icons.filter_alt_rounded,
            color: Colors.cyanAccent,
          ),
          _statusCard(
            title: 'التنبيه الصوتي',
            value: audioEnabled ? 'يعمل' : 'متوقف',
            icon: Icons.volume_up_rounded,
            color: Colors.greenAccent,
          ),
          _statusCard(
            title: 'الاهتزاز',
            value:
                vibrationEnabled ? 'يعمل' : 'متوقف',
            icon: Icons.vibration_rounded,
            color: Colors.cyanAccent,
          ),
        ];

        if (wide) {
          return Row(
            children: cards
                .map(
                  (Widget card) => Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 4,
                      ),
                      child: card,
                    ),
                  ),
                )
                .toList(),
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: cards
              .map(
                (Widget card) => SizedBox(
                  width:
                      (constraints.maxWidth - 8) / 2,
                  child: card,
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _statusCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return _panel(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(.07),
              border: Border.all(
                color: color.withOpacity(.25),
              ),
            ),
            child: Icon(
              icon,
              color: color,
              size: 23,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
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
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return _panel(
      child: Column(
        children: [
          _sectionTitle(
            'التحكم بالمسح',
            Icons.tune_rounded,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (
              BuildContext context,
              BoxConstraints constraints,
            ) {
              final bool wide =
                  constraints.maxWidth >= 600;

              final Widget startButton =
                  _actionButton(
                label: 'بدء المسح',
                icon: Icons.play_arrow_rounded,
                color: Colors.greenAccent,
                enabled: !scanning,
                onPressed: startScan,
              );

              final Widget stopButton =
                  _actionButton(
                label: 'إيقاف المسح',
                icon: Icons.stop_rounded,
                color: Colors.redAccent,
                enabled: scanning,
                onPressed: stopScan,
              );

              final Widget saveButton =
                  _actionButton(
                label: 'حفظ القراءة',
                icon: Icons.save_rounded,
                color: Colors.blueAccent,
                enabled: connected,
                onPressed: saveReading,
                filled: false,
              );

              final Widget resetButton =
                  _actionButton(
                label: 'تصفير',
                icon: Icons.refresh_rounded,
                color: Colors.white70,
                enabled: true,
                onPressed: resetDisplay,
                filled: false,
              );

              if (wide) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: startButton,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: stopButton,
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(
                          child: saveButton,
                        ),
            
