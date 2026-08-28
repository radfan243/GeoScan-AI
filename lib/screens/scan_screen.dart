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

  void _listenToBluetooth() {
    _dataSubscription = _bluetooth.dataStream.listen(
      _handleDeviceData,
      onError: (error) {
        debugPrint('GeoScan AI data error: $error');
      },
    );

    _connectionSubscription = _bluetooth.connectionStream.listen(
      _handleConnectionState,
      onError: (error) {
        debugPrint('GeoScan AI connection error: $error');
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
      debugPrint('GeoScan AI <- ESP32: $rawData');

      dynamic decoded;

      try {
        decoded = jsonDecode(rawData);
      } catch (_) {
        final match = RegExp(
          r'[-+]?\d*\.?\d+',
        ).firstMatch(rawData);

        if (match != null) {
          final value = double.tryParse(match.group(0)!);

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
          ? data['status'].toString()
          : deviceStatus;

      final incomingTarget = data.containsKey('target')
          ? data['target'].toString()
          : targetType;

      bool isScanning = scanning;

      if (data.containsKey('scanning')) {
        final value = data['scanning'];

        if (value is bool) {
          isScanning = value;
        } else {
          final text = value.toString().toLowerCase();

          isScanning =
              text == 'true' ||
              text == '1' ||
              text == 'scan' ||
              text == 'scanning';
        }
      }

      final safeRaw = incomingRaw.clamp(0.0, 100.0).toDouble();

      final safeIncomingSignal =
          incomingSignal.clamp(0.0, 100.0).toDouble();

      final safeStability =
          incomingStability.clamp(0.0, 100.0).toDouble();

      final safeDepth =
          incomingDepth < 0 ? 0.0 : incomingDepth.toDouble();

      final smoothed = signal == 0.0
          ? safeIncomingSignal
          : (signal * 0.72) + (safeIncomingSignal * 0.28);

      final safeSignal =
          smoothed.clamp(0.0, 100.0).toDouble();

      setState(() {
        signal = safeSignal;
        rawSignal = safeRaw;
        stability = safeStability;
        depth = safeDepth;
        deviceStatus = incomingStatus;
        scanning = isScanning;

        if (incomingTarget.isNotEmpty) {
          targetType = incomingTarget;
        }

        signalHistory.add(safeSignal);

        if (signalHistory.length > 80) {
          signalHistory.removeAt(0);
        }

        _lastSignalTime = DateTime.now();
      });
    } catch (e) {
      debugPrint('GeoScan AI parsing error: $e');
    }
  }

  void _updateSignalOnly(double value) {
    if (!mounted) return;

    final safe = value.clamp(0.0, 100.0).toDouble();

    final smoothed = signal == 0.0
        ? safe
        : (signal * 0.72) + (safe * 0.28);

    final finalSignal =
        smoothed.clamp(0.0, 100.0).toDouble();

    setState(() {
      rawSignal = safe;
      signal = finalSignal;

      signalHistory.add(finalSignal);

      if (signalHistory.length > 80) {
        signalHistory.removeAt(0);
      }

      _lastSignalTime = DateTime.now();
    });
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
  }

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value.toString().replaceAll(',', '.'),
        ) ??
        0.0;
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

    try {
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
    } catch (e) {
      debugPrint('Start scan error: $e');
      _showMessage('تعذر بدء المسح');
    }
  }

  Future<void> stopScan() async {
    if (!connected) return;

    try {
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
    } catch (e) {
      debugPrint('Stop scan error: $e');
      _showMessage('تعذر إيقاف المسح');
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
      debugPrint(
        'Calibration error: $e',
      );

      if (!mounted) return;

      setState(() {
        calibrating = false;
        deviceStatus =
            connected ? 'متصل' : 'غير متصل';
      });

      _showMessage(
        'تعذر تنفيذ المعايرة',
      );
    }
  }

  Future<void> changeSensitivity(
    double value,
  ) async {
    if (!connected) return;

    final safeValue =
        value.clamp(0.0, 100.0).toDouble();

    try {
      final success =
          await _bluetooth.setSensitivity(
        safeValue,
      );

      if (!mounted) return;

      if (success) {
        setState(() {
          sensitivity = safeValue;
        });
      } else {
        _showMessage(
          'تعذر تغيير الحساسية',
        );
      }
    } catch (e) {
      debugPrint(
        'Sensitivity error: $e',
      );
      _showMessage(
        'تعذر تغيير الحساسية',
      );
    }
  }

  Future<void> changeFilter(
    String value,
  ) async {
    if (!connected) return;

    try {
      final success =
          await _bluetooth.sendCommand(
        'FILTER:$value',
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
    } catch (e) {
      debugPrint(
        'Filter error: $e',
      );
      _showMessage(
        'تعذر تغيير الفلترة',
      );
    }
  }

  Future<void> toggleAudio() async {
    if (!connected) return;

    final newValue = !audioEnabled;

    try {
      final success =
          await _bluetooth.sendCommand(
        'AUDIO:${newValue ? 1 : 0}',
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
    } catch (e) {
      debugPrint(
        'Audio error: $e',
      );
      _showMessage(
        'تعذر تغيير الصوت',
      );
    }
  }

  Future<void> toggleVibration() async {
    if (!connected) return;

    final newValue = !vibrationEnabled;

    try {
      final success =
          await _bluetooth.sendCommand(
        'VIBRATION:${newValue ? 1 : 0}',
      );

      if (!mounted) return;

      if (success) {
        setState(() {
          vibrationEnabled = newValue;
        });
      } else {
        _showMessage(
          'تعذر تغيير الاهتزاز',
        );
      }
    } catch (e) {
      debugPrint(
        'Vibration error: $e',
      );
      _showMessage(
        'تعذر تغيير الاهتزاز',
      );
    }
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

  void _showMessage(String message) {
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
                color:
                    Colors.white.withOpacity(0.65),
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
              _mainGauge(color),
              const SizedBox(height: 12),
              _targetStatusCard(color),
              const SizedBox(height: 12),
              _informationRow(color),
              const SizedBox(height: 14),
              _signalLevelCard(),
              const SizedBox(height: 14),
              _graphCard(),
              const SizedBox(height: 14),
              _deviceStatusCard(),
              const SizedBox(height: 14),
              _settingsCard(),
              const SizedBox(height: 18),
              _scanButtons(),
              const SizedBox(height: 12),
              _calibrationButton(),
              const SizedBox(height: 18),
              _scientificNotice(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mainGauge(Color color) {
    return Container(
      height: 315,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF07111F),
        borderRadius:
            BorderRadius.circular(24),
        border: Border.all(
          color: color.withOpacity(0.22),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: GaugePainter(
                value: signal,
              ),
            ),
          ),
          Positioned(
            top: 105,
            child: Column(
              children: [
                const Text(
                  'LIVE SCAN',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${signal.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: color,
                    fontSize: 54,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  signalText,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetStatusCard(
    Color color,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color: color.withOpacity(0.18),
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
                    color: Colors.white70,
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
    );
  }

  Widget _informationRow(
    Color color,
  ) {
    return Row(
      children: [
        Expanded(
          child: _infoCard(
            title: 'الإشارة',
            value:
                '${signal.toStringAsFixed(1)}%',
            subtitle: signalText,
            icon: Icons.signal_cellular_alt,
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
                color: Colors.greenAccent,
              ),
              const SizedBox(height: 10),
              _smallInfoCard(
                title: 'الاستقرار',
                value:
                    '${stability.toStringAsFixed(0)}%',
                icon: Icons.graphic_eq,
                color: Colors.cyanAccent,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _signalLevelCard() {
    return _sectionCard(
      title: 'مستوى الإشارة',
      icon: Icons.bar_chart,
      child: Column(
        children: [
          SizedBox(
            height: 30,
            child: Row(
              children: List.generate(
                40,
                (index) {
                  final double level =
                      ((index + 1) / 40) *
                          100;

                  final active =
                      signal >= level;

                  Color barColor;

                  if (index < 8) {
                    barColor =
                        Colors.redAccent;
                  } else if (index < 18) {
                    barColor =
                        Colors.orangeAccent;
                  } else if (index < 28) {
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
                        milliseconds: 100,
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
                                    0.07),
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
                  color: Colors.redAccent,
                ),
              ),
              Text(
                'متوسطة',
                style: TextStyle(
                  color: Colors.amberAccent,
                ),
              ),
              Text(
                'قوية',
                style: TextStyle(
                  color: Colors.greenAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _graphCard() {
    return _sectionCard(
      title: 'منحنى الإشارة',
      icon: Icons.show_chart,
      height: 250,
      child: CustomPaint(
        painter: SignalPainter(
          values: signalHistory,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _deviceStatusCard() {
    return _sectionCard(
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
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'الهدف: $targetType',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
          if (_lastSignalTime != null) ...[
            const SizedBox(height: 6),
            const Text(
              'تم استقبال آخر قراءة',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _settingsCard() {
    return _sectionCard(
      title: 'إعدادات المسح',
      icon: Icons.settings,
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.tune,
                color: Colors.cyanAccent,
              ),
              const SizedBox(width: 10),
              const Text(
                'الحساسية',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
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
          const SizedBox(height: 5),
          Row(
            children: [
              const Icon(
                Icons.filter_alt,
                color: Colors.cyanAccent,
              ),
              const SizedBox(width: 10),
              const Text(
                'الفلترة',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              const Spacer(),
              DropdownButton<String>(
                value: filter,
                dropdownColor:
                    const Color(0xFF07111F),
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
                            if (value !=
                                null) {
                              changeFilter(
                                  value);
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
                color: Colors.white,
              ),
            ),
            secondary: const Icon(
              Icons.volume_up,
              color: Colors.cyanAccent,
            ),
            value: audioEnabled,
            onChanged: connected
                ? (_) => toggleAudio()
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
            onChanged: connected
                ? (_) => toggleVibration()
                : null,
          ),
        ],
      ),
    );
  }

  Widget _scanButtons() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 58,
            child: FilledButton.icon(
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
              style: FilledButton
                  .styleFrom(
                backgroundColor:
                    Colors.greenAccent
                        .withOpacity(
                            0.12),
                foregroundColor:
                    Colors.greenAccent,
                side: const BorderSide(
                  color: Colors.greenAccent,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 58,
            child: OutlinedButton.icon(
              onPressed:
                  scanning ? stopScan : null,
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
              style: OutlinedButton
                  .styleFrom(
                foregroundColor:
                    Colors.redAccent,
                side: const BorderSide(
                  color: Colors.redAccent,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _calibrationButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton.icon(
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
            : const Icon(Icons.refresh),
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
    );
  }

  Widget _scientificNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color:
            Colors.amber.withOpacity(0.05),
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color:
              Colors.amber.withOpacity(0.15),
        ),
      ),
      child: const Text(
        'مهم: التطبيق يعرض القياسات التي يرسلها ESP32. '
        'لا يتم اعتبار ارتفاع الإشارة ذهبًا أو معدنًا محددًا تلقائيًا. '
        'تحديد نوع الهدف والعمق الحقيقي يحتاج إلى دائرة الحساس والمعايرة.',
        textDirection:
            TextDirection.rtl,
        textAlign: TextAlign.right,
        style: TextStyle(
          color: Colors.white70,
          fontSize: 12,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _infoCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      height: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF07111F),
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color: color.withOpacity(0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: color,
            size: 28,
          ),
          const Spacer(),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallInfoCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      height: 70,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF07111F),
        borderRadius:
            BorderRadius.circular(15),
        border: Border.all(
          color: color.withOpacity(0.16),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: color,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    double? height,
  }) {
    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF07111F),
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white
              .withOpacity(0.07),
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
                color: Colors.cyanAccent,
                size: 21,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: child,
          ),
        ],
      ),
    );

    if (height != null) {
      return SizedBox(
        height: height,
        child: content,
      );
    }

    return content;
  }
}

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
      size.height / 2 + 35,
    );

    final double radius =
        math.min(
              size.width,
              size.height,
            ) *
            0.37;

    final backgroundPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap =
          StrokeCap.round
      ..color =
          Colors.white.withOpacity(0.06);

    final valuePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap =
          StrokeCap.round
      ..color =
          _colorForValue(value);

    const double startAngle =
        math.pi * 0.78;

    const double sweepAngle =
        math.pi * 1.44;

    canvas.drawArc(
      Rect.fromCircle(
        center: center,
        radius: radius,
      ),
      startAngle,
      sweepAngle,
      false,
      backgroundPaint,
    );

    final double safeValue =
        value.clamp(0.0, 100.0).toDouble();

    final double valueSweep =
        sweepAngle *
        (safeValue / 100.0);

    canvas.drawArc(
      Rect.fromCircle(
        center: center,
        radius: radius,
      ),
      startAngle,
      valueSweep,
      false,
      valuePaint,
    );

    final tickPaint = Paint()
      ..strokeWidth = 2
      ..color =
          Colors.white.withOpacity(0.25);

    for (int i = 0; i <= 10; i++) {
      final double angle =
          startAngle +
          (sweepAngle * i / 10);

      final outer = Offset(
        center.dx +
            math.cos(angle) *
                (radius + 13),
        center.dy +
            math.sin(angle) *
                (radius + 13),
      );

      final inner = Offset(
        center.dx +
            math.cos(angle) *
                (radius - 5),
        center.dy +
            math.sin(angle) *
                (radius - 5),
      );

      canvas.drawLine(
        inner,
        outer,
        tickPaint,
      );
    }
  }

  Color _colorForValue(
    double value,
  ) {
    if (value < 20) {
      return Colors.redAccent;
    }

    if (value < 40) {
      return Colors.orangeAccent;
    }

    if (value < 65) {
      return Colors.amberAccent;
    }

    return Colors.greenAccent;
  }

  @override
  bool shouldRepaint(
    covariant GaugePainter oldDelegate,
  ) {
    return oldDelegate.value != value;
  }
}

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
    final backgroundPaint = Paint()
      ..style = PaintingStyle.fill
      ..color =
          Colors.black.withOpacity(0.10);

    canvas.drawRect(
      Offset.zero & size,
      backgroundPaint,
    );

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color =
          Colors.white.withOpacity(0.06);

    for (int i = 1; i < 5; i++) {
      final double y =
          size.height * i / 5;

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    for (int i = 1; i < 8; i++) {
      final double x =
          size.width * i / 8;

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );
    }

    if (values.length < 2) {
      final textPainter = TextPainter(
        text: const TextSpan(
          text:
              'في انتظار البيانات من ESP32',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 13,
          ),
        ),
        textDirection:
            TextDirection.rtl,
      );

      textPainter.layout();

      textPainter.paint(
        canvas,
        Offset(
          (size.width -
                  textPainter.width) /
              2,
          (size.height -
                  textPainter.height) /
              2,
        ),
      );

      return;
    }

    final path = Path();

    for (int i = 0;
        i < values.length;
        i++) {
      final double x =
          values.length == 1
              ? 0.0
              : size.width *
                  i /
                  (values.length - 1);

      final double safe =
          values[i]
              .clamp(0.0, 100.0)
              .toDouble();

      final double y =
          size.height -
          (safe / 100.0) *
              size.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fillPath = Path.from(path)
      ..lineTo(
        size.width,
        size.height,
      )
      ..lineTo(
        0,
        size.height,
      )
      ..close();

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color =
          Colors.cyanAccent
              .withOpacity(0.08);

    canvas.drawPath(
      fillPath,
      fillPaint,
    );

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap =
          StrokeCap.round
      ..strokeJoin =
          StrokeJoin.round
      ..color = Colors.cyanAccent;

    canvas.drawPath(
      path,
      linePaint,
    );

    final double lastValue =
        values.last
            .clamp(0.0, 100.0)
            .toDouble();

    final double lastX =
        size.width;

    final double lastY =
        size.height -
        (lastValue / 100.0) *
            size.height;

    final pointPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.greenAccent;

    canvas.drawCircle(
      Offset(lastX, lastY),
      5,
      pointPaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant SignalPainter oldDelegate,
  ) {
    return oldDelegate.values != values;
  }
}
