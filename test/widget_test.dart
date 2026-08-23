import 'package:flutter_test/flutter_test.dart';
import 'package:geoscan_ai/main.dart';

void main() {
  testWidgets('App launches and shows title', (WidgetTester tester) async {
    await tester.pumpWidget(const GeoScanAI());
    await tester.pumpAndSettle();
    expect(find.text('GeoScan AI'), findsOneWidget);
  });
}
