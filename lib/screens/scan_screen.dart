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

class _ScanScreenState extends State<ScanScreen> {
  final BluetoothService _bluetooth = BluetoothService();

  // ============================================================
  // IMPORTANT:
  // BluetoothService.dataStream returns String
  // ============================================================

  StreamSubscription<String>? _dataSubscription;
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

  @override
  void initState() {
    super.initState();
    _listenToBluetooth();
  }

  // ============================================================
  // BLUETOOTH LISTENERS
  // ============================================================

  void _listenToBluetooth() {
    _dataSubscription =
        _bluetooth.dataStream.listen(
      _handleDeviceData,
      onError: (error) {
        debugPrint(
          'GeoScan AI data stream error: $error',
        );
      },
    );

    _connectionSubscription =
        _bluetooth.connectionStream.listen(
      _handleConnectionState,
      onError: (error) {
        debugPrint(
          'GeoScan AI connection stream error: $error',
        );
      },
    );

    connected = _bluetooth.isConnected;

    if (connected) {
      deviceStatus = 'متصل';
    }
  }

  // ============================================================
  // ESP32 DATA
  //
  // BluetoothService sends String.
  // ESP32 sends JSON text.
  // ============================================================

  void _handleDeviceData(String rawData) {
    if (!mounted) return;

    if (rawData.trim().isEmpty) {
      return;
    }

    try {
      debugPrint(
        'GeoScan AI <- SCREEN: $rawData',
      );

      dynamic decoded;

      try {
        decoded = jsonDecode(rawData);
      } catch (_) {
        // إذا لم تكن JSON نحاول قراءة رقم الإشارة
        final match = RegExp(
          r'[-+]?\d*\.?\d+',
        ).firstMatch(rawData);

        if (match != null) {
          final parsed =
              double.tryParse(match.group(0)!);

          if (parsed != null) {
            _updateSignalOnly(parsed);
          }
        }

        return;
      }

      if (decoded is! Map) {
        return;
      }

      final Map<String, dynamic> data =
          Map<String, dynamic>.from(decoded);

      // ----------------------------------------------------------
      // SIGNAL
      // ----------------------------------------------------------

      final incomingSignal =
          data.containsKey('signal')
              ? _toDouble(data['signal'])
              : signal;

      // ----------------------------------------------------------
      // RAW SIGNAL
      // ----------------------------------------------------------

      final incomingRaw =
          data.containsKey('raw')
              ? _toDouble(data['raw'])
              : incomingSignal;

      // ----------------------------------------------------------
      // STABILITY
      // ----------------------------------------------------------

      final incomingStability =
          data.containsKey('stability')
              ? _toDouble(data['stability'])
              : stability;

      // ----------------------------------------------------------
      // DEPTH
      // ----------------------------------------------------------

      final incomingDepth =
          data.containsKey('depth')
              ? _toDouble(data['depth'])
              : depth;

      // ----------------------------------------------------------
      // STATUS
      // ----------------------------------------------------------

      final incomingStatus =
          data.containsKey('status')
              ? data['status'].toString()
              : deviceStatus;

      // ----------------------------------------------------------
      // TARGET
      // ----------------------------------------------------------

      final incomingTarget =
          data.containsKey('target')
              ? data['target'].toString()
              : targetType;

      // ----------------------------------------------------------
      // SCANNING
      // ----------------------------------------------------------

      bool isScanning =
          scanning;

      if (data.containsKey('scanning')) {
        final scanningValue =
            data['scanning'];

        if (scanningValue is bool) {
          isScanning = scanningValue;
        } else {
          final text =
              scanningValue
                  .toString()
                  .toLowerCase();

          isScanning =
              text == 'true' ||
              text == '1' ||
              text == 'scanning' ||
              text == 'scan';
        }
      } else {
        final statusLower =
            incomingStatus.toLowerCase();

        isScanning =
            incomingStatus == 'يمسح' ||
            incomingStatus == 'جارٍ المسح' ||
            incomingStatus == 'جاري المسح' ||
            incomingStatus == 'SCANNING' ||
            statusLower == 'scanning' ||
            statusLower == 'scan' ||
            statusLower == 'active';
      }

      // ----------------------------------------------------------
      // SAFE VALUES
      // ----------------------------------------------------------

      final safeRawSignal =
          incomingRaw
              .clamp(0.0, 100.0)
              .toDouble();

      final safeIncomingSignal =
          incomingSignal
              .clamp(0.0, 100.0)
              .toDouble();

      final safeStability =
          incomingStability
              .clamp(0.0, 100.0)
              .toDouble();

      final safeDepth =
          incomingDepth < 0.0
              ? 0.0
              : incomingDepth.toDouble();

      // ----------------------------------------------------------
      // SIGNAL SMOOTHING
      // ----------------------------------------------------------

      final smoothedSignal =
          signal == 0.0
              ? safeIncomingSignal
              : (signal * 0.72) +
                  (safeIncomingSignal * 0.28);

      final safeSignal =
          smoothedSignal
              .clamp(0.0, 100.0)
              .toDouble();

      final now =
          DateTime.now();

      // ----------------------------------------------------------
      // UPDATE UI
      // ----------------------------------------------------------

      setState(() {
        signal = safeSignal;

        rawSignal =
            safeRawSignal;

        stability =
            safeStability;

        depth =
            safeDepth;

        deviceStatus =
            incomingStatus;

        if (incomingTarget.isNotEmpty) {
          targetType =
              incomingTarget;
        }

        scanning =
            isScanning;

        signalHistory.add(
          safeSignal,
        );

        if (signalHistory.length > 80) {
          signalHistory.removeAt(0);
        }

        _lastSignalTime =
            now;
      });
    } catch (e) {
      debugPrint(
        'GeoScan AI screen data error: $e',
      );
    }
  }

