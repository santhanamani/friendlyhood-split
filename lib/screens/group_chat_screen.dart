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
          _composer(),
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
        onLongPress: () => _showReactionPicker(item),
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
              const SizedBox(width: 8),
              _reactionSummary(item),
            ]),
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
        _ =>
          Text(item.text, style: const TextStyle(fontSize: 15.5, height: 1.3)),
      };

  Widget _reactionSummary(GroupMessage item) =>
      StreamBuilder<Map<String, String>>(
        stream: widget.database.watchMessageReactions(widget.group.id, item.id),
        builder: (context, snapshot) {
          final values =
              snapshot.data?.values ?? const Iterable<String>.empty();
          if (values.isEmpty) return const SizedBox.shrink();
          final counts = <String, int>{};
          for (final emoji in values) {
            counts[emoji] = (counts[emoji] ?? 0) + 1;
          }
          return Text(
              counts.entries
                  .map((entry) => '${entry.key}${entry.value}')
                  .join(' '),
              style: const TextStyle(fontSize: 10));
        },
      );

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

  Widget _composer() => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
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
            IconButton(
              onPressed: _showStickerPicker,
              tooltip: 'Emoji and stickers',
              icon: const Icon(Icons.emoji_emotions_outlined),
            ),
            Expanded(
              child: TextField(
                controller: message,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Message the group',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 15, vertical: 11),
                ),
                onSubmitted: (_) => _sendText(),
              ),
            ),
            const SizedBox(width: 5),
            IconButton.filled(
              onPressed: isSendingAudio
                  ? null
                  : isRecording
                      ? _stopAndSendRecording
                      : _startRecording,
              tooltip:
                  isRecording ? 'Send voice note' : 'Record up to 10 seconds',
              icon: Icon(isRecording ? Icons.send_rounded : Icons.mic_rounded),
            ),
            IconButton(
              onPressed: _sendText,
              tooltip: 'Send message',
              icon: const Icon(Icons.send_rounded),
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
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create a poll'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: question,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Question')),
            const SizedBox(height: 12),
            for (var index = 0; index < options.length; index++) ...[
              TextField(
                  controller: options[index],
                  decoration: InputDecoration(
                      labelText:
                          'Option ${index + 1}${index > 1 ? ' (optional)' : ''}')),
              const SizedBox(height: 9),
            ],
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create poll')),
        ],
      ),
    );
    final values = options
        .map((item) => item.text.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (create != true) return;
    if (question.text.trim().isEmpty || values.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Enter a question and at least two options.')));
      }
      return;
    }
    await widget.database.createPoll(
        groupId: widget.group.id, question: question.text, options: values);
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
