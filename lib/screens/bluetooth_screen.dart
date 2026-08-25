import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../services/bluetooth_service.dart';
import 'scan_screen.dart';

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  final BluetoothService _bluetooth = BluetoothService();

  List<fbp.ScanResult> _devices = [];

  bool _scanning = false;
  bool _connecting = false;

  fbp.BluetoothDevice? _connectedDevice;

  @override
  void initState() {
    super.initState();

    _connectedDevice = _bluetooth.connectedDevice;
  }

  // ============================================================
  // البحث عن أجهزة Bluetooth
  // ============================================================

  Future<void> _scanDevices() async {
    if (_scanning) return;

    if (!mounted) return;

    setState(() {
      _scanning = true;
      _devices = [];
    });

    try {
      final results = await _bluetooth.scanForDevices(
        duration: const Duration(seconds: 6),
      );

      if (!mounted) return;

      // ترتيب الأجهزة: التي تحمل اسمًا أولًا
      results.sort((a, b) {
        final nameA = a.device.name.trim();
        final nameB = b.device.name.trim();

        if (nameA.isEmpty && nameB.isNotEmpty) {
          return 1;
        }

        if (nameA.isNotEmpty && nameB.isEmpty) {
          return -1;
        }

        return nameA.compareTo(nameB);
      });

      setState(() {
        _devices = results;
      });

      if (_devices.isEmpty) {
        _showMessage(
          'لم يتم العثور على أجهزة Bluetooth.',
        );
      }
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'حدث خطأ أثناء البحث عن الأجهزة.',
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _scanning = false;
      });
    }
  }

  // ============================================================
  // الاتصال بالجهاز
  // ============================================================

  Future<void> _connect(
    fbp.BluetoothDevice device,
  ) async {
    if (_connecting) return;

    if (!mounted) return;

    setState(() {
      _connecting = true;
    });

    try {
      await _bluetooth.connect(device);

      if (!mounted) return;

      setState(() {
        _connectedDevice = device;
      });

      _showMessage(
        'تم الاتصال بجهاز ESP32 بنجاح.',
        success: true,
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'فشل الاتصال بجهاز ESP32.',
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _connecting = false;
      });
    }
  }

  // ============================================================
  // فصل الجهاز
  // ============================================================

  Future<void> _disconnect() async {
    try {
      await _bluetooth.disconnect();

      if (!mounted) return;

      setState(() {
        _connectedDevice = null;
      });

      _showMessage(
        'تم فصل جهاز ESP32.',
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'تعذر فصل الجهاز.',
      );
    }
  }

  // ============================================================
  // الانتقال إلى شاشة المسح
  // ============================================================

  void _openScanScreen() {
    if (!_bluetooth.isConnected) {
      _showMessage(
        'اتصل بجهاز ESP32 أولًا.',
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanScreen(),
      ),
    );
  }

  // ============================================================
  // الرسائل
  // ============================================================

  void _showMessage(
    String message, {
    bool success = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            message,
            textDirection: TextDirection.rtl,
          ),
          backgroundColor:
              success ? Colors.green.shade700 : null,
        ),
      );
  }

  // ============================================================
  // اسم الجهاز
  // ============================================================

  String _deviceName(
    fbp.BluetoothDevice device,
  ) {
    final name = device.name.trim();

    if (name.isNotEmpty) {
      return name;
    }

    return 'جهاز Bluetooth';
  }

  // ============================================================
  // قوة الإشارة
  // ============================================================

  String _signalText(
    fbp.ScanResult result,
  ) {
    final rssi = result.rssi;

    if (rssi >= -60) {
      return 'إشارة قوية';
    }

    if (rssi >= -80) {
      return 'إشارة جيدة';
    }

    return 'إشارة ضعيفة';
  }

  Color _signalColor(
    fbp.ScanResult result,
  ) {
    final rssi = result.rssi;

    if (rssi >= -60) {
      return Colors.greenAccent;
    }

    if (rssi >= -80) {
      return Colors.amberAccent;
    }

    return Colors.orangeAccent;
  }

  // ============================================================
  // واجهة المستخدم
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final connected = _bluetooth.isConnected;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF050B16),

        // ======================================================
        // AppBar
        // ======================================================

        appBar: AppBar(
          backgroundColor: const Color(0xFF050B16),
          elevation: 0,
          centerTitle: true,

          title: const Column(
            children: [
              Text(
                'GeoScan AI',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'اتصال الجهاز',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white54,
                ),
              ),
            ],
          ),

          actions: [
            Padding(
              padding: const EdgeInsets.only(
                left: 12,
              ),
              child: Icon(
                connected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                color: connected
                    ? Colors.greenAccent
                    : Colors.redAccent,
              ),
            ),
          ],
        ),

        // ======================================================
        // Body
        // ======================================================

        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              16,
              10,
              16,
              30,
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [

                // ==================================================
                // بطاقة الحالة
                // ==================================================

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient:
                        const LinearGradient(
                      colors: [
                        Color(0xFF123B4A),
                        Color(0xFF07111F),
                      ],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    borderRadius:
                        BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.cyanAccent
                          .withOpacity(0.15),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        connected
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth_searching,
                        size: 70,
                        color: connected
                            ? Colors.greenAccent
                            : Colors.cyanAccent,
                      ),

                      const SizedBox(height: 12),

                      Text(
                        connected
                            ? 'ESP32 متصل'
                            : 'Bluetooth غير متصل',
                        style: TextStyle(
                          color: connected
                              ? Colors.greenAccent
                              : Colors.white,
                          fontSize: 23,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        connected
                            ? _deviceName(
                                _connectedDevice!,
                              )
                            : 'ابحث عن جهاز ESP32 للبدء',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ==================================================
                // زر البحث
                // ==================================================

                SizedBox(
                  height: 58,
                  child: FilledButton.icon(
                    onPressed:
                        _scanning ? null : _scanDevices,
                    icon: _scanning
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Icon(
                            Icons.bluetooth_searching,
                            size: 27,
                          ),
                    label: Text(
                      _scanning
                          ? 'جاري البحث...'
                          : 'البحث عن أجهزة ESP32',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ==================================================
                // عنوان الأجهزة
                // ==================================================

                Row(
                  children: [
                    const Icon(
                      Icons.devices,
                      color: Colors.cyanAccent,
                    ),

                    const SizedBox(width: 8),

                    const Expanded(
                      child: Text(
                        'الأجهزة المكتشفة',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    if (_devices.isNotEmpty)
                      Text(
                        '${_devices.length}',
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 10),

                // ==================================================
                // قائمة الأجهزة
                // ==================================================

                if (_devices.isEmpty)
                  Container(
                    padding:
                        const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: const Color(0xFF07111F),
                      borderRadius:
                          BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white
                            .withOpacity(0.07),
                      ),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.bluetooth_disabled,
                          size: 55,
                          color: Colors.white38,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'لا توجد أجهزة مكتشفة',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'اضغط على زر البحث للعثور على جهاز ESP32.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ..._devices.map(
                    (result) {
                      final device =
                          result.device;

                      final name =
                          _deviceName(device);

                      final isCurrent =
                          _connectedDevice
                                  ?.remoteId ==
                              device.remoteId;

                      final signalColor =
                          _signalColor(result);

                      return Container(
                        margin:
                            const EdgeInsets.only(
                          bottom: 10,
                        ),
                        decoration:
                            BoxDecoration(
                          color:
                              const Color(0xFF07111F),
                          borderRadius:
                              BorderRadius.circular(
                            18,
                          ),
                          border: Border.all(
                            color: isCurrent
                                ? Colors.greenAccent
                                    .withOpacity(
                                    0.45,
                                  )
                                : Colors.white
                                    .withOpacity(
                                    0.07,
                                  ),
                          ),
                        ),
                        child: Padding(
                          padding:
                              const EdgeInsets.all(
                            12,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration:
                                    BoxDecoration(
                                  color: Colors
                                      .cyanAccent
                                      .withOpacity(
                                    0.08,
                                  ),
                                  borderRadius:
                                      BorderRadius
                                          .circular(
                                    14,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.memory,
                                  color: Colors
                                      .cyanAccent,
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
                                      name,
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow
                                              .ellipsis,
                                      style:
                                          const TextStyle(
                                        color:
                                            Colors.white,
                                        fontSize: 16,
                                        fontWeight:
                                            FontWeight
                                                .bold,
                                      ),
                                    ),

                                    const SizedBox(
                                      height: 4,
                                    ),

                                    Text(
                                      device.remoteId
                                          .str,
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow
                                              .ellipsis,
                                      style:
                                          const TextStyle(
                                        color:
                                            Colors.white38,
                                        fontSize: 10,
                                      ),
                                    ),

                                    const SizedBox(
                                      height: 4,
                                    ),

                                    Row(
                                      children: [
                                        Icon(
                                          Icons
                                              .signal_cellular_alt,
                                          size: 14,
                                          color:
                                              signalColor,
                                        ),
                                        const SizedBox(
                                          width: 4,
                                        ),
                                        Text(
                                          '${result.rssi} dBm — ${_signalText(result)}',
                                          style:
                                              TextStyle(
                                            color:
                                                signalColor,
                                            fontSize:
                                                11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(
                                width: 8,
                              ),

                              if (isCurrent)
                                IconButton(
                                  tooltip:
                                      'فصل الاتصال',
                                  onPressed:
                                      _disconnect,
                                  icon:
                                      const Icon(
                                    Icons
                                        .link_off,
                                    color:
                                        Colors
                                            .redAccent,
                                  ),
                                )
                              else
                                FilledButton(
                                  onPressed:
                                      _connecting
                                          ? null
                                          : () =>
                                              _connect(
                                                device,
                                              ),
                                  child: _connecting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child:
                                              CircularProgressIndicator(
                                            strokeWidth:
                                                2,
                                          ),
                                        )
                                      : const Text(
                                          'اتصال',
                                        ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                // ==================================================
                // الانتقال إلى المسح
                // ==================================================

                if (connected) ...[
                  const SizedBox(height: 14),

                  Container(
                    padding:
                        const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent
                          .withOpacity(0.05),
                      borderRadius:
                          BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.greenAccent
                            .withOpacity(0.18),
                      ),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color:
                                  Colors.greenAccent,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'الجهاز جاهز',
                              style: TextStyle(
                                color:
                                    Colors.greenAccent,
                                fontSize: 17,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        const Text(
                          'تم إنشاء اتصال Bluetooth ويمكن الآن الانتقال إلى شاشة المسح واستقبال بيانات الحساس.',
                          textAlign:
                              TextAlign.center,
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),

                        const SizedBox(height: 12),

                        SizedBox(
                          width:
                              double.infinity,
                          height: 52,
                          child:
                              FilledButton.icon(
                            onPressed:
                                _openScanScreen,
                            icon: const Icon(
                              Icons.radar,
                            ),
                            label: const Text(
                              'فتح شاشة المسح',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // ==================================================
                // ملاحظة
                // ==================================================

                Container(
                  padding:
                      const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber
                        .withOpacity(0.04),
                    borderRadius:
                        BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.amber
                          .withOpacity(0.12),
                    ),
                  ),
                  child: const Text(
                    'ملاحظة: يجب أن يكون جهاز ESP32 يعمل ويستخدم خدمة Bluetooth بنفس UUID الخاصة بتطبيق GeoScan AI حتى يتم الاتصال واستقبال البيانات.',
                    textAlign:
                        TextAlign.center,
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
