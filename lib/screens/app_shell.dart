import 'package:flutter/material.dart';
import 'bluetooth_screen.dart';
import 'scan_screen_v2.dart';
import '../services/bluetooth_service.dart';

class GeoScanShell extends StatefulWidget {
  const GeoScanShell({super.key});
  @override State<GeoScanShell> createState() => _GeoScanShellState();
}

class _GeoScanShellState extends State<GeoScanShell> {
  int index = 2;
  final List<Map<String, dynamic>> readings = <Map<String, dynamic>>[];
  final BluetoothService bluetooth = BluetoothService();

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _HomeTab(onScan: () => setState(() => index = 2), onBluetooth: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BluetoothScreen()))),
      _LogsTab(readings: readings),
      ScanScreenV2(onSaved: (r) => setState(() => readings.insert(0, r))),
      _AnalysisTab(readings: readings),
      _SettingsTab(bluetooth: bluetooth),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF020711),
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: _BottomNav(index: index, onChanged: (v) => setState(() => index = v)),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    const labels = ['الرئيسية', 'السجلات', 'المسح', 'التحليل', 'الإعدادات'];
    const icons = [Icons.home_rounded, Icons.folder_rounded, Icons.radar, Icons.bar_chart_rounded, Icons.settings_rounded];
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 6, 7, 8),
      decoration: const BoxDecoration(color: Color(0xFF06101D), border: Border(top: BorderSide(color: Color(0xFF183040)))),
      child: Row(children: List<Widget>.generate(5, (i) {
        final selected = index == i;
        return Expanded(child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onChanged(i),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(duration: const Duration(milliseconds: 180), padding: EdgeInsets.all(selected && i == 2 ? 9 : 6), decoration: BoxDecoration(color: selected ? const Color(0xFF071E2A) : Colors.transparent, shape: BoxShape.circle, border: selected ? Border.all(color: Colors.cyanAccent.withValues(alpha: .75)) : null), child: Icon(icons[i], color: selected ? Colors.cyanAccent : Colors.white54, size: selected && i == 2 ? 30 : 25)),
            const SizedBox(height: 2),
            Text(labels[i], style: TextStyle(color: selected ? Colors.cyanAccent : Colors.white60, fontSize: 11, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
          ]),
        ));
      })),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.onScan, required this.onBluetooth});
  final VoidCallback onScan;
  final VoidCallback onBluetooth;
  @override
  Widget build(BuildContext context) => SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
    const SizedBox(height: 10),
    const Text('GeoScan AI', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
    const SizedBox(height: 5),
    const Text('نظام تحليل الإشارات الأرضية', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 16)),
    const SizedBox(height: 24),
    Container(height: 190, decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: const LinearGradient(colors: [Color(0xFF0A2836), Color(0xFF07111F)]), border: Border.all(color: Colors.cyanAccent.withValues(alpha: .18))), child: const Center(child: Icon(Icons.radar, size: 110, color: Colors.cyanAccent))),
    const SizedBox(height: 20),
    SizedBox(height: 58, child: FilledButton.icon(onPressed: onScan, icon: const Icon(Icons.radar), label: const Text('فتح المسح المباشر', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
    const SizedBox(height: 12),
    SizedBox(height: 58, child: OutlinedButton.icon(onPressed: onBluetooth, icon: const Icon(Icons.bluetooth), label: const Text('الاتصال بجهاز ESP32', style: TextStyle(fontSize: 16)))),
    const SizedBox(height: 18),
    const _InfoBox('البيانات تأتي من جهاز GeoScan-AI الخارجي عبر Bluetooth. تحليل نوع المعدن والعمق تقديري ويحتاج معايرة واختبارًا ميدانيًا.'),
  ]));
}

