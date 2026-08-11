import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/app_models.dart';
import '../models/currency_data.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import 'about_screen.dart';
import 'group_chat_screen.dart';

InputDecoration _dropdownDecoration(String label, IconData icon) =>
    InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF9B8EFF)),
      prefixIconConstraints: const BoxConstraints(minWidth: 46),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
      filled: true,
      fillColor: const Color(0xFF1B1D2B),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF37344D)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF9B8EFF), width: 1.5),
      ),
    );

InputDecoration _amountDecoration(String currencyCode) => InputDecoration(
      labelText: 'Amount',
      hintText: '0.00',
      prefixIcon: Center(
        widthFactor: 1,
        child: Text(currencyForCode(currencyCode).symbol,
            style: const TextStyle(
                color: Color(0xFF65DDBA),
                fontSize: 20,
                fontWeight: FontWeight.w700)),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 46),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      filled: true,
      fillColor: const Color(0xFF202333),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF55506F), width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF9B8EFF), width: 2),
      ),
    );

class _DropdownChoice {
  const _DropdownChoice({
    required this.value,
    required this.label,
    this.subtitle,
    this.avatarText,
    this.isArchived = false,
  });

  final String value;
  final String label;
  final String? subtitle;
  final String? avatarText;
  final bool isArchived;

  bool matches(String query) {
    final search = query.trim().toLowerCase();
    return search.isEmpty ||
        label.toLowerCase().contains(search) ||
        value.toLowerCase().contains(search) ||
        (subtitle?.toLowerCase().contains(search) ?? false);
  }
}

class _FriendlyDropdown extends StatelessWidget {
  const _FriendlyDropdown({
    required this.value,
    required this.label,
    required this.leadingIcon,
    required this.items,
    required this.onChanged,
  });

  final String value;
  final String label;
  final IconData leadingIcon;
  final List<_DropdownChoice> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = items.where((item) => item.value == value).firstOrNull;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: items.isEmpty ? null : () => _openPicker(context),
      child: InputDecorator(
        isEmpty: selected == null,
        decoration: _dropdownDecoration(label, leadingIcon),
        child: Row(children: [
          Expanded(
            child: Text(
              selected?.label ?? 'Select an option',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: selected == null ? Colors.white54 : Colors.white),
            ),
          ),
          if (selected?.isArchived == true) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB45E).withValues(alpha: .13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('Removed',
                  style: TextStyle(
                      color: Color(0xFFFFB45E),
                      fontSize: 10,
                      fontWeight: FontWeight.w800)),
            ),
          ],
          const SizedBox(width: 8),
          const Icon(Icons.keyboard_arrow_down_rounded,
              color: Color(0xFFB7AEFF)),
        ]),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    var query = '';
    final selectedValue = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: items.length > 5 ? .72 : .5,
        child: StatefulBuilder(
          builder: (context, setLocalState) {
            final visible = items.where((item) => item.matches(query)).toList();
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  18, 0, 18, MediaQuery.viewInsetsOf(context).bottom + 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFF9B8EFF).withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child:
                            Icon(leadingIcon, color: const Color(0xFFB7AEFF)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Select $label',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900)),
                      ),
                      IconButton(
                        onPressed: () async {
                          FocusManager.instance.primaryFocus?.unfocus();
                          await Future<void>.delayed(
                              const Duration(milliseconds: 120));
                          if (context.mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ]),
                    if (items.length > 5) ...[
                      const SizedBox(height: 14),
                      TextField(
                        onChanged: (value) =>
                            setLocalState(() => query = value),
                        decoration: const InputDecoration(
                          hintText: 'Search...',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Expanded(
                      child: visible.isEmpty
                          ? const Center(child: Text('No matching option'))
                          : ListView.separated(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              itemCount: visible.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1, indent: 54),
                              itemBuilder: (context, index) {
                                final item = visible[index];
                                final isSelected = item.value == value;
                                return ListTile(
                                  contentPadding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  leading: item.avatarText == null
                                      ? Icon(leadingIcon,
                                          color: const Color(0xFF9B8EFF))
                                      : CircleAvatar(
                                          radius: 17,
                                          child: Text(item.avatarText!),
                                        ),
                                  title: Row(children: [
                                    Flexible(child: Text(item.label)),
                                    if (item.isArchived) ...[
                                      const SizedBox(width: 8),
                                      const Text('Removed member',
                                          style: TextStyle(
                                              color: Color(0xFFFFB45E),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800)),
                                    ],
                                  ]),
                                  subtitle: item.subtitle == null
                                      ? null
                                      : Text(item.subtitle!),
                                  trailing: isSelected
                                      ? const Icon(Icons.check_circle_rounded,
                                          color: Color(0xFF65DDBA))
                                      : null,
                                  onTap: () async {
                                    FocusManager.instance.primaryFocus
                                        ?.unfocus();
                                    await Future<void>.delayed(
                                        const Duration(milliseconds: 120));
                                    if (context.mounted) {
                                      Navigator.pop(context, item.value);
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                  ]),
            );
          },
        ),
      ),
    );
    if (selectedValue != null) onChanged(selectedValue);
  }
}

class _TransactionTypeSelector extends StatelessWidget {
  const _TransactionTypeSelector({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 52,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF12141E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF454159)),
        ),
        child: Row(
          children: [
            _option('expense', 'Expense', Icons.receipt_long_rounded),
            const SizedBox(width: 4),
            _option('contribution', 'Deposit', Icons.savings_rounded),
          ],
        ),
      );

  Widget _option(String option, String label, IconData icon) {
    final selected = value == option;
    return Expanded(
      child: InkWell(
        onTap: () => onChanged(option),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF57508E) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18, color: selected ? Colors.white : Colors.white60),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

OverlayEntry? _activeWarningToast;

void _showWarningToast(BuildContext context, String message) {
  _activeWarningToast?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) => Positioned(
      left: 20,
      right: 20,
      bottom: MediaQuery.viewInsetsOf(overlayContext).bottom + 24,
      child: SafeArea(
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFE0525E),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black54,
                      blurRadius: 24,
                      offset: Offset(0, 10)),
                ],
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(message,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700))),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
  _activeWarningToast = entry;
  Overlay.of(context, rootOverlay: true).insert(entry);
  Future<void>.delayed(const Duration(milliseconds: 2500), () {
    if (_activeWarningToast == entry) {
      entry.remove();
      _activeWarningToast = null;
    }
  });
}

Future<DateTime?> _pickTransactionDateTime(
    BuildContext context, DateTime initial) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime.now().add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

