import 'package:alert_app/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://cuoltgakafetqypsvasl.supabase.co',
      anonKey: 'sb_publishable_83R191bduf1U7tDPNqkF9g_cgZb0Z7i',
    );
  });

  testWidgets('AlertApp shows KLYCH start screen', (WidgetTester tester) async {
    await tester.pumpWidget(const AlertApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('KLYCH'), findsOneWidget);
    expect(find.text('СТВОРИТИ СЕРВЕР'), findsOneWidget);
  });
}