class _LogsTab extends StatelessWidget {
  const _LogsTab({required this.readings});
  final List<Map<String, dynamic>> readings;
  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) return const SafeArea(child: Center(child: _InfoBox('لا توجد قراءات محفوظة بعد. اضغط «حفظ القراءة» أثناء المسح.')));
    return SafeArea(child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: readings.length, itemBuilder: (_, i) {
      final r = readings[i];
      final s = _num(r['signal']);
      final st = _num(r['stability']);
      final d = _num(r['depth']);
      return Card(color: const Color(0xFF07111F), child: ListTile(leading: const Icon(Icons.radar, color: Colors.cyanAccent), title: Text('إشارة ${s.toStringAsFixed(1)}%'), subtitle: Text('استقرار ${st.toStringAsFixed(0)}% • عمق ${d.toStringAsFixed(2)} m • ${r['target'] ?? 'غير محدد'}')));
    }));
  }
}

class _AnalysisTab extends StatelessWidget {
  const _AnalysisTab({required this.readings});
  final List<Map<String, dynamic>> readings;
  @override
  Widget build(BuildContext context) {
    final avg = readings.isEmpty ? 0.0 : readings.map((e) => _num(e['signal'])).reduce((a, b) => a + b) / readings.length;
    return SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('التحليل', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 18),
      _metric('عدد القراءات', '${readings.length}', Colors.cyanAccent),
      _metric('متوسط الإشارة', '${avg.toStringAsFixed(1)}%', Colors.greenAccent),
      const SizedBox(height: 10),
      const _InfoBox('تحليل نوع المعدن في V1 احتمالي وتجريبي، وليس تعريفًا مؤكدًا للذهب أو الفضة. الدقة تتحسن فقط بعد المعايرة والاختبارات الحقيقية.'),
    ]));
  }
  Widget _metric(String a, String b, Color c) => Card(color: const Color(0xFF07111F), child: ListTile(title: Text(a), trailing: Text(b, style: TextStyle(color: c, fontSize: 20, fontWeight: FontWeight.bold))));
}

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({required this.bluetooth});
  final BluetoothService bluetooth;
  @override State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  bool audio = true, vibration = true;
  double sensitivity = 75;
  String filter = 'متوسطة';
  @override
  Widget build(BuildContext context) {
    final connected = widget.bluetooth.isConnected;
    return SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('الإعدادات', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Card(color: const Color(0xFF07111F), child: Column(children: [
        ListTile(leading: Icon(Icons.bluetooth, color: connected ? Colors.greenAccent : Colors.redAccent), title: const Text('Bluetooth'), subtitle: Text(connected ? 'متصل بجهاز GeoScan-AI' : 'غير متصل')),
        ListTile(title: const Text('الحساسية'), subtitle: Slider(value: sensitivity, min: 0, max: 100, divisions: 100, onChanged: connected ? (v) { setState(() => sensitivity = v); widget.bluetooth.setSensitivity(v); } : null), trailing: Text('${sensitivity.toStringAsFixed(0)}%')),
        ListTile(title: const Text('الفلترة'), trailing: DropdownButton<String>(value: filter, items: const ['منخفضة', 'متوسطة', 'عالية'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: connected ? (v) { if (v != null) { setState(() => filter = v); widget.bluetooth.setFilter(v); } } : null)),
        SwitchListTile(title: const Text('التنبيه الصوتي'), value: audio, onChanged: connected ? (v) async { if (await widget.bluetooth.setAudio(v)) setState(() => audio = v); } : null),
        SwitchListTile(title: const Text('الاهتزاز'), value: vibration, onChanged: connected ? (v) async { if (await widget.bluetooth.setVibration(v)) setState(() => vibration = v); } : null),
      ])),
      const SizedBox(height: 12),
      const _InfoBox('لا توصل البطارية مباشرة إلى ESP32. اضبط الجهود والحماية والـMOSFET وفق المخطط النهائي قبل التشغيل.'),
    ]));
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox(this.text);
  final String text;
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF07111F), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.cyanAccent.withValues(alpha: .18))), child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.5)));
}

double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
