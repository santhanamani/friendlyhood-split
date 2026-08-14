import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/app_models.dart';
import '../models/currency_data.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';

Color _chatSurfaceAccent(BuildContext context, Color color) =>
    Theme.of(context).brightness == Brightness.light
        ? Color.lerp(color, Colors.black, .28)!
        : color;

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({
    super.key,
    required this.group,
    required this.database,
    required this.currentUid,
  });

  final SplitGroup group;
  final DatabaseService database;
  final String currentUid;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  static const stickers = [
    '😀',
    '😂',
    '😍',
    '🥳',
    '😎',
    '🤝',
    '❤️',
    '🔥',
    '👍',
    '🙏',
    '🎉',
    '💸'
  ];
  static const reactions = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

  final message = TextEditingController();
  final messageFocus = FocusNode();
  final messageScrollController = ItemScrollController();
  final recorder = AudioRecorder();
  bool isRecording = false;
  bool isSendingAudio = false;
  final recordedSeconds = ValueNotifier<int>(0);
  int recordingSession = 0;
  int lastMarkedReadAt = 0;
  bool showSettlements = false;
  GroupMessage? replyingTo;
  Map<String, int> messageIndexes = const {};
  final highlightedMessage = ValueNotifier<String?>(null);
  int highlightSession = 0;

  bool get isAdmin => widget.group.ownerId == widget.currentUid;

  @override
  void dispose() {
    recordingSession++;
    recorder.dispose();
    message.dispose();
    messageFocus.dispose();
    recordedSeconds.dispose();
    highlightedMessage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final pageColor =
        isLight ? const Color(0xFFFBFAFF) : const Color(0xFF020711);
    return Scaffold(
      backgroundColor: pageColor,
      appBar: AppBar(
        backgroundColor: pageColor,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Row(children: [
          CircleAvatar(child: Text(widget.group.emoji)),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 17)),
              Text('${widget.group.members.length} members',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11)),
            ]),
          ),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<List<GroupMessage>>(
            stream: widget.database.watchMessages(widget.group.id),
            builder: (context, snapshot) {
              final allMessages = snapshot.data ?? [];
              final messages =
                  allMessages.where((item) => !item.isSettlementEvent).toList();
              final settlements =
                  allMessages.where((item) => item.isSettlementEvent).toList();
              if (messages.isNotEmpty &&
                  messages.last.createdAt > lastMarkedReadAt) {
                lastMarkedReadAt = messages.last.createdAt;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  widget.database
                      .markChatRead(widget.group.id, lastMarkedReadAt);
                });
              }
              final selected = showSettlements ? settlements : messages;
              final reversed = selected.reversed.toList();
              messageIndexes = showSettlements
                  ? const {}
                  : {
                      for (var index = 0; index < reversed.length; index++)
                        reversed[index].id: index,
                    };
              return Column(
                children: [
                  _categorySelector(),
                  Expanded(
                    child: snapshot.connectionState == ConnectionState.waiting
                        ? const Center(child: CircularProgressIndicator())
                        : selected.isEmpty
                            ? showSettlements
                                ? _emptySettlements()
                                : _emptyChat()
                            : ScrollablePositionedList.builder(
                                itemScrollController: messageScrollController,
                                reverse: true,
                                padding:
                                    const EdgeInsets.fromLTRB(14, 8, 14, 12),
                                itemCount: reversed.length,
                                itemBuilder: (context, index) => showSettlements
                                    ? _settlementCard(reversed[index])
                                    : _messageBubble(reversed[index]),
                              ),
                  ),
                ],
              );
            },
          ),
        ),
        if (!showSettlements && isRecording) _recordingBar(),
        if (!showSettlements) _composerArea(),
      ]),
    );
  }

  Widget _categorySelector() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.light
                ? Colors.white
                : const Color(0xFF061321),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.light
                  ? AppColors.border
                  : const Color(0xFF24527A),
            ),
          ),
          child: Row(children: [
            Expanded(
              child: _categoryButton(
                selected: !showSettlements,
                icon: Icons.forum_rounded,
                label: 'Messages',
                onTap: () => setState(() => showSettlements = false),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _categoryButton(
                selected: showSettlements,
                icon: Icons.handshake_rounded,
                label: 'Settlements',
                onTap: () async {
                  if (isRecording) await _cancelRecording();
                  if (mounted) setState(() => showSettlements = true);
                },
              ),
            ),
          ]),
        ),
      );

  Widget _categoryButton({
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) =>
      Material(
        color: selected
            ? (Theme.of(context).brightness == Brightness.light
                ? AppColors.primary
                : const Color(0xFF7049E8))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon,
                  size: 18,
                  color: selected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 7),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: selected
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ),
      );

  Widget _emptyChat() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.forum_rounded, size: 62, color: Color(0xFF9B8EFF)),
            const SizedBox(height: 14),
            Text('Start the group conversation',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 7),
            Text('Send a message, sticker, voice note or poll.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
      );

  Widget _emptySettlements() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.handshake_outlined,
                size: 62, color: Color(0xFF65DDBA)),
            const SizedBox(height: 14),
            Text('No settlement activity yet',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 7),
            Text(
                'Settlement requests, reminders and confirmations will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
      );

  Widget _settlementCard(GroupMessage item) {
    final isConfirmed = item.text.startsWith('✅ ');
    final isReminder = item.text.startsWith('⏰ ');
    final color = isConfirmed
        ? const Color(0xFF65DDBA)
        : isReminder
            ? const Color(0xFFFFB45E)
            : const Color(0xFF9B8EFF);
    final title = isConfirmed
        ? 'Settlement confirmed'
        : isReminder
            ? 'Payment reminder'
            : 'Settlement requested';
    final description = item.text.replaceFirst(RegExp(r'^(?:💸|✅|⏰)️?\s*'), '');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
              isConfirmed
                  ? Icons.check_circle_rounded
                  : isReminder
                      ? Icons.notifications_active_rounded
                      : Icons.payments_rounded,
              color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(color: color, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            _mentionText(description, fontSize: 13.5),
            const SizedBox(height: 8),
            Text(
              '${item.senderName} • ${DateFormat('d MMM, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(item.createdAt))}',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 10),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _messageBubble(GroupMessage item) {
    final mine = item.senderId == widget.currentUid;
    final colors = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return ValueListenableBuilder<String?>(
      valueListenable: highlightedMessage,
      builder: (context, highlightedId, _) {
        final highlighted = highlightedId == item.id;
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: GestureDetector(
            onLongPress: () => _showMessageActions(item),
            onDoubleTap: item.kind == 'expenseDiscussion'
                ? () => _showExpenseDiscussionDetails(item)
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              constraints: const BoxConstraints(maxWidth: 310),
              margin: const EdgeInsets.only(bottom: 10),
              padding: item.kind == 'sticker'
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 7)
                  : const EdgeInsets.fromLTRB(13, 10, 13, 8),
              decoration: BoxDecoration(
                color: item.kind == 'sticker'
                    ? Colors.transparent
                    : mine
                        ? (isLight
                            ? const Color(0xFFEEEAFE)
                            : colors.primaryContainer)
                        : (isLight
                            ? AppColors.surface
                            : colors.surfaceContainerHigh),
                borderRadius: BorderRadius.circular(18).copyWith(
                  bottomRight: mine ? const Radius.circular(5) : null,
                  bottomLeft: mine ? null : const Radius.circular(5),
                ),
                border: highlighted
                    ? Border.all(color: const Color(0xFFFFB45E), width: 2.2)
                    : item.kind == 'sticker'
                        ? null
                        : Border.all(
                            color: isLight
                                ? AppColors.border
                                : mine
                                    ? colors.primary.withValues(alpha: .35)
                                    : colors.outlineVariant),
                boxShadow: highlighted
                    ? const [
                        BoxShadow(
                            color: Color(0x55FFB45E),
                            blurRadius: 18,
                            spreadRadius: 1)
                      ]
                    : null,
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!mine)
                      Text(item.senderName,
                          style: TextStyle(
                              color: colors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    if (!mine) const SizedBox(height: 3),
                    if (item.replyToId.isNotEmpty) ...[
                      _replyQuote(item),
                      const SizedBox(height: 7),
                    ],
                    _messageContent(item),
                    const SizedBox(height: 5),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                          DateFormat('h:mm a').format(
                              DateTime.fromMillisecondsSinceEpoch(
                                  item.createdAt)),
                          style: TextStyle(
                              color: colors.onSurfaceVariant, fontSize: 9)),
                      if (item.editedAt > 0) ...[
                        const SizedBox(width: 4),
                        Text('(edited)',
                            style: TextStyle(
                                color: colors.onSurfaceVariant, fontSize: 9)),
                      ],
                    ]),
                    _reactionSummary(item),
                  ]),
            ),
          ),
        );
      },
    );
  }

  Widget _replyQuote(GroupMessage item) {
    final colors = Theme.of(context).colorScheme;
    final repliesToMe = item.replyToSenderId == widget.currentUid;
    return Tooltip(
      message: 'Tap to view original message',
      child: InkWell(
        onTap: () => _jumpToMessage(item.replyToId),
        borderRadius: BorderRadius.circular(11),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 8, 7, 8),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.light
                ? const Color(0xFFE2DEFA)
                : colors.surface.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(11),
            border: Border(
              left: BorderSide(
                  color: repliesToMe ? const Color(0xFFFFB45E) : colors.primary,
                  width: 3),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        repliesToMe
                            ? 'Replying to you'
                            : item.replyToSenderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: repliesToMe
                                ? const Color(0xFFFFB45E)
                                : colors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(item.replyToText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 11,
                            height: 1.25)),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Icon(Icons.north_west_rounded,
                  size: 15, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _jumpToMessage(String messageId) async {
    final index = messageIndexes[messageId];
    if (index == null || !messageScrollController.isAttached) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('The original message is no longer available.'),
        duration: Duration(milliseconds: 2500),
      ));
      return;
    }
    final session = ++highlightSession;
    highlightedMessage.value = messageId;
    await messageScrollController.scrollTo(
      index: index,
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
      alignment: .35,
    );
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (!mounted || session != highlightSession) return;
    highlightedMessage.value = null;
  }

  Widget _messageContent(GroupMessage item) => switch (item.kind) {
        'sticker' => Text(item.text, style: const TextStyle(fontSize: 54)),
        'audio' => _AudioMessage(item: item),
        'poll' => _PollMessage(
            item: item,
            groupId: widget.group.id,
            currentUid: widget.currentUid,
            database: widget.database),
        'expenseDiscussion' => _expenseDiscussionMessage(item),
        _ => _mentionText(item.text),
      };

  Widget _expenseDiscussionMessage(GroupMessage item) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.report_problem_rounded,
                size: 17, color: Color(0xFFFFB45E)),
            SizedBox(width: 6),
            Text('Expense review',
                style: TextStyle(
                    color: Color(0xFFFFB45E), fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 6),
          _mentionText(item.text, fontSize: 13.5),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.light
                  ? AppColors.inputBackground
                  : Colors.black.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(Icons.receipt_long_rounded,
                  size: 18,
                  color: Theme.of(context).brightness == Brightness.light
                      ? AppColors.warning
                      : const Color(0xFFFFD75E)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(item.expenseTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              Text(formatMoney(item.expenseAmount, widget.group.currencyCode),
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ]),
          ),
          const SizedBox(height: 7),
          Text('Reason: ${item.discussionReason}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _showExpenseDiscussionDetails(item),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: const Text('Show details'),
            ),
          ),
        ],
      );

  Future<void> _showExpenseDiscussionDetails(GroupMessage item) async {
    if (item.transactionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Expense details are not available for this message.'),
        duration: Duration(milliseconds: 2500),
      ));
      return;
    }

    final entry = await widget.database
        .getTransaction(widget.group.id, item.transactionId);
    if (!mounted) return;
    if (entry == null || entry.isDeposit) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('This expense is no longer available.'),
        duration: Duration(milliseconds: 2500),
      ));
      return;
    }

    final members = {
      ...widget.group.formerMembers,
      ...widget.group.members,
    };
    final payer = members[entry.paidBy];
    final creator = members[entry.createdBy];
    final date = DateTime.fromMillisecondsSinceEpoch(entry.createdAt);
    const accent = Color(0xFFFFD75E);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .9,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(children: [
            Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.receipt_long_rounded, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Expense details',
                        style: Theme.of(sheetContext)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900)),
                    Text(entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Theme.of(sheetContext)
                                .colorScheme
                                .onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(sheetContext),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      accent.withValues(
                          alpha: Theme.of(sheetContext).brightness ==
                                  Brightness.light
                              ? .12
                              : .22),
                      Theme.of(sheetContext).brightness == Brightness.light
                          ? Theme.of(sheetContext)
                              .colorScheme
                              .surfaceContainerHighest
                          : const Color(0xFF171A27),
                    ]),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: accent.withValues(alpha: .35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TOTAL EXPENSE',
                          style: TextStyle(
                              color: Theme.of(sheetContext).brightness ==
                                      Brightness.light
                                  ? Theme.of(sheetContext)
                                      .colorScheme
                                      .onSurfaceVariant
                                  : Colors.white54,
                              fontSize: 11,
                              letterSpacing: 1.1)),
                      const SizedBox(height: 6),
                      Text(formatMoney(entry.amount, widget.group.currencyCode),
                          style: TextStyle(
                              color: _chatSurfaceAccent(sheetContext, accent),
                              fontSize: 32,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 5),
                      Text(
                        entry.paymentSource == 'wallet'
                            ? 'Paid from the group wallet'
                            : '${payer?.name ?? 'Former member'} paid personally',
                        style: TextStyle(
                            color: Theme.of(sheetContext)
                                .colorScheme
                                .onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB45E).withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: const Color(0xFFFFB45E).withValues(alpha: .25)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.forum_outlined,
                          size: 19, color: Color(0xFFFFB45E)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Discussion reason',
                                style: TextStyle(
                                    color: Color(0xFFFFB45E),
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text(item.discussionReason,
                                style: const TextStyle(height: 1.35)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      _expenseDetailRow('Category', entry.category),
                      _expenseDetailRow(
                          'Paid by', payer?.name ?? 'Former member'),
                      _expenseDetailRow(
                          'Added by', creator?.name ?? 'Former member'),
                      _expenseDetailRow(
                          'Payment source',
                          entry.paymentSource == 'wallet'
                              ? 'Group wallet'
                              : 'Personal money'),
                      if (entry.personalPaid > 0)
                        _expenseDetailRow(
                          'Outside wallet',
                          formatMoney(
                              entry.personalPaid, widget.group.currencyCode),
                          valueColor: const Color(0xFF62B8FF),
                        ),
                      _expenseDetailRow(
                          'Date', DateFormat('d MMM yyyy').format(date)),
                      _expenseDetailRow(
                          'Time', DateFormat('h:mm a').format(date),
                          showDivider: false),
                    ]),
                  ),
                ),
                if (entry.splitAmong.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Split shares',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: entry.splitAmong.entries.map((share) {
                        final member = members[share.key];
                        final settlement = entry.settlements[share.key];
                        final status = share.key == entry.paidBy
                            ? 'Paid the expense'
                            : settlement?.isConfirmed == true
                                ? 'Settled'
                                : settlement?.isPending == true
                                    ? 'Pending confirmation'
                                    : 'Unpaid';
                        return ListTile(
                          leading: _chatMemberAvatar(member),
                          title: Text(member?.name ?? 'Former member'),
                          subtitle: Text(status),
                          trailing: Text(
                              formatMoney(
                                  share.value, widget.group.currencyCode),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900)),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _expenseDetailRow(String label, String value,
          {Color? valueColor, bool showDivider = true}) =>
      Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 116,
              child: Text(label,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: valueColor, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        if (showDivider) const Divider(height: 1),
      ]);

  Widget _chatMemberAvatar(GroupMember? member) {
    final photoUri = Uri.tryParse(member?.photoUrl.trim() ?? '');
    final hasPhoto = photoUri != null &&
        (photoUri.scheme == 'https' || photoUri.scheme == 'http');
    final initial = member?.name.trim().isNotEmpty == true
        ? member!.name.trim()[0].toUpperCase()
        : '?';
    return CircleAvatar(
      foregroundColor: Colors.white,
      backgroundColor: Theme.of(context).brightness == Brightness.light
          ? AppColors.primary
          : const Color(0xFF514987),
      foregroundImage: hasPhoto ? NetworkImage(photoUri.toString()) : null,
      onForegroundImageError: hasPhoto ? (_, __) {} : null,
      child: Text(initial),
    );
  }

  Widget _mentionText(String text, {double fontSize = 15.5}) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final allMembers = {
      ...widget.group.formerMembers,
      ...widget.group.members,
    };
    final names = allMembers.values
        .map((member) => member.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    if (names.isEmpty) {
      return Text(text, style: TextStyle(fontSize: fontSize, height: 1.3));
    }
    final pattern = RegExp(
        '@(?:${names.map(RegExp.escape).join('|')})(?=\\s|[.,!?;:]|\$)',
        caseSensitive: false);
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final memberName = match.group(0)!.substring(1);
      final mentionsMe = allMembers[widget.currentUid]?.name.toLowerCase() ==
          memberName.toLowerCase();
      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(
          color: mentionsMe
              ? isLight
                  ? const Color(0xFF8A4700)
                  : const Color(0xFFFFD27A)
              : isLight
                  ? const Color(0xFF5141C5)
                  : const Color(0xFFBEB5FF),
          fontWeight: FontWeight.w900,
          backgroundColor: mentionsMe
              ? isLight
                  ? const Color(0x33E68A00)
                  : const Color(0x33FFB45E)
              : isLight
                  ? const Color(0xFFDCD6FF)
                  : const Color(0x229B8EFF),
        ),
      ));
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(
      TextSpan(children: spans),
      style: TextStyle(fontSize: fontSize, height: 1.3),
    );
  }

  Widget _reactionSummary(GroupMessage item) =>
      StreamBuilder<Map<String, String>>(
        stream: widget.database.watchMessageReactions(widget.group.id, item.id),
        builder: (context, snapshot) {
          final reactionsByUser = snapshot.data ?? const <String, String>{};
          if (reactionsByUser.isEmpty) return const SizedBox.shrink();
          final counts = <String, int>{};
          for (final emoji in reactionsByUser.values) {
            counts[emoji] = (counts[emoji] ?? 0) + 1;
          }
          return Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Wrap(
              spacing: 5,
              runSpacing: 4,
              children: counts.entries
                  .map((entry) => InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () =>
                            _showReactionMembers(entry.key, reactionsByUser),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.light
                                    ? AppColors.primaryTint
                                    : const Color(0xFF242638),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: Theme.of(context).brightness ==
                                        Brightness.light
                                    ? AppColors.border
                                    : const Color(0xFF3A3D54)),
                          ),
                          child: Text('${entry.key} ${entry.value}',
                              style: const TextStyle(fontSize: 11)),
                        ),
                      ))
                  .toList(),
            ),
          );
        },
      );

  Future<void> _showReactionMembers(
      String emoji, Map<String, String> reactionsByUser) {
    final members = reactionsByUser.entries
        .where((entry) => entry.value == emoji)
        .map((entry) => widget.group.members[entry.key])
        .whereType<GroupMember>()
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 10),
              Text('Reacted by',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('${members.length}',
                  style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.light
                          ? AppColors.textMuted
                          : Colors.white54)),
            ]),
            const SizedBox(height: 12),
            ...members.map((member) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text(member.name.isEmpty ? '?' : member.name[0]),
                  ),
                  title: Text(member.name),
                  subtitle: member.email.isEmpty ? null : Text(member.email),
                )),
          ]),
        ),
      ),
    );
  }

  Widget _recordingBar() {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isLight ? AppColors.expenseBackground : const Color(0xFF3A2029),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isLight ? AppColors.border : const Color(0xFF7B3D48)),
      ),
      child: Row(children: [
        const Icon(Icons.mic_rounded, color: Color(0xFFE05D69)),
        const SizedBox(width: 10),
        Expanded(
          child: ValueListenableBuilder<int>(
            valueListenable: recordedSeconds,
            builder: (context, seconds, _) => Text(
              'Recording voice note  0:${seconds.toString().padLeft(2, '0')} / 0:10',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ),
        TextButton(onPressed: _cancelRecording, child: const Text('Cancel')),
        IconButton.filled(
            onPressed: _stopAndSendRecording,
            icon: const Icon(Icons.send_rounded)),
      ]),
    );
  }

  Widget _composerArea() => ValueListenableBuilder<TextEditingValue>(
        valueListenable: message,
        builder: (context, value, _) {
          final mention = _activeMention(value);
          final matches = mention == null
              ? const <GroupMember>[]
              : widget.group.members.values
                  .where((member) => member.name
                      .toLowerCase()
                      .contains(mention.query.toLowerCase()))
                  .take(5)
                  .toList();
          return Column(mainAxisSize: MainAxisSize.min, children: [
            if (matches.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 190),
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Theme.of(context).dividerColor),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(
                            alpha:
                                Theme.of(context).brightness == Brightness.light
                                    ? .06
                                    : .16),
                        blurRadius: 18,
                        offset: const Offset(0, -4)),
                  ],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: matches.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 54),
                  itemBuilder: (context, index) {
                    final member = matches[index];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        child: Text(member.name.isEmpty ? '?' : member.name[0]),
                      ),
                      title: Text(member.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: member.uid == widget.currentUid
                          ? const Text('You')
                          : null,
                      trailing: Text('@',
                          style: TextStyle(
                              color: Theme.of(context).brightness ==
                                      Brightness.light
                                  ? AppColors.primary
                                  : const Color(0xFFB7AEFF),
                              fontSize: 20,
                              fontWeight: FontWeight.w900)),
                      onTap: () => _insertMention(member, value),
                    );
                  },
                ),
              ),
            _composer(),
          ]);
        },
      );

  ({int start, int end, String query})? _activeMention(TextEditingValue value) {
    final cursor = value.selection.isValid
        ? value.selection.baseOffset
        : value.text.length;
    if (cursor < 0 || cursor > value.text.length) return null;
    final beforeCursor = value.text.substring(0, cursor);
    final match = RegExp(r'(?:^|\s)@([^@\n]*)$').firstMatch(beforeCursor);
    if (match == null) return null;
    final atIndex = beforeCursor.lastIndexOf('@');
    if (atIndex < 0) return null;
    final rawQuery = match.group(1)!;
    final query = rawQuery.trim();
    if (rawQuery.endsWith(' ') &&
        widget.group.members.values.any(
            (member) => member.name.toLowerCase() == query.toLowerCase())) {
      return null;
    }
    return (start: atIndex, end: cursor, query: query);
  }

  void _insertMention(GroupMember member, TextEditingValue currentValue) {
    final mention = _activeMention(currentValue);
    if (mention == null) return;
    final replacement = '@${member.name} ';
    final updated =
        currentValue.text.replaceRange(mention.start, mention.end, replacement);
    final cursor = mention.start + replacement.length;
    message.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }

  Widget _composer() => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border:
                Border(top: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (replyingTo != null) ...[
              _composerReplyPreview(replyingTo!),
              const SizedBox(height: 8),
            ],
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              IconButton.filledTonal(
                onPressed: _createPoll,
                tooltip: 'Create poll',
                icon: const Icon(Icons.poll_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: message,
                  focusNode: messageFocus,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: replyingTo == null
                        ? 'Message or @mention'
                        : 'Reply to ${replyingTo!.senderName}',
                    prefixIcon: IconButton(
                      onPressed: _showStickerPicker,
                      tooltip: 'Emoji and stickers',
                      icon: const Icon(Icons.emoji_emotions_outlined),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  onSubmitted: (_) => _sendText(),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: message,
                builder: (context, value, _) {
                  final hasText = value.text.trim().isNotEmpty;
                  return IconButton.filled(
                    onPressed: isSendingAudio
                        ? null
                        : isRecording
                            ? _stopAndSendRecording
                            : hasText
                                ? _sendText
                                : _startRecording,
                    tooltip: isRecording
                        ? 'Send voice note'
                        : hasText
                            ? 'Send reply'
                            : 'Record up to 10 seconds',
                    icon: Icon(isRecording || hasText
                        ? Icons.send_rounded
                        : Icons.mic_rounded),
                  );
                },
              ),
            ]),
          ]),
        ),
      );

  Widget _composerReplyPreview(GroupMessage item) {
    final colors = Theme.of(context).colorScheme;
    final preview = switch (item.kind) {
      'audio' => 'Voice message',
      'poll' => 'Poll: ${item.pollQuestion}',
      'expenseDiscussion' => 'Expense: ${item.expenseTitle}',
      _ => item.text,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 8, 5, 8),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(13),
        border: Border(left: BorderSide(color: colors.primary, width: 3)),
      ),
      child: Row(children: [
        const Icon(Icons.reply_rounded, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Replying to ${item.senderName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: colors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: colors.onSurfaceVariant, fontSize: 11)),
            ],
          ),
        ),
        IconButton(
          onPressed: () => setState(() => replyingTo = null),
          tooltip: 'Cancel reply',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close_rounded, size: 19),
        ),
      ]),
    );
  }

  Future<void> _sendText() async {
    final value = message.text.trim();
    if (value.isEmpty) return;
    final reply = replyingTo;
    final mention = reply != null &&
            reply.senderId != widget.currentUid &&
            !value.toLowerCase().contains('@${reply.senderName.toLowerCase()}')
        ? '@${reply.senderName}, '
        : '';
    message.clear();
    setState(() => replyingTo = null);
    try {
      await widget.database.sendTextMessage(
        widget.group.id,
        '$mention$value',
        replyTo: reply,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => replyingTo = reply);
      message.text = value;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not send the reply. Please try again.'),
        duration: Duration(milliseconds: 2500),
      ));
    }
  }

  Future<void> _showStickerPicker() async {
    final sticker = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Send a feeling',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 14),
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 6,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: stickers
                      .map((emoji) => InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.pop(context, emoji),
                            child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                    color: Theme.of(context).brightness ==
                                            Brightness.light
                                        ? AppColors.primaryTint
                                        : const Color(0xFF202231),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: Theme.of(context).brightness ==
                                                Brightness.light
                                            ? AppColors.primaryBorder
                                            : const Color(0xFF34364A))),
                                child: Text(emoji,
                                    style: const TextStyle(fontSize: 28))),
                          ))
                      .toList(),
                ),
              ]),
        ),
      ),
    );
    if (sticker != null) {
      await widget.database
          .sendTextMessage(widget.group.id, sticker, sticker: true);
    }
  }

  Future<void> _showReactionPicker(GroupMessage item) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: reactions
                .map((reaction) => InkWell(
                      borderRadius: BorderRadius.circular(30),
                      onTap: () => Navigator.pop(context, reaction),
                      child: Padding(
                          padding: const EdgeInsets.all(9),
                          child: Text(reaction,
                              style: const TextStyle(fontSize: 29))),
                    ))
                .toList(),
          ),
        ),
      ),
    );
    if (emoji != null) {
      await widget.database.reactToMessage(widget.group.id, item.id, emoji);
    }
  }

  Future<void> _showMessageActions(GroupMessage item) async {
    final mine = item.senderId == widget.currentUid;
    final canEdit = mine && item.kind == 'text';
    final canDelete = mine || isAdmin;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading:
                  const Icon(Icons.reply_rounded, color: Color(0xFF9B8EFF)),
              title: const Text('Reply to message'),
              subtitle: Text('Reply and tag ${item.senderName}'),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
            ListTile(
              leading: const Icon(Icons.add_reaction_outlined,
                  color: Color(0xFFFFB45E)),
              title: const Text('React'),
              onTap: () => Navigator.pop(context, 'react'),
            ),
            if (canEdit)
              ListTile(
                leading:
                    const Icon(Icons.edit_rounded, color: Color(0xFF9B8EFF)),
                title: const Text('Edit message'),
                subtitle: const Text('Only text messages can be edited'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            if (canDelete)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFFF837A)),
                title: Text(mine ? 'Delete message' : 'Delete as admin'),
                subtitle: Text(mine
                    ? 'Remove your message for everyone'
                    : 'Remove ${item.senderName}\'s message for everyone'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ]),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'reply') {
      setState(() => replyingTo = item);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) messageFocus.requestFocus();
      });
    }
    if (action == 'react') await _showReactionPicker(item);
    if (action == 'edit') await _editMessage(item);
    if (action == 'delete') await _deleteMessage(item);
  }

  Future<void> _editMessage(GroupMessage item) async {
    final controller = TextEditingController(text: item.text);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 6,
          maxLength: 2000,
          decoration: const InputDecoration(hintText: 'Message'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    final value = controller.text.trim();
    controller.dispose();
    if (save != true || value.isEmpty || value == item.text) return;
    await widget.database.editTextMessage(widget.group.id, item.id, value);
  }

  Future<void> _deleteMessage(GroupMessage item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: Text(item.senderId == widget.currentUid
            ? 'This message will be removed for everyone.'
            : 'Remove ${item.senderName}\'s message for everyone?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD94C5C)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.database.deleteMessage(widget.group.id, item.id);
  }

  Future<void> _startRecording() async {
    if (!await recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Microphone permission is required for voice notes.')));
      }
      return;
    }
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}${Platform.pathSeparator}frensplit_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await recorder.start(
      const RecordConfig(
          encoder: AudioEncoder.aacLc, bitRate: 32000, sampleRate: 16000),
      path: path,
    );
    final session = ++recordingSession;
    if (!mounted) return;
    recordedSeconds.value = 0;
    setState(() => isRecording = true);
    for (var second = 1; second <= 10; second++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted || !isRecording || recordingSession != session) return;
      recordedSeconds.value = second;
      if (second == 10) await _stopAndSendRecording();
    }
  }

  Future<void> _cancelRecording() async {
    recordingSession++;
    final path = await recorder.stop();
    if (path != null) await File(path).delete().catchError((_) => File(path));
    if (mounted) setState(() => isRecording = false);
  }

  Future<void> _stopAndSendRecording() async {
    if (!isRecording) return;
    recordingSession++;
    final duration = recordedSeconds.value.clamp(1, 10);
    setState(() {
      isRecording = false;
      isSendingAudio = true;
    });
    final path = await recorder.stop();
    if (path != null) {
      final file = File(path);
      final encoded = base64Encode(await file.readAsBytes());
      await widget.database.sendAudioMessage(
          groupId: widget.group.id,
          audioBase64: encoded,
          durationSeconds: duration);
      await file.delete().catchError((_) => file);
    }
    if (mounted) setState(() => isSendingAudio = false);
  }

  Future<void> _createPoll() async {
    final question = TextEditingController();
    final options = List.generate(4, (_) => TextEditingController());
    String? error;
    final create = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .86,
        child: StatefulBuilder(
          builder: (context, setLocalState) => Padding(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.light
                        ? AppColors.primaryLight
                        : const Color(0xFF9B8EFF).withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.poll_rounded,
                      color: Theme.of(context).brightness == Brightness.light
                          ? AppColors.primary
                          : const Color(0xFFB7AEFF)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Create a poll',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900)),
                      Text('Ask the group and decide together',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.pop(context, false);
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(children: [
                    TextField(
                      controller: question,
                      maxLength: 180,
                      minLines: 2,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Your question',
                        hintText: 'Where should we go this weekend?',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.help_outline_rounded,
                            color: Color(0xFF9B8EFF)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (var index = 0; index < options.length; index++) ...[
                      TextField(
                        controller: options[index],
                        maxLength: 80,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: index < 2
                              ? 'Option ${index + 1}'
                              : 'Option ${index + 1} (optional)',
                          counterText: '',
                          prefixIcon: CircleAvatar(
                            radius: 12,
                            backgroundColor:
                                Theme.of(context).brightness == Brightness.light
                                    ? AppColors.primaryLight
                                    : const Color(0xFF34304F),
                            child: Text('${index + 1}',
                                style: TextStyle(
                                    color: Theme.of(context).brightness ==
                                            Brightness.light
                                        ? AppColors.primary
                                        : const Color(0xFFCEC7FF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ]),
                ),
              ),
              if (error != null) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF837A).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 18, color: Color(0xFFFF837A)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(error!)),
                  ]),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: () {
                    final values = options
                        .map((item) => item.text.trim())
                        .where((item) => item.isNotEmpty)
                        .toList();
                    if (question.text.trim().isEmpty) {
                      setLocalState(() => error = 'Enter a poll question.');
                    } else if (values.length < 2) {
                      setLocalState(
                          () => error = 'Add at least two poll options.');
                    } else {
                      FocusManager.instance.primaryFocus?.unfocus();
                      Navigator.pop(context, true);
                    }
                  },
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Create poll'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    final questionText = question.text.trim();
    final values = options
        .map((item) => item.text.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    // The bottom sheet pop future resolves before its reverse animation has
    // fully detached the text fields. Wait for that route to unmount before
    // disposing controllers to avoid inherited-widget lifecycle assertions.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    question.dispose();
    for (final option in options) {
      option.dispose();
    }
    if (create != true) return;
    await widget.database.createPoll(
        groupId: widget.group.id, question: questionText, options: values);
  }
}

class _AudioMessage extends StatefulWidget {
  const _AudioMessage({required this.item});
  final GroupMessage item;

  @override
  State<_AudioMessage> createState() => _AudioMessageState();
}

class _AudioMessageState extends State<_AudioMessage> {
  final player = AudioPlayer();
  bool playing = false;
  String? path;

  @override
  void initState() {
    super.initState();
    player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => playing = false);
    });
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  Future<void> toggle() async {
    if (playing) {
      await player.stop();
      if (mounted) setState(() => playing = false);
      return;
    }
    path ??= await _writeAudio();
    await player.play(DeviceFileSource(path!));
    if (mounted) setState(() => playing = true);
  }

  Future<String> _writeAudio() async {
    final directory = await getTemporaryDirectory();
    final output =
        '${directory.path}${Platform.pathSeparator}chat_${widget.item.id}.m4a';
    await File(output)
        .writeAsBytes(base64Decode(widget.item.audioBase64), flush: true);
    return output;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 210,
        child: Row(children: [
          IconButton.filledTonal(
              onPressed: toggle,
              icon: Icon(
                  playing ? Icons.stop_rounded : Icons.play_arrow_rounded)),
          const SizedBox(width: 8),
          Expanded(
              child: LinearProgressIndicator(
                  value: playing ? null : 0,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 9),
          Text(
              '0:${widget.item.audioDurationSeconds.toString().padLeft(2, '0')}'),
        ]),
      );
}

class _PollMessage extends StatelessWidget {
  const _PollMessage({
    required this.item,
    required this.groupId,
    required this.currentUid,
    required this.database,
  });

  final GroupMessage item;
  final String groupId;
  final String currentUid;
  final DatabaseService database;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 270,
        child: StreamBuilder<Map<String, String>>(
          stream: database.watchPollVotes(groupId, item.id),
          builder: (context, snapshot) {
            final votes = snapshot.data ?? {};
            final selected = votes[currentUid];
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.poll_rounded,
                        color: Color(0xFFFFB45E), size: 19),
                    const SizedBox(width: 7),
                    Expanded(
                        child: Text(item.pollQuestion,
                            style:
                                const TextStyle(fontWeight: FontWeight.w900))),
                  ]),
                  const SizedBox(height: 10),
                  ...item.pollOptions.entries.map((option) {
                    final count = votes.values
                        .where((value) => value == option.key)
                        .length;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () =>
                            database.votePoll(groupId, item.id, option.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 9),
                          decoration: BoxDecoration(
                            color: selected == option.key
                                ? const Color(0xFF5B528F)
                                : Colors.white.withValues(alpha: .06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: selected == option.key
                                    ? const Color(0xFF9B8EFF)
                                    : Colors.white12),
                          ),
                          child: Row(children: [
                            Expanded(child: Text(option.value)),
                            Text('$count',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900)),
                          ]),
                        ),
                      ),
                    );
                  }),
                  Text('${votes.length} vote${votes.length == 1 ? '' : 's'}',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11)),
                ]);
          },
        ),
      );
}
