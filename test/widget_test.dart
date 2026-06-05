import 'package:flutter_test/flutter_test.dart';

import 'package:relaxation/main.dart';

void main() {
  testWidgets('Relaxation home renders demo library', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const RelaxationApp(firebaseReady: false));

    expect(find.text('Relaxation'), findsOneWidget);
    expect(find.text('Newest Movies'), findsOneWidget);
    expect(find.text('Newest Series'), findsOneWidget);
    expect(find.textContaining('Demo mode'), findsOneWidget);
  });
}
