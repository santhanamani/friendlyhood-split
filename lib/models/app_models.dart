class SplitGroup {
  const SplitGroup({
    required this.id,
    required this.name,
    required this.emoji,
    required this.ownerId,
    required this.accessCode,
    required this.members,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String emoji;
  final String ownerId;
  final String accessCode;
  final Map<String, GroupMember> members;
  final int createdAt;

  SplitGroup copyWith({
    String? name,
    String? accessCode,
    Map<String, GroupMember>? members,
  }) =>
      SplitGroup(
        id: id,
        name: name ?? this.name,
        emoji: emoji,
        ownerId: ownerId,
        accessCode: accessCode ?? this.accessCode,
        members: members ?? this.members,
        createdAt: createdAt,
      );

  factory SplitGroup.fromMap(String id, Map<dynamic, dynamic> data) {
    final rawMembers =
        Map<dynamic, dynamic>.from(data['members'] as Map? ?? {});
    return SplitGroup(
      id: id,
      name: data['name'] as String? ?? 'Untitled group',
      emoji: data['emoji'] as String? ?? '✨',
      ownerId: data['ownerId'] as String? ?? '',
      accessCode: data['accessCode'] as String? ?? '',
      createdAt: (data['createdAt'] as num?)?.toInt() ?? 0,
      members: rawMembers.map((key, value) => MapEntry(
            key.toString(),
            GroupMember.fromMap(
                key.toString(), Map<dynamic, dynamic>.from(value as Map)),
          )),
    );
  }
}

class GroupMember {
  const GroupMember(
      {required this.uid,
      required this.name,
      required this.email,
      required this.role});
  final String uid;
  final String name;
  final String email;
  final String role;

  factory GroupMember.fromMap(String uid, Map<dynamic, dynamic> data) =>
      GroupMember(
        uid: uid,
        name: data['name'] as String? ?? 'Friend',
        email: data['email'] as String? ?? '',
        role: data['role'] as String? ?? 'viewer',
      );
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.category,
    required this.amount,
    required this.paidBy,
    required this.createdBy,
    required this.paymentSource,
    required this.walletUsed,
    required this.personalPaid,
    required this.splitAmong,
    required this.createdAt,
  });
  final String id;
  final String type;
  final String title;
  final String category;
  final double amount;
  final String paidBy;
  final String createdBy;
  final String paymentSource;
  final double walletUsed;
  final double personalPaid;
  final Map<String, double> splitAmong;
  final int createdAt;

  factory LedgerEntry.fromMap(String id, Map<dynamic, dynamic> data) {
    final rawSplit =
        Map<dynamic, dynamic>.from(data['splitAmong'] as Map? ?? {});
    final type = data['type'] as String? ?? 'expense';
    final amount = (data['amount'] as num?)?.toDouble() ?? 0;
    final paymentSource = data['paymentSource'] as String? ??
        (type == 'expense' ? 'wallet' : 'deposit');
    return LedgerEntry(
      id: id,
      type: type,
      title: data['title'] as String? ?? 'Transaction',
      category: data['category'] as String? ?? 'Other',
      amount: amount,
      paidBy: data['paidBy'] as String? ?? '',
      createdBy: data['createdBy'] as String? ?? '',
      paymentSource: paymentSource,
      walletUsed: (data['walletUsed'] as num?)?.toDouble() ??
          (type == 'expense' && paymentSource == 'wallet' ? amount : 0),
      personalPaid: (data['personalPaid'] as num?)?.toDouble() ??
          (type == 'expense' && paymentSource == 'personal' ? amount : 0),
      splitAmong:
          rawSplit.map((k, v) => MapEntry(k.toString(), (v as num).toDouble())),
      createdAt: (data['createdAt'] as num?)?.toInt() ?? 0,
    );
  }
}

class GroupMessage {
  const GroupMessage({
    required this.id,
    required this.kind,
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.audioBase64,
    required this.audioDurationSeconds,
    required this.pollQuestion,
    required this.pollOptions,
    required this.createdAt,
  });

  final String id;
  final String kind;
  final String text;
  final String senderId;
  final String senderName;
  final String audioBase64;
  final int audioDurationSeconds;
  final String pollQuestion;
  final Map<String, String> pollOptions;
  final int createdAt;

  factory GroupMessage.fromMap(String id, Map<dynamic, dynamic> data) {
    final rawOptions =
        Map<dynamic, dynamic>.from(data['pollOptions'] as Map? ?? {});
    return GroupMessage(
      id: id,
      kind: data['kind'] as String? ?? 'text',
      text: data['text'] as String? ?? '',
      senderId: data['senderId'] as String? ?? '',
      senderName: data['senderName'] as String? ?? 'Friend',
      audioBase64: data['audioBase64'] as String? ?? '',
      audioDurationSeconds:
          (data['audioDurationSeconds'] as num?)?.toInt() ?? 0,
      pollQuestion: data['pollQuestion'] as String? ?? '',
      pollOptions: rawOptions.map((key, value) => MapEntry('$key', '$value')),
      createdAt: (data['createdAt'] as num?)?.toInt() ?? 0,
    );
  }
}
