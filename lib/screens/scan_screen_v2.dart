import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/bluetooth_service.dart';

class ScanScreenV2 extends StatefulWidget {
  const ScanScreenV2({super.key, this.onSaved});

  final ValueChanged<Map<String, dynamic>>? onSaved;

  @override
  State<ScanScreenV2> createState() => _ScanScreenV2State();
}

class _ScanScreenV2State extends State<ScanScreenV2> {
  final BluetoothService bt = BluetoothService();
  final List<double> history = <double>[];

  StreamSubscription<String>? dataSub;
  StreamSubscription<bool>? connectionSub;

  double signal = 0;
  double raw = 0;
  double stability = 0;
  double depth = 0;
  double sensitivity = 75;

  bool connected = false;
  bool scanning = false;
  bool calibrating = false;
  bool audio = true;
  bool vibration = true;

  String filter = 'متوسطة';
  String status = 'غير متصل';
  String target = 'غير محدد';
  DateTime? lastData;

  @override
  void initState() {
    super.initState();
    connected = bt.isConnected;
    status = connected ? 'متصل' : 'غير متصل';
    dataSub = bt.dataStream.listen(_onData);
    connectionSub = bt.connectionStream.listen(_onConnection);
  }

  @override
  void dispose() {
    dataSub?.cancel();
    connectionSub?.cancel();
    super.dispose();
  }

  void _onConnection(bool value) {
    if (!mounted) return;
    setState(() {
      connected = value;
      status = value ? 'متصل' : 'غير متصل';
      if (!value) {
        scanning = false;
        calibrating = false;
        signal = 0;
        raw = 0;
        stability = 0;
        depth = 0;
        history.clear();
        lastData = null;
      }
    });
  }