Widget _transactionDateTimeField(DateTime value, VoidCallback onTap) =>
    Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1D2B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF37344D)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.event_rounded, color: Color(0xFF9B8EFF)),
        title: const Text('Transaction date & time',
            style: TextStyle(color: Colors.white60, fontSize: 12)),
        subtitle: Text(DateFormat('d MMM yyyy, h:mm a').format(value),
            style: const TextStyle(fontWeight: FontWeight.w800)),
        trailing: const Icon(Icons.edit_calendar_rounded),
      ),
    );

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user});
  final User user;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final DatabaseService database = DatabaseService(widget.user);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<SplitGroup>>(
          stream: database.watchGroups(),
          builder: (context, snapshot) {
            final groups = snapshot.data ?? [];
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  sliver: SliverToBoxAdapter(child: _header()),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(child: _hero(groups)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Text('Your circles',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const Spacer(),
                        Text('${groups.length} groups',
                            style: const TextStyle(color: Colors.white54)),
                      ],
                    ),
                  ),
                ),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()))
                else if (groups.isEmpty)
                  SliverFillRemaining(
                      hasScrollBody: false, child: _emptyState())
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    sliver: SliverList.separated(
                      itemCount: groups.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _GroupCard(
                        group: groups[index],
                        database: database,
                        currentUid: widget.user.uid,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showGroupActions,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add group'),
      ),
    );
  }

  Widget _header() => Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: const Color(0xFF29263F),
            backgroundImage: widget.user.photoURL == null
                ? null
                : NetworkImage(widget.user.photoURL!),
            child: widget.user.photoURL == null
                ? Text((widget.user.displayName ?? 'F')[0])
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Good to see you',
                    style: TextStyle(color: Colors.white54)),
                Text(widget.user.displayName ?? 'Friend',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 17)),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Copy my member ID',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.user.uid));
              _message('Member ID copied');
            },
            icon: const Icon(Icons.badge_outlined),
          ),
          IconButton(
            tooltip: 'About BroSplit',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
            icon: const Icon(Icons.info_outline_rounded),
          ),
          IconButton(
              onPressed: AuthService().signOut,
              icon: const Icon(Icons.logout_rounded)),
        ],
      );

  Widget _hero(List<SplitGroup> groups) => Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF745CFF), Color(0xFF4738AE), Color(0xFF252055)],
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x445F4AE3), blurRadius: 35, offset: Offset(0, 15))
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CONNECTED MONEY',
                      style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.6,
                          color: Colors.white70)),
                  const SizedBox(height: 10),
                  Text('${groups.length}',
                      style: const TextStyle(
                          fontSize: 38,
                          height: 1,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  const Text('active money circles',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .12),
                  shape: BoxShape.circle),
              child: const Icon(Icons.blur_circular_rounded, size: 40),
            ),
          ],
        ),
      );

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.group_add_rounded,
                  size: 68, color: Color(0xFF8B7CFF)),
              const SizedBox(height: 18),
              Text('Start your first circle',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                  'Create a group for a trip, flat, food or anything you share.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      );

  Future<void> _createGroup() async {
    final name = TextEditingController();
    final defaultCurrencyCode = defaultCurrencyCodeForLocale(
        WidgetsBinding.instance.platformDispatcher.locale);
    final defaultCurrency = currencyForCode(defaultCurrencyCode);
    String emoji = '✈️';
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          scrollable: true,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          title: const Text('Create a money circle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: ['✈️', '🍕', '🏠', '🎉', '🏏']
                    .map((item) => ChoiceChip(
                          label:
                              Text(item, style: const TextStyle(fontSize: 20)),
                          selected: emoji == item,
                          onSelected: (_) => setLocalState(() => emoji = item),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 18),
              TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'Group name', hintText: 'Goa getaway')),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(defaultCurrency.flag,
                    style: const TextStyle(fontSize: 26)),
                title:
                    Text('${defaultCurrency.symbol}  ${defaultCurrency.code}'),
                subtitle: const Text('Default from your device region'),
                trailing: const Icon(Icons.public_rounded),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  Navigator.pop(context, false);
                },
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  Navigator.pop(context, true);
                },
                child: const Text('Create')),
          ],
        ),
      ),
    );
    if (created == true && name.text.trim().isNotEmpty) {
      await database.createGroup(name.text.trim(), emoji, defaultCurrencyCode);
      _message('Group created — you are the admin');
    }
  }

  Future<void> _showGroupActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.add_rounded)),
              title: const Text('Create new group'),
              subtitle: const Text('You will be the group admin'),
              onTap: () => Navigator.pop(context, 'create'),
            ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.key_rounded)),
              title: const Text('Join with access code'),
              subtitle:
                  const Text('Enter the 8-character code shared by an admin'),
              onTap: () => Navigator.pop(context, 'join'),
            ),
          ]),
        ),
      ),
    );
    if (action == 'create') await _createGroup();
    if (action == 'join') await _joinGroup();
  }

  Future<void> _joinGroup() async {
    final code = TextEditingController();
    final join = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join a group'),
        content: TextField(
          controller: code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]'))
          ],
          maxLength: 8,
          decoration: const InputDecoration(
            labelText: 'Access code',
            hintText: 'ABCD2345',
            prefixIcon: Icon(Icons.key_rounded),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Join')),
        ],
      ),
    );
    if (join != true) return;
    try {
      await database.joinGroup(code.text);
      _message('Connected to the group');
    } catch (error) {
      _message(error
          .toString()
          .replaceFirst(RegExp(r'^(Bad state|Invalid argument): '), ''));
    }
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
    }
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard(
      {required this.group, required this.database, required this.currentUid});
  final SplitGroup group;
  final DatabaseService database;
  final String currentUid;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GroupScreen(
                    group: group, database: database, currentUid: currentUid),
              )),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: const Color(0xFF242137),
                      borderRadius: BorderRadius.circular(18)),
                  child:
                      Text(group.emoji, style: const TextStyle(fontSize: 27)),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                            child: Text(group.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17))),
                        if (group.ownerId == currentUid) ...[
                          const SizedBox(width: 7),
                          const Icon(Icons.verified_rounded,
                              size: 16, color: Color(0xFF65DDBA)),
                        ],
                      ]),
                      const SizedBox(height: 5),
                      Text(
                          '${group.members.length} members • ${group.ownerId == currentUid ? 'Admin' : 'Member'}',
                          style: const TextStyle(color: Colors.white54)),
                    ],
                  ),
                ),
                _GroupCardChatStatus(
                  database: database,
                  groupId: group.id,
                  mentionName: group.members[currentUid]?.name,
                ),
              ],
            ),
          ),
        ),
      );
}

class _GroupCardChatStatus extends StatefulWidget {
  const _GroupCardChatStatus(
      {required this.database, required this.groupId, this.mentionName});
  final DatabaseService database;
  final String groupId;
  final String? mentionName;

  @override
  State<_GroupCardChatStatus> createState() => _GroupCardChatStatusState();
}

class _GroupCardChatStatusState extends State<_GroupCardChatStatus> {
  late Stream<ChatBadge> stream;

  @override
  void initState() {
    super.initState();
    stream = widget.database
        .watchChatBadge(widget.groupId, mentionName: widget.mentionName);
  }

  @override
  void didUpdateWidget(covariant _GroupCardChatStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId != widget.groupId ||
        oldWidget.database != widget.database ||
        oldWidget.mentionName != widget.mentionName) {
      stream = widget.database
          .watchChatBadge(widget.groupId, mentionName: widget.mentionName);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<ChatBadge>(
        stream: stream,
        initialData: ChatBadge.empty,
        builder: (context, snapshot) {
          final badge = snapshot.data ?? ChatBadge.empty;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            if (badge.hasMention)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB45E).withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('@',
                    style: TextStyle(
                        color: Color(0xFFFFC978), fontWeight: FontWeight.w900)),
              ),
            if (badge.unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                constraints: const BoxConstraints(minWidth: 24),
                decoration: BoxDecoration(
                  color: const Color(0xFFD94C5C),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(badge.countLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900)),
              ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 15, color: Colors.white38),
          ]);
        },
      );
}

