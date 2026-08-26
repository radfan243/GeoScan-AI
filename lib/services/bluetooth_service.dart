import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

class BluetoothService {
  // ============================================================
  // GeoScan AI - FINAL Bluetooth Service
  //
  // Flutter <-> ESP32
  //
  // مسؤول عن:
  // 1. البحث عن ESP32
  // 2. الاتصال
  // 3. اكتشاف BLE Service / Characteristics
  // 4. استقبال البيانات الحقيقية
  // 5. تجميع الحزم المجزأة
  // 6. التحقق من JSON
  // 7. تنظيف البيانات
  // 8. التحقق من signal / stability / depth
  // 9. الاحتفاظ بـ raw و baseline
  // 10. اكتشاف انقطاع البيانات
  // 11. إرسال أوامر التحكم
  //
  // ملاحظة:
  // هذا الملف لا يصنع قراءة وهمية.
  // البيانات تأتي من ESP32 كما هي ثم يتم التحقق منها.
  // ============================================================

  // ============================================================
  // UUIDs
  // يجب أن تطابق ESP32
  // ============================================================

  static const String serviceUuid =
      '12345678-1234-1234-1234-1234567890ab';

  static const String notifyCharacteristicUuid =
      '12345678-1234-1234-1234-1234567890ac';

  static const String writeCharacteristicUuid =
      '12345678-1234-1234-1234-1234567890ad';

  // ============================================================
  // الجهاز
  // ============================================================

  fbp.BluetoothDevice? connectedDevice;

  fbp.BluetoothCharacteristic? _notifyCharacteristic;

  fbp.BluetoothCharacteristic? _writeCharacteristic;

  // ============================================================
  // اشتراكات BLE
  // ============================================================

  StreamSubscription<List<fbp.ScanResult>>? _scanSubscription;

  StreamSubscription<fbp.BluetoothConnectionState>?
      _connectionSubscription;

  StreamSubscription<List<int>>? _notifySubscription;

  // ============================================================
  // Connection Stream
  // ============================================================

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<bool> get connectionStream =>
      _connectionController.stream;

  // ============================================================
  // Data Stream
  // ============================================================

  final StreamController<Map<String, dynamic>> _dataController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get dataStream =>
      _dataController.stream;

  // ============================================================
  // أخطاء Bluetooth
  // ============================================================

  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  Stream<String> get errorStream =>
      _errorController.stream;

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

  bool get receivingData =>
      _receivingData;

  // ============================================================
  // آخر قراءة
  // ============================================================

  DateTime? _lastDataTime;

  DateTime? get lastDataTime =>
      _lastDataTime;

  // ============================================================
  // عدد القراءات المستلمة
  // ============================================================

  int _receivedPackets = 0;

  int get receivedPackets =>
      _receivedPackets;

  // ============================================================
  // آخر رقم تسلسلي
  //
  // إذا أرسل ESP32:
  // "sequence": 123
  //
  // سيتم حفظه هنا.
  // ============================================================

  int? _lastSequence;

  int? get lastSequence =>
      _lastSequence;

  // ============================================================
  // Buffer
  // ============================================================

  String _receiveBuffer = '';

  // ============================================================
  // البحث عن الأجهزة
  // ============================================================

