import 'package:flutter/material.dart';
import 'screens/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GeoScanAI());
}

class GeoScanAI extends StatelessWidget {
  const GeoScanAI({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GeoScan AI',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF020711),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyan, brightness: Brightness.dark),
      ),
      home: const Directionality(textDirection: TextDirection.rtl, child: GeoScanShell()),
    );
  }
}
