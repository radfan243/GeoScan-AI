import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/bluetooth_service.dart';

class ScanScreenV2 extends StatefulWidget {
  const ScanScreenV2({super.key, this.onSaved});
  final ValueChanged<Map<String, dynamic>>? onSaved;
  @override State<ScanScreenV2> createState() => _ScanScreenV2State();
}

class _ScanScreenV2State extends State<ScanScreenV2> {
  final BluetoothService bt = BluetoothService();
  StreamSubscription<String>? dataSub;
  StreamSubscription<bool>? connectionSub;
  final List<double> history = <double>[];
  double signal = 0, raw = 0, stability = 0, depth = 0, sensitivity = 75;
  bool connected = false, scanning = false, calibrating = false, audio = true, vibration = true;
  String filter = 'متوسطة', status = 'غير متصل', target = 'غير محدد';
  DateTime? lastData;

  @override void initState() {
    super.initState();
    connected = bt.isConnected;
    status = connected ? 'متصل' : 'غير متصل';
    dataSub = bt.dataStream.listen(_onData);
    connectionSub = bt.connectionStream.listen(_onConnection);
  }
  @override void dispose() { dataSub?.cancel(); connectionSub?.cancel(); super.dispose(); }

  void _onConnection(bool value) {
    if (!mounted) return;
    setState(() {
      connected = value; status = value ? 'متصل' : 'غير متصل';
      if (!value) { scanning = false; calibrating = false; signal = 0; raw = 0; stability = 0; depth = 0; history.clear(); lastData = null; }
    });
  }

  void _onData(String text) {
    if (!mounted || text.trim().isEmpty) return;
    Map<String, dynamic> d = <String, dynamic>{};
    try {
      final decoded = jsonDecode(text.trim());
      if (decoded is Map) d = Map<String, dynamic>.from(decoded);
    } catch (_) {
      final n = double.tryParse(text.trim().replaceAll(',', '.'));
      if (n != null) d['signal'] = n;
    }
    if (d.isEmpty) return;
    final s = _num(d, const ['signal', 'value', 'strength', 'reading'], signal).clamp(0.0, 100.0).toDouble();
    final r = _num(d, const ['raw', 'rawSignal'], raw);
    final st = _num(d, const ['stability', 'stable'], stability).clamp(0.0, 100.0).toDouble();
    final dp = _num(d, const ['depth', 'distance'], depth);
    final isScanning = d['scanning'] == true || '${d['status'] ?? ''}'.toLowerCase() == 'scanning' || d['status'] == 'يمسح' || d['status'] == 'مسح';
    setState(() {
      signal = (signal * 0.70 + s * 0.30).clamp(0.0, 100.0).toDouble();
      if (signal == 0) signal = s;
      raw = r; stability = st; depth = dp.isFinite && dp >= 0 ? dp : 0; scanning = isScanning;
      status = (d['status']?.toString().trim().isNotEmpty ?? false) ? d['status'].toString().trim() : (isScanning ? 'يمسح' : 'متصل');
      if (d['target']?.toString().trim().isNotEmpty ?? false) target = d['target'].toString().trim();
      lastData = DateTime.now();
      if (history.length >= 80) history.removeAt(0);
      history.add(signal);
    });
  }

