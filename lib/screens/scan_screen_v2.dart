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

class _ScanScreenV2State extends State<ScanScreenV2> with SingleTickerProviderStateMixin {
  final BluetoothService bt = BluetoothService();
  StreamSubscription<String>? dataSub;
  StreamSubscription<bool>? connectionSub;
  late final AnimationController pulse;
  final List<double> history = <double>[];
  double signal = 0, raw = 0, stability = 0, depth = 0, sensitivity = 75;
  double baseline = 0;
  bool connected = false, scanning = false, calibrating = false, audio = true, vibration = true;
  String filter = 'متوسطة', status = 'غير متصل', target = 'غير محدد';
  DateTime? lastData;

  @override
  void initState() {
    super.initState();
    pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    connected = bt.isConnected;
    status = connected ? 'متصل' : 'غير متصل';
    dataSub = bt.dataStream.listen(_onData);
    connectionSub = bt.connectionStream.listen(_onConnection);
  }

  @override
  void dispose() {
    dataSub?.cancel();
    connectionSub?.cancel();
    pulse.dispose();
    super.dispose();
  }

  void _onConnection(bool value) {
    if (!mounted) return;
    setState(() {
      connected = value;
      status = value ? 'متصل' : 'غير متصل';
      if (!value) {
        scanning = false; calibrating = false; signal = 0; raw = 0; stability = 0; depth = 0; history.clear(); lastData = null;
      }
    });
  }

  void _onData(String text) {
    if (!mounted || text.trim().isEmpty) return;
    Map<String, dynamic> d = <String, dynamic>{};
    try {
      final x = jsonDecode(text.trim());
      if (x is Map) d = Map<String, dynamic>.from(x);
    } catch (_) {
      final n = double.tryParse(text.trim().replaceAll(',', '.'));
      if (n != null) d['signal'] = n;
    }
    if (d.isEmpty) return;
    final s = _num(d, ['signal', 'value', 'strength', 'reading'], signal).clamp(0.0, 100.0).toDouble();
    final r = _num(d, ['raw', 'rawSignal'], raw);
    final b = _num(d, ['baseline', 'base'], baseline);
    final st = _num(d, ['stability', 'stable'], stability).clamp(0.0, 100.0).toDouble();
    final dp = _num(d, ['depth', 'distance'], depth);
    final scan = d['scanning'] == true || '${d['status'] ?? ''}'.toLowerCase() == 'scanning' || d['status'] == 'يمسح' || d['status'] == 'مسح';
    setState(() {
      signal = (signal == 0 ? s : signal * .70 + s * .30).clamp(0.0, 100.0).toDouble();
      raw = r; baseline = b; stability = st; depth = dp >= 0 && dp.isFinite ? dp : 0; scanning = scan;
      status = (d['status']?.toString().trim().isNotEmpty ?? false) ? d['status'].toString().trim() : (scan ? 'يمسح' : 'متصل');
      if ((d['target']?.toString().trim() ?? '').isNotEmpty) target = d['target'].toString().trim();
      lastData = DateTime.now();
      if (history.length >= 80) history.removeAt(0);
      history.add(signal);
    });
  }