class _ChatIconWithBadge extends StatelessWidget {
  const _ChatIconWithBadge({required this.badge});
  final ChatBadge badge;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 32,
        height: 32,
        child: Stack(clipBehavior: Clip.none, children: [
          const Center(child: Icon(Icons.forum_rounded)),
          if (badge.unreadCount > 0)
            Positioned(
              right: -8,
              top: -8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                constraints: const BoxConstraints(minWidth: 19),
                decoration: BoxDecoration(
                  color: const Color(0xFFD94C5C),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF12131A), width: 2),
                ),
                child: Text(badge.countLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900)),
              ),
            ),
          if (badge.hasMention)
            Positioned(
              left: -7,
              bottom: -7,
              child: Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB45E),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF12131A), width: 2),
                ),
                child: const Text('@',
                    style: TextStyle(
                        color: Color(0xFF231B11),
                        fontSize: 10,
                        fontWeight: FontWeight.w900)),
              ),
            ),
        ]),
      );
}

class GroupScreen extends StatefulWidget {
  const GroupScreen(
      {super.key,
      required this.group,
      required this.database,
      required this.currentUid});
  final SplitGroup group;
  final DatabaseService database;
  final String currentUid;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  late SplitGroup group = widget.group;
  late final Stream<ChatBadge> chatBadgeStream = widget.database.watchChatBadge(
      widget.group.id,
      mentionName: widget.group.members[widget.currentUid]?.name);
  DatabaseService get database => widget.database;
  String get currentUid => widget.currentUid;

  bool get isAdmin => group.ownerId == currentUid;

