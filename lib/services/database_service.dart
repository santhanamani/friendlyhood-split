import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/app_models.dart';

class DatabaseService {
  DatabaseService(this.user);
  final User user;
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  static const _codeCharacters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

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

  Future<void> sendTextMessage(String groupId, String text,
      {bool sticker = false}) {
    final ref = _db.ref('groupChats/$groupId/messages').push();
    return ref.set({
      'kind': sticker ? 'sticker' : 'text',
      'text': text.trim(),
      'senderId': user.uid,
      'senderName': user.displayName ?? 'Friend',
      'createdAt': ServerValue.timestamp,
    });
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
      if (entry.type == 'contribution') deposited += entry.amount;
      if (entry.type == 'expense') walletSpent += entry.walletUsed;
    }
    return max(0, deposited - walletSpent).toDouble();
  }

  Future<String> createGroup(String name, String emoji) async {
    final ref = _db.ref('groups').push();
    final id = ref.key!;
    final member = {
      'name': user.displayName ?? 'Friend',
      'email': user.email ?? '',
      'role': 'admin',
      'joinedAt': ServerValue.timestamp,
    };
    final accessCode = await _unusedAccessCode();
    await _db.ref().update({
      'groups/$id': {
        'name': name,
        'emoji': emoji,
        'ownerId': user.uid,
        'accessCode': accessCode,
        'createdAt': ServerValue.timestamp,
        'members': {user.uid: member},
      },
      'groupMembers/${user.uid}/$id': true,
    });
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
    await _db.ref().update({
      'groups/$groupId/members/${user.uid}': {
        'name': user.displayName ?? 'Friend',
        'email': user.email ?? '',
        'role': 'viewer',
        'joinedAt': ServerValue.timestamp,
      },
      'groupMembers/${user.uid}/$groupId': true,
    });
    return groupId;
  }

  Future<void> addMember(
      String groupId, String uid, String name, String email) {
    return _db.ref().update({
      'groups/$groupId/members/$uid': {
        'name': name,
        'email': email,
        'role': 'viewer',
        'joinedAt': ServerValue.timestamp,
      },
      'groupMembers/$uid/$groupId': true,
    });
  }

  Future<void> removeMember(String groupId, String uid) => _db.ref().update({
        'groups/$groupId/members/$uid': null,
        'groupMembers/$uid/$groupId': null,
      });

  Future<void> renameGroup(String groupId, String name) =>
      _db.ref('groups/$groupId/name').set(name.trim());

  Future<void> deleteGroup(SplitGroup group) async {
    final transactions = await _db.ref('transactions/${group.id}').get();
    final transactionIds = transactions.children.map((item) => item.key);
    await _db.ref().update({
      'groups/${group.id}': null,
      'groupChats/${group.id}': null,
      'pollVotes/${group.id}': null,
      'messageReactions/${group.id}': null,
      if (group.accessCode.isNotEmpty) 'joinCodes/${group.accessCode}': null,
      for (final uid in group.members.keys)
        'groupMembers/$uid/${group.id}': null,
      for (final transactionId in transactionIds)
        if (transactionId != null)
          'transactions/${group.id}/$transactionId': null,
    });
  }

  Future<void> addContribution({
    required String groupId,
    required String memberId,
    required double amount,
    required int occurredAt,
  }) {
    final ref = _db.ref('transactions/$groupId').push();
    return ref.set({
      'type': 'contribution',
      'title': 'Wallet contribution',
      'category': 'Contribution',
      'amount': amount,
      'paidBy': memberId,
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

  Future<void> updateContribution({
    required String groupId,
    required String transactionId,
    required String memberId,
    required double amount,
    required int occurredAt,
  }) =>
      _db.ref('transactions/$groupId/$transactionId').update({
        'amount': amount,
        'paidBy': memberId,
        'createdAt': occurredAt,
      });

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
      'createdAt': occurredAt,
    });
  }

  Future<void> deleteTransaction(String groupId, String transactionId) =>
      _db.ref('transactions/$groupId/$transactionId').remove();
}
