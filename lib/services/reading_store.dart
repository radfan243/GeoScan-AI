import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ReadingStore {
  static const _key = 'geoscan_readings_v1';

  Future<List<Map<String, dynamic>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    return raw.map((e) {
      try { return Map<String, dynamic>.from(jsonDecode(e) as Map); }
      catch (_) { return <String, dynamic>{}; }
    }).where((e) => e.isNotEmpty).toList();
  }

  Future<void> save(Map<String, dynamic> reading) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await load();
    items.insert(0, reading);
    final trimmed = items.take(200).map(jsonEncode).toList();
    await prefs.setStringList(_key, trimmed);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
