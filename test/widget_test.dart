import 'package:flutter_test/flutter_test.dart';
import 'package:friendlyhood_split/models/app_update_model.dart';
import 'package:friendlyhood_split/models/app_models.dart';

void main() {
  test('ledger entry parses Firebase numeric values', () {
    final entry = LedgerEntry.fromMap('tx-1', {
      'type': 'expense',
      'title': 'Dinner',
      'category': 'Food',
      'amount': 900,
      'paidBy': 'one',
      'splitAmong': {'one': 450, 'two': 450},
      'createdAt': 1,
    });

    expect(entry.amount, 900);
    expect(entry.splitAmong['two'], 450);
    expect(entry.walletUsed, 900);
    expect(entry.personalPaid, 0);
  });

  test('wallet expense keeps only the shortfall as personal payment', () {
    final entry = LedgerEntry.fromMap('tx-2', {
      'type': 'expense',
      'title': 'Hotel',
      'category': 'Stay',
      'amount': 1500,
      'paidBy': 'admin',
      'paymentSource': 'wallet',
      'walletUsed': 1000,
      'personalPaid': 500,
      'splitAmong': {'admin': 750, 'friend': 750},
      'createdAt': 2,
    });

    expect(entry.walletUsed, 1000);
    expect(entry.personalPaid, 500);
  });

  test('app update configuration validates and parses correctly', () {
    final update = AppUpdateInfo.fromMap({
      'latestVersion': '1.0.2',
      'latestVersionCode': 3,
      'apkUrl': 'https://friends-split-up.web.app/downloads/app-release.apk',
      'forceUpdate': true,
      'updateTitle': 'Update available',
      'updateMessage': 'Install the latest version.',
    });

    expect(update.latestVersionCode, 3);
    expect(update.forceUpdate, isTrue);
    expect(update.apkUrl.scheme, 'https');
  });

  test('app update configuration rejects insecure APK URLs', () {
    expect(
      () => AppUpdateInfo.fromMap({
        'latestVersionCode': 2,
        'apkUrl': 'http://example.com/app.apk',
      }),
      throwsFormatException,
    );
  });
}