  // ============================================================
  // SIGNAL ONLY
  // ============================================================

  void _updateSignalOnly(
    double value,
  ) {
    if (!mounted) return;

    final safe =
        value
            .clamp(0.0, 100.0)
            .toDouble();

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

  // ============================================================
  // CONNECTION
  // ============================================================

  void _handleConnectionState(
    bool isConnected,
  ) {
    if (!mounted) return;

    setState(() {
      connected =
          isConnected;

      if (!connected) {
        scanning = false;
        calibrating = false;

        deviceStatus =
            'غير متصل';

        signal = 0.0;
        rawSignal = 0.0;
        stability = 0.0;
        depth = 0.0;

        signalHistory.clear();
      } else {
        deviceStatus =
            'متصل';
      }
    });
  }

  // ============================================================
  // DOUBLE CONVERTER
  // ============================================================

  double _toDouble(
    dynamic value,
  ) {
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
  // START REAL SCAN
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
      final success =
          await _bluetooth.startScan();

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
    } catch (e) {
      debugPrint(
        'Start scan error: $e',
      );

      _showMessage(
        'تعذر بدء المسح',
      );
    }
  }

  // ============================================================
  // STOP REAL SCAN
  // ============================================================

  Future<void> stopScan() async {
    if (!connected) {
      return;
    }

    try {
      final success =
          await _bluetooth.stopScan();

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
    } catch (e) {
      debugPrint(
        'Stop scan error: $e',
      );

      _showMessage(
        'تعذر إيقاف المسح',
      );
    }
  }

  // ============================================================
  // CALIBRATION
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

