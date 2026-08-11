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