  double _num(Map<String, dynamic> d, List<String> keys, double fallback) {
    for (final k in keys) {
      final v = d[k];
      if (v is num) return v.toDouble();
      final n = double.tryParse(v?.toString().replaceAll(',', '.').trim() ?? '');
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
    if (calibrating) return _msg('انتظر انتهاء المعايرة');
    if (await bt.startScan() && mounted) { setState(() { scanning = true; status = 'يمسح'; history.clear(); lastData = null; }); _msg('بدأ المسح الحقيقي'); }
  }
  Future<void> stop() async { if (!connected) return _msg('الجهاز غير متصل'); if (await bt.stopScan() && mounted) { setState(() { scanning = false; status = 'متوقف'; }); _msg('تم إيقاف المسح'); } }
  Future<void> calibrate() async {
    if (!connected) return _msg('اتصل بجهاز ESP32 أولًا');
    if (scanning) return _msg('أوقف المسح أولًا');
    setState(() { calibrating = true; status = 'معايرة'; });
    final ok = await bt.calibrate();
    if (mounted) { setState(() { calibrating = false; status = ok ? 'جاهز' : 'متصل'; }); _msg(ok ? 'تم إرسال أمر المعايرة' : 'تعذر إرسال المعايرة'); }
  }
  Future<void> setSens(double v) async { if (!connected || calibrating) return; if (await bt.setSensitivity(v) && mounted) setState(() => sensitivity = v); }
  Future<void> setFilt(String v) async { if (!connected || calibrating) return; if (await bt.setFilter(v) && mounted) setState(() => filter = v); }
  Future<void> setAudio(bool v) async { if (connected && await bt.setAudio(v) && mounted) setState(() => audio = v); }
  Future<void> setVibration(bool v) async { if (connected && await bt.setVibration(v) && mounted) { setState(() => vibration = v); if (v) HapticFeedback.mediumImpact(); } }
  Future<void> setTarget(String v) async { if (!connected) return _msg('اتصل بجهاز ESP32 أولًا'); if (await bt.setTarget(v) && mounted) setState(() => target = v); }
  void save() {
    if (!connected) return _msg('الجهاز غير متصل');
    if (lastData == null) return _msg('لا توجد قراءة مستلمة');
    widget.onSaved?.call({'time': DateTime.now().toIso8601String(), 'signal': signal, 'raw': raw, 'baseline': baseline, 'stability': stability, 'depth': depth, 'target': target, 'status': status, 'sensitivity': sensitivity, 'filter': filter});
    HapticFeedback.mediumImpact(); _msg('تم حفظ القراءة');
  }
  void _msg(String x) { if (!mounted) return; ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(x), behavior: SnackBarBehavior.floating)); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF020711),
    body: SafeArea(child: CustomScrollView(slivers: [
      SliverToBoxAdapter(child: _header()),
      SliverToBoxAdapter(child: _gauge()),
      SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 18), sliver: SliverList(delegate: SliverChildListDelegate([
        _topCards(), const SizedBox(height: 10), _signalBar(), const SizedBox(height: 10), _chart(), const SizedBox(height: 10), _targetAnalysis(), const SizedBox(height: 10), _statusRow(), const SizedBox(height: 10), _actions(), const SizedBox(height: 10), _controls(), const SizedBox(height: 10), _depthNote(),
      ]))),
    ])),
  );

  Widget _header() => Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 2), child: Row(children: [
    IconButton(onPressed: () => _msg('استخدم تبويب الإعدادات للتحكم بالجهاز'), icon: const Icon(Icons.menu, size: 30)),
    const Expanded(child: Column(children: [Text('GeoScan AI', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)), Text('المسح المباشر', style: TextStyle(color: Colors.white70))])),
    Column(children: [Icon(Icons.bluetooth, color: connected ? Colors.cyanAccent : Colors.grey, size: 27), Text(connected ? 'متصل' : 'غير متصل', style: TextStyle(color: connected ? Colors.greenAccent : Colors.white54, fontSize: 12))]),
    IconButton(onPressed: () => _msg('التحكم الكامل من الإعدادات'), icon: const Icon(Icons.more_vert)),
  ]));

  Widget _gauge() => SizedBox(height: 270, child: AnimatedBuilder(animation: pulse, builder: (_, __) => Stack(alignment: Alignment.center, children: [
    CustomPaint(size: const Size(double.infinity, 255), painter: _GaugePainter(signal, pulse.value)),
    Positioned(top: 102, child: Column(children: [const Text('LIVE SCAN', style: TextStyle(fontSize: 20, letterSpacing: 1.2)), Text('${signal.toStringAsFixed(1)}%', style: TextStyle(fontSize: 56, fontWeight: FontWeight.w800, color: signalColor)), Text(signalText, style: TextStyle(color: signalColor, fontWeight: FontWeight.bold))])),
  ]));

  Widget _card({required String title, required String value, required String sub, required IconData icon, required Color color}) => Container(padding: const EdgeInsets.all(12), decoration: _dec(), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: Colors.white, size: 25), const SizedBox(height: 5), Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)), const SizedBox(height: 3), FittedBox(alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(color: color, fontSize: 25, fontWeight: FontWeight.bold))), Text(sub, style: TextStyle(color: color.withOpacity(.85), fontSize: 11))]));

  Widget _topCards() => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 5, child: _card(title: 'شدة الإشارة', value: '${signal.toStringAsFixed(1)}%', sub: signalText, icon: Icons.graphic_eq, color: signalColor)), const SizedBox(width: 10), Expanded(flex: 6, child: Column(children: [_card(title: 'العمق التقديري', value: depth > 0 ? '${depth.toStringAsFixed(2)} m' : '--', sub: 'بعد المعايرة', icon: Icons.gps_fixed, color: Colors.greenAccent), const SizedBox(height: 10), _card(title: 'استقرار الإشارة', value: '${stability.toStringAsFixed(0)}%', sub: 'من ESP32', icon: Icons.multiline_chart, color: Colors.greenAccent)]))]);

  Widget _signalBar() => Container(padding: const EdgeInsets.all(12), decoration: _dec(), child: Column(children: [const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('0'), Text('20'), Text('40'), Text('60'), Text('80'), Text('100')]), const SizedBox(height: 8), ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(height: 15, child: CustomPaint(painter: _BarPainter(signal / 100)))), const SizedBox(height: 6), const Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [Text('ضعيفة', style: TextStyle(color: Colors.redAccent)), Text('متوسطة', style: TextStyle(color: Colors.orangeAccent)), Text('قوية', style: TextStyle(color: Colors.greenAccent))])])));

  Widget _chart() => Container(height: 225, padding: const EdgeInsets.all(12), decoration: _dec(), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Text('حركة الإشارة', textAlign: TextAlign.right, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Expanded(child: CustomPaint(painter: _ChartPainter(history)))]));

  Widget _targetAnalysis() {
    final vals = {'ذهب': signal * .95, 'نحاس': signal * .62, 'فضة': signal * .36, 'حديد': signal * .22, 'ماء': stability * .55};
    final colors = {'ذهب': Colors.greenAccent, 'نحاس': Colors.orangeAccent, 'فضة': Colors.lightBlueAccent, 'حديد': Colors.redAccent, 'ماء': Colors.cyanAccent};
    return Container(padding: const EdgeInsets.all(12), decoration: _dec(), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('تحليل الهدف', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), IconButton(onPressed: () => _msg('تحليل احتمالي تجريبي ولا يثبت نوع المعدن'), icon: const Icon(Icons.help_outline))]), ...vals.entries.map((e) { final v = e.value.clamp(0.0, 100.0).toDouble(); final c = colors[e.key]!; return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [SizedBox(width: 52, child: Text(e.key)), Expanded(child: LinearProgressIndicator(value: v / 100, minHeight: 8, borderRadius: BorderRadius.circular(8), backgroundColor: const Color(0xFF17202D), color: c)), const SizedBox(width: 8), SizedBox(width: 45, child: Text('${v.toStringAsFixed(0)}%', textAlign: TextAlign.right, style: TextStyle(color: c, fontWeight: FontWeight.bold)))]); }), const SizedBox(height: 4), Text('الهدف المختار: $target', style: const TextStyle(color: Colors.white70))]));
  }

  Widget _statusRow() => SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
    _small('حالة الجهاز', status, connected ? Colors.greenAccent : Colors.redAccent, Icons.multiline_chart),
    _small('الحساسية', '${sensitivity.toStringAsFixed(0)}%', Colors.greenAccent, Icons.tune),
    _small('الفلترة', filter, Colors.cyanAccent, Icons.filter_alt_outlined),
    _small('الصوت', audio ? 'يعمل' : 'متوقف', audio ? Colors.greenAccent : Colors.white54, Icons.volume_up),
    _small('الاهتزاز', vibration ? 'يعمل' : 'متوقف', vibration ? Colors.greenAccent : Colors.white54, Icons.vibration),
  ]));
  Widget _small(String a, String b, Color c, IconData i) => Container(width: 112, height: 98, margin: const EdgeInsets.only(right: 7), padding: const EdgeInsets.all(8), decoration: _dec(), child: Column(children: [Icon(i, color: c, size: 23), const SizedBox(height: 4), Text(a, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.white70)), const SizedBox(height: 4), FittedBox(child: Text(b, style: TextStyle(color: c, fontWeight: FontWeight.bold)))]));

  Widget _actions() => Row(children: [Expanded(child: _button(Icons.play_arrow, 'بدء المسح', Colors.greenAccent, scanning ? null : start)), const SizedBox(width: 8), Expanded(child: _button(Icons.stop, 'إيقاف المسح', Colors.redAccent, scanning ? stop : null)), const SizedBox(width: 8), Expanded(child: _button(Icons.save, 'حفظ القراءة', Colors.white70, save))]);
  Widget _button(IconData i, String t, Color c, VoidCallback? f) => SizedBox(height: 56, child: OutlinedButton.icon(onPressed: f, icon: Icon(i, color: c), label: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold))));

  Widget _controls() => Container(padding: const EdgeInsets.all(12), decoration: _dec(), child: Column(children: [Row(children: [const Expanded(child: Text('المعايرة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))), FilledButton.icon(onPressed: calibrating ? null : calibrate, icon: const Icon(Icons.my_location), label: const Text('معايرة'))]), Row(children: [const Text('الحساسية'), Expanded(child: Slider(value: sensitivity, min: 0, max: 100, divisions: 100, onChanged: connected && !calibrating ? setSens : null)), Text('${sensitivity.toStringAsFixed(0)}%')]), Row(children: [const Text('الفلترة'), const SizedBox(width: 10), Expanded(child: DropdownButton<String>(isExpanded: true, value: filter, items: const ['منخفضة', 'متوسطة', 'عالية'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: connected && !calibrating ? (v) { if (v != null) setFilt(v); } : null))]), const Divider(), Wrap(spacing: 7, children: ['ذهب', 'نحاس', 'فضة', 'حديد', 'ماء'].map((e) => ChoiceChip(label: Text(e), selected: target == e, onSelected: (_) => setTarget(e))).toList()), SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('التنبيه الصوتي'), value: audio, onChanged: connected ? setAudio : null), SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('الاهتزاز'), value: vibration, onChanged: connected ? setVibration : null)]));

  Widget _depthNote() => Container(padding: const EdgeInsets.all(13), decoration: _dec(), child: const Text('العمق تقديري ويحتاج معايرة واختبارات حقيقية على أهداف مدفونة. لا يعتبر قياسًا مضمونًا، خصوصًا للأهداف الصغيرة أو الأعماق الكبيرة.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, height: 1.5)));
  BoxDecoration _dec() => BoxDecoration(color: const Color(0xFF07111F), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.cyanAccent.withOpacity(.18)));
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter(this.signal, this.pulse);
  final double signal, pulse;
  @override void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, 205); final r = math.min(size.width * .43, 180.0); final rect = Rect.fromCircle(center: center, radius: r);
    canvas.drawArc(rect, math.pi * 1.10, math.pi * .80, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 19..color = const Color(0xFF17212B));
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 19..shader = const SweepGradient(colors: [Colors.red, Colors.orange, Colors.yellow, Colors.green]).createShader(rect);
    canvas.drawArc(rect, math.pi * 1.10, math.pi * .80 * signal.clamp(0.0, 100.0) / 100, false, p);
    final a = math.pi * 1.10 + math.pi * .80 * signal.clamp(0.0, 100.0) / 100; final tip = Offset(center.dx + math.cos(a) * (r - 10), center.dy + math.sin(a) * (r - 10));
    canvas.drawLine(center, tip, Paint()..color = Colors.greenAccent.withOpacity(.75 + pulse * .25)..strokeWidth = 5..strokeCap = StrokeCap.round); canvas.drawCircle(center, 7, Paint()..color = Colors.white);
  }
  @override bool shouldRepaint(covariant _GaugePainter old) => old.signal != signal || old.pulse != pulse;
}
class _BarPainter extends CustomPainter {
  const _BarPainter(this.value); final double value;
  @override void paint(Canvas canvas, Size size) { final rect = Offset.zero & size; canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)), Paint()..shader = const LinearGradient(colors: [Colors.red, Colors.orange, Colors.yellow, Colors.green]).createShader(rect)); canvas.drawCircle(Offset(size.width * value.clamp(0.0, 1.0), size.height / 2), 7, Paint()..color = Colors.white); }
  @override bool shouldRepaint(covariant _BarPainter old) => old.value != value;
}
class _ChartPainter extends CustomPainter {
  const _ChartPainter(this.values); final List<double> values;
  @override void paint(Canvas canvas, Size size) { final grid = Paint()..color = Colors.white.withOpacity(.07); for (int i = 0; i <= 4; i++) canvas.drawLine(Offset(0, size.height * i / 4), Offset(size.width, size.height * i / 4), grid); for (int i = 0; i <= 6; i++) canvas.drawLine(Offset(size.width * i / 6, 0), Offset(size.width * i / 6, size.height), grid); if (values.isEmpty) return; final path = Path(); for (int i = 0; i < values.length; i++) { final x = values.length == 1 ? 0.0 : size.width * i / (values.length - 1); final y = size.height * (1 - values[i].clamp(0.0, 100.0) / 100); if (i == 0) path.moveTo(x, y); else path.lineTo(x, y); } canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..strokeCap = StrokeCap.round..color = Colors.greenAccent); }
  @override bool shouldRepaint(covariant _ChartPainter old) => old.values.length != values.length || old.values != values;
}