        signal = 0.0;
        rawSignal = 0.0;
        depth = 0.0;
      });

      final success =
          await _bluetooth.calibrate();

      if (!mounted) return;

      if (!success) {
        setState(() {
          calibrating = false;
          deviceStatus =
              connected
                  ? 'متصل'
                  : 'غير متصل';
        });

        _showMessage(
          'تعذر إرسال أمر المعايرة',
        );

        return;
      }

      setState(() {
        calibrating = false;
        stability = 100.0;
        deviceStatus = 'جاهز';
      });

      _showMessage(
        'تم إرسال أمر المعايرة إلى ESP32',
      );
    } catch (e) {
      debugPrint(
        'Calibration error: $e',
      );

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
  // SENSITIVITY
  // ============================================================

  Future<void> changeSensitivity(
    double value,
  ) async {
    if (!connected) return;

    final safeValue =
        value
            .clamp(0.0, 100.0)
            .toDouble();

    try {
      final success =
          await _bluetooth
              .setSensitivity(
        safeValue,
      );

      if (!mounted) return;

      if (success) {
        setState(() {
          sensitivity =
              safeValue;
        });
      } else {
        _showMessage(
          'تعذر تغيير الحساسية',
        );
      }
    } catch (e) {
      _showMessage(
        'تعذر تغيير الحساسية',
      );
    }
  }

  // ============================================================
  // FILTER
  // ============================================================

  Future<void> changeFilter(
    String value,
  ) async {
    if (!connected) return;

    try {
      final success =
          await _bluetooth
              .setFilter(
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
    } catch (_) {
      _showMessage(
        'تعذر تغيير الفلترة',
      );
    }
  }

  // ============================================================
  // AUDIO
  // ============================================================

  Future<void> toggleAudio() async {
    if (!connected) return;

    final newValue =
        !audioEnabled;

    try {
      final success =
          await _bluetooth
              .setAudio(
        newValue,
      );

      if (!mounted) return;

      if (success) {
        setState(() {
          audioEnabled =
              newValue;
        });
      } else {
        _showMessage(
          'تعذر تغيير الصوت',
        );
      }
    } catch (_) {
      _showMessage(
        'تعذر تغيير الصوت',
      );
    }
  }

  // ============================================================
  // VIBRATION
  // ============================================================

  Future<void> toggleVibration() async {
    if (!connected) return;

    final newValue =
        !vibrationEnabled;

    try {
      final success =
          await _bluetooth
              .setVibration(
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
    } catch (_) {
      _showMessage(
        'تعذر تغيير الاهتزاز',
      );
    }
  }

  // ============================================================
  // SIGNAL COLOR
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
  // SIGNAL TEXT
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
  // TARGET STATUS
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
      ),
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _connectionSubscription?.cancel();

    super.dispose();
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final color =
        signalColor;

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
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            Text(
              'نظام المسح الذكي',
              style: TextStyle(
                color: Colors.white
                    .withOpacity(0.65),
                fontSize: 13,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding:
                const EdgeInsets.only(
              right: 10,
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
                ),
                const SizedBox(
                  width: 4,
                ),
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
        child:
            SingleChildScrollView(
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
              // MAIN GAUGE
              // ==================================================

              Container(
                height: 315,
                width:
                    double.infinity,
                decoration:
                    BoxDecoration(
                  color:
                      const Color(
                    0xFF07111F,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    24,
                  ),
                  border:
                      Border.all(
                    color: color
                        .withOpacity(
                      0.22,
                    ),
                  ),
                ),
                child: Stack(
                  alignment:
                      Alignment.center,
                  children: [
                    Positioned.fill(
                      child:
                          CustomPaint(
                        painter:
                            GaugePainter(
                          value:
                              signal,
                        ),
                      ),
                    ),

                    Positioned(
                      top: 115,
                      child: Column(
                        children: [
                          const Text(
                            'LIVE SCAN',
                            style:
                                TextStyle(
                              color:
                                  Colors.white,
                              fontSize:
                                  21,
                              fontWeight:
                                  FontWeight.bold,
                              letterSpacing:
                                  2,
                            ),
                          ),

                          const SizedBox(
                            height: 5,
                          ),

                          Text(
                            '${signal.toStringAsFixed(1)}%',
                            style:
                                TextStyle(
                              color:
                                  color,
                              fontSize:
                                  54,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),

                          Text(
                            signalText,
                            style:
                                TextStyle(
                              color:
                                  color,
                              fontSize:
                                  16,
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

              const SizedBox(
                height: 12,
              ),

              // ==================================================
              // TARGET STATUS
              // ==================================================

              Container(
                width:
                    double.infinity,
                padding:
                    const EdgeInsets.all(
                  14,
                ),
                decoration:
                    BoxDecoration(
                  color: color
                      .withOpacity(
                    0.06,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    18,
                  ),
                  border:
                      Border.all(
                    color: color
                        .withOpacity(
                      0.18,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      signal >= 65
                          ? Icons
                              .warning_amber
                          : Icons.radar,
                      color: color,
                      size: 32,
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
                            'تحليل الإشارة',
                            style:
                                TextStyle(
                              color:
                                  Colors.white70,
                              fontSize:
                                  12,
                            ),
                          ),
                          const SizedBox(
                            height: 3,
                          ),
                          Text(
                            targetStatus,
                            style:
                                TextStyle(
                              color:
                                  color,
                              fontSize:
                                  16,
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

              const SizedBox(
                height: 12,
              ),

              // ==================================================
              // INFORMATION
              // ==================================================

              Row(
                children: [
                  Expanded(
                    child:
                        _infoCard(
                      title:
                          'الإشارة',
                      value:
                          '${signal.toStringAsFixed(1)}%',
                      subtitle:
                          signalText,
                      icon: Icons
                          .signal_cellular_alt,
                      color: color,
                    ),
                  ),

                  const SizedBox(
                    width: 10,
                  ),

                  Expanded(
                    child: Column(
                      children: [
                        _smallInfoCard(
                          title:
                              'العمق',
                          value:
                              depth > 0
                                  ? '${depth.toStringAsFixed(2)} m'
                                  : '--',
                          icon: Icons
                              .vertical_align_bottom,
                          color: Colors
                              .greenAccent,
                        ),

                        const SizedBox(
                          height: 10,
                        ),

                        _smallInfoCard(
                          title:
                              'الاستقرار',
                          value:
                              '${stability.toStringAsFixed(0)}%',
                          icon: Icons
                              .graphic_eq,
                          color: Colors
                              .cyanAccent,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height: 14,
              ),

              // ==================================================
              // SIGNAL LEVEL
              // ==================================================

              _sectionCard(
                title:
                    'مستوى الإشارة',
                icon:
                    Icons.bar_chart,
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
                                ((index +
                                            1) /
                                        40) *
                                    100;

                            final active =
                                signal >=
                                    level;

                            Color barColor;

                            if (index <
                                8) {
                              barColor =
                                  Colors
                                      .redAccent;
                            } else if (index <
                                18) {
                              barColor =
                                  Colors
                                      .orangeAccent;
                            } else if (index <
                                28) {
                              barColor =
                                  Colors
                                      .amberAccent;
                            } else {
                              barColor =
                                  Colors
                                      .greenAccent;
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
                                  horizontal:
                                      1,
                                ),
                                decoration:
                                    BoxDecoration(
                                  color: active
                                      ? barColor
                                      : Colors
                                          .white
                                          .withOpacity(
                                          0.07,
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
                          style:
                              TextStyle(
                            color: Colors
                                .redAccent,
                          ),
                        ),
                        Text(
                          'متوسطة',
                          style:
                              TextStyle(
                            color: Colors
                                .amberAccent,
                          ),
                        ),
                        Text(
                          'قوية',
                          style:
                              TextStyle(
                            color: Colors
                                .greenAccent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(
                height: 14,
              ),

              // ==================================================
              // REAL SIGNAL GRAPH
              // ==================================================

              _sectionCard(
                title:
                    'منحنى الإشارة',
                icon:
                    Icons.show_chart,
                height: 250,
                child:
                    CustomPaint(
                  painter:
                      SignalPainter(
                    values:
                        signalHistory,
                  ),
                  child:
                      const SizedBox
                          .expand(),
                ),
              ),

              const SizedBox(
                height: 14,
              ),

              // ==================================================
              // ESP32 STATUS
              // ==================================================

              _sectionCard(
                title:
                    'حالة جهاز ESP32',
                icon:
                    Icons.memory,
                child: Column(
                  children: [
                    Icon(
                      connected
                          ? Icons
                              .bluetooth_connected
                          : Icons
                              .bluetooth_disabled,
                      size: 58,
                      color: connected
                          ? Colors
                              .greenAccent
                          : Colors
                              .redAccent,
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    Text(
                      connected
                          ? deviceStatus
                          : 'غير متصل',
                      style:
                          TextStyle(
                        color: connected
                            ? Colors
                                .greenAccent
                            : Colors
                                .redAccent,
                        fontSize: 21,
                        fontWeight:
                            FontWeight
                                .bold,
                      ),
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    Text(
                      connected
                          ? 'البيانات تصل مباشرة من ESP32'
                          : 'اتصل بجهاز ESP32 للبدء',
                      textAlign:
                          TextAlign.center,
                      style:
                          const TextStyle(
                        color:
                            Colors.white54,
                      ),
                    ),

                    const SizedBox(
                      height: 10,
                    ),

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

              const SizedBox(
                height: 14,
              ),

              // ==================================================
              // SETTINGS
              // ==================================================

              _sectionCard(
                title:
                    'إعدادات المسح',
                icon:
                    Icons.settings,
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.tune,
                          color: Colors
                              .cyanAccent,
                        ),

                        const SizedBox(
                          width: 10,
                        ),

                        const Text(
                          'الحساسية',
                          style:
                              TextStyle(
                            color:
                                Colors.white,
                            fontSize:
                                16,
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
                      value:
                          sensitivity,
                      min: 0,
                      max: 100,
                      divisions:
                          100,
                      activeColor:
                          Colors
                              .cyanAccent,
                      onChanged:
                          connected &&
                                  !calibrating
                              ? changeSensitivity
                              : null,
                    ),

                    const SizedBox(
                      height: 5,
                    ),

                    Row(
                      children: [
                        const Icon(
                          Icons
                              .filter_alt,
                          color: Colors
                              .cyanAccent,
                        ),

                        const SizedBox(
                          width: 10,
                        ),

                        const Text(
                          'الفلترة',
                          style:
                              TextStyle(
                            color:
                                Colors.white,
                            fontSize:
                                16,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        const Spacer(),

                        DropdownButton<
                            String>(
                          value:
                              filter,
                          dropdownColor:
                              const Color(
                            0xFF07111F,
                          ),
                          style:
                              const TextStyle(
                            color:
                                Colors.white,
                          ),
                          items:
                              const [
                            DropdownMenuItem(
                              value:
                                  'منخفضة',
                              child:
                                  Text(
                                'منخفضة',
                              ),
                            ),
                            DropdownMenuItem(
                              value:
                                  'متوسطة',
                              child:
                                  Text(
                                'متوسطة',
                              ),
                            ),
                            DropdownMenuItem(
                              value:
                                  'عالية',
                              child:
                                  Text(
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
                      color:
                          Colors.white12,
                    ),

                    SwitchListTile(
                      contentPadding:
                          EdgeInsets.zero,
                      title:
                          const Text(
                        'الصوت',
                        style:
                            TextStyle(
                          color:
                              Colors.white,
                        ),
                      ),
                      secondary:
                          const Icon(
                        Icons
                            .volume_up,
                        color: Colors
                            .cyanAccent,
                      ),
                      value:
                          audioEnabled,
                      onChanged:
                          connected
                              ? (_) =>
                                  toggleAudio()
                              : null,
                    ),

                    SwitchListTile(
                      contentPadding:
                          EdgeInsets.zero,
                      title:
                          const Text(
                        'الاهتزاز',
                        style:
                            TextStyle(
                          color:
                              Colors.white,
                        ),
                      ),
                      secondary:
                          const Icon(
                        Icons
                            .vibration,
                        color: Colors
                            .cyanAccent,
                      ),
                      value:
                          vibrationEnabled,
                      onChanged:
                          connected
                              ? (_) =>
                                  toggleVibration()
                              : null,
                    ),
                  ],
                ),
              ),

              const SizedBox(
                height: 18,
              ),

              // ==================================================
              // SCAN BUTTONS
              // ==================================================

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 58,
                      child:
                          FilledButton
                              .icon(
                        onPressed:
                            scanning ||
                                    !connected ||
                                    calibrating
                                ? null
                                : startScan,
                        icon:
                            const Icon(
                          Icons.radar,
                          size: 26,
                        ),
                        label:
                            const Text(
                          'بدء المسح',
                          style:
                              TextStyle(
                            fontSize:
                                17,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        style:
                            FilledButton
                                .styleFrom(
                          backgroundColor:
                              Colors
                                  .greenAccent
                                  .withOpacity(
                            0.12,
                          ),
                          foregroundColor:
                              Colors
                                  .greenAccent,
                          side:
                              const BorderSide(
                            color: Colors
                                .greenAccent,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(
                    width: 10,
                  ),

                  Expanded(
                    child: SizedBox(
                      height: 58,
                      child:
                          OutlinedButton
                              .icon(
                        onPressed:
                            scanning
                                ? stopScan
                                : null,
                        icon:
                            const Icon(
                          Icons.stop,
                          size: 24,
                        ),
                        label:
                            const Text(
                          'إيقاف',
                          style:
                              TextStyle(
                            fontSize:
                                17,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        style:
                            OutlinedButton
                                .styleFrom(
                          foregroundColor:
                              Colors
                                  .redAccent,
                          side:
                              const BorderSide(
                            color: Colors
                                .redAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height: 12,
              ),

              // ==================================================
              // CALIBRATION
              // ==================================================

              SizedBox(
                width:
                    double.infinity,
                height: 54,
                child:
                    OutlinedButton
                        .icon(
                  onPressed:
                      connected &&
                              !scanning &&
                              !calibrating
                          ? calibrate
                          : null,
                  icon:
                      calibrating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth:
                                    2,
                              ),
                            )
                          : const Icon(
                              Icons.refresh,
                            ),
                  label:
                      Text(
                    calibrating
                        ? 'جاري المعايرة...'
                        : 'معايرة الحساس',
                    style:
                        const TextStyle(
                      fontSize: 16,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(
                height: 18,
              ),

              // ==================================================
              // SCIENTIFIC NOTICE
              // ==================================================

              Container(
                width:
                    double.infinity,
                padding:
                    const EdgeInsets.all(
                  13,
                ),
                decoration:
                    BoxDecoration(
                  color: Colors.amber
                      .withOpacity(
                    0.05,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    14,
                  ),
                  border:
                      Border.all(
                    color: Colors.amber
                        .withOpacity(
                      0.15,
                    ),
                  ),
                ),
                child:
                    const Text(
                  'مهم: التطبيق يعرض القياسات التي يرسلها ESP32. لا يتم اعتبار ارتفاع الإشارة ذهبًا أو معدنًا محددًا تلقائيًا. تحديد نوع الهدف والعمق الحقيقي يحتاج إلى دائرة الحساس والمعايرة
