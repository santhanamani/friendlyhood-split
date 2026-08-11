class SplitGroup {
  const SplitGroup({
    required this.id,
    required this.name,
    required this.emoji,
    required this.ownerId,
    required this.accessCode,
    required this.currencyCode,
    required this.customExpenseCategories,
    required this.members,
    required this.formerMembers,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String emoji;
  final String ownerId;
  final String accessCode;
  final String currencyCode;
  final List<String> customExpenseCategories;
  final Map<String, GroupMember> members;
  final Map<String, GroupMember> formerMembers;
  final int createdAt;

  SplitGroup copyWith({
    String? name,
    String? accessCode,
    String? currencyCode,
    List<String>? customExpenseCategories,
    Map<String, GroupMember>? members,
    Map<String, GroupMember>? formerMembers,
  }) =>
      SplitGroup(
        id: id,
        name: name ?? this.name,
        emoji: emoji,
        ownerId: ownerId,
        accessCode: accessCode ?? this.accessCode,
        currencyCode: currencyCode ?? this.currencyCode,
        customExpenseCategories:
            customExpenseCategories ?? this.customExpenseCategories,
        members: members ?? this.members,
        formerMembers: formerMembers ?? this.formerMembers,
        createdAt: createdAt,
      );

  factory SplitGroup.fromMap(String id, Map<dynamic, dynamic> data) {
    final rawMembers =
        Map<dynamic, dynamic>.from(data['members'] as Map? ?? {});
    final rawFormerMembers =
        Map<dynamic, dynamic>.from(data['formerMembers'] as Map? ?? {});
    final rawCustomCategories = Map<dynamic, dynamic>.from(
        data['customExpenseCategories'] as Map? ?? {});
    return SplitGroup(
      id: id,
      name: data['name'] as String? ?? 'Untitled group',
      emoji: data['emoji'] as String? ?? '✨',
      ownerId: data['ownerId'] as String? ?? '',
      accessCode: data['accessCode'] as String? ?? '',
      currencyCode: data['currencyCode'] as String? ?? 'INR',
      customExpenseCategories: rawCustomCategories.values
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      createdAt: (data['createdAt'] as num?)?.toInt() ?? 0,
      members: rawMembers.map((key, value) => MapEntry(
            key.toString(),
            GroupMember.fromMap(
                key.toString(), Map<dynamic, dynamic>.from(value as Map)),
          )),
      formerMembers: rawFormerMembers.map((key, value) => MapEntry(
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
      required this.role,
      required this.photoUrl});
  final String uid;
  final String name;
  final String email;
  final String role;
  final String photoUrl;

  factory GroupMember.fromMap(String uid, Map<dynamic, dynamic> data) =>
      GroupMember(
        uid: uid,
        name: data['name'] as String? ?? 'Friend',
        email: data['email'] as String? ?? '',
        role: data['role'] as String? ?? 'viewer',
        photoUrl: data['photoUrl'] as String? ?? '',
      );
}

class ExpenseSettlement {
  const ExpenseSettlement({
    required this.memberId,
    required this.status,
    required this.requestedBy,
    required this.requestedAt,
    required this.confirmedBy,
    required this.confirmedAt,
  });

  final String memberId;
  final String status;
  final String requestedBy;
  final int requestedAt;
  final String confirmedBy;
  final int confirmedAt;

  bool get isPending => status == 'pending';
  bool get isConfirmed => status == 'confirmed';

  factory ExpenseSettlement.fromMap(
          String memberId, Map<dynamic, dynamic> data) =>
      ExpenseSettlement(
        memberId: memberId,
        status: data['status'] as String? ?? 'unpaid',
        requestedBy: data['requestedBy'] as String? ?? '',
        requestedAt: (data['requestedAt'] as num?)?.toInt() ?? 0,
        confirmedBy: data['confirmedBy'] as String? ?? '',
        confirmedAt: (data['confirmedAt'] as num?)?.toInt() ?? 0,
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
    required this.depositTarget,
    required this.depositTo,
    required this.status,
    required this.reviewedBy,
    required this.reviewedAt,
    required this.rejectionReason,
    required this.settlements,
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
  final String depositTarget;
  final String depositTo;
  final String status;
  final String reviewedBy;
  final int reviewedAt;
  final String rejectionReason;
  final Map<String, ExpenseSettlement> settlements;
  final int createdAt;

  bool get isDeposit => type == 'contribution';
  bool get isLegacyDeposit => isDeposit && status.isEmpty;
  bool get isPendingDeposit => isDeposit && status == 'pending';
  bool get isConfirmedDeposit =>
      isDeposit && (status == 'confirmed' || isLegacyDeposit);
  bool get isRejectedDeposit => isDeposit && status == 'rejected';
  bool get isWalletDeposit =>
      isDeposit && (depositTarget == 'wallet' || depositTarget.isEmpty);
  bool get isMemberDeposit => isDeposit && depositTarget == 'member';

  factory LedgerEntry.fromMap(String id, Map<dynamic, dynamic> data) {
    final rawSplit =
        Map<dynamic, dynamic>.from(data['splitAmong'] as Map? ?? {});
    final rawSettlements =
        Map<dynamic, dynamic>.from(data['settlements'] as Map? ?? {});
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
      depositTarget: data['depositTarget'] as String? ??
          (type == 'contribution' ? 'wallet' : ''),
      depositTo: data['depositTo'] as String? ?? '',
      status: data['status'] as String? ?? '',
      reviewedBy: data['reviewedBy'] as String? ?? '',
      reviewedAt: (data['reviewedAt'] as num?)?.toInt() ?? 0,
      rejectionReason: data['rejectionReason'] as String? ?? '',
      settlements: rawSettlements.map((key, value) => MapEntry(
            key.toString(),
            ExpenseSettlement.fromMap(
                key.toString(), Map<dynamic, dynamic>.from(value as Map)),
          )),
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
    required this.transactionId,
    required this.expenseTitle,
    required this.expenseAmount,
    required this.discussionReason,
    required this.replyToId,
    required this.replyToSenderId,
    required this.replyToSenderName,
    required this.replyToText,
    required this.createdAt,
    required this.editedAt,
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
  final String transactionId;
  final String expenseTitle;
  final double expenseAmount;
  final String discussionReason;
  final String replyToId;
  final String replyToSenderId;
  final String replyToSenderName;
  final String replyToText;
  final int createdAt;
  final int editedAt;

  bool get isSettlementEvent =>
      kind == 'settlement' ||
      text.startsWith('💸 ') ||
      text.startsWith('✅ ') ||
      text.startsWith('⏰ ');

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
      transactionId: data['transactionId'] as String? ?? '',
      expenseTitle: data['expenseTitle'] as String? ?? '',
      expenseAmount: (data['expenseAmount'] as num?)?.toDouble() ?? 0,
      discussionReason: data['discussionReason'] as String? ?? '',
      replyToId: data['replyToId'] as String? ?? '',
      replyToSenderId: data['replyToSenderId'] as String? ?? '',
      replyToSenderName: data['replyToSenderName'] as String? ?? '',
      replyToText: data['replyToText'] as String? ?? '',
      createdAt: (data['createdAt'] as num?)?.toInt() ?? 0,
      editedAt: (data['editedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChatBadge {
  const ChatBadge({required this.unreadCount, required this.hasMention});

  static const empty = ChatBadge(unreadCount: 0, hasMention: false);

  final int unreadCount;
  final bool hasMention;

  String get countLabel => unreadCount > 99 ? '99+' : '$unreadCount';
}