  Future<List<fbp.ScanResult>> scanForDevices({
    Duration duration =
        const Duration(seconds: 6),
  }) async {
    final Map<String, fbp.ScanResult> devices =
        {};

    await _scanSubscription?.cancel();

    _scanSubscription =
        fbp.FlutterBluePlus.scanResults.listen(
      (results) {
        for (final result in results) {
          final id =
              result.device.remoteId.str;

          devices[id] = result;
        }
      },
      onError: (error) {
        _emitError(
          'خطأ أثناء البحث عن أجهزة Bluetooth: $error',
        );
      },
    );

    try {
      await fbp.FlutterBluePlus.startScan(
        timeout: duration,
      );

      await Future.delayed(
        duration,
      );
    } catch (e) {
      _emitError(
        'تعذر بدء البحث عن Bluetooth: $e',
      );

      rethrow;
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
    // تنظيف اتصال سابق
    await disconnect();

    _resetReceiveState();

    try {
      await device.connect(
        timeout:
            const Duration(seconds: 10),
        autoConnect: false,
      );
    } catch (e) {
      final message =
          'فشل الاتصال بجهاز ESP32: $e';

      _emitError(message);

      throw Exception(message);
    }

    connectedDevice = device;

    // ==========================================================
    // مراقبة الاتصال
    // ==========================================================

    _connectionSubscription =
        device.connectionState.listen(
      (state) async {
        final connected =
            state ==
                fbp.BluetoothConnectionState
                    .connected;

        if (!_connectionController
            .isClosed) {
          _connectionController.add(
            connected,
          );
        }

        if (!connected) {
          _notifyCharacteristic =
              null;

          _writeCharacteristic =
              null;

          _receivingData = false;

          _resetReceiveState();
        }
      },
      onError: (error) {
        _receivingData = false;

        _emitError(
          'انقطع اتصال Bluetooth: $error',
        );
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

      final message =
          'تعذر اكتشاف خدمات ESP32: $e';

      _emitError(message);

      throw Exception(message);
    }

    fbp.BluetoothCharacteristic?
        notifyCharacteristic;

    fbp.BluetoothCharacteristic?
        writeCharacteristic;

    // ==========================================================
    // البحث عن الخدمة
    // ==========================================================

    for (final service in services) {
      final currentServiceUuid =
          service.uuid
              .toString()
              .toLowerCase();

      if (currentServiceUuid !=
          serviceUuid.toLowerCase()) {
        continue;
      }

      // ========================================================
      // البحث عن Characteristics
      // ========================================================

      for (final characteristic
          in service.characteristics) {
        final currentUuid =
            characteristic.uuid
                .toString()
                .toLowerCase();

        if (currentUuid ==
            notifyCharacteristicUuid
                .toLowerCase()) {
          notifyCharacteristic =
              characteristic;
        }

        if (currentUuid ==
            writeCharacteristicUuid
                .toLowerCase()) {
          writeCharacteristic =
              characteristic;
        }
      }
    }

    // ==========================================================
    // التحقق من Notify
    // ==========================================================

    if (notifyCharacteristic == null) {
      await disconnect();

      const message =
          'لم يتم العثور على قناة استقبال البيانات من ESP32.';

      _emitError(message);

      throw Exception(message);
    }

    // ==========================================================
    // التحقق من Write
    // ==========================================================

    if (writeCharacteristic == null) {
      await disconnect();

      const message =
          'لم يتم العثور على قناة إرسال الأوامر إلى ESP32.';

      _emitError(message);

      throw Exception(message);
    }

    _notifyCharacteristic =
        notifyCharacteristic;

    _writeCharacteristic =
        writeCharacteristic;

    // ==========================================================
    // تفعيل استقبال Notifications
    // ==========================================================

    try {
      await _notifyCharacteristic!
          .setNotifyValue(true);
    } catch (e) {
      await disconnect();

      final message =
          'تعذر تفعيل استقبال بيانات ESP32: $e';

      _emitError(message);

      throw Exception(message);
    }

    // ==========================================================
    // إلغاء الاشتراك السابق
    // ==========================================================

    await _notifySubscription?.cancel();

    // ==========================================================
    // استقبال بيانات ESP32
    // ==========================================================

    _notifySubscription =
        _notifyCharacteristic!
            .lastValueStream
            .listen(
      (bytes) {
        _handleIncomingData(bytes);
      },
      onError: (error) {
        _receivingData = false;

        _emitError(
          'خطأ في استقبال بيانات ESP32: $error',
        );
      },
    );

    // ==========================================================
    // الاتصال أصبح جاهزًا
    // ==========================================================

    _receivingData = true;

    if (!_connectionController.isClosed) {
      _connectionController.add(true);
    }

    // ==========================================================
    // طلب الحالة الحالية من ESP32
    // ==========================================================

    try {
      await getStatus();
    } catch (_) {
      // لا نفشل الاتصال إذا لم يرد ESP32 فورًا.
    }
  }

  // ============================================================
  // استقبال bytes من ESP32
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

      _lastDataTime =
          DateTime.now();

      _receivedPackets++;

      _receiveBuffer += text;

      // ========================================================
      // حماية الذاكرة
      // ========================================================

      if (_receiveBuffer.length > 16384) {
        _receiveBuffer =
            _receiveBuffer.substring(
          _receiveBuffer.length - 8192,
        );
      }

      _processReceiveBuffer();
    } catch (e) {
      _emitError(
        'تعذر قراءة بيانات ESP32: $e',
      );
    }
  }

  // ============================================================
  // معالجة Buffer
  // ============================================================

