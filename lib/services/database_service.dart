import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/app_models.dart';

class DatabaseService {
  DatabaseService(this.user);
  final User user;
  final FirebaseDatabase _db = FirebaseDatabase.instance;

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
      final rows = value.entries.map((entry) => LedgerEntry.fromMap(
            entry.key.toString(),
            Map<dynamic, dynamic>.from(entry.value as Map),
          )).toList();
      rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return rows;
    });
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
    await _db.ref().update({
      'groups/$id': {
        'name': name,
        'emoji': emoji,
        'ownerId': user.uid,
        'createdAt': ServerValue.timestamp,
        'members': {user.uid: member},
      },
      'groupMembers/${user.uid}/$id': true,
    });
    return id;
  }

  Future<void> addMember(String groupId, String uid, String name, String email) {
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

  Future<void> addContribution({
    required String groupId,
    required String memberId,
    required double amount,
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
      'createdAt': ServerValue.timestamp,
    });
  }

  Future<void> addExpense({
    required String groupId,
    required String title,
    required String category,
    required double amount,
    required String paidBy,
    required List<String> memberIds,
  }) {
    final share = amount / memberIds.length;
    final split = {for (final uid in memberIds) uid: share};
    final ref = _db.ref('transactions/$groupId').push();
    return ref.set({
      'type': 'expense',
      'title': title,
      'category': category,
      'amount': amount,
      'paidBy': paidBy,
      'splitAmong': split,
      'createdBy': user.uid,
      'createdAt': ServerValue.timestamp,
    });
  }

  Future<void> deleteTransaction(String groupId, String transactionId) =>
      _db.ref('transactions/$groupId/$transactionId').remove();
}
