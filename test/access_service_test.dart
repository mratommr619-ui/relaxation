import 'package:flutter_test/flutter_test.dart';
import 'package:relaxation/services/access_service.dart';

void main() {
  test('license expiry is activation date plus license days', () {
    final activatedAt = DateTime(2026, 6, 5, 10, 30);

    expect(
      licenseExpiryFromActivation(activatedAt, 30),
      DateTime(2026, 7, 5, 10, 30),
    );
  });

  test('trial expiry starts from Telegram login time', () {
    final loggedInAt = DateTime(2026, 6, 5, 20, 15);

    expect(
      trialExpiryFromTelegramLogin(loggedInAt),
      DateTime(2026, 6, 8, 20, 15),
    );
  });
}