  void _processReceiveBuffer() {
    // ==========================================================
    // الحالة الأولى:
    // JSON كامل
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
        // JSON قد يكون مجزأ.
      }
    }

    // ==========================================================
    // الحالة الثانية:
    // JSON مع newline
    // ==========================================================

    while (true) {
      final newlineIndex =
          _receiveBuffer.indexOf('\n');

      if (newlineIndex == -1) {
        break;
      }

      final line =
          _receiveBuffer.substring(
        0,
        newlineIndex,
      ).trim();

      _receiveBuffer =
          _receiveBuffer.substring(
        newlineIndex + 1,
      );

      if (line.isEmpty) {
        continue;
      }

      _tryDecodeJson(line);
    }

    // ==========================================================
    // تنظيف البيانات التالفة قبل بداية JSON
    // ==========================================================

    final firstBrace =
        _receiveBuffer.indexOf('{');

    if (firstBrace > 0) {
      _receiveBuffer =
          _receiveBuffer.substring(
        firstBrace,
      );
    }
  }

  // ============================================================
  // فك JSON
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
      // تجاهل packet تالفة.
    }
  }

  // ============================================================
  // نشر البيانات
  // ============================================================

  void _publishData(
    Map<String, dynamic> rawData,
  ) {
    if (rawData.isEmpty) {
      return;
    }

    final data =
        Map<String, dynamic>.from(
      rawData,
    );

    // ==========================================================
    // type
    // ==========================================================

    if (data.containsKey('type')) {
      data['type'] =
          data['type']
              .toString()
              .trim();
    }

    // ==========================================================
    // signal
    // ==========================================================

    if (data.containsKey('signal')) {
      final value =
          _parseFiniteDouble(
        data['signal'],
      );

      if (value == null) {
        return;
      }

      data['signal'] =
          value.clamp(
        0.0,
        100.0,
      );
    }

    // ==========================================================
    // raw
    //
    // لا نعدل raw.
    // هذه القيمة هي قراءة ADC التي أرسلها ESP32.
    // ==========================================================

    if (data.containsKey('raw')) {
      final raw =
          _parseFiniteDouble(
        data['raw'],
      );

      if (raw == null) {
        data.remove('raw');
      } else {
        data['raw'] = raw;
      }
    }

    // ==========================================================
    // baseline
    // ==========================================================

    if (data.containsKey('baseline')) {
      final baseline =
          _parseFiniteDouble(
        data['baseline'],
      );

      if (baseline == null) {
        data.remove('baseline');
      } else {
        data['baseline'] =
            baseline;
      }
    }

    // ==========================================================
    // stability
    // ==========================================================

    if (data.containsKey('stability')) {
      final value =
          _parseFiniteDouble(
        data['stability'],
      );

      if (value == null) {
        return;
      }

      data['stability'] =
          value.clamp(
        0.0,
        100.0,
      );
    }

    // ==========================================================
    // depth
    //
    // لا نخترع العمق.
    // إذا لم يرسله ESP32 يبقى غير موجود.
    // ==========================================================

    if (data.containsKey('depth')) {
      final value =
          _parseFiniteDouble(
        data['depth'],
      );

      if (value == null ||
          value < 0) {
        data.remove('depth');
      } else {
        data['depth'] =
            value.clamp(
          0.0,
          1000.0,
        );
      }
    }

    // ==========================================================
    // sequence
    // ==========================================================

    if (data.containsKey('sequence')) {
      final sequence =
          _parseInteger(
        data['sequence'],
      );

      if (sequence != null &&
          sequence >= 0) {
        data['sequence'] =
            sequence;

        _lastSequence =
            sequence;
      } else {
        data.remove('sequence');
      }
    }

    // ==========================================================
    // timestamp
    // ==========================================================

    if (data.containsKey('timestamp')) {
      final timestamp =
          _parseInteger(
        data['timestamp'],
      );

      if (timestamp != null &&
          timestamp >= 0) {
        data['timestamp'] =
            timestamp;
      } else {
        data.remove('timestamp');
      }
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
    // scanning
    // ==========================================================

    if (data.containsKey('scanning')) {
      final scanning =
          _parseBool(
        data['scanning'],
      );

      if (scanning != null) {
        data['scanning'] =
            scanning;
      }
    }

    // ==========================================================
    // sensitivity
    // ==========================================================

    if (data.containsKey('sensitivity')) {
      final value =
          _parseFiniteDouble(
        data['sensitivity'],
      );

      if (value != null) {
        data['sensitivity'] =
            value.clamp(
          0.0,
          100.0,
        );
      }
    }

    // ==========================================================
    // filter
    // ==========================================================

    if (data.containsKey('filter')) {
      data['filter'] =
          data['filter']
              .toString()
              .trim();
    }

    // ==========================================================
    // مصدر البيانات
    // ==========================================================

    data['source'] =
        'ESP32';

    // ==========================================================
    // وقت استلام Flutter للبيانات
    // ==========================================================

    data['receivedAt'] =
        DateTime.now()
            .millisecondsSinceEpoch;

    // ==========================================================
    // حالة استقبال البيانات
    // ==========================================================

    _receivingData = true;

    // ==========================================================
    // إرسال البيانات إلى ScanScreen
    // ==========================================================

    if (!_dataController.isClosed) {
      _dataController.add(data);
    }
  }

  // ============================================================
  // تحويل رقم آمن
  // ============================================================

  double? _parseFiniteDouble(
    dynamic value,
  ) {
    double? result;

    if (value is num) {
      result = value.toDouble();
    } else {
      result =
          double.tryParse(
        value.toString().trim(),
      );
    }

    if (result == null ||
        !result.isFinite) {
      return null;
    }

    return result;
  }

  // ============================================================
  // تحويل Integer
  // ============================================================

  int? _parseInteger(
    dynamic value,
  ) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      final double number =
          value.toDouble();

      if (!number.isFinite) {
        return null;
      }

      return number.round();
    }

    return int.tryParse(
      value.toString().trim(),
    );
  }

  // ============================================================
  // Boolean
  // ============================================================

  bool? _parseBool(
    dynamic value,
  ) {
    if (value is bool) {
      return value;
    }

    final text =
        value.toString().trim().toLowerCase();

    if (text == 'true' ||
        text == '1' ||
        text == 'yes') {
      return true;
    }

    if (text == 'false' ||
        text == '0' ||
        text == 'no') {
      return false;
    }

    return null;
  }

  // ============================================================
  // إرسال أمر إلى ESP32
  // ============================================================

  Future<void> sendCommand(
    String command,
  ) async {
    if (!isConnected ||
        _writeCharacteristic == null) {
      const message =
          'ESP32 غير متصل أو قناة الأوامر غير جاهزة.';

      _emitError(message);

      throw Exception(message);
    }

    final cleanCommand =
        command.trim();

    if (cleanCommand.isEmpty) {
      return;
    }

    // ==========================================================
    // ESP32 يستقبل الأمر كسطر
    // ==========================================================

    final payload =
        utf8.encode(
      '$cleanCommand\n',
    );

    try {
      // ========================================================
      // نستخدم Write Without Response
      // لأن ESP32 أعد characteristic بهذه الخاصية.
      // ========================================================

      if (_writeCharacteristic!
          .properties
          .writeWithoutResponse) {
        await _writeCharacteristic!
            .write(
          payload,
          withoutResponse: true,
        );
      } else {
        await _writeCharacteristic!
            .write(
          payload,
          withoutResponse: false,
        );
      }
    } catch (e) {
      final message =
          'فشل إرسال الأمر إلى ESP32: $e';

      _emitError(message);

      throw Exception(message);
    }
  }

  // ============================================================
  // START
  // ============================================================

  Future<void> startScan() async {
    await sendCommand(
      'START',
    );
  }

  // ============================================================
  // STOP
  // ============================================================

  Future<void> stopScan() async {
    await sendCommand(
      'STOP',
    );
  }

  // ============================================================
  // CALIBRATE
  // ============================================================

  Future<void> calibrate() async {
    await sendCommand(
      'CALIBRATE',
    );
  }

  // ============================================================
  // GET STATUS
  // ============================================================

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
  // فحص سلامة استقبال البيانات
  //
  // إذا مر وقت طويل بدون بيانات:
  // receivingData يصبح false.
  // ============================================================

  bool get hasRecentData {
    if (_lastDataTime == null) {
      return false;
    }

    final elapsed =
        DateTime.now()
            .difference(
      _lastDataTime!,
    );

    return elapsed.inSeconds < 3;
  }

  // ============================================================
  // آخر عمر للبيانات بالميلي ثانية
  // ============================================================

  int? get dataAgeMilliseconds {
    if (_lastDataTime == null) {
      return null;
    }

    return DateTime.now()
        .difference(
          _lastDataTime!,
        )
        .inMilliseconds;
  }

  // ============================================================
  // إعادة ضبط حالة الاستقبال
  // ============================================================

  void _resetReceiveState() {
    _receiveBuffer = '';

    _receivingData = false;

    _lastDataTime = null;

    _receivedPackets = 0;

    _lastSequence = null;
  }

  // ============================================================
  // إرسال خطأ
  // ============================================================

  void _emitError(
    String message,
  ) {
    if (!_errorController.isClosed) {
      _errorController.add(
        message,
      );
    }
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

    if (_notifyCharacteristic != null) {
      try {
        await _notifyCharacteristic!
            .setNotifyValue(false);
      } catch (_) {}
    }

    if (connectedDevice != null) {
      try {
        await connectedDevice!
            .disconnect();
      } catch (_) {}
    }

    connectedDevice = null;

    _notifyCharacteristic =
        null;

    _writeCharacteristic =
        null;

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

    try {
      await disconnect();
    } catch (_) {}

    if (!_connectionController.isClosed) {
      await _connectionController.close();
    }

    if (!_dataController.isClosed) {
      await _dataController.close();
    }

    if (!_errorController.isClosed) {
      await _errorController.close();
    }
  }
}