  List<GroupMember> get orderedMembers {
    final members = group.members.values.toList();
    members.sort((a, b) {
      if (a.uid == currentUid) return -1;
      if (b.uid == currentUid) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return members;
  }

  List<_DropdownChoice> _memberChoices({String? includeFormerUid}) {
    final choices = orderedMembers
        .map((member) => _DropdownChoice(
              value: member.uid,
              label: member.name,
              subtitle: member.email.isEmpty ? 'Active member' : member.email,
              avatarText: member.name.isEmpty ? '?' : member.name[0],
            ))
        .toList();
    if (includeFormerUid != null &&
        !group.members.containsKey(includeFormerUid)) {
      final former = group.formerMembers[includeFormerUid];
      final name = former?.name.trim();
      choices.insert(
        0,
        _DropdownChoice(
          value: includeFormerUid,
          label: name == null || name.isEmpty ? 'Former member' : name,
          subtitle: former?.email.isNotEmpty == true
              ? former!.email
              : 'Historical contributor',
          avatarText: name == null || name.isEmpty ? '?' : name[0],
          isArchived: true,
        ),
      );
    }
    return choices;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${group.emoji}  ${group.name}',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          StreamBuilder<ChatBadge>(
            stream: chatBadgeStream,
            initialData: ChatBadge.empty,
            builder: (context, snapshot) => IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupChatScreen(
                    group: group,
                    database: database,
                    currentUid: currentUid,
                  ),
                ),
              ),
              icon: _ChatIconWithBadge(badge: snapshot.data ?? ChatBadge.empty),
              tooltip: (snapshot.data?.hasMention ?? false)
                  ? 'You were mentioned'
                  : 'Group chat',
            ),
          ),
          IconButton(
            onPressed: _openGroupSettings,
            icon: Icon(
                isAdmin ? Icons.manage_accounts_rounded : Icons.group_outlined),
            tooltip: isAdmin ? 'Manage group' : 'Group information',
          ),
        ],
      ),
      body: StreamBuilder<List<LedgerEntry>>(
        stream: database.watchTransactions(group.id),
        builder: (context, snapshot) {
          final entries = snapshot.data ?? [];
          final contributed = entries
              .where((e) => e.type == 'contribution')
              .fold<double>(0, (sum, e) => sum + e.amount);
          final spent = entries
              .where((e) => e.type == 'expense')
              .fold<double>(0, (sum, e) => sum + e.walletUsed);
          final myDeposits = entries
              .where((e) => e.type == 'contribution' && e.paidBy == currentUid)
              .fold<double>(0, (sum, e) => sum + e.amount);
          final myPersonalPaid = entries
              .where((e) => e.type == 'expense' && e.paidBy == currentUid)
              .fold<double>(0, (sum, e) => sum + e.personalPaid);
          final myShare = entries
              .where((e) => e.type == 'expense')
              .fold<double>(
                  0, (sum, e) => sum + (e.splitAmong[currentUid] ?? 0));
          final myNetCredit =
              math.max(0.0, myDeposits + myPersonalPaid - myShare);
          final now = DateTime.now();
          final thisMonth = entries.where((entry) {
            final date = DateTime.fromMillisecondsSinceEpoch(entry.createdAt);
            return date.year == now.year && date.month == now.month;
          }).toList();
          final lastMonthDate = DateTime(now.year, now.month - 1);
          final lastMonth = entries.where((entry) {
            final date = DateTime.fromMillisecondsSinceEpoch(entry.createdAt);
            return date.year == lastMonthDate.year &&
                date.month == lastMonthDate.month;
          }).toList();
          double monthShare(List<LedgerEntry> rows) =>
              rows.where((entry) => entry.type == 'expense').fold(
                  0, (sum, entry) => sum + (entry.splitAmong[currentUid] ?? 0));
          final currentMonthSpend = monthShare(thisMonth);
          final previousMonthSpend = monthShare(lastMonth);
          final monthChange = previousMonthSpend == 0
              ? 0.0
              : ((currentMonthSpend - previousMonthSpend) /
                      previousMonthSpend) *
                  100;
          final categories = <String, double>{};
          for (final entry in thisMonth.where((entry) =>
              entry.type == 'expense' &&
              entry.splitAmong.containsKey(currentUid))) {
            categories[entry.category] = (categories[entry.category] ?? 0) +
                (entry.splitAmong[currentUid] ?? 0);
          }
          final categoryRanking = categories.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
            children: [
              _WalletCard(
                  currencyCode: group.currencyCode,
                  balance: contributed - spent,
                  contributed: contributed,
                  spent: spent,
                  currentNetCredit: myNetCredit,
                  currentMonthSpend: currentMonthSpend,
                  topCategory: categoryRanking.isEmpty
                      ? null
                      : categoryRanking.first.key,
                  monthChange: monthChange),
              const SizedBox(height: 26),
              Row(children: [
                Text('Members',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('${group.members.length}',
                    style: const TextStyle(color: Colors.white54)),
              ]),
              const SizedBox(height: 10),
              SizedBox(
                height: 83,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: group.members.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final member = orderedMembers[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: isAdmin || member.uid == currentUid
                          ? () => showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                builder: (_) => _MemberDashboard(
                                  member: member,
                                  entries: entries,
                                  database: database,
                                  groupId: group.id,
                                  members: {
                                    ...group.formerMembers,
                                    ...group.members,
                                  },
                                  currencyCode: group.currencyCode,
                                ),
                              )
                          : null,
                      child: Container(
                        width: 112,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: const Color(0xFF151721),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFF252836))),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                CircleAvatar(
                                    radius: 13,
                                    child: Text(member.name.isEmpty
                                        ? '?'
                                        : member.name[0])),
                                const Spacer(),
                                if (member.role == 'admin')
                                  const Icon(Icons.shield_rounded,
                                      size: 15, color: Color(0xFF65DDBA))
                              ]),
                              const Spacer(),
                              Text(member.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                            ]),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 26),
              _TransactionHistory(
                entries: entries,
                currentUid: currentUid,
                isAdmin: isAdmin,
                database: database,
                groupId: group.id,
                members: {
                  ...group.formerMembers,
                  ...group.members,
                },
                currencyCode: group.currencyCode,
                onEdit: (entry) => _editTransaction(context, entry),
                onDelete: (entry) =>
                    database.deleteTransaction(group.id, entry.id),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addTransaction(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
    );
  }

  Future<void> _openGroupSettings() async {
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupSettingsScreen(
          group: group,
          database: database,
          currentUid: currentUid,
        ),
      ),
    );
    if (!mounted) return;
    if (deleted == true) {
      Navigator.pop(context);
      return;
    }
    final updated = await database.getGroup(group.id);
    if (!mounted) return;
    if (updated == null) {
      Navigator.pop(context);
    } else {
      setState(() => group = updated);
    }
  }

  Future<void> _editTransaction(BuildContext context, LedgerEntry entry) async {
    final title = TextEditingController(text: entry.title);
    final amount = TextEditingController(text: entry.amount.toString());
    var category = entry.category;
    var paidBy = entry.paidBy;
    var paymentSource = entry.paymentSource;
    var occurredAt = DateTime.fromMillisecondsSinceEpoch(entry.createdAt);
    final selected = entry.splitAmong.keys.toSet();
    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .9,
        child: StatefulBuilder(
          builder: (context, setLocalState) => Padding(
            padding: EdgeInsets.fromLTRB(
                20, 4, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
            child: Column(children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.edit_rounded,
                            color: Color(0xFF9B8EFF)),
                        const SizedBox(width: 10),
                        Text(
                            'Edit ${entry.type == 'expense' ? 'expense' : 'deposit'}',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900)),
                      ]),
                      const SizedBox(height: 20),
                      if (entry.type == 'expense') ...[
                        TextField(
                          controller: title,
                          decoration: const InputDecoration(
                              labelText: 'What was it for?'),
                        ),
                        const SizedBox(height: 12),
                        _FriendlyDropdown(
                          value: category,
                          label: 'Category',
                          leadingIcon: Icons.category_rounded,
                          items: [
                            'Food',
                            'Travel',
                            'Stay',
                            'Shopping',
                            'Bills',
                            'Other'
                          ]
                              .map((value) =>
                                  _DropdownChoice(value: value, label: value))
                              .toList(),
                          onChanged: (value) =>
                              setLocalState(() => category = value!),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: amount,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: _amountDecoration(group.currencyCode),
                      ),
                      const SizedBox(height: 12),
                      _transactionDateTimeField(occurredAt, () async {
                        final picked =
                            await _pickTransactionDateTime(context, occurredAt);
                        if (picked != null) {
                          setLocalState(() => occurredAt = picked);
                        }
                      }),
                      const SizedBox(height: 12),
                      if (entry.type == 'contribution')
                        _FriendlyDropdown(
                          value: paidBy,
                          label: 'Contributed by',
                          leadingIcon: Icons.person_rounded,
                          items: _memberChoices(includeFormerUid: paidBy),
                          onChanged: (value) =>
                              setLocalState(() => paidBy = value!),
                        )
                      else ...[
                        _FriendlyDropdown(
                          value: paymentSource,
                          label: 'Payment source',
                          leadingIcon: Icons.account_balance_wallet_rounded,
                          items: const [
                            _DropdownChoice(
                                value: 'personal', label: 'Personal money'),
                            _DropdownChoice(
                                value: 'wallet', label: 'Group wallet'),
                          ],
                          onChanged: (value) =>
                              setLocalState(() => paymentSource = value!),
                        ),
                        const SizedBox(height: 18),
                        Row(children: [
                          const Expanded(
                              child: Text('Split equally between',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700))),
                          Text('${selected.length}/${group.members.length}',
                              style: const TextStyle(color: Colors.white54)),
                        ]),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: orderedMembers
                              .map((member) => FilterChip(
                                    label: Text(member.name),
                                    selected: selected.contains(member.uid),
                                    onSelected: (checked) => setLocalState(() =>
                                        checked
                                            ? selected.add(member.uid)
                                            : selected.remove(member.uid)),
                                  ))
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: () {
                    final enteredAmount = double.tryParse(amount.text.trim());
                    String? warning;
                    if (entry.type == 'expense' && title.text.trim().isEmpty) {
                      warning = 'Enter the expense name';
                    } else if (enteredAmount == null || enteredAmount <= 0) {
                      warning = 'Enter a valid amount';
                    } else if (entry.type == 'expense' && selected.isEmpty) {
                      warning = 'Select at least one member for the split';
                    }
                    if (warning != null) {
                      _showWarningToast(context, warning);
                      return;
                    }
                    Navigator.pop(context, true);
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Save changes'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    final value = double.tryParse(amount.text.trim());
    if (save != true || value == null || value <= 0) return;
    if (entry.type == 'contribution') {
      await database.updateContribution(
        groupId: group.id,
        transactionId: entry.id,
        memberId: paidBy,
        amount: value,
        occurredAt: occurredAt.millisecondsSinceEpoch,
      );
    } else if (title.text.trim().isNotEmpty && selected.isNotEmpty) {
      final currentWallet = await database.getWalletBalance(group.id);
      await database.updateExpense(
        groupId: group.id,
        transactionId: entry.id,
        title: title.text.trim(),
        category: category,
        amount: value,
        paidBy: paymentSource == 'wallet' ? currentUid : entry.paidBy,
        memberIds: selected.toList(),
        paymentSource: paymentSource,
        walletBalance: currentWallet + entry.walletUsed,
        occurredAt: occurredAt.millisecondsSinceEpoch,
      );
    }
  }

  Future<void> _addTransaction(BuildContext context) async {
    String type = 'expense';
    String category = 'Food';
    String paidBy = currentUid;
    String paymentSource = 'personal';
    var occurredAt = DateTime.now();
    final selected = group.members.keys.toSet();
    final title = TextEditingController();
    final amount = TextEditingController();
    final membersScrollController = ScrollController();
    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.9,
        child: StatefulBuilder(
          builder: (context, setLocalState) => Padding(
            padding: EdgeInsets.fromLTRB(
                20, 4, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('New transaction',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 18),
                          if (isAdmin)
                            _TransactionTypeSelector(
                              value: type,
                              onChanged: (value) => setLocalState(() {
                                type = value;
                                if (type == 'contribution') {
                                  paymentSource = 'personal';
                                }
                              }),
                            ),
                          const SizedBox(height: 16),
                          if (type == 'expense') ...[
                            TextField(
                                controller: title,
                                decoration: const InputDecoration(
                                    labelText: 'What was it for?')),
                            const SizedBox(height: 10),
                            _FriendlyDropdown(
                                value: category,
                                label: 'Category',
                                leadingIcon: Icons.category_rounded,
                                items: [
                                  'Food',
                                  'Travel',
                                  'Stay',
                                  'Shopping',
                                  'Bills',
                                  'Other'
                                ]
                                    .map((value) => _DropdownChoice(
                                        value: value, label: value))
                                    .toList(),
                                onChanged: (value) =>
                                    setLocalState(() => category = value!)),
                            const SizedBox(height: 10),
                          ],
                          TextField(
                              controller: amount,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration:
                                  _amountDecoration(group.currencyCode)),
                          const SizedBox(height: 10),
                          _transactionDateTimeField(occurredAt, () async {
                            final picked = await _pickTransactionDateTime(
                                context, occurredAt);
                            if (picked != null) {
                              setLocalState(() => occurredAt = picked);
                            }
                          }),
                          const SizedBox(height: 10),
                          if (type == 'contribution')
                            _FriendlyDropdown(
                                value: paidBy,
                                label: 'Contributed by',
                                leadingIcon: Icons.person_rounded,
                                items: _memberChoices(),
                                onChanged: (value) =>
                                    setLocalState(() => paidBy = value!)),
                          if (type == 'expense') ...[
                            if (isAdmin) ...[
                              _FriendlyDropdown(
                                value: paymentSource,
                                label: 'Payment source',
                                leadingIcon:
                                    Icons.account_balance_wallet_rounded,
                                items: const [
                                  _DropdownChoice(
                                      value: 'personal',
                                      label: 'My personal money'),
                                  _DropdownChoice(
                                      value: 'wallet',
                                      label:
                                          'Group wallet (uses wallet first)'),
                                ],
                                onChanged: (value) =>
                                    setLocalState(() => paymentSource = value!),
                              ),
                              const SizedBox(height: 8),
                            ] else
                              const ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.person_rounded),
                                title: Text('Paid by you'),
                                subtitle: Text(
                                    'Only the admin can spend from the group wallet'),
                              ),
                            const SizedBox(height: 18),
                            Row(children: [
                              const Expanded(
                                child: Text('Split equally between',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                              ),
                              Text('${selected.length}/${group.members.length}',
                                  style:
                                      const TextStyle(color: Colors.white54)),
                              const SizedBox(width: 4),
                              TextButton(
                                onPressed: () => setLocalState(() {
                                  if (selected.length == group.members.length) {
                                    selected.clear();
                                  } else {
                                    selected
                                      ..clear()
                                      ..addAll(group.members.keys);
                                  }
                                }),
                                child: Text(
                                    selected.length == group.members.length
                                        ? 'Clear'
                                        : 'Select all'),
                              ),
                            ]),
                            Container(
                              height: math
                                  .min(216, group.members.length * 54)
                                  .toDouble(),
                              decoration: BoxDecoration(
                                color: const Color(0xFF12141E),
                                borderRadius: BorderRadius.circular(16),
                                border:
                                    Border.all(color: const Color(0xFF343247)),
                              ),
                              child: Scrollbar(
                                controller: membersScrollController,
                                thumbVisibility: group.members.length > 4,
                                child: ListView.separated(
                                  controller: membersScrollController,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  itemCount: group.members.length,
                                  separatorBuilder: (_, __) => const Divider(
                                      height: 1, indent: 52, endIndent: 12),
                                  itemBuilder: (context, index) {
                                    final member = orderedMembers[index];
                                    return CheckboxListTile(
                                      dense: true,
                                      contentPadding: const EdgeInsets.only(
                                          left: 12, right: 8),
                                      secondary: CircleAvatar(
                                        radius: 15,
                                        child: Text(member.name.isEmpty
                                            ? '?'
                                            : member.name[0]),
                                      ),
                                      title: Text(member.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      value: selected.contains(member.uid),
                                      onChanged: (checked) => setLocalState(
                                          () => checked == true
                                              ? selected.add(member.uid)
                                              : selected.remove(member.uid)),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                        ]),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: () {
                      final enteredAmount = double.tryParse(amount.text.trim());
                      String? warning;
                      if (type == 'expense' && title.text.trim().isEmpty) {
                        warning = 'Enter the expense name';
                      } else if (enteredAmount == null || enteredAmount <= 0) {
                        warning = 'Enter a valid amount';
                      } else if (type == 'expense' && selected.isEmpty) {
                        warning = 'Select at least one member for the split';
                      }
                      if (warning != null) {
                        _showWarningToast(context, warning);
                        return;
                      }
                      Navigator.pop(context, true);
                    },
                    child: const Text('Save transaction'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    membersScrollController.dispose();
    final value = double.tryParse(amount.text.trim());
    if (save != true || value == null || value <= 0) return;
    if (type == 'contribution') {
      await database.addContribution(
          groupId: group.id,
          memberId: paidBy,
          amount: value,
          occurredAt: occurredAt.millisecondsSinceEpoch);
    } else if (title.text.trim().isNotEmpty && selected.isNotEmpty) {
      final walletBalance = await database.getWalletBalance(group.id);
      await database.addExpense(
          groupId: group.id,
          title: title.text.trim(),
          category: category,
          amount: value,
          paidBy: currentUid,
          memberIds: selected.toList(),
          paymentSource: paymentSource,
          walletBalance: walletBalance,
          occurredAt: occurredAt.millisecondsSinceEpoch);
    }
  }
}

class GroupSettingsScreen extends StatefulWidget {
  const GroupSettingsScreen({
    super.key,
    required this.group,
    required this.database,
    required this.currentUid,
  });

  final SplitGroup group;
  final DatabaseService database;
  final String currentUid;

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  late SplitGroup group = widget.group;
  bool get isAdmin => group.ownerId == widget.currentUid;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Group settings',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                    colors: [Color(0xFF302A62), Color(0xFF172E3A)]),
              ),
              child: Row(children: [
                Text(group.emoji, style: const TextStyle(fontSize: 38)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(group.name,
                            style: const TextStyle(
                                fontSize: 21, fontWeight: FontWeight.w900)),
                        Text(
                            isAdmin
                                ? 'Admin controls enabled'
                                : 'View-only group information',
                            style: const TextStyle(color: Colors.white60)),
                      ]),
                ),
                Icon(isAdmin ? Icons.admin_panel_settings : Icons.lock_outline,
                    color: const Color(0xFF65DDBA)),
              ]),
            ),
            const SizedBox(height: 22),
            Row(children: [
              Text('Group details',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const Spacer(),
              if (isAdmin)
                TextButton.icon(
                  onPressed: _renameGroup,
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Rename'),
                ),
            ]),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.drive_file_rename_outline_rounded,
                    color: Color(0xFF9B8EFF)),
                title: const Text('Group name'),
                subtitle: Text(group.name),
                trailing: isAdmin
                    ? const Icon(Icons.chevron_right_rounded)
                    : const Icon(Icons.visibility_outlined),
                onTap: isAdmin ? _renameGroup : null,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: Text(currencyForCode(group.currencyCode).flag,
                    style: const TextStyle(fontSize: 26)),
                title: const Text('Group currency'),
                subtitle: Text(
                    '${currencyForCode(group.currencyCode).symbol}  ${currencyForCode(group.currencyCode).code} • ${currencyForCode(group.currencyCode).name}'),
                trailing: isAdmin
                    ? const Icon(Icons.chevron_right_rounded)
                    : const Icon(Icons.visibility_outlined),
                onTap: isAdmin ? _chooseCurrency : null,
              ),
            ),
            const SizedBox(height: 12),
            _accessCodeCard(),
            const SizedBox(height: 24),
            Row(children: [
              Text('Members',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const Spacer(),
              Text('${group.members.length}',
                  style: const TextStyle(color: Colors.white54)),
              if (isAdmin) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _addMember,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  tooltip: 'Add member',
                ),
              ],
            ]),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: group.members.values.map((member) {
                  final isOwner = member.uid == group.ownerId;
                  return Column(children: [
                    ListTile(
                      leading: CircleAvatar(
                          child:
                              Text(member.name.isEmpty ? '?' : member.name[0])),
                      title: Text(member.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(isOwner
                          ? 'Group admin'
                          : member.email.isEmpty
                              ? 'Member'
                              : member.email),
                      trailing: isAdmin && !isOwner
                          ? IconButton(
                              onPressed: () => _removeMember(member),
                              icon: const Icon(Icons.person_remove_rounded,
                                  color: Color(0xFFFF837A)),
                              tooltip: 'Remove member',
                            )
                          : Icon(
                              isOwner
                                  ? Icons.shield_rounded
                                  : Icons.visibility_outlined,
                              color: isOwner
                                  ? const Color(0xFF65DDBA)
                                  : Colors.white38,
                            ),
                    ),
                    if (member.uid != group.members.keys.last)
                      const Divider(height: 1, indent: 64),
                  ]);
                }).toList(),
              ),
            ),
            if (group.formerMembers.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text('Former members',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: group.formerMembers.values
                      .map((member) => ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFFFB45E)
                                  .withValues(alpha: .12),
                              child: Text(
                                  member.name.isEmpty ? '?' : member.name[0]),
                            ),
                            title: Text(member.name),
                            subtitle: const Text(
                                'Removed • Historical transactions retained'),
                            trailing: const Icon(Icons.history_rounded,
                                color: Color(0xFFFFB45E)),
                          ))
                      .toList(),
                ),
              ),
            ],
            if (!isAdmin) ...[
              const SizedBox(height: 18),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline_rounded,
                      color: Color(0xFF62B8FF)),
                  title: Text('View-only access'),
                  subtitle: Text(
                      'Only the group admin can rename, manage members or delete this group.'),
                ),
              ),
            ],
            if (isAdmin) ...[
              const SizedBox(height: 30),
              const Text('Danger zone',
                  style: TextStyle(
                      color: Color(0xFFFF837A),
                      fontSize: 16,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 9),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF837A),
                    side: const BorderSide(color: Color(0xFF7B3D48)),
                    minimumSize: const Size.fromHeight(54)),
                onPressed: _deleteGroup,
                icon: const Icon(Icons.delete_forever_rounded),
                label: const Text('Delete group permanently'),
              ),
            ],
          ],
        ),
      );

  Widget _accessCodeCard() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF181827),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF3D3862)),
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: const Color(0xFF2C2948),
                borderRadius: BorderRadius.circular(15)),
            child: const Icon(Icons.key_rounded, color: Color(0xFF9B8EFF)),
          ),
          const SizedBox(width: 13),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('GROUP ACCESS CODE',
                  style: TextStyle(
                      color: Colors.white54, fontSize: 11, letterSpacing: 1.2)),
              const SizedBox(height: 4),
              Text(
                  group.accessCode.isEmpty
                      ? 'Not created yet'
                      : group.accessCode,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2)),
            ]),
          ),
          if (group.accessCode.isNotEmpty)
            IconButton.filledTonal(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: group.accessCode));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Access code copied')));
              },
              icon: const Icon(Icons.copy_rounded),
            )
          else if (isAdmin)
            FilledButton(onPressed: _createCode, child: const Text('Create')),
        ]),
      );

  Future<void> _createCode() async {
    final code = await widget.database.createAccessCode(group.id);
    if (!mounted) return;
    setState(() => group = group.copyWith(accessCode: code));
  }

  Future<void> _renameGroup() async {
    final name = TextEditingController(text: group.name);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(
            controller: name,
            autofocus: true,
            maxLength: 50,
            decoration: const InputDecoration(labelText: 'Group name')),
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
    if (save == true && name.text.trim().isNotEmpty) {
      await widget.database.renameGroup(group.id, name.text);
      if (mounted) {
        setState(() => group = group.copyWith(name: name.text.trim()));
      }
    }
  }

  Future<void> _chooseCurrency() async {
    var query = '';
    final selected = await showModalBottomSheet<CurrencyOption>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .88,
        child: StatefulBuilder(
          builder: (context, setLocalState) {
            final currencies = worldCurrencies
                .where((currency) => currency.matches(query))
                .toList();
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
              child: Column(children: [
                Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF9B8EFF).withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.currency_exchange_rounded,
                        color: Color(0xFFB7AEFF)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Choose currency',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900)),
                        const Text('Used everywhere in this group',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      FocusManager.instance.primaryFocus?.unfocus();
                      await Future<void>.delayed(
                          const Duration(milliseconds: 120));
                      if (context.mounted) Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
                const SizedBox(height: 16),
                TextField(
                  onChanged: (value) => setLocalState(() => query = value),
                  decoration: const InputDecoration(
                    hintText: r'Search INR, Rupee, $, Euro...',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: currencies.isEmpty
                      ? const Center(child: Text('No currency found'))
                      : ListView.separated(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: currencies.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 58),
                          itemBuilder: (context, index) {
                            final currency = currencies[index];
                            final isSelected =
                                currency.code == group.currencyCode;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              leading: Text(currency.flag,
                                  style: const TextStyle(fontSize: 27)),
                              title: Text(currency.name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  '${currency.code}  •  ${currency.symbol}'),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle_rounded,
                                      color: Color(0xFF65DDBA))
                                  : null,
                              onTap: () async {
                                FocusManager.instance.primaryFocus?.unfocus();
                                await Future<void>.delayed(
                                    const Duration(milliseconds: 120));
                                if (context.mounted) {
                                  Navigator.pop(context, currency);
                                }
                              },
                            );
                          },
                        ),
                ),
              ]),
            );
          },
        ),
      ),
    );
    if (selected == null || selected.code == group.currencyCode) return;
    await widget.database.updateGroupCurrency(group.id, selected.code);
    if (mounted) {
      setState(() => group = group.copyWith(currencyCode: selected.code));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('Currency changed to ${selected.code}')));
    }
  }

  Future<void> _addMember() async {
    final uid = TextEditingController();
    final name = TextEditingController();
    final email = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add member'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: uid,
                decoration: const InputDecoration(labelText: 'Member ID')),
            const SizedBox(height: 10),
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 10),
            TextField(
                controller: email,
                decoration:
                    const InputDecoration(labelText: 'Email (optional)')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (save == true &&
        uid.text.trim().isNotEmpty &&
        name.text.trim().isNotEmpty) {
      await widget.database.addMember(
          group.id, uid.text.trim(), name.text.trim(), email.text.trim());
      final updated = await widget.database.getGroup(group.id);
      if (mounted && updated != null) {
        setState(() => group = updated);
      }
    }
  }

  Future<void> _removeMember(GroupMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text(
            '${member.name} will lose group access. Their old deposits and expenses will stay in history for correct wallet totals, and the admin can still edit those records.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.database.removeMember(group.id, member);
    if (!mounted) return;
    final members = Map<String, GroupMember>.from(group.members)
      ..remove(member.uid);
    setState(() => group = group.copyWith(members: members));
  }

  Future<void> _deleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: Color(0xFFFF837A), size: 38),
        title: const Text('Delete this group?'),
        content: Text(
            '“${group.name}” and its complete history will be permanently deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD64D54)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete permanently')),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.database.deleteGroup(group);
      if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.currencyCode,
    required this.balance,
    required this.contributed,
    required this.spent,
    required this.currentNetCredit,
    required this.currentMonthSpend,
    required this.topCategory,
    required this.monthChange,
  });
  final String currencyCode;
  final double balance;
  final double contributed;
  final double spent;
  final double currentNetCredit;
  final double currentMonthSpend;
  final String? topCategory;
  final double monthChange;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
                colors: [Color(0xFF23354A), Color(0xFF132B31)])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('GROUP WALLET',
              style: TextStyle(
                  letterSpacing: 1.5, fontSize: 11, color: Colors.white60)),
          const SizedBox(height: 8),
          Text(formatMoney(balance, currencyCode),
              style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1)),
          const SizedBox(height: 22),
          Row(children: [
            Expanded(
                child: _MiniStat(
                    currencyCode: currencyCode,
                    icon: Icons.south_west_rounded,
                    label: 'Added',
                    value: contributed,
                    color: const Color(0xFF65DDBA))),
            Expanded(
                child: _MiniStat(
                    currencyCode: currencyCode,
                    icon: Icons.north_east_rounded,
                    label: 'Spent',
                    value: spent,
                    color: const Color(0xFFFF837A)))
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: _WalletInsight(
                icon: Icons.account_balance_rounded,
                label: 'Your credit',
                value: formatMoney(currentNetCredit, currencyCode),
                caption: 'Net balance',
                color: const Color(0xFF65DDBA),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _WalletInsight(
                icon: Icons.auto_graph_rounded,
                label: 'This month',
                value: formatMoney(currentMonthSpend, currencyCode),
                caption: topCategory == null
                    ? 'No spend yet'
                    : '$topCategory • ${monthChange <= 0 ? '↓' : '↑'}${monthChange.abs().toStringAsFixed(0)}%',
                color: const Color(0xFFFFB45E),
              ),
            ),
          ]),
        ]),
      );
}

