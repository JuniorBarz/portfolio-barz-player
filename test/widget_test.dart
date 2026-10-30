import 'package:flutter_test/flutter_test.dart';

import 'package:barz_player/main.dart';

void main() {
  testWidgets('shows splash screen before configuration check', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Barz Player'), findsOneWidget);
  });
}
