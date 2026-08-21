import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/app_models.dart';

class DatabaseService {
  DatabaseService(this.user);
  final User user;
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  static const _codeCharacters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static bool isValidUpiId(String value) => RegExp(
        r'^[A-Za-z0-9._-]{2,256}@[A-Za-z][A-Za-z0-9.-]{1,63}$',
      ).hasMatch(value.trim());

  Future<String> getCurrentUserUpiId() async {
    final snapshot = await _db.ref('users/${user.uid}/upiId').get();
    return snapshot.value?.toString().trim() ?? '';
  }

  Future<String> getMemberUpiId(String groupId, String uid) async {
    final snapshot = await _db.ref('memberUpiIds/$groupId/$uid').get();
    return snapshot.value?.toString().trim() ?? '';
  }

  Future<String> getGroupWalletUpiId(String groupId) async {
    final snapshot = await _db.ref('groupWalletUpiIds/$groupId').get();
    return snapshot.value?.toString().trim() ?? '';
  }

  Future<void> updateCurrentUserUpiId(String rawValue) async {
    final value = rawValue.trim();
    if (value.isNotEmpty && !isValidUpiId(value)) {
      throw ArgumentError('Enter a valid UPI ID, for example name@bank.');
    }
    final membershipSnapshot = await _db.ref('groupMembers/${user.uid}').get();
    final memberships = membershipSnapshot.value;
    final updates = <String, Object?>{
      'users/${user.uid}/upiId': value.isEmpty ? null : value,
    };
    if (memberships is Map) {
      for (final groupId in memberships.keys.map((key) => '$key')) {
        updates['memberUpiIds/$groupId/${user.uid}'] =
            value.isEmpty ? null : value;
      }
    }
    await _db.ref().update(updates);
  }

