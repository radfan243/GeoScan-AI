import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../services/bluetooth_service.dart';

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});

  @override
  State<BluetoothScreen> createState() =>
      _BluetoothScreenState();
}

class _BluetoothScreenState
    extends State<BluetoothScreen> {
  // ============================================================
  // SHARED BluetoothService
  //
  // هذه ليست نسخة جديدة من الاتصال.
  // factory يعيد نفس النسخة المستخدمة في ScanScreen.
  // ============================================================

  final BluetoothService _bluetoothService =
      BluetoothService();

  final List<fbp.ScanResult> _devices = [];

  StreamSubscription<bool>?
      _connectionSubscription;

  bool _scanning = false;
  bool _connecting = false;
  bool _connected = false;

  String _status =
      'جاهز للبحث عن ESP32';

  String _connectedDevice = '';

  @override
  void initState() {
    super.initState();

    // قراءة الحالة الحالية أولًا
    _connected =
        _bluetoothService.isConnected;

    if (_connected) {
      _status =
          'متصل بجهاز ESP32';

      _connectedDevice =
          _bluetoothService.deviceName;
    }

    // متابعة الاتصال المشترك
    _connectionSubscription =
        _bluetoothService.connectionStream
            .listen(
      (connected) {
        if (!mounted) return;

        setState(() {
          _connected = connected;

          if (connected) {
            _status =
                'متصل بجهاز ESP32';

            _connectedDevice =
                _bluetoothService.deviceName;
          } else {
            _status =
                'غير متصل';

            _connectedDevice = '';
          }
        });
      },
    );
  }

  @override
  void dispose() {
    // مهم جدًا:
    //
    // لا نعمل:
    // _bluetoothService.dispose();
    //
    // لأن الخدمة مشتركة مع ScanScreen.
    //
    // نلغي اشتراك هذه الشاشة فقط.
    _connectionSubscription?.cancel();

    super.dispose();
  }

  // ============================================================
  // SEARCH FOR ESP32
  // ============================================================

  Future<void> _startScan() async {
    if (_scanning) return;

    if (!mounted) return;

    setState(() {
      _scanning = true;
      _devices.clear();
      _status =
          'جاري البحث عن أجهزة ESP32...';
    });

    try {
      final results =
          await _bluetoothService.scan();

      if (!mounted) return;

      setState(() {
        _devices
          ..clear()
          ..addAll(results);

        _scanning = false;

        if (_devices.isEmpty) {
          _status =
              'لم يتم العثور على جهاز';
        } else {
          _status =
              'تم العثور على ${_devices.length} جهاز';
        }
      });
    } catch (e) {
      debugPrint(
        'Bluetooth scan error: $e',
      );

      if (!mounted) return;

      setState(() {
        _scanning = false;
        _status =
            'حدث خطأ أثناء البحث';
      });

      _showMessage(
        'تعذر البحث عن أجهزة Bluetooth',
      );
    }
  }

  // ============================================================
  // CONNECT
  // ============================================================

  Future<void> _connect(
    fbp.BluetoothDevice device,
  ) async {
    if (_connecting) return;

    if (!mounted) return;

    setState(() {
      _connecting = true;
      _status =
          'جاري الاتصال بـ ESP32...';
    });

    try {
      final success =
          await _bluetoothService.connect(
        device,
      );

      if (!mounted) return;

      if (success) {
        // مهم:
        //
        // connect() داخل BluetoothService
        // يقوم أصلًا بتشغيل Notifications.
        //
        // لذلك لا نستدعي startNotifications()
        // مرة ثانية.

        setState(() {
          _connecting = false;
          _connected = true;

          _connectedDevice =
              _bluetoothService.deviceName;

          _status =
              'متصل وجاهز لاستقبال البيانات';
        });

        _showMessage(
          'تم الاتصال بنجاح',
        );
      } else {
        setState(() {
          _connecting = false;
          _connected = false;
          _status =
              'فشل الاتصال';
        });

        _showMessage(
          'فشل الاتصال بجهاز ESP32',
        );
      }
    } catch (e) {
      debugPrint(
        'Bluetooth connection error: $e',
      );

      if (!mounted) return;

      setState(() {
        _connecting = false;
        _connected = false;
        _status =
            'فشل الاتصال';
      });

      _showMessage(
        'حدث خطأ أثناء الاتصال',
      );
    }
  }

  // ============================================================
  // DISCONNECT
  // ============================================================

  Future<void> _disconnect() async {
    await _bluetoothService.disconnect();

    if (!mounted) return;

    setState(() {
      _connected = false;
      _connectedDevice = '';
      _status =
          'تم فصل الجهاز';
    });
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
  // DEVICE NAME
  // ============================================================

  String _deviceName(
    fbp.ScanResult result,
  ) {
    final platformName =
        result.device.platformName.trim();

    if (platformName.isNotEmpty) {
      return platformName;
    }

    final advertisedName =
        result.advertisementData.advName
            .trim();

    if (advertisedName.isNotEmpty) {
      return advertisedName;
    }

    return 'جهاز Bluetooth';
  }

  // ============================================================
  // GEOSCAN DEVICE CHECK
  // ============================================================

  bool _isGeoScanDevice(
    fbp.ScanResult result,
  ) {
    final name =
        _deviceName(result).toLowerCase();

    return name.contains('geoscan') ||
        name.contains('esp32');
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          const Color(0xFF060B18),

      appBar: AppBar(
        backgroundColor:
            const Color(0xFF060B18),
        elevation: 0,
        centerTitle: true,

        title: const Text(
          'GeoScan AI',
          style: TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),

        actions: [
          IconButton(
            onPressed:
                _scanning
                    ? null
                    : _startScan,
            icon: const Icon(
              Icons.refresh,
            ),
            tooltip: 'بحث',
          ),
        ],
      ),

      body: SafeArea(
        child: Directionality(
          textDirection:
              TextDirection.rtl,

          child: Padding(
            padding:
                const EdgeInsets.all(16),

            child: Column(
              children: [
                _connectionCard(),

                const SizedBox(
                  height: 16,
                ),

                _scanButton(),

                const SizedBox(
                  height: 18,
                ),

                Expanded(
                  child:
                      _deviceList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // CONNECTION CARD
  // ============================================================

  Widget _connectionCard() {
    return Container(
      width: double.infinity,

      padding:
          const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color:
            const Color(0xFF101827),

        borderRadius:
            BorderRadius.circular(20),

        border: Border.all(
          color: _connected
              ? Colors.greenAccent
                  .withOpacity(0.45)
              : Colors.white10,
        ),
      ),

      child: Column(
        children: [
          Icon(
            _connected
                ? Icons
                    .bluetooth_connected
                : Icons
                    .bluetooth_disabled,

            size: 48,

            color: _connected
                ? Colors.greenAccent
                : Colors.white54,
          ),

          const SizedBox(
            height: 12,
          ),

          Text(
            _connected
                ? 'متصل'
                : 'غير متصل',

            style: TextStyle(
              color: _connected
                  ? Colors.greenAccent
                  : Colors.white70,

              fontSize: 22,

              fontWeight:
                  FontWeight.bold,
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          Text(
            _connected
                ? _connectedDevice
                : _status,

            textAlign:
                TextAlign.center,

            style: const TextStyle(
              color: Colors.white60,
              fontSize: 15,
            ),
          ),

          if (_connected) ...[
            const SizedBox(
              height: 14,
            ),

            SizedBox(
              width: double.infinity,

              child:
                  OutlinedButton.icon(
                onPressed:
                    _disconnect,

                icon: const Icon(
                  Icons.link_off,
                ),

                label: const Text(
                  'فصل ESP32',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // SCAN BUTTON
  // ============================================================

  Widget _scanButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,

      child:
          ElevatedButton.icon(
        onPressed:
            (_scanning ||
                    _connecting)
                ? null
                : _startScan,

        icon: _scanning
            ? const SizedBox(
                width: 20,
                height: 20,

                child:
                    CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
            : const Icon(
                Icons
                    .bluetooth_searching,
              ),

        label: Text(
          _scanning
              ? 'جاري البحث...'
              : 'البحث عن ESP32',

          style:
              const TextStyle(
            fontSize: 17,
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // DEVICE LIST
  // ============================================================

  Widget _deviceList() {
    if (_scanning) {
      return const Center(
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,

          children: [
            CircularProgressIndicator(),

            SizedBox(
              height: 16,
            ),

            Text(
              'جاري البحث عن الأجهزة...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    if (_devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,

          children: [
            const Icon(
              Icons
                  .bluetooth_searching,

              size: 70,

              color: Colors.white24,
            ),

            const SizedBox(
              height: 16,
            ),

            const Text(
              'لا توجد أجهزة مكتشفة',

              style: TextStyle(
                color: Colors.white70,
                fontSize: 18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            const Text(
              'شغّل ESP32 ثم اضغط البحث',

              style: TextStyle(
                color: Colors.white38,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    final sortedDevices =
        [..._devices];

    sortedDevices.sort(
      (a, b) {
        final aGeo =
            _isGeoScanDevice(a);

        final bGeo =
            _isGeoScanDevice(b);

        if (aGeo && !bGeo) {
          return -1;
        }

        if (!aGeo && bGeo) {
          return 1;
        }

        return b.rssi.compareTo(
          a.rssi,
        );
      },
    );

    return ListView.separated(
      itemCount:
          sortedDevices.length,

      separatorBuilder:
          (_, __) =>
              const SizedBox(
        height: 10,
      ),

      itemBuilder:
          (context, index) {
        final result =
            sortedDevices[index];

        final name =
            _deviceName(result);

        final isGeoScan =
            _isGeoScanDevice(
          result,
        );

        return Container(
          decoration:
              BoxDecoration(
            color:
                const Color(
              0xFF101827,
            ),

            borderRadius:
                BorderRadius.circular(
              18,
            ),

            border: Border.all(
              color: isGeoScan
                  ? Colors.blueAccent
                      .withOpacity(
                      0.5,
                    )
                  : Colors.white10,
            ),
          ),

          child: ListTile(
            contentPadding:
                const EdgeInsets
                    .symmetric(
              horizontal: 16,
              vertical: 8,
            ),

            leading:
                CircleAvatar(
              radius: 25,

              backgroundColor:
                  isGeoScan
                      ? Colors
                          .blueAccent
                          .withOpacity(
                          0.15,
                        )
                      : Colors.white10,

              child: Icon(
                Icons.memory,

                color: isGeoScan
                    ? Colors.blueAccent
                    : Colors.white54,
              ),
            ),

            title: Row(
              children: [
                Expanded(
                  child: Text(
                    name,

                    style:
                        const TextStyle(
                      color:
                          Colors.white,

                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),

                if (isGeoScan)
                  Container(
                    padding:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),

                    decoration:
                        BoxDecoration(
                      color: Colors.green
                          .withOpacity(
                        0.15,
                      ),

                      borderRadius:
                          BorderRadius
                              .circular(
                        8,
                      ),
                    ),

                    child:
                        const Text(
                      'GeoScan',

                      style:
                          TextStyle(
                        color:
                            Colors.greenAccent,

                        fontSize: 11,

                        fontWeight:
                            FontWeight
                                .bold,
                      ),
                    ),
                  ),
              ],
            ),

            subtitle:
                Padding(
              padding:
                  const EdgeInsets
                      .only(
                top: 6,
              ),

              child: Text(
                '${result.device.remoteId.str}\nالإشارة: ${result.rssi} dBm',

                style:
                    const TextStyle(
                  color:
                      Colors.white54,

                  fontSize: 12,
                ),
              ),
            ),

            trailing:
                ElevatedButton(
              onPressed:
                  _connecting
                      ? null
                      : () =>
                          _connect(
                            result.device,
                          ),

              child:
                  const Text(
                'اتصال',
              ),
            ),
          ),
        );
      },
    );
  }
}
