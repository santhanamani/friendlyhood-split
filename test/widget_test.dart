import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friendlyhood_split/models/app_update_model.dart';
import 'package:friendlyhood_split/models/app_models.dart';
import 'package:friendlyhood_split/services/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test('group parses its own custom expense categories', () {
    final group = SplitGroup.fromMap('group-1', {
      'name': 'Trip',
      'ownerId': 'admin',
      'createdAt': 1,
      'members': {
        'admin': {'name': 'Admin', 'email': '', 'role': 'admin'},
      },
      'customExpenseCategories': {
        'first': 'Medical',
        'second': 'Fuel',
      },
    });

    expect(group.customExpenseCategories, ['Medical', 'Fuel']);
  });

  test('pending member deposit stays outside confirmed balances', () {
    final deposit = LedgerEntry.fromMap('deposit-1', {
      'type': 'contribution',
      'title': 'Member deposit',
      'category': 'Contribution',
      'amount': 500,
      'paidBy': 'sender',
      'createdBy': 'sender',
      'depositTarget': 'member',
      'depositTo': 'receiver',
      'status': 'pending',
      'createdAt': 3,
    });

    expect(deposit.isPendingDeposit, isTrue);
    expect(deposit.isConfirmedDeposit, isFalse);
    expect(deposit.isMemberDeposit, isTrue);
    expect(deposit.depositTo, 'receiver');
  });

  test('legacy contributions remain confirmed wallet deposits', () {
    final deposit = LedgerEntry.fromMap('deposit-legacy', {
      'type': 'contribution',
      'title': 'Wallet contribution',
      'amount': 250,
      'paidBy': 'member',
      'createdBy': 'admin',
      'createdAt': 2,
    });

    expect(deposit.isConfirmedDeposit, isTrue);
    expect(deposit.isWalletDeposit, isTrue);
  });

  test('expense parses participant settlement confirmation', () {
    final expense = LedgerEntry.fromMap('expense-settled', {
      'type': 'expense',
      'title': 'Dinner',
      'category': 'Food',
      'amount': 600,
      'paidBy': 'payer',
      'createdBy': 'payer',
      'paymentSource': 'personal',
      'walletUsed': 0,
      'personalPaid': 600,
      'splitAmong': {'payer': 300, 'debtor': 300},
      'settlements': {
        'debtor': {
          'status': 'confirmed',
          'requestedBy': 'debtor',
          'requestedAt': 4,
          'confirmedBy': 'payer',
          'confirmedAt': 5,
        },
      },
      'createdAt': 3,
    });

    expect(expense.settlements['debtor']?.isConfirmed, isTrue);
    expect(expense.splitAmong['debtor'], 300);
  });

  test('settlement events stay separate from normal group messages', () {
    final event = GroupMessage.fromMap('settlement-1', {
      'kind': 'settlement',
      'text': '💸 @Alex, payment confirmation requested.',
      'senderId': 'member',
      'senderName': 'Member',
      'createdAt': 10,
    });
    final legacyEvent = GroupMessage.fromMap('settlement-legacy', {
      'kind': 'text',
      'text': '⏰ @Alex, your expense share is still unsettled.',
      'senderId': 'admin',
      'senderName': 'Admin',
      'createdAt': 9,
    });
    final chat = GroupMessage.fromMap('chat-1', {
      'kind': 'text',
      'text': 'Dinner at 8?',
      'senderId': 'member',
      'senderName': 'Member',
      'createdAt': 11,
    });

    expect(event.isSettlementEvent, isTrue);
    expect(legacyEvent.isSettlementEvent, isTrue);
    expect(chat.isSettlementEvent, isFalse);
  });

  test('expense discussion message keeps compact card metadata', () {
    final discussion = GroupMessage.fromMap('discussion-1', {
      'kind': 'expenseDiscussion',
      'text': '@Alex, please review "Dinner".',
      'transactionId': 'expense-1',
      'expenseTitle': 'Dinner',
      'expenseAmount': 825.50,
      'discussionReason': 'Please verify this amount.',
      'senderId': 'member',
      'senderName': 'Member',
      'createdAt': 12,
    });

    expect(discussion.kind, 'expenseDiscussion');
    expect(discussion.transactionId, 'expense-1');
    expect(discussion.expenseTitle, 'Dinner');
    expect(discussion.expenseAmount, 825.50);
    expect(discussion.discussionReason, 'Please verify this amount.');
    expect(discussion.isSettlementEvent, isFalse);
  });

  test('group message parses reply and mention metadata', () {
    final reply = GroupMessage.fromMap('reply-1', {
      'kind': 'text',
      'text': '@Alex, I will check it.',
      'senderId': 'member-2',
      'senderName': 'Sam',
      'replyToId': 'message-1',
      'replyToSenderId': 'member-1',
      'replyToSenderName': 'Alex',
      'replyToText': 'Can you verify this?',
      'createdAt': 13,
    });

    expect(reply.replyToId, 'message-1');
    expect(reply.replyToSenderId, 'member-1');
    expect(reply.replyToSenderName, 'Alex');
    expect(reply.replyToText, 'Can you verify this?');
    expect(reply.text, startsWith('@Alex'));
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

  test('dark is default and manual appearance choices persist', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = await AppThemeController.load();

    expect(controller.preference, AppThemePreference.dark);
    expect(controller.themeMode, ThemeMode.dark);

    await controller.setPreference(AppThemePreference.light);
    final restored = await AppThemeController.load();

    expect(restored.preference, AppThemePreference.light);
    expect(restored.themeMode, ThemeMode.light);
  });
}
