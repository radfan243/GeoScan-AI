import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

class BluetoothService {
  // ============================================================
  // GeoScan AI - Bluetooth Service
  // الهاتف <-> ESP32
  //
  // مسؤول عن:
  // 1) البحث عن ESP32
  // 2) الاتصال
  // 3) اكتشاف خدمات BLE
  // 4) استقبال البيانات
  // 5) تجميع الحزم المجزأة
  // 6) التحقق من JSON
  // 7) تنظيف القراءات
  // 8) إرسال الأوامر إلى ESP32
  // ============================================================

  static const String serviceUuid =
      '12345678-1234-1234-1234-1234567890ab';

  static const String notifyCharacteristicUuid =
      '12345678-1234-1234-1234-1234567890ac';

  static const String writeCharacteristicUuid =
      '12345678-1234-1234-1234-1234567890ad';

  // ============================================================
  // الجهاز المتصل
  // ============================================================

  fbp.BluetoothDevice? connectedDevice;

  fbp.BluetoothCharacteristic? _notifyCharacteristic;
  fbp.BluetoothCharacteristic? _writeCharacteristic;

  // ============================================================
  // اشتراكات Bluetooth
  // ============================================================

  StreamSubscription<List<fbp.ScanResult>>? _scanSubscription;

  StreamSubscription<fbp.BluetoothConnectionState>?
      _connectionSubscription;

  StreamSubscription<List<int>>? _notifySubscription;

  // ============================================================
  // Streams
  // ============================================================

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<bool> get connectionStream =>
      _connectionController.stream;

  final StreamController<Map<String, dynamic>> _dataController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get dataStream =>
      _dataController.stream;

  // ============================================================
  // حالة الاتصال
  // ============================================================

  bool get isConnected =>
      connectedDevice != null &&
      _notifyCharacteristic != null &&
      _writeCharacteristic != null;

  // ============================================================
  // حالة استقبال البيانات
  // ============================================================

  bool _receivingData = false;

  bool get receivingData => _receivingData;

  DateTime? _lastDataTime;

  DateTime? get lastDataTime => _lastDataTime;

  // ============================================================
  // Buffer
  //
  // مهم جدًا:
  // Bluetooth قد يرسل JSON على أكثر من حزمة.
  // لذلك لا نعتمد على أن كل packet = JSON كامل.
  // ============================================================

  String _receiveBuffer = '';

  // ============================================================
  // البحث عن أجهزة Bluetooth
  // ============================================================

  Future<List<fbp.ScanResult>> scanForDevices({
    Duration duration = const Duration(seconds: 6),
  }) async {
    final Map<String, fbp.ScanResult> devices = {};

    await _scanSubscription?.cancel();

    _scanSubscription =
        fbp.FlutterBluePlus.scanResults.listen(
      (results) {
        for (final result in results) {
          final id = result.device.remoteId.str;

          devices[id] = result;
        }
      },
      onError: (_) {},
    );

    try {
      await fbp.FlutterBluePlus.startScan(
        timeout: duration,
      );

      await Future.delayed(duration);
    } finally {
      try {
        await fbp.FlutterBluePlus.stopScan();
      } catch (_) {}

      await _scanSubscription?.cancel();

      _scanSubscription = null;
    }

    return devices.values.toList();
  }

  // ============================================================
  // الاتصال بـ ESP32
  // ============================================================

  Future<void> connect(
    fbp.BluetoothDevice device,
  ) async {
    await disconnect();

    _resetReceiveState();

    try {
      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );
    } catch (e) {
      throw Exception(
        'فشل الاتصال بجهاز ESP32: $e',
      );
    }

    connectedDevice = device;

    // ==========================================================
    // مراقبة حالة الاتصال
    // ==========================================================

    _connectionSubscription =
        device.connectionState.listen(
      (state) async {
        final connected =
            state ==
                fbp.BluetoothConnectionState.connected;

        if (!_connectionController.isClosed) {
          _connectionController.add(
            connected,
          );
        }

        if (!connected) {
          _notifyCharacteristic = null;
          _writeCharacteristic = null;

          _receivingData = false;

          _resetReceiveState();
        }
      },
      onError: (_) {
        _receivingData = false;
      },
    );

