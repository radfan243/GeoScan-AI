import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/bluetooth_service.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final BluetoothService _bluetooth = BluetoothService();

  StreamSubscription<Map<String, dynamic>>? _dataSubscription;
  StreamSubscription<bool>? _connectionSubscription;

  final List<double> signalHistory = [];

  double signal = 0;
  double rawSignal = 0;
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

  DateTime? _lastSignalTime;

  @override
  void initState() {
    super.initState();

    _listenToBluetooth();
  }

  // ============================================================
  // الاستماع إلى Bluetooth والبيانات القادمة من ESP32
  // ============================================================

  void _listenToBluetooth() {
    _dataSubscription = _bluetooth.dataStream.listen(
      _handleDeviceData,
    );

    _connectionSubscription =
        _bluetooth.connectionStream.listen(
      _handleConnectionState,
    );

    connected = _bluetooth.isConnected;

    if (connected) {
      deviceStatus = 'متصل';
    }
  }

  // ============================================================
  // معالجة بيانات ESP32
  // ============================================================

  void _handleDeviceData(
    Map<String, dynamic> data,
  ) {
    if (!mounted) return;

    final incomingSignal =
        data.containsKey('signal')
            ? _toDouble(data['signal'])
            : signal;

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

    // ----------------------------------------------------------
    // حماية القيم
    // ----------------------------------------------------------

    final safeRawSignal =
        incomingSignal.clamp(0, 100).toDouble();

    final safeStability =
        incomingStability.clamp(0, 100).toDouble();

    final safeDepth =
        (incomingDepth < 0
            ? 0
            : incomingDepth)
        .toDouble();

    // ----------------------------------------------------------
    // تنعيم الإشارة
    // ----------------------------------------------------------

    rawSignal = safeRawSignal;

    final smoothedSignal =
        signal == 0
            ? safeRawSignal
            : (signal * 0.72) +
                (safeRawSignal * 0.28);

    final safeSignal =
        smoothedSignal.clamp(0, 100).toDouble();

    final now = DateTime.now();

    // ----------------------------------------------------------
    // تحديد حالة المسح
    // ----------------------------------------------------------

    final statusLower =
        incomingStatus.toLowerCase();

    final isScanning =
        incomingStatus == 'يمسح' ||
        incomingStatus == 'SCANNING' ||
        statusLower == 'scanning' ||
        statusLower == 'scan';

    setState(() {
      signal = safeSignal;
      stability = safeStability;
      depth = safeDepth;
      deviceStatus = incomingStatus;
      targetType = incomingTarget;

      scanning = isScanning;

      signalHistory.add(safeSignal);

      if (signalHistory.length > 80) {
        signalHistory.removeAt(0);
      }

      _lastSignalTime = now;
    });
  }

  // ============================================================
  // حالة الاتصال
  // ============================================================

  void _handleConnectionState(
    bool isConnected,
  ) {
    if (!mounted) return;

    setState(() {
      connected = isConnected;

      if (!connected) {
        scanning = false;
        calibrating = false;
        deviceStatus = 'غير متصل';

        signal = 0;
        rawSignal = 0;
        stability = 0;
        depth = 0;

        signalHistory.clear();
      } else {
        deviceStatus = 'متصل';
      }
    });
  }

  // ============================================================
  // تحويل البيانات إلى double
  // ============================================================

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value.toString().replaceAll(',', '.'),
        ) ??
        0;
  }

  // ============================================================
  // بدء المسح الحقيقي
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

    try {
      await _bluetooth.startScan();

      if (!mounted) return;

      setState(() {
        scanning = true;
        deviceStatus = 'يمسح';
        signalHistory.clear();
      });
    } catch (e) {
      _showMessage(
        'تعذر بدء المسح',
      );
    }
  }

  // ============================================================
  // إيقاف المسح
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
    } catch (e) {
      _showMessage(
        'تعذر إيقاف المسح',
      );
    }
  }

  // ============================================================
  // المعايرة
  // ============================================================

  Future<void> calibrate() async {
    if (!connected) {
      _showMessage(
        'يجب الاتصال بجهاز ESP32 أولًا',
      );
      return;
    }

    if (scanning) {
      _showMessage(
        'أوقف المسح أولًا ثم قم بالمعايرة',
      );
      return;
    }

    try {
      setState(() {
        calibrating = true;
        deviceStatus = 'معايرة';
        signalHistory.clear();
        signal = 0;
        rawSignal = 0;
        depth = 0;
      });

      await _bluetooth.calibrate();

      if (!mounted) return;

      setState(() {
        calibrating = false;
        stability = 100;
        deviceStatus = 'جاهز';
      });

      _showMessage(
        'تم إرسال أمر المعايرة إلى ESP32',
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        calibrating = false;
      });

      _showMessage(
        'تعذر تنفيذ المعايرة',
      );
    }
  }

  // ============================================================
  // تغيير الحساسية
  // ============================================================

  Future<void> changeSensitivity(
    double value,
  ) async {
    if (!connected) return;

    final safeValue =
        value.clamp(0, 100).toDouble();

    try {
      await _bluetooth.setSensitivity(
        safeValue,
      );

      if (!mounted) return;

      setState(() {
        sensitivity = safeValue;
      });
    } catch (_) {
      _showMessage(
        'تعذر تغيير الحساسية',
      );
    }
  }

  // ============================================================
  // تغيير الفلترة
  // ============================================================

  Future<void> changeFilter(
    String value,
  ) async {
    if (!connected) return;

    try {
      await _bluetooth.setFilter(
        value,
      );

      if (!mounted) return;

      setState(() {
        filter = value;
      });
    } catch (_) {
      _showMessage(
        'تعذر تغيير الفلترة',
      );
    }
  }

  // ============================================================
  // الصوت
  // ============================================================

  Future<void> toggleAudio() async {
    if (!connected) return;

    final newValue = !audioEnabled;

    try {
      await _bluetooth.setAudio(
        newValue,
      );

      if (!mounted) return;

      setState(() {
        audioEnabled = newValue;
      });
    } catch (_) {
      _showMessage(
        'تعذر تغيير الصوت',
      );
    }
  }

  // ============================================================
  // الاهتزاز
  // ============================================================

  Future<void> toggleVibration() async {
    if (!connected) return;

    final newValue = !vibrationEnabled;

    try {
      await _bluetooth.setVibration(
        newValue,
      );

      if (!mounted) return;

      setState(() {
        vibrationEnabled = newValue;
      });
    } catch (_) {
      _showMessage(
        'تعذر تغيير الاهتزاز',
      );
    }
  }

  // ============================================================
  // لون الإشارة
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

  // ============================================================
  // نص الإشارة
  // ============================================================

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

  // ============================================================
  // تقييم الهدف
  // ============================================================

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
      return 'تغير ضعيف';
    }

    if (signal < 65) {
      return 'تغير يحتاج إلى فحص';
    }

    return 'تغير قوي - تحقق ميدانيًا';
  }

  // ============================================================
  // رسالة
  // ============================================================

  void _showMessage(
    String message,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          textDirection: TextDirection.rtl,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _connectionSubscription?.cancel();

    super.dispose();
  }

  // ============================================================
  // الواجهة
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final color = signalColor;

    return Scaffold(
      backgroundColor:
          const Color(0xFF050B16),

      appBar: AppBar(
        backgroundColor:
            const Color(0xFF050B16),
        elevation: 0,
        centerTitle: true,

        title: Column(
          children: [
            const Text(
              'GeoScan AI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'نظام المسح الذكي',
              style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                fontSize: 13,
              ),
            ),
          ],
        ),

        actions: [
          Padding(
            padding:
                const EdgeInsets.only(right: 10),
            child: Row(
              children: [
                Icon(
                  connected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color: connected
                      ? Colors.greenAccent
                      : Colors.redAccent,
                ),
                const SizedBox(width: 4),
                Text(
                  connected
                      ? 'متصل'
                      : 'غير متصل',
                  style: TextStyle(
                    color: connected
                        ? Colors.greenAccent
                        : Colors.redAccent,
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

      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.fromLTRB(
            14,
            8,
            14,
            30,
          ),
          child: Column(
            children: [

              // ==================================================
              // المؤشر الرئيسي
              // ==================================================

              Container(
                height: 315,
                width: double.infinity,
                decoration: BoxDecoration(
                  color:
                      const Color(0xFF07111F),
                  borderRadius:
                      BorderRadius.circular(24),
                  border: Border.all(
                    color:
                        color.withOpacity(0.22),
                  ),
                ),
                child: Stack(
                  alignment:
                      Alignment.center,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter:
                            GaugePainter(
                          value: signal,
                        ),
                      ),
                    ),

                    Positioned(
                      top: 115,
                      child: Column(
                        children: [
                          const Text(
                            'LIVE SCAN',
                            style: TextStyle(
                              color:
                                  Colors.white,
                              fontSize: 21,
                              fontWeight:
                                  FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),

                          const SizedBox(
                            height: 5,
                          ),

                          Text(
                            '${signal.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: color,
                              fontSize: 54,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),

                          Text(
                            signalText,
                            style: TextStyle(
                              color: color,
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ==================================================
              // حالة الهدف
              // ==================================================

              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:
                      color.withOpacity(0.06),
                  borderRadius:
                      BorderRadius.circular(18),
                  border: Border.all(
                    color:
                        color.withOpacity(0.18),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      signal >= 65
                          ? Icons.warning_amber
                          : Icons.radar,
                      color: color,
                      size: 32,
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'تحليل الإشارة',
                            style: TextStyle(
                              color:
                                  Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            targetStatus,
                            style: TextStyle(
                              color: color,
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ==================================================
              // المعلومات
              // ==================================================

              Row(
                children: [
                  Expanded(
                    child: _infoCard(
                      title: 'الإشارة',
                      value:
                          '${signal.toStringAsFixed(1)}%',
                      subtitle:
                          signalText,
                      icon:
                          Icons.signal_cellular_alt,
                      color: color,
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Column(
                      children: [
                        _smallInfoCard(
                          title: 'العمق',
                          value: depth > 0
                              ? '${depth.toStringAsFixed(2)} m'
                              : '--',
                          icon:
                              Icons.vertical_align_bottom,
                          color:
                              Colors.greenAccent,
                        ),

                        const SizedBox(height: 10),

                        _smallInfoCard(
                          title: 'الاستقرار',
                          value:
                              '${stability.toStringAsFixed(0)}%',
                          icon:
                              Icons.graphic_eq,
                          color:
                              Colors.cyanAccent,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // ==================================================
              // مستوى الإشارة
              // ==================================================

              _sectionCard(
                title: 'مستوى الإشارة',
                icon: Icons.bar_chart,
                child: Column(
                  children: [
                    SizedBox(
                      height: 30,
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
                                signal >= level;

                            Color barColor;

                            if (index < 8) {
                              barColor =
                                  Colors.redAccent;
                            } else if (index <
                                18) {
                              barColor =
                                  Colors.orangeAccent;
                            } else if (index <
                                28) {
                              barColor =
                                  Colors.amberAccent;
                            } else {
                              barColor =
                                  Colors.greenAccent;
                            }

                            return Expanded(
                              child:
                                  AnimatedContainer(
                                duration:
                                    const Duration(
                                  milliseconds:
                                      100,
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
                                          0.07,
                                        ),
                                  borderRadius:
                                      BorderRadius
                                          .circular(3),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

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
                          ),
                        ),
                        Text(
                          'متوسطة',
                          style: TextStyle(
                            color:
                                Colors.amberAccent,
                          ),
                        ),
                        Text(
                          'قوية',
                          style: TextStyle(
                            color:
                                Colors.greenAccent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ==================================================
              // الرسم الحقيقي
              // ==================================================

              _sectionCard(
                title: 'منحنى الإشارة',
                icon: Icons.show_chart,
                height: 250,
                child: CustomPaint(
                  painter:
                      SignalPainter(
                    values:
                        signalHistory,
                  ),
                  child:
                      const SizedBox.expand(),
                ),
              ),

              const SizedBox(height: 14),

              // ==================================================
              // حالة ESP32
              // ==================================================

              _sectionCard(
                title: 'حالة جهاز ESP32',
                icon: Icons.memory,
                child: Column(
                  children: [
                    Icon(
                      connected
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth_disabled,
                      size: 58,
                      color: connected
                          ? Colors.greenAccent
                          : Colors.redAccent,
                    ),

                    const SizedBox(height: 8),

                    Text(
                      connected
                          ? deviceStatus
                          : 'غير متصل',
                      style: TextStyle(
                        color: connected
                            ? Colors.greenAccent
                            : Colors.redAccent,
                        fontSize: 21,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      connected
                          ? 'البيانات تصل مباشرة من ESP32'
                          : 'اتصل بجهاز ESP32 للبدء',
                      textAlign:
                          TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white54,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      'الهدف: $targetType',
                      style:
                          const TextStyle(
                        color:
                            Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ==================================================
              // الإعدادات
              // ==================================================

              _sectionCard(
                title: 'إعدادات المسح',
                icon: Icons.settings,
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.tune,
                          color:
                              Colors.cyanAccent,
                        ),

                        const SizedBox(width: 10),

                        const Text(
                          'الحساسية',
                          style: TextStyle(
                            color:
                                Colors.white,
                            fontSize: 16,
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
                      onChanged:
                          connected &&
                                  !calibrating
                              ? changeSensitivity
                              : null,
                    ),

                    const SizedBox(height: 5),

                    Row(
                      children: [
                        const Icon(
                          Icons.filter_alt,
                          color:
                              Colors.cyanAccent,
                        ),

                        const SizedBox(width: 10),

                        const Text(
                          'الفلترة',
                          style: TextStyle(
                            color:
                                Colors.white,
                            fontSize: 16,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        const Spacer(),

                        DropdownButton<String>(
                          value: filter,
                          dropdownColor:
                              const Color(
                            0xFF07111F,
                          ),
                          style:
                              const TextStyle(
                            color:
                                Colors.white,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'منخفضة',
                              child: Text(
                                'منخفضة',
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'متوسطة',
                              child: Text(
                                'متوسطة',
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'عالية',
                              child: Text(
                                'عالية',
                              ),
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
                      color: Colors.white12,
                    ),

                    SwitchListTile(
                      contentPadding:
                          EdgeInsets.zero,
                      title: const Text(
                        'الصوت',
                        style: TextStyle(
                          color:
                              Colors.white,
                        ),
                      ),
                      secondary:
                          const Icon(
                        Icons.volume_up,
                        color:
                            Colors.cyanAccent,
                      ),
                      value: audioEnabled,
                      onChanged: connected
                          ? (_) =>
                              toggleAudio()
                          : null,
                    ),

                    SwitchListTile(
                      contentPadding:
                          EdgeInsets.zero,
                      title: const Text(
                        'الاهتزاز',
                        style: TextStyle(
                          color:
                              Colors.white,
                        ),
                      ),
                      secondary:
                          const Icon(
                        Icons.vibration,
                        color:
                            Colors.cyanAccent,
                      ),
                      value:
                          vibrationEnabled,
                      onChanged: connected
                          ? (_) =>
                              toggleVibration()
                          : null,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ==================================================
              // أزرار المسح
              // ==================================================

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 58,
                      child:
                          FilledButton.icon(
                        onPressed:
                            scanning ||
                                    !connected ||
                                    calibrating
                                ? null
                                : startScan,
                        icon: const Icon(
                          Icons.radar,
                          size: 26,
                        ),
                        label: const Text(
                          'بدء المسح',
                          style: TextStyle(
                            fontSize: 17,
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
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: SizedBox(
                      height: 58,
                      child:
                          OutlinedButton.icon(
                        onPressed:
                            scanning
                                ? stopScan
                                : null,
                        icon: const Icon(
                          Icons.stop,
                          size: 24,
                        ),
                        label: const Text(
                          'إيقاف',
                          style: TextStyle(
                            fontSize: 17,
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
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ==================================================
              // المعايرة
              // ==================================================

              SizedBox(
                width: double.infinity,
                height: 54,
                child:
                    OutlinedButton.icon(
                  onPressed:
                      connected &&
                              !scanning &&
                              !calibrating
                          ? calibrate
                          : null,
                  icon: calibrating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // ==================================================
              // تنبيه علمي
              // ==================================================

              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: Colors.amber
                      .withOpacity(0.05),
                  borderRadius:
                      BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.amber
                        .withOpacity(0.15),
                  ),
                ),
                child: const Text(
                  'مهم: التطبيق يعرض القياسات التي يرسلها ESP32. لا يتم اعتبار ارتفاع الإشارة ذهبًا أو معدنًا محددًا تلقائيًا. تحديد نوع الهدف والعمق الحقيقي يحتاج إلى دائرة الحساس والمعايرة والاختبارات الميدانية.',
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    height: 1.5,
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
  // بطاقة المعلومات الرئيسية
  // ============================================================

  Widget _infoCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding:
          const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            const Color(0xFF07111F),
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color:
              color.withOpacity(0.25),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 28,
          ),

          const SizedBox(height: 5),

          Text(
            title,
            style:
                const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 25,
              fontWeight:
                  FontWeight.bold,
            ),
          ),

          Text(
            subtitle,
            style: TextStyle(
              color: color,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // بطاقة صغيرة
  // ============================================================

  Widget _smallInfoCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            const Color(0xFF07111F),
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color:
              Colors.white.withOpacity(0.08),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: color,
            size: 25,
          ),

          const SizedBox(width: 8),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                      const TextStyle(
                    color:
                        Colors.white60,
                    fontSize: 11,
                  ),
                ),

                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 19,
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
  // بطاقة القسم
  // ============================================================

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    double? height,
  }) {
    return Container(
      width: double.infinity,
      height: height,
      padding:
          const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            const Color(0xFF07111F),
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color:
              Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color:
                    Colors.cyanAccent,
              ),

              const SizedBox(width: 8),

              Text(
                title,
                style:
                    const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (height != null)
            Expanded(
              child: child,
            )
          else
            child,
        ],
      ),
    );
  }
}

// ============================================================
// Gauge Painter
// ============================================================

class GaugePainter extends CustomPainter {
  final double value;

  GaugePainter({
    required this.value,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final center = Offset(
      size.width / 2,
      size.height * 0.78,
    );

    const radius = 110.0;

    const startAngle =
        math.pi * 1.05;

    const sweepAngle =
        math.pi * 0.90;

    const segments = 42;

    for (int i = 0;
        i < segments;
        i++) {
      final progress =
          i / segments;

      final angle =
          startAngle +
              sweepAngle *
                  progress;

      Color segmentColor;

      if (progress < 0.20) {
        segmentColor =
            Colors.redAccent;
      } else if (progress < 0.45) {
        segmentColor =
            Colors.orangeAccent;
      } else if (progress < 0.70) {
        segmentColor =
            Colors.amberAccent;
      } else {
        segmentColor =
            Colors.greenAccent;
      }

      final active =
          value >=
              progress * 100;

      final paint = Paint()
        ..color = active
            ? segmentColor
            : Colors.white
                .withOpacity(0.07)
        ..strokeWidth = 17
        ..strokeCap =
            StrokeCap.square;

      final inner = Offset(
        center.dx +
            math.cos(angle) *
                radius,
        center.dy +
            math.sin(angle) *
                radius,
      );

      final outer = Offset(
        center.dx +
            math.cos(angle) *
                (radius + 8),
        center.dy +
            math.sin(angle) *
                (radius + 8),
      );

      canvas.drawLine(
        inner,
        outer,
        paint,
      );
    }

    final normalized =
        value.clamp(0, 100) /
            100;

    final pointerAngle =
        startAngle +
            sweepAngle *
                normalized;

    final pointerEnd =
        Offset(
      center.dx +
          math.cos(pointerAngle) *
              (radius - 12),
      center.dy +
          math.sin(pointerAngle) *
              (radius - 12),
    );

    final pointerColor =
        value < 20
            ? Colors.redAccent
            : value < 40
                ? Colors.orangeAccent
                : value < 65
                    ? Colors.amberAccent
                    : Colors.greenAccent;

    final pointerPaint =
        Paint()
          ..color = pointerColor
          ..strokeWidth = 7
          ..strokeCap =
              StrokeCap.round;

    canvas.drawLine(
      center,
      pointerEnd,
      pointerPaint,
    );

    canvas.drawCircle(
      center,
      10,
      Paint()..color = pointerColor,
    );
  }

  @override
  bool shouldRepaint(
    covariant GaugePainter oldDelegate,
  ) {
    return oldDelegate.value !=
        value;
  }
}

// ============================================================
// Signal Painter
// ============================================================

class SignalPainter extends CustomPainter {
  final List<double> values;

  SignalPainter({
    required this.values,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final gridPaint = Paint()
      ..color =
          Colors.white.withOpacity(0.06)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y =
          size.height * i / 4;

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
          i *
              size.width /
              (values.length - 1);

      final normalized =
          values[i]
                  .clamp(0, 100) /
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

    final paint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 3.5
      ..style =
          PaintingStyle.stroke
      ..strokeCap =
          StrokeCap.round
      ..strokeJoin =
          StrokeJoin.round;

    canvas.drawPath(
      path,
      paint,
    );
  }

  @override
  bool shouldRepaint(
    covariant SignalPainter oldDelegate,
  ) {
    return true;
  }
}