  Stream<List<SplitGroup>> watchGroups() {
    return _db.ref('groups').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <SplitGroup>[];
      final groups = <SplitGroup>[];
      for (final entry in value.entries) {
        final data = Map<dynamic, dynamic>.from(entry.value as Map);
        final group = SplitGroup.fromMap(entry.key.toString(), data);
        if (group.members.containsKey(user.uid)) groups.add(group);
      }
      groups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return groups;
    });
  }

  Future<void> syncCurrentUserProfileToGroups() async {
    final membershipSnapshot = await _db.ref('groupMembers/${user.uid}').get();
    final value = membershipSnapshot.value;
    if (value is! Map) return;
    final updates = <String, Object?>{};
    for (final groupId in value.keys.map((key) => '$key')) {
      updates['groups/$groupId/members/${user.uid}/name'] =
          user.displayName ?? 'Friend';
      updates['groups/$groupId/members/${user.uid}/email'] = user.email ?? '';
      updates['groups/$groupId/members/${user.uid}/photoUrl'] =
          user.photoURL ?? '';
    }
    if (updates.isNotEmpty) await _db.ref().update(updates);
  }

  Stream<List<LedgerEntry>> watchTransactions(String groupId) {
    return _db.ref('transactions/$groupId').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <LedgerEntry>[];
      final rows = value.entries
          .map((entry) => LedgerEntry.fromMap(
                entry.key.toString(),
                Map<dynamic, dynamic>.from(entry.value as Map),
              ))
          .toList();
      rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return rows;
    });
  }

  Stream<List<GroupMessage>> watchMessages(String groupId) {
    return _db
        .ref('groupChats/$groupId/messages')
        .limitToLast(200)
        .onValue
        .map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <GroupMessage>[];
      final messages = value.entries
          .map((entry) => GroupMessage.fromMap(entry.key.toString(),
              Map<dynamic, dynamic>.from(entry.value as Map)))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return messages;
    });
  }

  Stream<ChatBadge> watchChatBadge(String groupId, {String? mentionName}) {
    late final StreamController<ChatBadge> controller;
    StreamSubscription<DatabaseEvent>? messagesSubscription;
    StreamSubscription<DatabaseEvent>? readSubscription;
    var messages = <GroupMessage>[];
    var lastReadAt = 0;

    void emit() {
      final unread = messages
          .where((item) =>
              !item.isSettlementEvent &&
              item.createdAt > lastReadAt &&
              item.senderId != user.uid)
          .toList();
      final displayName = mentionName?.trim().isNotEmpty == true
          ? mentionName!.trim()
          : user.displayName?.trim() ?? '';
      final mentionPattern = displayName.isEmpty
          ? null
          : RegExp('@${RegExp.escape(displayName)}(?=\\s|[.,!?;:]|\$)',
              caseSensitive: false);
      controller.add(ChatBadge(
        unreadCount: unread.length,
        hasMention: mentionPattern != null &&
            unread.any((item) => mentionPattern.hasMatch(item.text)),
      ));
    }

    controller = StreamController<ChatBadge>(
      onListen: () {
        messagesSubscription = _db
            .ref('groupChats/$groupId/messages')
            .limitToLast(100)
            .onValue
            .listen((event) {
          final value = event.snapshot.value;
          if (value is! Map) {
            messages = [];
          } else {
            messages = value.entries
                .map((entry) => GroupMessage.fromMap(entry.key.toString(),
                    Map<dynamic, dynamic>.from(entry.value as Map)))
                .toList();
          }
          emit();
        }, onError: controller.addError);
        readSubscription = _db
            .ref('chatReadState/${user.uid}/$groupId')
            .onValue
            .listen((event) {
          lastReadAt = (event.snapshot.value as num?)?.toInt() ?? 0;
          emit();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await messagesSubscription?.cancel();
        await readSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  Future<void> markChatRead(String groupId, int lastMessageAt) async {
    if (lastMessageAt <= 0) return;
    final ref = _db.ref('chatReadState/${user.uid}/$groupId');
    await ref.runTransaction((current) {
      final existing = (current as num?)?.toInt() ?? 0;
      return Transaction.success(max(existing, lastMessageAt));
    });
  }

  Future<void> sendTextMessage(
    String groupId,
    String text, {
    bool sticker = false,
    GroupMessage? replyTo,
  }) {
    final ref = _db.ref('groupChats/$groupId/messages').push();
    return ref.set({
      'kind': sticker ? 'sticker' : 'text',
      'text': text.trim(),
      if (replyTo != null) ...{
        'replyToId': replyTo.id,
        'replyToSenderId': replyTo.senderId,
        'replyToSenderName': replyTo.senderName,
        'replyToText': _replyPreviewText(replyTo),
      },
      'senderId': user.uid,
      'senderName': user.displayName ?? 'Friend',
      'createdAt': ServerValue.timestamp,
    });
  }

  String _replyPreviewText(GroupMessage message) {
    final preview = switch (message.kind) {
      'audio' => 'Voice message',
      'poll' => 'Poll: ${message.pollQuestion}',
      'expenseDiscussion' => 'Expense: ${message.expenseTitle}',
      _ => message.text,
    };
    final clean = preview.trim();
    return clean.length <= 300 ? clean : clean.substring(0, 300);
  }

  Future<void> sendExpenseDiscussion({
    required String groupId,
    required LedgerEntry entry,
    required String creatorName,
    required String reason,
  }) {
    final ref = _db.ref('groupChats/$groupId/messages').push();
    return ref.set({
      'kind': 'expenseDiscussion',
      'text': '@$creatorName, please review "${entry.title}".',
      'transactionId': entry.id,
      'expenseTitle': entry.title,
      'expenseAmount': entry.amount,
      'discussionReason': reason.trim(),
      'senderId': user.uid,
      'senderName': user.displayName ?? 'Friend',
      'createdAt': ServerValue.timestamp,
    });
  }

  Future<LedgerEntry?> getTransaction(
      String groupId, String transactionId) async {
    final snapshot =
        await _db.ref('transactions/$groupId/$transactionId').get();
    final value = snapshot.value;
    if (value is! Map) return null;
    return LedgerEntry.fromMap(
        transactionId, Map<dynamic, dynamic>.from(value));
  }

  Future<void> editTextMessage(String groupId, String messageId, String text) =>
      _db.ref('groupChats/$groupId/messages/$messageId').update({
        'text': text.trim(),
        'editedAt': ServerValue.timestamp,
      });

  Future<void> deleteMessage(String groupId, String messageId) =>
      _db.ref().update({
        'groupChats/$groupId/messages/$messageId': null,
        'pollVotes/$groupId/$messageId': null,
        'messageReactions/$groupId/$messageId': null,
      });

  Future<void> sendAudioMessage({
    required String groupId,
    required String audioBase64,
    required int durationSeconds,
  }) {
    final ref = _db.ref('groupChats/$groupId/messages').push();
    return ref.set({
      'kind': 'audio',
      'senderId': user.uid,
      'senderName': user.displayName ?? 'Friend',
      'audioBase64': audioBase64,
      'audioDurationSeconds': durationSeconds.clamp(1, 10),
      'createdAt': ServerValue.timestamp,
    });
  }

  Future<void> createPoll({
    required String groupId,
    required String question,
    required List<String> options,
  }) {
    final ref = _db.ref('groupChats/$groupId/messages').push();
    return ref.set({
      'kind': 'poll',
      'senderId': user.uid,
      'senderName': user.displayName ?? 'Friend',
      'pollQuestion': question.trim(),
      'pollOptions': {
        for (var index = 0; index < options.length; index++)
          'option$index': options[index].trim(),
      },
      'createdAt': ServerValue.timestamp,
    });
  }

  Stream<Map<String, String>> watchPollVotes(String groupId, String messageId) {
    return _db.ref('pollVotes/$groupId/$messageId').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <String, String>{};
      return value.map((key, value) => MapEntry('$key', '$value'));
    });
  }

  Future<void> votePoll(String groupId, String messageId, String optionId) =>
      _db.ref('pollVotes/$groupId/$messageId/${user.uid}').set(optionId);

  Stream<Map<String, String>> watchMessageReactions(
      String groupId, String messageId) {
    return _db.ref('messageReactions/$groupId/$messageId').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <String, String>{};
      return value.map((key, value) => MapEntry('$key', '$value'));
    });
  }

  Future<void> reactToMessage(String groupId, String messageId, String emoji) =>
      _db.ref('messageReactions/$groupId/$messageId/${user.uid}').set(emoji);

  Stream<Map<String, String>> watchTransactionReactions(
      String groupId, String transactionId) {
    return _db
        .ref('transactionReactions/$groupId/$transactionId')
        .onValue
        .map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <String, String>{};
      return value.map((key, value) => MapEntry('$key', '$value'));
    });
  }

  Future<void> reactToTransaction(
          String groupId, String transactionId, String emoji) =>
      _db
          .ref('transactionReactions/$groupId/$transactionId/${user.uid}')
          .set(emoji);

  Future<SplitGroup?> getGroup(String groupId) async {
    final snapshot = await _db.ref('groups/$groupId').get();
    if (!snapshot.exists || snapshot.value is! Map) return null;
    return SplitGroup.fromMap(
        groupId, Map<dynamic, dynamic>.from(snapshot.value as Map));
  }

  Future<double> getWalletBalance(String groupId) async {
    final snapshot = await _db.ref('transactions/$groupId').get();
    final value = snapshot.value;
    if (value is! Map) return 0;
    var deposited = 0.0;
    var walletSpent = 0.0;
    for (final row in value.entries) {
      final entry = LedgerEntry.fromMap(
        row.key.toString(),
        Map<dynamic, dynamic>.from(row.value as Map),
      );
      if (entry.isConfirmedDeposit && entry.isWalletDeposit) {
        deposited += entry.amount;
      }
      if (entry.type == 'expense') walletSpent += entry.walletUsed;
    }
    return max(0, deposited - walletSpent).toDouble();
  }

  Future<String> createGroup(
      String name, String emoji, String currencyCode) async {
    final ref = _db.ref('groups').push();
    final id = ref.key!;
    final member = {
      'name': user.displayName ?? 'Friend',
      'email': user.email ?? '',
      'photoUrl': user.photoURL ?? '',
      'role': 'admin',
      'joinedAt': ServerValue.timestamp,
    };
    final accessCode = await _unusedAccessCode();
    final upiId = await getCurrentUserUpiId();
    await _db.ref().update({
      'groups/$id': {
        'name': name,
        'emoji': emoji,
        'ownerId': user.uid,
        'accessCode': accessCode,
        'currencyCode': currencyCode,
        'createdAt': ServerValue.timestamp,
        'members': {user.uid: member},
      },
      'groupMembers/${user.uid}/$id': true,
    });
    if (upiId.isNotEmpty) {
      await _db.ref('memberUpiIds/$id/${user.uid}').set(upiId);
    }
    await _db.ref('joinCodes/$accessCode').set(id);
    return id;
  }

  Future<String> createAccessCode(String groupId) async {
    final code = await _unusedAccessCode();
    await _db.ref('groups/$groupId/accessCode').set(code);
    await _db.ref('joinCodes/$code').set(groupId);
    return code;
  }

  Future<String> _unusedAccessCode() async {
    final random = Random.secure();
    for (var attempt = 0; attempt < 12; attempt++) {
      final code = List.generate(
        8,
        (_) => _codeCharacters[random.nextInt(_codeCharacters.length)],
      ).join();
      if (!(await _db.ref('joinCodes/$code').get()).exists) return code;
    }
    throw StateError('Could not create a unique group code. Please try again.');
  }

  Future<String> joinGroup(String rawCode) async {
    final code = rawCode.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (code.isEmpty) throw ArgumentError('Enter a group access code.');
    final codeSnapshot = await _db.ref('joinCodes/$code').get();
    final groupId = codeSnapshot.value?.toString();
    if (groupId == null || groupId.isEmpty) {
      throw StateError('That access code is not valid.');
    }
    final groupSnapshot = await _db.ref('groups/$groupId').get();
    if (!groupSnapshot.exists) throw StateError('This group no longer exists.');
    final groupData = Map<dynamic, dynamic>.from(groupSnapshot.value as Map);
    final members =
        Map<dynamic, dynamic>.from(groupData['members'] as Map? ?? {});
    if (members.containsKey(user.uid)) return groupId;
    final upiId = await getCurrentUserUpiId();
    await _db.ref().update({
      'groups/$groupId/members/${user.uid}': {
        'name': user.displayName ?? 'Friend',
        'email': user.email ?? '',
        'photoUrl': user.photoURL ?? '',
        'role': 'viewer',
        'joinedAt': ServerValue.timestamp,
      },
      'groupMembers/${user.uid}/$groupId': true,
    });
    if (upiId.isNotEmpty) {
      await _db.ref('memberUpiIds/$groupId/${user.uid}').set(upiId);
    }
    return groupId;
  }

  Future<void> addMember(
      String groupId, String uid, String name, String email) {
    return _db.ref().update({
      'groups/$groupId/members/$uid': {
        'name': name,
        'email': email,
        'photoUrl': '',
        'role': 'viewer',
        'joinedAt': ServerValue.timestamp,
      },
      'groups/$groupId/formerMembers/$uid': null,
      'groupMembers/$uid/$groupId': true,
    });
  }

  Future<void> removeMember(String groupId, GroupMember member) =>
      _db.ref().update({
        'groups/$groupId/members/${member.uid}': null,
        'groups/$groupId/formerMembers/${member.uid}': {
          'name': member.name,
          'email': member.email,
          'photoUrl': member.photoUrl,
          'role': 'former',
          'removedAt': ServerValue.timestamp,
        },
        'groupMembers/${member.uid}/$groupId': null,
        'chatReadState/${member.uid}/$groupId': null,
        'memberUpiIds/$groupId/${member.uid}': null,
      });

  Future<void> renameGroup(String groupId, String name) =>
      _db.ref('groups/$groupId/name').set(name.trim());

  Future<void> updateGroupCurrency(String groupId, String currencyCode) =>
      _db.ref('groups/$groupId/currencyCode').set(currencyCode.toUpperCase());

  Future<void> updateGroupWalletUpiId(String groupId, String rawValue) {
    final value = rawValue.trim();
    if (value.isNotEmpty && !isValidUpiId(value)) {
      throw ArgumentError('Enter a valid UPI ID, for example group@bank.');
    }
    return _db
        .ref('groupWalletUpiIds/$groupId')
        .set(value.isEmpty ? null : value);
  }

  Future<void> addExpenseCategory(String groupId, String category) {
    final value = category.trim();
    if (value.isEmpty || value.length > 30) {
      throw ArgumentError('Category must contain 1 to 30 characters.');
    }
    return _db.ref('groups/$groupId/customExpenseCategories').push().set(value);
  }

  Future<void> deleteGroup(SplitGroup group) async {
    final transactions = await _db.ref('transactions/${group.id}').get();
    final transactionIds = transactions.children.map((item) => item.key);
    await _db.ref().update({
      'groups/${group.id}': null,
      'groupChats/${group.id}': null,
      'pollVotes/${group.id}': null,
      'messageReactions/${group.id}': null,
      'transactionReactions/${group.id}': null,
      'memberUpiIds/${group.id}': null,
      'groupWalletUpiIds/${group.id}': null,
      if (group.accessCode.isNotEmpty) 'joinCodes/${group.accessCode}': null,
      for (final uid in group.members.keys)
        'groupMembers/$uid/${group.id}': null,
      for (final uid in group.members.keys)
        'chatReadState/$uid/${group.id}': null,
      for (final transactionId in transactionIds)
        if (transactionId != null)
          'transactions/${group.id}/$transactionId': null,
    });
  }

  Future<void> addDeposit({
    required String groupId,
    required String depositTarget,
    required String depositTo,
    required double amount,
    required int occurredAt,
    String paymentMethod = 'manual',
    String paymentReference = '',
    String paymentAppStatus = '',
    String paymentDescription = '',
  }) {
    if (depositTarget != 'wallet' && depositTarget != 'member') {
      throw ArgumentError('Invalid deposit target.');
    }
    if (depositTarget == 'member' && depositTo.isEmpty) {
      throw ArgumentError('Choose a member to receive the deposit.');
    }
    final ref = _db.ref('transactions/$groupId').push();
    return ref.set({
      'type': 'contribution',
      'title': depositTarget == 'wallet' ? 'Wallet deposit' : 'Member deposit',
      'category': 'Contribution',
      'amount': amount,
      'paidBy': user.uid,
      'depositTarget': depositTarget,
      'depositTo': depositTarget == 'member' ? depositTo : '',
      'status': 'pending',
      'paymentMethod': paymentMethod,
      if (paymentReference.isNotEmpty) 'paymentReference': paymentReference,
      if (paymentAppStatus.isNotEmpty) 'paymentAppStatus': paymentAppStatus,
      if (paymentDescription.trim().isNotEmpty)
        'paymentDescription': paymentDescription.trim(),
      'splitAmong': <String, double>{},
      'createdBy': user.uid,
      'createdAt': occurredAt,
    });
  }

  Future<void> addExpense({
    required String groupId,
    required String title,
    required String category,
    required double amount,
    required String paidBy,
    required List<String> memberIds,
    required String paymentSource,
    required double walletBalance,
    required int occurredAt,
  }) {
    final share = amount / memberIds.length;
    final split = {for (final uid in memberIds) uid: share};
    final walletUsed = paymentSource == 'wallet'
        ? min(max(walletBalance, 0), amount).toDouble()
        : 0.0;
    final personalPaid = amount - walletUsed;
    final ref = _db.ref('transactions/$groupId').push();
    return ref.set({
      'type': 'expense',
      'title': title,
      'category': category,
      'amount': amount,
      'paidBy': paidBy,
      'paymentSource': paymentSource,
      'walletUsed': walletUsed,
      'personalPaid': personalPaid,
      'splitAmong': split,
      'createdBy': user.uid,
      'createdAt': occurredAt,
    });
  }

  Future<void> updateDeposit({
    required String groupId,
    required String transactionId,
    required String depositTarget,
    required String depositTo,
    required double amount,
    required int occurredAt,
  }) =>
      _db.ref('transactions/$groupId/$transactionId').update({
        'title':
            depositTarget == 'wallet' ? 'Wallet deposit' : 'Member deposit',
        'amount': amount,
        'depositTarget': depositTarget,
        'depositTo': depositTarget == 'member' ? depositTo : '',
        'createdAt': occurredAt,
      });

  Future<void> reviewDeposit({
    required String groupId,
    required LedgerEntry entry,
    required bool approve,
    required String reviewerName,
    required String senderName,
    String rejectionReason = '',
  }) {
    final updates = <String, Object?>{
      'transactions/$groupId/${entry.id}/status':
          approve ? 'confirmed' : 'rejected',
      'transactions/$groupId/${entry.id}/reviewedBy': user.uid,
      'transactions/$groupId/${entry.id}/reviewedAt': ServerValue.timestamp,
      'transactions/$groupId/${entry.id}/rejectionReason':
          approve ? null : rejectionReason.trim(),
    };
    if (!approve) {
      final messageRef = _db.ref('groupChats/$groupId/messages').push();
      updates['groupChats/$groupId/messages/${messageRef.key}'] = {
        'kind': 'text',
        'text':
            '❌ @$senderName, your ${entry.isWalletDeposit ? 'group wallet' : 'member'} deposit was rejected by $reviewerName.${rejectionReason.trim().isEmpty ? '' : ' Reason: ${rejectionReason.trim()}'}',
        'senderId': user.uid,
        'senderName': reviewerName,
        'createdAt': ServerValue.timestamp,
      };
    }
    return _db.ref().update(updates);
  }

  Future<void> requestExpenseSettlement({
    required String groupId,
    required LedgerEntry entry,
    required String debtorName,
    required String payerName,
  }) {
    final messageRef = _db.ref('groupChats/$groupId/messages').push();
    return _db.ref().update({
      'transactions/$groupId/${entry.id}/settlements/${user.uid}': {
        'status': 'pending',
        'requestedBy': user.uid,
        'requestedAt': ServerValue.timestamp,
      },
      'groupChats/$groupId/messages/${messageRef.key}': {
        'kind': 'settlement',
        'text':
            '💸 @$payerName, $debtorName marked ${entry.title} as settled. Please confirm the payment.',
        'senderId': user.uid,
        'senderName': debtorName,
        'createdAt': ServerValue.timestamp,
      },
    });
  }

  Future<void> confirmExpenseSettlement({
    required String groupId,
    required LedgerEntry entry,
    required String debtorUid,
    required String debtorName,
    required String confirmerName,
  }) {
    final current = entry.settlements[debtorUid];
    final messageRef = _db.ref('groupChats/$groupId/messages').push();
    return _db.ref().update({
      'transactions/$groupId/${entry.id}/settlements/$debtorUid/status':
          'confirmed',
      'transactions/$groupId/${entry.id}/settlements/$debtorUid/requestedBy':
          current?.requestedBy.isNotEmpty == true
              ? current!.requestedBy
              : user.uid,
      'transactions/$groupId/${entry.id}/settlements/$debtorUid/requestedAt':
          current?.requestedAt != null && current!.requestedAt > 0
              ? current.requestedAt
              : ServerValue.timestamp,
      'transactions/$groupId/${entry.id}/settlements/$debtorUid/confirmedBy':
          user.uid,
      'transactions/$groupId/${entry.id}/settlements/$debtorUid/confirmedAt':
          ServerValue.timestamp,
      'groupChats/$groupId/messages/${messageRef.key}': {
        'kind': 'settlement',
        'text':
            '✅ @$debtorName, your settlement for ${entry.title} was confirmed by $confirmerName.',
        'senderId': user.uid,
        'senderName': confirmerName,
        'createdAt': ServerValue.timestamp,
      },
    });
  }

  Future<void> remindExpenseSettlement({
    required String groupId,
    required LedgerEntry entry,
    required String debtorName,
    required String payerName,
    required double amount,
  }) {
    final messageRef = _db.ref('groupChats/$groupId/messages').push();
    return messageRef.set({
      'kind': 'settlement',
      'text':
          '⏰ @$debtorName, reminder from $payerName: your ${amount.toStringAsFixed(2)} share for ${entry.title} is still unsettled.',
      'senderId': user.uid,
      'senderName': payerName,
      'createdAt': ServerValue.timestamp,
    });
  }

  Future<void> updateExpense({
    required String groupId,
    required String transactionId,
    required String title,
    required String category,
    required double amount,
    required String paidBy,
    required List<String> memberIds,
    required String paymentSource,
    required double walletBalance,
    required int occurredAt,
  }) {
    final share = amount / memberIds.length;
    final walletUsed = paymentSource == 'wallet'
        ? min(max(walletBalance, 0), amount).toDouble()
        : 0.0;
    return _db.ref('transactions/$groupId/$transactionId').update({
      'title': title,
      'category': category,
      'amount': amount,
      'paidBy': paidBy,
      'splitAmong': {for (final uid in memberIds) uid: share},
      'paymentSource': paymentSource,
      'walletUsed': walletUsed,
      'personalPaid': amount - walletUsed,
      'settlements': null,
      'createdAt': occurredAt,
    });
  }

  Future<void> deleteTransaction(String groupId, String transactionId) =>
      _db.ref().update({
        'transactions/$groupId/$transactionId': null,
        'transactionReactions/$groupId/$transactionId': null,
      });
}