  void _onData(String text) {
    if (!mounted || text.trim().isEmpty) return;

    final Map<String, dynamic> data = <String, dynamic>{};
    try {
      final dynamic decoded = jsonDecode(text.trim());
      if (decoded is Map) {
        data.addAll(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      final double? number = double.tryParse(
        text.trim().replaceAll(',', '.'),
      );
      if (number != null) data['signal'] = number;
    }

    if (data.isEmpty) return;

    final double nextSignal = _number(
      data,
      const <String>['signal', 'value', 'strength', 'reading'],
      signal,
    ).clamp(0.0, 100.0).toDouble();
    final double nextRaw = _number(
      data,
      const <String>['raw', 'rawSignal'],
      raw,
    );
    final double nextStability = _number(
      data,
      const <String>['stability', 'stable'],
      stability,
    ).clamp(0.0, 100.0).toDouble();
    final double nextDepth = _number(
      data,
      const <String>['depth', 'distance'],
      depth,
    );

    final String rawStatus = '${data['status'] ?? ''}'.toLowerCase();
    final bool deviceScanning = data['scanning'] == true ||
        rawStatus == 'scanning' ||
        data['status'] == 'يمسح' ||
        data['status'] == 'مسح';

    setState(() {
      signal = signal == 0
          ? nextSignal
          : (signal * 0.70 + nextSignal * 0.30).clamp(0.0, 100.0).toDouble();
      raw = nextRaw;
      stability = nextStability;
      depth = nextDepth.isFinite && nextDepth >= 0 ? nextDepth : 0;
      scanning = deviceScanning;
      status = data['status']?.toString().trim().isNotEmpty == true
          ? data['status'].toString().trim()
          : (deviceScanning ? 'يمسح' : 'متصل');

      final String incomingTarget = data['target']?.toString().trim() ?? '';
      if (incomingTarget.isNotEmpty) target = incomingTarget;

      lastData = DateTime.now();
      if (history.length >= 80) history.removeAt(0);
      history.add(signal);
    });
  }

  double _number(
    Map<String, dynamic> data,
    List<String> keys,
    double fallback,
  ) {
    for (final String key in keys) {
      final dynamic value = data[key];
      if (value is num) return value.toDouble();
      final double? parsed = double.tryParse(
        value?.toString().replaceAll(',', '.').trim() ?? '',
      );
      if (parsed != null && parsed.isFinite) return parsed;
    }
    return fallback;
  }

  bool get recent =>
      lastData != null && DateTime.now().difference(lastData!).inSeconds < 3;

  Color get signalColor {
    if (signal < 20) return Colors.redAccent;
    if (signal < 40) return Colors.orangeAccent;
    if (signal < 65) return Colors.amberAccent;
    return Colors.greenAccent;
  }

  String get signalText {
    if (!connected) return 'غير متصل';
    if (calibrating) return 'جاري المعايرة';
    if (scanning && !recent) return 'بانتظار البيانات';
    if (!scanning) return 'جاهز للمسح';
    if (signal < 20) return 'إشارة ضعيفة';
    if (signal < 40) return 'إشارة متوسطة';
    if (signal < 65) return 'إشارة جيدة';
    if (signal < 85) return 'إشارة قوية';
    return 'إشارة قوية جدًا';
  }

  Future<void> start() async {
    if (!connected) {
      _msg('اتصل بجهاز ESP32 أولًا');
      return;
    }
    final bool ok = await bt.startScan();
    if (!mounted) return;
    if (ok) {
      setState(() {
        scanning = true;
        status = 'يمسح';
        history.clear();
      });
      _msg('بدأ المسح');
    } else {
      _msg('تعذر بدء المسح');
    }
  }

  Future<void> stop() async {
    if (!connected) {
      _msg('الجهاز غير متصل');
      return;
    }
    final bool ok = await bt.stopScan();
    if (!mounted) return;
    if (ok) {
      setState(() {
        scanning = false;
        status = 'متوقف';
      });
      _msg('تم إيقاف المسح');
    } else {
      _msg('تعذر إيقاف المسح');
    }
  }

  Future<void> calibrate() async {
    if (!connected) {
      _msg('اتصل بجهاز ESP32 أولًا');
      return;
    }
    if (scanning) {
      _msg('أوقف المسح أولًا');
      return;
    }

    setState(() {
      calibrating = true;
      status = 'معايرة';
    });

    final bool ok = await bt.calibrate();
    if (!mounted) return;
    setState(() {
      calibrating = false;
      status = ok ? 'جاهز' : 'متصل';
    });
    _msg(ok ? 'تم إرسال أمر المعايرة' : 'تعذر إرسال المعايرة');
  }

  Future<void> changeSensitivity(double value) async {
    if (!connected || calibrating) return;
    final bool ok = await bt.setSensitivity(value);
    if (ok && mounted) setState(() => sensitivity = value);
  }

  Future<void> changeFilter(String value) async {
    if (!connected || calibrating) return;
    final bool ok = await bt.setFilter(value);
    if (ok && mounted) setState(() => filter = value);
  }

  Future<void> changeAudio(bool value) async {
    if (!connected) return;
    final bool ok = await bt.setAudio(value);
    if (ok && mounted) setState(() => audio = value);
  }

  Future<void> changeVibration(bool value) async {
    if (!connected) return;
    final bool ok = await bt.setVibration(value);
    if (!ok || !mounted) return;
    setState(() => vibration = value);
    if (value) HapticFeedback.mediumImpact();
  }

  Future<void> changeTarget(String value) async {
    if (!connected) {
      _msg('اتصل بجهاز ESP32 أولًا');
      return;
    }
    final bool ok = await bt.setTarget(value);
    if (ok && mounted) setState(() => target = value);
  }

  void save() {
    if (!connected) {
      _msg('الجهاز غير متصل');
      return;
    }
    if (lastData == null) {
      _msg('لا توجد قراءة مستلمة');
      return;
    }

    widget.onSaved?.call(<String, dynamic>{
      'time': DateTime.now().toIso8601String(),
      'signal': signal,
      'raw': raw,
      'stability': stability,
      'depth': depth,
      'target': target,
      'status': status,
      'sensitivity': sensitivity,
      'filter': filter,
    });
    HapticFeedback.mediumImpact();
    _msg('تم حفظ القراءة');
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  BoxDecoration _box() {
    return BoxDecoration(
      color: const Color(0xFF07111F),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: Colors.cyanAccent.withValues(alpha: 0.18),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020711),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          children: <Widget>[
            _header(),
            const SizedBox(height: 8),
            _gauge(),
            const SizedBox(height: 8),
            _topCards(),
            const SizedBox(height: 10),
            _signalBar(),
            const SizedBox(height: 10),
            _chart(),
            const SizedBox(height: 10),
            _targetAnalysis(),
            const SizedBox(height: 10),
            _statusRow(),
            const SizedBox(height: 10),
            _actions(),
            const SizedBox(height: 10),
            _controls(),
            const SizedBox(height: 10),
            _depthNote(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: <Widget>[
        IconButton(
          onPressed: () => _msg('الإعدادات من تبويب الإعدادات'),
          icon: const Icon(Icons.menu, size: 30),
        ),
        const Expanded(
          child: Column(
            children: <Widget>[
              Text(
                'GeoScan AI',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
              ),
              Text(
                'المسح المباشر',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        Column(
          children: <Widget>[
            Icon(
              Icons.bluetooth,
              color: connected ? Colors.cyanAccent : Colors.grey,
              size: 27,
            ),
            Text(
              connected ? 'متصل' : 'غير متصل',
              style: TextStyle(
                color: connected ? Colors.greenAccent : Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
        IconButton(
          onPressed: () => _msg('حالة الجهاز: $status'),
          icon: const Icon(Icons.more_vert),
        ),
      ],
    );
  }

  Widget _gauge() {
    return SizedBox(
      height: 275,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CustomPaint(
            size: const Size(double.infinity, 255),
            painter: _GaugePainter(signal),
          ),
          Positioned(
            top: 104,
            child: Column(
              children: <Widget>[
                const Text(
                  'LIVE SCAN',
                  style: TextStyle(fontSize: 20, letterSpacing: 1.2),
                ),
                Text(
                  '${signal.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w800,
                    color: signalColor,
                  ),
                ),
                Text(
                  signalText,
                  style: TextStyle(
                    color: signalColor,
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

  Widget _card(
    String title,
    String value,
    String sub,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 25, fontWeight: FontWeight.bold),
          ),
          Text(
            sub,
            style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _topCards() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          flex: 5,
          child: _card(
            'شدة الإشارة',
            '${signal.toStringAsFixed(1)}%',
            signalText,
            Icons.graphic_eq,
            signalColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 6,
          child: Column(
            children: <Widget>[
              _card(
                'العمق التقديري',
                depth > 0 ? '${depth.toStringAsFixed(2)} m' : '--',
                'بعد المعايرة',
                Icons.gps_fixed,
                Colors.greenAccent,
              ),
              const SizedBox(height: 10),
              _card(
                'استقرار الإشارة',
                '${stability.toStringAsFixed(0)}%',
                'من ESP32',
                Icons.multiline_chart,
                Colors.greenAccent,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _signalBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _box(),
      child: Column(
        children: <Widget>[
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('0'), Text('20'), Text('40'), Text('60'), Text('80'), Text('100'),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: signal / 100,
              minHeight: 15,
              backgroundColor: Color(0xFF17202D),
              color: signalColor,
            ),
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              Text('ضعيفة', style: TextStyle(color: Colors.redAccent)),
              Text('متوسطة', style: TextStyle(color: Colors.orangeAccent)),
              Text('قوية', style: TextStyle(color: Colors.greenAccent)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chart() {
    return Container(
      height: 225,
      padding: const EdgeInsets.all(12),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'حركة الإشارة',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Expanded(child: CustomPaint(painter: _ChartPainter(history))),
        ],
      ),
    );
  }

  Widget _targetAnalysis() {
    final Map<String, double> values = <String, double>{
      'ذهب': signal * 0.95,
      'نحاس': signal * 0.62,
      'فضة': signal * 0.36,
      'حديد': signal * 0.22,
      'ماء': stability * 0.55,
    };
    final Map<String, Color> colors = <String, Color>{
      'ذهب': Colors.greenAccent,
      'نحاس': Colors.orangeAccent,
      'فضة': Colors.lightBlueAccent,
      'حديد': Colors.redAccent,
      'ماء': Colors.cyanAccent,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _box(),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text(
                'تحليل الهدف',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: () => _msg('التحليل احتمالي وتجريبي ولا يثبت نوع المعدن'),
                icon: const Icon(Icons.help_outline),
              ),
            ],
          ),
          ...values.entries.map((MapEntry<String, double> entry) {
            final double value = entry.value.clamp(0.0, 100.0).toDouble();
            final Color color = colors[entry.key]!;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: <Widget>[
                  SizedBox(width: 52, child: Text(entry.key)),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: value / 100,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(8),
                      backgroundColor: const Color(0xFF17202D),
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 45,
                    child: Text(
                      '${value.toStringAsFixed(0)}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: color, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
          Text('الهدف المختار: $target', style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _small(String title, String value, Color color, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _box(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: const TextStyle(fontSize: 11, color: Colors.white60)),
              Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _small('حالة الجهاز', status, connected ? Colors.greenAccent : Colors.redAccent, Icons.multiline_chart),
          _small('الحساسية', '${sensitivity.toStringAsFixed(0)}%', Colors.greenAccent, Icons.tune),
          _small('الفلترة', filter, Colors.cyanAccent, Icons.filter_alt_outlined),
          _small('الصوت', audio ? 'يعمل' : 'متوقف', audio ? Colors.greenAccent : Colors.white54, Icons.volume_up),
          _small('الاهتزاز', vibration ? 'يعمل' : 'متوقف', vibration ? Colors.greenAccent : Colors.white54, Icons.vibration),
        ],
      ),
    );
  }

  Widget _actions() {
    return Row(
      children: <Widget>[
        Expanded(
          child: ElevatedButton.icon(
            onPressed: scanning ? null : start,
            icon: const Icon(Icons.play_arrow),
            label: const Text('بدء المسح'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF123D22),
              foregroundColor: Colors.greenAccent,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: scanning ? stop : null,
            icon: const Icon(Icons.stop),
            label: const Text('إيقاف المسح'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF42161B),
              foregroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: save,
            icon: const Icon(Icons.save),
            label: const Text('حفظ القراءة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF172536),
              foregroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _controls() {
    const List<String> filters = <String>['منخفضة', 'متوسطة', 'عالية'];
    const List<String> targets = <String>['غير محدد', 'ذهب', 'نحاس', 'فضة', 'حديد', 'ماء'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _box(),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text('الحساسية ${sensitivity.toStringAsFixed(0)}%')),
              Expanded(
                child: Slider(
                  value: sensitivity,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  onChanged: connected ? changeSensitivity : null,
                ),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              const Expanded(child: Text('الفلترة')),
              DropdownButton<String>(
                value: filter,
                items: filters.map((String e) => DropdownMenuItem<String>(value: e, child: Text(e))).toList(),
                onChanged: connected
                    ? (String? value) {
                        if (value != null) changeFilter(value);
                      }
                    : null,
              ),
            ],
          ),
          Row(
            children: <Widget>[
              const Expanded(child: Text('التنبيه الصوتي')),
              Switch(value: audio, onChanged: connected ? changeAudio : null),
            ],
          ),
          Row(
            children: <Widget>[
              const Expanded(child: Text('الاهتزاز')),
              Switch(value: vibration, onChanged: connected ? changeVibration : null),
            ],
          ),
          Row(
            children: <Widget>[
              const Expanded(child: Text('الهدف')),
              DropdownButton<String>(
                value: targets.contains(target) ? target : 'غير محدد',
                items: targets.map((String e) => DropdownMenuItem<String>(value: e, child: Text(e))).toList(),
                onChanged: connected
                    ? (String? value) {
                        if (value != null) changeTarget(value);
                      }
                    : null,
              ),
            ],
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: calibrating ? null : calibrate,
              icon: const Icon(Icons.tune),
              label: Text(calibrating ? 'جاري المعايرة...' : 'معايرة الجهاز'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _depthNote() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _box(),
      child: const Text(
        'العمق ونوع الهدف تقديريان في V1. يجب معايرة النظام واختباره بأهداف مدفونة بأعماق معروفة قبل الاعتماد على أي قراءة بالمتر.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white70, height: 1.5),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height * 0.82);
    final double radius = math.min(size.width * 0.43, size.height * 0.70);
    final Rect rect = Rect.fromCircle(center: center, radius: radius);
    const double startAngle = math.pi * 1.08;
    const double sweepAngle = math.pi * 0.84;

    final Paint base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..color = const Color(0xFF18212B);
    canvas.drawArc(rect, startAngle, sweepAngle, false, base);

    final Color color = value < 20
        ? Colors.redAccent
        : value < 40
            ? Colors.orangeAccent
            : value < 65
                ? Colors.amberAccent
                : Colors.greenAccent;

    final Paint active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..color = color;
    canvas.drawArc(rect, startAngle, sweepAngle * (value / 100), false, active);

    final double angle = startAngle + sweepAngle * (value / 100);
    final Offset end = Offset(
      center.dx + radius * 0.75 * math.cos(angle),
      center.dy + radius * 0.75 * math.sin(angle),
    );
    final Paint needle = Paint()
      ..color = color
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, end, needle);
    canvas.drawCircle(center, 7, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.value != value;
  }
}

class _ChartPainter extends CustomPainter {
  const _ChartPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint grid = Paint()
      ..color = const Color(0xFF1A2A38)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final double y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    if (values.length < 2) return;

    final Path path = Path();
    for (int i = 0; i < values.length; i++) {
      final double x = size.width * i / (values.length - 1);
      final double normalized = values[i].clamp(0.0, 100.0).toDouble();
      final double y = size.height * (1 - normalized / 100);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.greenAccent;
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}