class _WalletInsight extends StatelessWidget {
  const _WalletInsight({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 11)),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: color, fontSize: 15, fontWeight: FontWeight.w900)),
              Text(caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ]),
          ),
        ]),
      );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(
      {required this.currencyCode,
      required this.icon,
      required this.label,
      required this.value,
      required this.color});
  final String currencyCode;
  final IconData icon;
  final String label;
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text(formatMoney(value, currencyCode),
              style: const TextStyle(fontWeight: FontWeight.w800))
        ])
      ]);
}

class _TransactionHistory extends StatefulWidget {
  const _TransactionHistory({
    required this.entries,
    required this.currentUid,
    required this.isAdmin,
    required this.onDelete,
    required this.currencyCode,
    this.onEdit,
    this.title,
    this.canDelete,
    this.previewLimit = 10,
    this.initialFilter = 'all',
    this.database,
    this.groupId,
    this.members = const {},
  });

  final List<LedgerEntry> entries;
  final String currentUid;
  final bool isAdmin;
  final ValueChanged<LedgerEntry> onDelete;
  final String currencyCode;
  final ValueChanged<LedgerEntry>? onEdit;
  final String? title;
  final bool? canDelete;
  final int? previewLimit;
  final String initialFilter;
  final DatabaseService? database;
  final String? groupId;
  final Map<String, GroupMember> members;