  double _num(Map<String, dynamic> d, List<String> keys, double fallback) {
    for (final key in keys) {
      final value = d[key];
      if (value is num) return value.toDouble();
      final n = double.tryParse(value?.toString().replaceAll(',', '.').trim() ?? '');
      if (n != null && n.isFinite) return n;
    }
    return fallback;
  }
  bool get recent => lastData != null && DateTime.now().difference(lastData!).inSeconds < 3;
  Color get signalColor => signal < 20 ? Colors.redAccent : signal < 40 ? Colors.orangeAccent : signal < 65 ? Colors.amberAccent : Colors.greenAccent;
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
    if (!connected) return _msg('اتصل بجهاز ESP32 أولًا');
    if (await bt.startScan() && mounted) { setState(() { scanning = true; status = 'يمسح'; history.clear(); }); _msg('بدأ المسح'); }
  }
  Future<void> stop() async {
    if (!connected) return _msg('الجهاز غير متصل');
    if (await bt.stopScan() && mounted) { setState(() { scanning = false; status = 'متوقف'; }); _msg('تم إيقاف المسح'); }
  }
  Future<void> calibrate() async {
    if (!connected) return _msg('اتصل بجهاز ESP32 أولًا');
    if (scanning) return _msg('أوقف المسح أولًا');
    setState(() { calibrating = true; status = 'معايرة'; });
    final ok = await bt.calibrate();
    if (mounted) { setState(() { calibrating = false; status = ok ? 'جاهز' : 'متصل'; }); _msg(ok ? 'تم إرسال أمر المعايرة' : 'تعذر إرسال المعايرة'); }
  }
  Future<void> changeSensitivity(double value) async { if (!connected || calibrating) return; if (await bt.setSensitivity(value) && mounted) setState(() => sensitivity = value); }
  Future<void> changeFilter(String value) async { if (!connected || calibrating) return; if (await bt.setFilter(value) && mounted) setState(() => filter = value); }
  Future<void> changeAudio(bool value) async { if (connected && await bt.setAudio(value) && mounted) setState(() => audio = value); }
  Future<void> changeVibration(bool value) async { if (connected && await bt.setVibration(value) && mounted) { setState(() => vibration = value); if (value) HapticFeedback.mediumImpact(); } }
  Future<void> changeTarget(String value) async { if (!connected) return _msg('اتصل بجهاز ESP32 أولًا'); if (await bt.setTarget(value) && mounted) setState(() => target = value); }

  void save() {
    if (!connected) return _msg('الجهاز غير متصل');
    if (lastData == null) return _msg('لا توجد قراءة مستلمة');
    widget.onSaved?.call({'time': DateTime.now().toIso8601String(), 'signal': signal, 'raw': raw, 'stability': stability, 'depth': depth, 'target': target, 'status': status, 'sensitivity': sensitivity, 'filter': filter});
    HapticFeedback.mediumImpact(); _msg('تم حفظ القراءة');
  }
  void _msg(String text) { if (!mounted) return; ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating)); }
  BoxDecoration _box() => BoxDecoration(color: const Color(0xFF07111F), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.18)));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF020711),
    body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 20), children: [
      _header(), const SizedBox(height: 8), _gauge(), const SizedBox(height: 8), _topCards(), const SizedBox(height: 10), _signalBar(), const SizedBox(height: 10), _chart(), const SizedBox(height: 10), _targetAnalysis(), const SizedBox(height: 10), _statusRow(), const SizedBox(height: 10), _actions(), const SizedBox(height: 10), _controls(), const SizedBox(height: 10), _depthNote(),
    ])),
  );

  Widget _header() => Row(children: [
    IconButton(onPressed: () => _msg('الإعدادات من تبويب الإعدادات'), icon: const Icon(Icons.menu, size: 30)),
    const Expanded(child: Column(children: [Text('GeoScan AI', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)), Text('المسح المباشر', style: TextStyle(color: Colors.white70))])),
    Column(children: [Icon(Icons.bluetooth, color: connected ? Colors.cyanAccent : Colors.grey, size: 27), Text(connected ? 'متصل' : 'غير متصل', style: TextStyle(color: connected ? Colors.greenAccent : Colors.white54, fontSize: 12))]),
    IconButton(onPressed: () => _msg('حالة الجهاز: $status'), icon: const Icon(Icons.more_vert)),
  ]);

  Widget _gauge() => SizedBox(height: 275, child: Stack(alignment: Alignment.center, children: [CustomPaint(size: const Size(double.infinity, 255), painter: _GaugePainter(signal)), Positioned(top: 104, child: Column(children: [const Text('LIVE SCAN', style: TextStyle(fontSize: 20, letterSpacing: 1.2)), Text('${signal.toStringAsFixed(1)}%', style: TextStyle(fontSize: 56, fontWeight: FontWeight.w800, color: signalColor)), Text(signalText, style: TextStyle(color: signalColor, fontWeight: FontWeight.bold))]))]));

  Widget _card(String title, String value, String sub, IconData icon, Color color) => Container(padding: const EdgeInsets.all(12), decoration: _box(), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: Colors.white, size: 24), const SizedBox(height: 4), Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)), Text(value, style: TextStyle(color: color, fontSize: 25, fontWeight: FontWeight.bold)), Text(sub, style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 11))]));
  Widget _topCards() => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 5, child: _card('شدة الإشارة', '${signal.toStringAsFixed(1)}%', signalText, Icons.graphic_eq, signalColor)), const SizedBox(width: 10), Expanded(flex: 6, child: Column(children: [_card('العمق التقديري', depth > 0 ? '${depth.toStringAsFixed(2)} m' : '--', 'بعد المعايرة', Icons.gps_fixed, Colors.greenAccent), const SizedBox(height: 10), _card('استقرار الإشارة', '${stability.toStringAsFixed(0)}%', 'من ESP32', Icons.multiline_chart, Colors.greenAccent)]))]);
  Widget _signalBar() => Container(padding: const EdgeInsets.all(12), decoration: _box(), child: Column(children: [const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('0'), Text('20'), Text('40'), Text('60'), Text('80'), Text('100')]), const SizedBox(height: 8), ClipRRect(borderRadius: BorderRadius.circular(12), child: LinearProgressIndicator(value: signal / 100, minHeight: 15, backgroundColor: const Color(0xFF17202D), color: signalColor)), const SizedBox(height: 6), const Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [Text('ضعيفة', style: TextStyle(color: Colors.redAccent)), Text('متوسطة', style: TextStyle(color: Colors.orangeAccent)), Text('قوية', style: TextStyle(color: Colors.greenAccent))])])));
  Widget _chart() => Container(height: 225, padding: const EdgeInsets.all(12), decoration: _box(), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Text('حركة الإشارة', textAlign: TextAlign.right, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Expanded(child: CustomPaint(painter: _ChartPainter(history)))]));

  Widget _targetAnalysis() {
    final values = <String, double>{'ذهب': signal * .95, 'نحاس': signal * .62, 'فضة': signal * .36, 'حديد': signal * .22, 'ماء': stability * .55};
    final colors = <String, Color>{'ذهب': Colors.greenAccent, 'نحاس': Colors.orangeAccent, 'فضة': Colors.lightBlueAccent, 'حديد': Colors.redAccent, 'ماء': Colors.cyanAccent};
    return Container(padding: const EdgeInsets.all(12), decoration: _box(), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('تحليل الهدف', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), IconButton(onPressed: () => _msg('التحليل احتمالي وتجريبي ولا يثبت نوع المعدن'), icon: const Icon(Icons.help_outline))]), ...values.entries.map((entry) { final value = entry.value.clamp(0.0, 100.0).toDouble(); final color = colors[entry.key]!; return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [SizedBox(width: 52, child: Text(entry.key)), Expanded(child: LinearProgressIndicator(value: value / 100, minHeight: 8, borderRadius: BorderRadius.circular(8), backgroundColor: const Color(0xFF17202D), color: color)), const SizedBox(width: 8), SizedBox(width: 45, child: Text('${value.toStringAsFixed(0)}%', textAlign: TextAlign.right, style: TextStyle(color: color, fontWeight: FontWeight.bold)))])); }), const SizedBox(height: 4), Text('الهدف المختار: $target', style: const TextStyle(color: Colors.white70))]));
  }

  Widget _small(String title, String value, Color color, IconData icon) => Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: _box(), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: color, size: 20), const SizedBox(width: 6), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 11, color: Colors.white60)), Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold))])]));
  Widget _statusRow() => SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [_small('حالة الجهاز', status, connected ? Colors.greenAccent : Colors.redAccent, Icons.multiline_chart), _small('الحساسية', '${sensitivity.toStringAsFixed(0)}%', Colors.greenAccent, Icons.tune), _small('الفلترة', filter, Colors.cyanAccent, Icons.filter_alt_outlined), _small('الصوت', audio ? 'يعمل' : 'متوقف', audio ? Colors.greenAccent : Colors.white54, Icons.volume_up), _small('الاهتزاز', vibration ? 'يعمل' : 'متوقف', vibration ? Colors.greenAccent : Colors.white54, Icons.vibration)]));
  Widget _actions() => Row(children: [Expanded(child: ElevatedButton.icon(onPressed: scanning ? null : start, icon: const Icon(Icons.play_arrow), label: const Text('بدء المسح'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF123D22), foregroundColor: Colors.greenAccent, padding: const EdgeInsets.symmetric(vertical: 16)))), const SizedBox(width: 8), Expanded(child: ElevatedButton.icon(onPressed: scanning ? stop : null, icon: const Icon(Icons.stop), label: const Text('إيقاف المسح'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF42161B), foregroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 16)))), const SizedBox(width: 8), Expanded(child: ElevatedButton.icon(onPressed: save, icon: const Icon(Icons.save), label: const Text('حفظ القراءة'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF172536), foregroundColor: Colors.white70, padding: const EdgeInsets.symmetric(vertical: 16))))]);
  Widget _controls() => Container(padding: const EdgeInsets.all(12), decoration: _box(), child: Column(children: [Row(children: [Expanded(child: Text('الحساسية ${sensitivity.toStringAsFixed(0)}%')), Expanded(child: Slider(value: sensitivity, min: 0, max: 100, divisions: 100, onChanged: connected ? changeSensitivity : null))]), Row(children: [const Expanded(child: Text('الفلترة')), DropdownButton<String>(value: filter, items: const ['منخفضة', 'متوسطة', 'عالية'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: connected ? (v) { if (v != null) changeFilter(v); } : null)]), Row(children: [const Expanded(child: Text('التنبيه الصوتي')), Switch(value: audio, onChanged: connected ? changeAudio : null)]), Row(children: [const Expanded(child: Text('الاهتزاز')), Switch(value: vibration, onChanged: connected ? changeVibration : null)]), Row(children: [const Expanded(child: Text('الهدف')), DropdownButton<String>(value: ['غير محدد', 'ذهب', 'نحاس', 'فضة', 'حديد', 'ماء'].contains(target) ? target : 'غير محدد', items: const ['غير محدد', 'ذهب', 'نحاس', 'فضة', 'حديد', 'ماء'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: connected ? (v) { if (v != null) changeTarget(v); } : null)]), SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: calibrating ? null : calibrate, icon: const Icon(Icons.tune), label: Text(calibrating ? 'جاري المعايرة...' : 'معايرة الجهاز'))]));
  Widget _depthNote() => Container(padding: const EdgeInsets.all(12), decoration: _box(), child: const Text('العمق ونوع الهدف تقديريان في V1. يجب معايرة النظام واختباره بأهداف مدفونة بأعماق معروفة قبل الاعتماد على أي قراءة بالمتر.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, height: 1.5)));
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.value); final double value;
  @override void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .82); final radius = math.min(size.width * .43, size.height * .70); final rect = Rect.fromCircle(center: center, radius: radius);
    final base = Paint()..style = PaintingStyle.stroke..strokeWidth = 22..color = const Color(0xFF18212B);
    canvas.drawArc(rect, math.pi * 1.08, math.pi * .84, false, base);
    final color = value < 20 ? Colors.redAccent : value < 40 ? Colors.orangeAccent : value < 65 ? Colors.amberAccent : Colors.greenAccent;
    final active = Paint()..style = PaintingStyle.stroke..strokeWidth = 22..color = color;
    canvas.drawArc(rect, math.pi * 1.08, math.pi * .84 * (value / 100), false, active);
    final angle = math.pi * 1.08 + math.pi * .84 * (value / 100); final end = Offset(center.dx + radius * .75 * math.cos(angle), center.dy + radius * .75 * math.sin(angle));
    canvas.drawLine(center, end, Paint()..color = color..strokeWidth = 5..strokeCap = StrokeCap.round); canvas.drawCircle(center, 7, Paint()..color = Colors.white);
  }
  @override bool shouldRepaint(covariant _GaugePainter oldDelegate) => oldDelegate.value != value;
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.values); final List<double> values;
  @override void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0xFF1A2A38)..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) { final y = size.height * i / 4; canvas.drawLine(Offset(0, y), Offset(size.width, y), grid); }
    if (values.length < 2) return;
    final path = Path();
    for (int i = 0; i < values.length; i++) { final x = size.width * i / (values.length - 1); final y = size.height * (1 - values[i].clamp(0, 100) / 100); if (i == 0) path.moveTo(x, y); else path.lineTo(x, y); }
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = Colors.greenAccent);
  }
  @override bool shouldRepaint(covariant _ChartPainter oldDelegate) => oldDelegate.values != values;
}