    // ==========================================================
    // اكتشاف الخدمات
    // ==========================================================

    List<fbp.BluetoothService> services;

    try {
      services =
          await device.discoverServices();
    } catch (e) {
      await disconnect();

      throw Exception(
        'تعذر اكتشاف خدمات ESP32: $e',
      );
    }

    fbp.BluetoothCharacteristic? notifyCharacteristic;
    fbp.BluetoothCharacteristic? writeCharacteristic;

    // ==========================================================
    // البحث عن الخدمة والخصائص المطلوبة
    // ==========================================================

    for (final service in services) {
      final serviceId =
          service.uuid
              .toString()
              .toLowerCase();

      if (serviceId !=
          serviceUuid.toLowerCase()) {
        continue;
      }

      for (final characteristic
          in service.characteristics) {
        final id =
            characteristic.uuid
                .toString()
                .toLowerCase();

        if (id ==
            notifyCharacteristicUuid
                .toLowerCase()) {
          notifyCharacteristic =
              characteristic;
        }

        if (id ==
            writeCharacteristicUuid
                .toLowerCase()) {
          writeCharacteristic =
              characteristic;
        }
      }
    }

    // ==========================================================
    // التحقق من قناة الاستقبال
    // ==========================================================

    if (notifyCharacteristic == null) {
      await disconnect();

      throw Exception(
        'لم يتم العثور على قناة استقبال البيانات من ESP32.',
      );
    }

    // ==========================================================
    // التحقق من قناة الإرسال
    // ==========================================================

    if (writeCharacteristic == null) {
      await disconnect();

      throw Exception(
        'لم يتم العثور على قناة إرسال الأوامر إلى ESP32.',
      );
    }

    _notifyCharacteristic =
        notifyCharacteristic;

    _writeCharacteristic =
        writeCharacteristic;

    // ==========================================================
    // تفعيل Notifications
    // ==========================================================

    try {
      await _notifyCharacteristic!
          .setNotifyValue(true);
    } catch (e) {
      await disconnect();

      throw Exception(
        'تعذر تفعيل استقبال بيانات ESP32: $e',
      );
    }

    // ==========================================================
    // إلغاء الاشتراك السابق
    // ==========================================================

    await _notifySubscription?.cancel();

    // ==========================================================
    // استقبال البيانات
    // ==========================================================

    _notifySubscription =
        _notifyCharacteristic!
            .lastValueStream
            .listen(
      (value) {
        _handleIncomingData(value);
      },
      onError: (_) {
        _receivingData = false;
      },
    );

    // ==========================================================
    // تأكيد الاتصال
    // ==========================================================

    _receivingData = true;