  @override
  State<_TransactionHistory> createState() => _TransactionHistoryState();
}

class _TransactionHistoryState extends State<_TransactionHistory> {
  late String filter = widget.initialFilter;

  @override
  Widget build(BuildContext context) {
    final owned = widget.isAdmin
        ? widget.entries
        : widget.entries.where((entry) {
            if (entry.type == 'contribution') {
              return entry.paidBy == widget.currentUid;
            }
            return entry.createdBy == widget.currentUid ||
                entry.paidBy == widget.currentUid ||
                entry.splitAmong.containsKey(widget.currentUid);
          }).toList();
    final visible = filter == 'all'
        ? owned
        : owned.where((entry) => entry.type == filter).toList();
    final preview = widget.previewLimit == null
        ? visible
        : visible.take(widget.previewLimit!).toList();
    final hasMore = preview.length < visible.length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(
            widget.title ??
                (widget.isAdmin ? 'All member history' : 'Your history'),
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
        const Spacer(),
        Text('${visible.length}',
            style: const TextStyle(color: Colors.white54)),
      ]),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'all', label: Text('All')),
            ButtonSegment(value: 'expense', label: Text('Expense')),
            ButtonSegment(value: 'contribution', label: Text('Deposit')),
          ],
          selected: {filter},
          onSelectionChanged: (value) => setState(() => filter = value.first),
        ),
      ),
      const SizedBox(height: 10),
      if (visible.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: Text(
                filter == 'all'
                    ? 'No activity yet'
                    : 'No ${filter == 'expense' ? 'expenses' : 'deposits'} yet',
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          ),
        )
      else
        ...preview.map((entry) => _TransactionTile(
              entry: entry,
              canDelete: widget.canDelete ?? widget.isAdmin,
              onEdit:
                  widget.onEdit == null ? null : () => widget.onEdit!(entry),
              onDelete: () => widget.onDelete(entry),
              database: widget.database,
              groupId: widget.groupId,
              members: widget.members,
              currencyCode: widget.currencyCode,
            )),
      if (hasMore) ...[
        const SizedBox(height: 3),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _openFullHistory,
            icon: const Icon(Icons.history_rounded),
            label: Text('View all ${visible.length} transactions'),
          ),
        ),
      ],
    ]);
  }

  void _openFullHistory() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _FullTransactionHistoryScreen(
            entries: widget.entries,
            currentUid: widget.currentUid,
            isAdmin: widget.isAdmin,
            onDelete: widget.onDelete,
            onEdit: widget.onEdit,
            canDelete: widget.canDelete,
            initialFilter: filter,
            database: widget.database,
            groupId: widget.groupId,
            members: widget.members,
            currencyCode: widget.currencyCode,
          ),
        ),
      );
}

