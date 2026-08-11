import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/app_models.dart';
import '../services/database_service.dart';

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
  final recorder = AudioRecorder();
  bool isRecording = false;
  bool isSendingAudio = false;
  int recordedSeconds = 0;
  int recordingSession = 0;
  int lastMarkedReadAt = 0;

  bool get isAdmin => widget.group.ownerId == widget.currentUid;

  @override
  void dispose() {
    recordingSession++;
    recorder.dispose();
    message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(children: [
            CircleAvatar(child: Text(widget.group.emoji)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 17)),
                    Text('${widget.group.members.length} members',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11)),
                  ]),
            ),
          ]),
        ),
        body: Column(children: [
          Expanded(
            child: StreamBuilder<List<GroupMessage>>(
              stream: widget.database.watchMessages(widget.group.id),
              builder: (context, snapshot) {
                final messages = snapshot.data ?? [];
                if (messages.isNotEmpty &&
                    messages.last.createdAt > lastMarkedReadAt) {
                  lastMarkedReadAt = messages.last.createdAt;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    widget.database
                        .markChatRead(widget.group.id, lastMarkedReadAt);
                  });
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (messages.isEmpty) return _emptyChat();
                final reversed = messages.reversed.toList();
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  itemCount: reversed.length,
                  itemBuilder: (context, index) =>
                      _messageBubble(reversed[index]),
                );
              },
            ),
          ),
          if (isRecording) _recordingBar(),
          _composerArea(),
        ]),
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
            const Text('Send a message, sticker, voice note or poll.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54)),
          ]),
        ),
      );

  Widget _messageBubble(GroupMessage item) {
    final mine = item.senderId == widget.currentUid;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageActions(item),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 310),
          margin: const EdgeInsets.only(bottom: 10),
          padding: item.kind == 'sticker'
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 7)
              : const EdgeInsets.fromLTRB(13, 10, 13, 8),
          decoration: BoxDecoration(
            color: item.kind == 'sticker'
                ? Colors.transparent
                : mine
                    ? const Color(0xFF4A427D)
                    : const Color(0xFF171925),
            borderRadius: BorderRadius.circular(18).copyWith(
              bottomRight: mine ? const Radius.circular(5) : null,
              bottomLeft: mine ? null : const Radius.circular(5),
            ),
            border: item.kind == 'sticker'
                ? null
                : Border.all(
                    color: mine
                        ? const Color(0xFF665D9E)
                        : const Color(0xFF292C3B)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!mine)
              Text(item.senderName,
                  style: const TextStyle(
                      color: Color(0xFF65DDBA),
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            if (!mine) const SizedBox(height: 3),
            _messageContent(item),
            const SizedBox(height: 5),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                  DateFormat('h:mm a').format(
                      DateTime.fromMillisecondsSinceEpoch(item.createdAt)),
                  style: const TextStyle(color: Colors.white38, fontSize: 9)),
              if (item.editedAt > 0) ...[
                const SizedBox(width: 4),
                const Text('(edited)',
                    style: TextStyle(color: Colors.white38, fontSize: 9)),
              ],
            ]),
            _reactionSummary(item),
          ]),
        ),
      ),
    );
  }

  Widget _messageContent(GroupMessage item) => switch (item.kind) {
        'sticker' => Text(item.text, style: const TextStyle(fontSize: 54)),
        'audio' => _AudioMessage(item: item),
        'poll' => _PollMessage(
            item: item,
            groupId: widget.group.id,
            currentUid: widget.currentUid,
            database: widget.database),
        _ => _mentionText(item.text),
      };

  Widget _mentionText(String text) {
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
      return Text(text, style: const TextStyle(fontSize: 15.5, height: 1.3));
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
          color: mentionsMe ? const Color(0xFFFFD27A) : const Color(0xFFBEB5FF),
          fontWeight: FontWeight.w900,
          backgroundColor:
              mentionsMe ? const Color(0x33FFB45E) : const Color(0x229B8EFF),
        ),
      ));
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(
      TextSpan(children: spans),
      style: const TextStyle(fontSize: 15.5, height: 1.3),
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
                            color: const Color(0xFF242638),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF3A3D54)),
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
                  style: const TextStyle(color: Colors.white54)),
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

  Widget _recordingBar() => Container(
        margin: const EdgeInsets.fromLTRB(14, 4, 14, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF3A2029),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF7B3D48)),
        ),
        child: Row(children: [
          const Icon(Icons.mic_rounded, color: Color(0xFFFF837A)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(
                  'Recording voice note  0:${recordedSeconds.toString().padLeft(2, '0')} / 0:10')),
          TextButton(onPressed: _cancelRecording, child: const Text('Cancel')),
          IconButton.filled(
              onPressed: _stopAndSendRecording,
              icon: const Icon(Icons.send_rounded)),
        ]),
      );

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
                  color: const Color(0xFF1A1C29),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF35384B)),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black38,
                        blurRadius: 18,
                        offset: Offset(0, -4)),
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
                      trailing: const Text('@',
                          style: TextStyle(
                              color: Color(0xFFB7AEFF),
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
          decoration: const BoxDecoration(
            color: Color(0xFF101119),
            border: Border(top: BorderSide(color: Color(0xFF252836))),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton.filledTonal(
              onPressed: _createPoll,
              tooltip: 'Create poll',
              icon: const Icon(Icons.poll_rounded),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: message,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Message or @mention',
                  prefixIcon: IconButton(
                    onPressed: _showStickerPicker,
                    tooltip: 'Emoji and stickers',
                    icon: const Icon(Icons.emoji_emotions_outlined),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                          ? 'Send message'
                          : 'Record up to 10 seconds',
                  icon: Icon(isRecording || hasText
                      ? Icons.send_rounded
                      : Icons.mic_rounded),
                );
              },
            ),
          ]),
        ),
      );

  Future<void> _sendText() async {
    final value = message.text.trim();
    if (value.isEmpty) return;
    message.clear();
    await widget.database.sendTextMessage(widget.group.id, value);
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
                                    color: const Color(0xFF202231),
                                    borderRadius: BorderRadius.circular(14)),
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
    setState(() {
      isRecording = true;
      recordedSeconds = 0;
    });
    for (var second = 1; second <= 10; second++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted || !isRecording || recordingSession != session) return;
      setState(() => recordedSeconds = second);
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
    final duration = recordedSeconds.clamp(1, 10);
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
                    color: const Color(0xFF9B8EFF).withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child:
                      const Icon(Icons.poll_rounded, color: Color(0xFFB7AEFF)),
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
                      const Text('Ask the group and decide together',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 12)),
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
                            backgroundColor: const Color(0xFF34304F),
                            child: Text('${index + 1}',
                                style: const TextStyle(
                                    color: Color(0xFFCEC7FF),
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
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11)),
                ]);
          },
        ),
      );
}