    if (!_connectionController.isClosed) {
      _connectionController.add(true);
    }
  }

  // ============================================================
  // استقبال البيانات من ESP32
  // ============================================================

  void _handleIncomingData(
    List<int> bytes,
  ) {
    if (bytes.isEmpty) {
      return;
    }

    try {
      final text =
          utf8.decode(
        bytes,
        allowMalformed: true,
      );

      if (text.trim().isEmpty) {
        return;
      }

      _lastDataTime = DateTime.now();

      _receiveBuffer += text;

      // ========================================================
      // حماية من تضخم الذاكرة في حالة بيانات تالفة
      // ========================================================

      if (_receiveBuffer.length > 8192) {
        _receiveBuffer =
            _receiveBuffer.substring(
          _receiveBuffer.length - 4096,
        );
      }

      _processReceiveBuffer();
    } catch (_) {
      // لا نوقف التطبيق بسبب packet تالفة.
    }
  }

  // ============================================================
  // معالجة Buffer
  // ============================================================

  void _processReceiveBuffer() {
    // ==========================================================
    // أولًا:
    // نحاول التعامل مع JSON كامل مباشرة.
    //
    // هذا مهم إذا كان ESP32 يرسل:
    // {"signal":50,"stability":90}
    //
    // بدون newline.
    // ==========================================================

    final trimmed =
        _receiveBuffer.trim();

    if (trimmed.startsWith('{') &&
        trimmed.endsWith('}')) {
      try {
        final decoded =
            jsonDecode(trimmed);

        if (decoded
            is Map<String, dynamic>) {
          _publishData(decoded);

          _receiveBuffer = '';

          return;
        }
      } catch (_) {
        // قد يكون JSON مجزأ.
        // ننتظر packet التالية.
      }
    }

    // ==========================================================
    // ثانيًا:
    // إذا كان ESP32 يرسل JSON بهذا الشكل:
    //
    // {"signal":20}\n
    // {"signal":30}\n
    //
    // نعالج كل سطر بشكل مستقل.
    // ==========================================================

    while (true) {
      final newlineIndex =
          _receiveBuffer.indexOf('\n');

      if (newlineIndex == -1) {
        break;
      }

      final line =
          _receiveBuffer
              .substring(
                0,
                newlineIndex,
              )
              .trim();

      _receiveBuffer =
          _receiveBuffer.substring(
        newlineIndex + 1,
      );

      if (line.isEmpty) {
        continue;
      }

      _tryDecodeJson(line);
    }
  }

  // ============================================================
  // محاولة فك JSON
  // ============================================================

  void _tryDecodeJson(
    String text,
  ) {
    try {
      final decoded =
          jsonDecode(text);

      if (decoded
          is Map<String, dynamic>) {
        _publishData(decoded);
      }
    } catch (_) {
      // تجاهل البيانات غير الصالحة.
    }
  }

  // ============================================================
  // نشر البيانات بعد تنظيفها
  // ============================================================

  void _publishData(
    Map<String, dynamic> rawData,
  ) {
    final data =
        Map<String, dynamic>.from(
      rawData,
    );

    // ==========================================================
    // signal
    // ==========================================================

    if (data.containsKey('signal')) {
      data['signal'] =
          _sanitizePercentage(
        data['signal'],
      );
    }

    // ==========================================================
    // stability
    // ==========================================================

    if (data.containsKey('stability')) {
      data['stability'] =
          _sanitizePercentage(
        data['stability'],
      );
    }

    // ==========================================================
    // depth
    // ==========================================================

    if (data.containsKey('depth')) {
      data['depth'] =
          _sanitizeDepth(
        data['depth'],
      );
    }

    // ==========================================================
    // status
    // ==========================================================

    if (data.containsKey('status')) {
      data['status'] =
          data['status']
              .toString()
              .trim();
    }

    // ==========================================================
    // وقت القراءة
    // ==========================================================

    data['receivedAt'] =
        DateTime.now()
            .millisecondsSinceEpoch;

    _receivingData = true;

    if (!_dataController.isClosed) {
      _dataController.add(data);
    }
  }

  // ============================================================
  // تنظيف النسبة المئوية
  //
  // signal و stability:
  // 0 -> 100
  // ============================================================

  double _sanitizePercentage(
    dynamic value,
  ) {
    double result;

    if (value is num) {
      result = value.toDouble();
    } else {
      result =
          double.tryParse(
            value.toString(),
          ) ??
          0;
    }

    if (!result.isFinite) {
      return 0;
    }

    return result.clamp(
      0.0,
      100.0,
    );
  }

  // ============================================================
  // تنظيف العمق
  //
  // لا نفرض رقمًا وهميًا.
  // فقط نمنع القيم السالبة أو غير الصالحة.
  // ============================================================

  double _sanitizeDepth(
    dynamic value,
  ) {
    double result;

    if (value is num) {
      result = value.toDouble();
    } else {
      result =
          double.tryParse(
            value.toString(),
          ) ??
          0;
    }

    if (!result.isFinite ||
        result < 0) {
      return 0;
    }

    // حماية من القيم الشاذة.
    // يمكن تعديل الحد لاحقًا حسب الدائرة الحقيقية.
    return result.clamp(
      0.0,
      1000.0,
    );
  }

  // ============================================================
  // إرسال أمر إلى ESP32
  // ============================================================

  Future<void> sendCommand(
    String command,
  ) async {
    if (!isConnected ||
        _writeCharacteristic == null) {
      throw Exception(
        'ESP32 غير متصل أو قناة الأوامر غير جاهزة.',
      );
    }

    final cleanCommand =
        command.trim();

    if (cleanCommand.isEmpty) {
      return;
    }

    // ==========================================================
    // نرسل الأمر مع newline.
    //
    // ESP32 يستطيع قراءة الأمر كسطر كامل.
    // ==========================================================

    final payload =
        utf8.encode(
      '$cleanCommand\n',
    );

    try {
      await _writeCharacteristic!.write(
        payload,
        withoutResponse: true,
      );
    } catch (e) {
      throw Exception(
        'فشل إرسال الأمر إلى ESP32: $e',
      );
    }
  }

  // ============================================================
  // أوامر GeoScan AI
  // ============================================================

  Future<void> startScan() async {
    await sendCommand(
      'START',
    );
  }

  Future<void> stopScan() async {
    await sendCommand(
      'STOP',
    );
  }

  Future<void> calibrate() async {
    await sendCommand(
      'CALIBRATE',
    );
  }

  Future<void> getStatus() async {
    await sendCommand(
      'GET_STATUS',
    );
  }

  // ============================================================
  // الحساسية
  // ============================================================

  Future<void> setSensitivity(
    double value,
  ) async {
    final safeValue =
        value.clamp(
      0.0,
      100.0,
    );

    final sensitivity =
        safeValue.toStringAsFixed(0);

    await sendCommand(
      'SENSITIVITY:$sensitivity',
    );
  }

  // ============================================================
  // الفلترة
  // ============================================================

  Future<void> setFilter(
    String filter,
  ) async {
    final cleanFilter =
        filter.trim();

    if (cleanFilter.isEmpty) {
      return;
    }

    await sendCommand(
      'FILTER:$cleanFilter',
    );
  }

  // ============================================================
  // الصوت
  // ============================================================

  Future<void> setAudio(
    bool enabled,
  ) async {
    await sendCommand(
      enabled
          ? 'AUDIO:ON'
          : 'AUDIO:OFF',
    );
  }

  // ============================================================
  // الاهتزاز
  // ============================================================

  Future<void> setVibration(
    bool enabled,
  ) async {
    await sendCommand(
      enabled
          ? 'VIBRATION:ON'
          : 'VIBRATION:OFF',
    );
  }

  // ============================================================
  // إعادة ضبط حالة استقبال البيانات
  // ============================================================

  void _resetReceiveState() {
    _receiveBuffer = '';
    _receivingData = false;
    _lastDataTime = null;
  }

  // ============================================================
  // فصل الاتصال
  // ============================================================

  Future<void> disconnect() async {
    await _notifySubscription?.cancel();

    _notifySubscription = null;

    await _connectionSubscription?.cancel();

    _connectionSubscription = null;

    _resetReceiveState();

    if (connectedDevice != null) {
      try {
        await connectedDevice!.disconnect();
      } catch (_) {}
    }

    connectedDevice = null;

    _notifyCharacteristic = null;
    _writeCharacteristic = null;

    if (!_connectionController.isClosed) {
      _connectionController.add(false);
    }
  }

  // ============================================================
  // تنظيف الموارد
  // ============================================================

  Future<void> dispose() async {
    await _scanSubscription?.cancel();
    await _notifySubscription?.cancel();
    await _connectionSubscription?.cancel();

    _scanSubscription = null;
    _notifySubscription = null;
    _connectionSubscription = null;

    _resetReceiveState();

    if (!_connectionController.isClosed) {
      await _connectionController.close();
    }

    if (!_dataController.isClosed) {
      await _dataController.close();
    }
  }
}
