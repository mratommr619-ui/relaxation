import 'package:flutter_test/flutter_test.dart';
import 'package:relaxation_admin/main.dart';

void main() {
  testWidgets('Relaxation Studio renders admin shell', (tester) async {
    await tester.pumpWidget(const RelaxationStudio(firebaseReady: false));

    expect(find.text('Relaxation Studio'), findsOneWidget);
    expect(find.text('Config needed'), findsOneWidget);
    expect(
      find.text('Configure Firebase before signing in to Studio.'),
      findsOneWidget,
    );
  });

  test('parses Telegram public post links', () {
    final full = parseTelegramPublicLink(
      'https://t.me/MagicChineseSeriesPage/18499',
    );
    expect(full?.chat, 'MagicChineseSeriesPage');
    expect(full?.messageId, 18499);

    final raw = parseTelegramPublicLink('MagicChineseSeriesPage/18499');
    expect(raw?.chat, 'MagicChineseSeriesPage');
    expect(raw?.messageId, 18499);
  });
}