class _FullTransactionHistoryScreen extends StatelessWidget {
  const _FullTransactionHistoryScreen({
    required this.entries,
    required this.currentUid,
    required this.isAdmin,
    required this.onDelete,
    required this.initialFilter,
    required this.currencyCode,
    this.onEdit,
    this.canDelete,
    this.database,
    this.groupId,
    this.members = const {},
  });

  final List<LedgerEntry> entries;
  final String currentUid;
  final bool isAdmin;
  final ValueChanged<LedgerEntry> onDelete;
  final ValueChanged<LedgerEntry>? onEdit;
  final bool? canDelete;
  final String initialFilter;
  final String currencyCode;
  final DatabaseService? database;
  final String? groupId;
  final Map<String, GroupMember> members;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Transaction history',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: database != null && groupId != null
            ? StreamBuilder<List<LedgerEntry>>(
                stream: database!.watchTransactions(groupId!),
                initialData: entries,
                builder: (context, snapshot) =>
                    _historyList(snapshot.data ?? entries),
              )
            : _historyList(entries),
      );

  Widget _historyList(List<LedgerEntry> rows) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
        children: [
          _TransactionHistory(
            entries: rows,
            currentUid: currentUid,
            isAdmin: isAdmin,
            onDelete: onDelete,
            onEdit: onEdit,
            canDelete: canDelete,
            title: isAdmin ? 'All transactions' : 'Your transactions',
            previewLimit: null,
            initialFilter: initialFilter,
            database: database,
            groupId: groupId,
            members: members,
            currencyCode: currencyCode,
          ),
        ],
      );
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.entry,
    required this.canDelete,
    required this.onDelete,
    required this.currencyCode,
    this.onEdit,
    this.database,
    this.groupId,
    this.members = const {},
  });
  static const _reactions = ['👍', '❤️', '😂', '😮', '😢', '🔥'];
  final LedgerEntry entry;
  final bool canDelete;
  final VoidCallback onDelete;
  final String currencyCode;
  final VoidCallback? onEdit;
  final DatabaseService? database;
  final String? groupId;
  final Map<String, GroupMember> members;
  @override
  Widget build(BuildContext context) {
    final isIncome = entry.type == 'contribution';
    final contributor = members[entry.paidBy];
    final contributionNote = contributor == null
        ? 'Contribution • Former member'
        : 'Contribution • ${contributor.name}${contributor.role == 'former' ? ' • Removed member' : ''}';
    final paymentNote = entry.type != 'expense'
        ? ''
        : entry.paymentSource == 'wallet'
            ? ' • Wallet ${formatMoney(entry.walletUsed, currencyCode)}${entry.personalPaid > 0 ? ' + personal ${formatMoney(entry.personalPaid, currencyCode)}' : ''}'
            : ' • Paid personally';
    return Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Card(
            child: Column(children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
            leading: CircleAvatar(
                backgroundColor: (isIncome
                        ? const Color(0xFF65DDBA)
                        : const Color(0xFFFF837A))
                    .withValues(alpha: .12),
                child: Icon(
                    isIncome
                        ? Icons.savings_rounded
                        : _categoryIcon(entry.category),
                    color: isIncome
                        ? const Color(0xFF65DDBA)
                        : const Color(0xFFFF837A))),
            title: Text(entry.title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
                '${isIncome ? contributionNote : '${entry.category}$paymentNote'} • ${DateFormat('d MMM, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(entry.createdAt))}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                  '${isIncome ? '+' : '-'}${formatMoney(entry.amount, currencyCode)}',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color:
                          isIncome ? const Color(0xFF65DDBA) : Colors.white)),
              if (canDelete)
                PopupMenuButton<String>(
                    itemBuilder: (_) => const [
                          PopupMenuItem(
                              height: 44,
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              value: 'edit',
                              child: Row(children: [
                                Icon(Icons.edit_rounded, size: 20),
                                SizedBox(width: 10),
                                Text('Edit'),
                              ])),
                          PopupMenuItem(
                              height: 44,
                              padding: EdgeInsets.symmetric(horizontal: 14),
                              value: 'delete',
                              child: Row(children: [
                                Icon(Icons.delete_rounded,
                                    size: 20, color: Color(0xFFFF837A)),
                                SizedBox(width: 10),
                                Text('Delete'),
                              ])),
                        ],
                    onSelected: (value) {
                      if (value == 'edit') onEdit?.call();
                      if (value == 'delete') onDelete();
                    })
            ]),
          ),
          if (database != null && groupId != null) _reactionBar(context),
        ])));
  }

  Widget _reactionBar(BuildContext context) =>
      StreamBuilder<Map<String, String>>(
        stream: database!.watchTransactionReactions(groupId!, entry.id),
        builder: (context, snapshot) {
          final reactionsByUser = snapshot.data ?? const <String, String>{};
          final counts = <String, int>{};
          for (final emoji in reactionsByUser.values) {
            counts[emoji] = (counts[emoji] ?? 0) + 1;
          }
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 7),
            child: Row(children: [
              Expanded(
                child: counts.isEmpty
                    ? const Text('Be the first to react',
                        style: TextStyle(color: Colors.white38, fontSize: 11))
                    : Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: counts.entries
                            .map((item) => InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => _showReactionMembers(
                                      context, item.key, reactionsByUser),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF242638),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                          color: const Color(0xFF3A3D54)),
                                    ),
                                    child: Text('${item.key} ${item.value}',
                                        style: const TextStyle(fontSize: 12)),
                                  ),
                                ))
                            .toList(),
                      ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'React',
                onPressed: () => _showReactionPicker(context),
                icon: const Icon(Icons.add_reaction_outlined,
                    size: 20, color: Color(0xFFFFB45E)),
              ),
            ]),
          );
        },
      );

  Future<void> _showReactionPicker(BuildContext context) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('React to transaction',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _reactions
                  .map((reaction) => InkWell(
                        borderRadius: BorderRadius.circular(28),
                        onTap: () => Navigator.pop(context, reaction),
                        child: Padding(
                          padding: const EdgeInsets.all(9),
                          child: Text(reaction,
                              style: const TextStyle(fontSize: 28)),
                        ),
                      ))
                  .toList(),
            ),
          ]),
        ),
      ),
    );
    if (emoji != null) {
      try {
        await database!.reactToTransaction(groupId!, entry.id, emoji);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            duration: Duration(seconds: 2),
            content: Text('Reaction could not be saved. Please try again.'),
          ));
        }
      }
    }
  }

  Future<void> _showReactionMembers(
      BuildContext context, String emoji, Map<String, String> reactionsByUser) {
    final reactedMembers = reactionsByUser.entries
        .where((item) => item.value == emoji)
        .map((item) => members[item.key])
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
              Text('${reactedMembers.length}',
                  style: const TextStyle(color: Colors.white54)),
            ]),
            const SizedBox(height: 12),
            ...reactedMembers.map((member) => ListTile(
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

  IconData _categoryIcon(String value) => switch (value) {
        'Food' => Icons.restaurant_rounded,
        'Travel' => Icons.directions_car_rounded,
        'Stay' => Icons.bed_rounded,
        'Shopping' => Icons.shopping_bag_rounded,
        'Bills' => Icons.receipt_rounded,
        _ => Icons.payments_rounded
      };
}

class _MemberDashboard extends StatelessWidget {
  const _MemberDashboard({
    required this.member,
    required this.entries,
    required this.database,
    required this.groupId,
    required this.members,
    required this.currencyCode,
  });
  final GroupMember member;
  final List<LedgerEntry> entries;
  final DatabaseService database;
  final String groupId;
  final Map<String, GroupMember> members;
  final String currencyCode;
  @override
  Widget build(BuildContext context) {
    final deposits = entries
        .where((e) => e.type == 'contribution' && e.paidBy == member.uid)
        .fold<double>(0, (s, e) => s + e.amount);
    final share = entries
        .where((e) => e.type == 'expense')
        .fold<double>(0, (s, e) => s + (e.splitAmong[member.uid] ?? 0));
    final paid = entries
        .where((e) => e.type == 'expense' && e.paidBy == member.uid)
        .fold<double>(0, (s, e) => s + e.personalPaid);
    final score = math.max(0.0, deposits + paid - share);
    return SafeArea(
        child: FractionallySizedBox(
            heightFactor: .88,
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        CircleAvatar(
                            radius: 26,
                            child: Text(
                                member.name.isEmpty ? '?' : member.name[0],
                                style: const TextStyle(fontSize: 20))),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(member.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w900)),
                              Text(member.email,
                                  style: const TextStyle(color: Colors.white54))
                            ]))
                      ]),
                      const SizedBox(height: 26),
                      Text('Personal dashboard',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: _Metric(
                                currencyCode: currencyCode,
                                label: 'Deposited',
                                value: deposits,
                                color: const Color(0xFF65DDBA))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _Metric(
                                currencyCode: currencyCode,
                                label: 'Own share',
                                value: share,
                                color: const Color(0xFFFFB45E)))
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: _Metric(
                                currencyCode: currencyCode,
                                label: 'Paid personally',
                                value: paid,
                                color: const Color(0xFF9B8EFF))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _Metric(
                                currencyCode: currencyCode,
                                label: 'Net credit',
                                value: score,
                                color: const Color(0xFF62B8FF)))
                      ]),
                      const SizedBox(height: 28),
                      _TransactionHistory(
                        entries: entries,
                        currentUid: member.uid,
                        isAdmin: false,
                        canDelete: false,
                        title: '${member.name} history',
                        database: database,
                        groupId: groupId,
                        members: members,
                        currencyCode: currencyCode,
                        onDelete: (_) {},
                      ),
                      const SizedBox(height: 14),
                    ]))));
  }
}

class _Metric extends StatelessWidget {
  const _Metric(
      {required this.currencyCode,
      required this.label,
      required this.value,
      required this.color});
  final String currencyCode;
  final String label;
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 5),
        Text(formatMoney(value, currencyCode),
            style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 18, color: color))
      ]));
}
