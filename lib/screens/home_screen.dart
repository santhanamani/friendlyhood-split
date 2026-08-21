import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/app_models.dart';
import '../models/currency_data.dart';
import '../services/database_service.dart';
import '../services/theme_controller.dart';
import '../services/upi_payment_service.dart';
import '../theme/app_colors.dart';
import 'app_settings_screen.dart';
import 'group_chat_screen.dart';

const _defaultExpenseCategories = <String>[
  'Food',
  'Travel',
  'Stay',
  'Shopping',
  'Bills',
  'Other',
];

List<String> _expenseCategoriesFor(SplitGroup group, {String? include}) {
  final seen = <String>{};
  return <String>[
    ..._defaultExpenseCategories,
    ...group.customExpenseCategories,
    if (include != null && include.trim().isNotEmpty) include.trim(),
  ].where((value) => seen.add(value.toLowerCase())).toList();
}

double _confirmedDepositCreditFor(
    Iterable<LedgerEntry> entries, String memberId) {
  var credit = 0.0;
  for (final entry in entries.where((entry) => entry.isConfirmedDeposit)) {
    if (entry.paidBy == memberId) credit += entry.amount;
    if (entry.isMemberDeposit && entry.depositTo == memberId) {
      credit -= entry.amount;
    }
  }
  return credit;
}

double _confirmedSettlementCreditFor(
    Iterable<LedgerEntry> entries, String memberId) {
  var credit = 0.0;
  for (final entry in entries.where((entry) => entry.type == 'expense')) {
    for (final settlement in entry.settlements.values
        .where((settlement) => settlement.isConfirmed)) {
      final amount = entry.splitAmong[settlement.memberId] ?? 0;
      if (settlement.memberId == memberId) credit += amount;
      if (entry.paidBy == memberId) credit -= amount;
    }
  }
  return credit;
}

typedef _ExpenseSettlementAction = void Function(
    LedgerEntry entry, String memberUid);
typedef _ExpenseObligation = ({
  LedgerEntry entry,
  String debtorUid,
  double amount,
});

Color _surfaceAccent(BuildContext context, Color color) =>
    Theme.of(context).brightness == Brightness.light
        ? Color.lerp(color, Colors.black, .28)!
        : color;

InputDecoration _transactionTextDecoration(
    BuildContext context, String label, IconData icon) {
  final isLight = Theme.of(context).brightness == Brightness.light;
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon,
        color: isLight ? AppColors.primary : const Color(0xFF9B8EFF)),
    filled: true,
    fillColor: isLight ? Colors.white : const Color(0xFF061321),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
          color: isLight ? AppColors.border : const Color(0xFF24527A)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
          color: isLight ? AppColors.primary : const Color(0xFF8C62FF),
          width: 1.8),
    ),
  );
}

InputDecoration _dropdownDecoration(
    BuildContext context, String label, IconData icon) {
  final isLight = Theme.of(context).brightness == Brightness.light;
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(
      icon,
      color: isLight ? AppColors.primary : const Color(0xFF9B8EFF),
    ),
    prefixIconConstraints: const BoxConstraints(minWidth: 46),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
    filled: true,
    fillColor: isLight ? Colors.white : const Color(0xFF061321),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
          color: isLight ? AppColors.border : const Color(0xFF24527A)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: isLight ? AppColors.primary : const Color(0xFF9B8EFF),
        width: 1.5,
      ),
    ),
  );
}

InputDecoration _amountDecoration(BuildContext context, String currencyCode) {
  final isLight = Theme.of(context).brightness == Brightness.light;
  return InputDecoration(
    labelText: 'Amount',
    hintText: '0.00',
    prefixIcon: Center(
      widthFactor: 1,
      child: Text(currencyForCode(currencyCode).symbol,
          style: TextStyle(
              color: isLight ? AppColors.success : const Color(0xFF65DDBA),
              fontSize: 20,
              fontWeight: FontWeight.w700)),
    ),
    prefixIconConstraints: const BoxConstraints(minWidth: 46),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
    filled: true,
    fillColor: isLight ? Colors.white : const Color(0xFF061321),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
          color: isLight ? AppColors.border : const Color(0xFF24527A),
          width: 1.2),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: isLight ? AppColors.primary : const Color(0xFF9B8EFF),
        width: 2,
      ),
    ),
  );
}

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
        decoration: _dropdownDecoration(context, label, leadingIcon),
        child: Row(children: [
          Expanded(
            child: Text(
              selected?.label ?? 'Select an option',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: selected == null
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.onSurface),
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
          Icon(Icons.keyboard_arrow_down_rounded,
              color: Theme.of(context).brightness == Brightness.light
                  ? AppColors.primary
                  : const Color(0xFFB7AEFF)),
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
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isLight ? AppColors.inputBackground : const Color(0xFF061321),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isLight ? AppColors.border : const Color(0xFF24527A)),
      ),
      child: Row(
        children: [
          _option(context, 'expense', 'Expense', Icons.receipt_long_rounded),
          const SizedBox(width: 4),
          _option(context, 'contribution', 'Deposit', Icons.savings_rounded),
        ],
      ),
    );
  }

  Widget _option(
      BuildContext context, String option, String label, IconData icon) {
    final selected = value == option;
    final inactive = Theme.of(context).brightness == Brightness.light
        ? const Color(0xFF555968)
        : Colors.white70;
    return Expanded(
      child: InkWell(
        onTap: () => onChanged(option),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? (Theme.of(context).brightness == Brightness.light
                    ? AppColors.primary
                    : const Color(0xFF7049E8))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? Colors.white : inactive),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(
                      color: selected ? Colors.white : inactive,
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

Widget _transactionDateTimeField(
    BuildContext context, DateTime value, VoidCallback onTap) {
  final isLight = Theme.of(context).brightness == Brightness.light;
  return Container(
    decoration: BoxDecoration(
      color: isLight ? Colors.white : const Color(0xFF061321),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
          color: isLight ? AppColors.border : const Color(0xFF24527A)),
    ),
    child: ListTile(
      onTap: onTap,
      leading: Icon(Icons.event_rounded,
          color: isLight ? AppColors.primary : const Color(0xFF9B8EFF)),
      title: Text('Transaction date & time',
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12)),
      subtitle: Text(DateFormat('d MMM yyyy, h:mm a').format(value),
          style: const TextStyle(fontWeight: FontWeight.w800)),
      trailing: const Icon(Icons.edit_calendar_rounded),
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.user,
    required this.themeController,
  });
  final User user;
  final AppThemeController themeController;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final DatabaseService database = DatabaseService(widget.user);

  @override
  void initState() {
    super.initState();
    _syncProfilePhoto();
  }

  Future<void> _syncProfilePhoto() async {
    try {
      await database.syncCurrentUserProfileToGroups();
    } catch (_) {
      // Existing group data still works with the initial fallback.
    }
  }

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
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
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
            foregroundColor: Colors.white,
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
                Text('Good to see you',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                Text(widget.user.displayName ?? 'Friend',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 17)),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'App settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AppSettingsScreen(
                  user: widget.user,
                  themeController: widget.themeController,
                ),
              ),
            ),
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      );

  Widget _hero(List<SplitGroup> groups) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final muted = isLight ? const Color(0xFFE5E2FF) : Colors.white70;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isLight
              ? const [Color(0xFF7163F4), Color(0xFF6254DF), Color(0xFF5148BA)]
              : const [Color(0xFF745CFF), Color(0xFF4738AE), Color(0xFF252055)],
        ),
        border: isLight ? Border.all(color: AppColors.primaryBorder) : null,
        boxShadow: [
          BoxShadow(
              color:
                  isLight ? const Color(0x185B4BE8) : const Color(0x445F4AE3),
              blurRadius: 35,
              offset: const Offset(0, 15))
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CONNECTED MONEY',
                    style: TextStyle(
                        fontSize: 11, letterSpacing: 1.6, color: muted)),
                const SizedBox(height: 10),
                Text('${groups.length}',
                    style: TextStyle(
                        color: isLight ? Colors.white : null,
                        fontSize: 38,
                        height: 1,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('active money circles', style: TextStyle(color: muted)),
              ],
            ),
          ),
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
                color: isLight
                    ? Colors.white.withValues(alpha: .15)
                    : Colors.white.withValues(alpha: .12),
                shape: BoxShape.circle),
            child: Icon(Icons.blur_circular_rounded,
                size: 40, color: isLight ? Colors.white : null),
          ),
        ],
      ),
    );
  }

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
              Text(
                  'Create a group for a trip, flat, food or anything you share.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: .55),
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
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
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
            Icon(Icons.arrow_forward_ios_rounded,
                size: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
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

  List<_DropdownChoice> _depositTargetChoices(
      {String? includeMemberUid, String? senderUid}) {
    final excludedUid = senderUid ?? currentUid;
    final choices = <_DropdownChoice>[
      const _DropdownChoice(
        value: 'wallet',
        label: 'Group wallet',
        subtitle: 'Admin confirmation required',
      ),
      ...orderedMembers
          .where((member) => member.uid != excludedUid)
          .map((member) => _DropdownChoice(
                value: 'member:${member.uid}',
                label: member.name,
                subtitle: 'Member deposit',
                avatarText: member.name.isEmpty ? '?' : member.name[0],
              )),
    ];
    if (includeMemberUid != null &&
        !group.members.containsKey(includeMemberUid)) {
      final former = group.formerMembers[includeMemberUid];
      choices.add(_DropdownChoice(
        value: 'member:$includeMemberUid',
        label: former?.name ?? 'Former member',
        subtitle: 'Historical recipient',
        avatarText: former?.name.isNotEmpty == true ? former!.name[0] : '?',
        isArchived: true,
      ));
    }
    return choices;
  }

  @override
  Widget build(BuildContext context) {
    final isLightTheme = Theme.of(context).brightness == Brightness.light;
    return Scaffold(
      backgroundColor:
          isLightTheme ? const Color(0xFFFBFAFF) : const Color(0xFF020711),
      appBar: AppBar(
        backgroundColor:
            isLightTheme ? const Color(0xFFFBFAFF) : const Color(0xFF020711),
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 68,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${group.emoji}  ${group.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 2),
          Text('Hey ${group.members[currentUid]?.name ?? 'friend'} 👋',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
        ]),
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
      body: SafeArea(
        top: false,
        child: StreamBuilder<List<LedgerEntry>>(
          stream: database.watchTransactions(group.id),
          builder: (context, snapshot) {
            final entries = snapshot.data ?? [];
            final contributed = entries
                .where((e) => e.isConfirmedDeposit && e.isWalletDeposit)
                .fold<double>(0, (sum, e) => sum + e.amount);
            final spent = entries
                .where((e) => e.type == 'expense')
                .fold<double>(0, (sum, e) => sum + e.walletUsed);
            final totalExpenses = entries
                .where((e) => e.type == 'expense')
                .fold<double>(0, (sum, e) => sum + e.amount);
            final myPersonalPaid = entries
                .where((e) => e.type == 'expense' && e.paidBy == currentUid)
                .fold<double>(0, (sum, e) => sum + e.personalPaid);
            var myOutstandingToReceive = 0.0;
            for (final entry in entries.where((entry) =>
                entry.type == 'expense' &&
                entry.paymentSource == 'personal' &&
                entry.personalPaid > 0)) {
              for (final share in entry.splitAmong.entries) {
                if (share.key == entry.paidBy ||
                    entry.settlements[share.key]?.isConfirmed == true) {
                  continue;
                }
                if (entry.paidBy == currentUid && share.key != currentUid) {
                  myOutstandingToReceive += share.value;
                }
              }
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                _SimpleMoneySummary(
                    currencyCode: group.currencyCode,
                    walletBalance: contributed - spent,
                    totalExpenses: totalExpenses,
                    youPaid: myPersonalPaid,
                    youReceive: myOutstandingToReceive),
                const SizedBox(height: 16),
                _MemberQuickStrip(
                  members: orderedMembers,
                  currentUid: currentUid,
                  onSelected: (member) => _openMemberDashboard(member, entries),
                  onViewAll: () => _openPeopleDirectory(entries),
                ),
                const SizedBox(height: 16),
                _HomeQuickActions(
                  onAddExpense: () => _addTransaction(context),
                  onSettle: () => _openSettlementScreen(entries),
                ),
                const SizedBox(height: 16),
                _HomeRecentActivity(
                  entries: entries,
                  currentUid: currentUid,
                  isAdmin: isAdmin,
                  members: {
                    ...group.formerMembers,
                    ...group.members,
                  },
                  currencyCode: group.currencyCode,
                  onViewAll: () => _openActivityScreen(entries),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openSettlementScreen(List<LedgerEntry> initialEntries) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (routeContext) => Scaffold(
          appBar: AppBar(
            title: Text('${group.emoji}  ${group.name}',
                style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          body: SafeArea(
            top: false,
            child: StreamBuilder<List<LedgerEntry>>(
              stream: database.watchTransactions(group.id),
              initialData: initialEntries,
              builder: (context, snapshot) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                children: [
                  _SettlementOverview(
                    entries: snapshot.data ?? initialEntries,
                    currentUid: currentUid,
                    isAdmin: isAdmin,
                    members: {...group.formerMembers, ...group.members},
                    currencyCode: group.currencyCode,
                    onRequestSettlement: _requestExpenseSettlement,
                    onConfirmSettlement: _confirmExpenseSettlement,
                    onRemindSettlement: _remindExpenseSettlement,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openActivityScreen(List<LedgerEntry> entries) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullTransactionHistoryScreen(
          entries: entries,
          currentUid: currentUid,
          isAdmin: isAdmin,
          onDelete: (entry) => database.deleteTransaction(group.id, entry.id),
          onEdit: (entry) => _editTransaction(context, entry),
          initialFilter: 'all',
          database: database,
          groupId: group.id,
          members: {...group.formerMembers, ...group.members},
          currencyCode: group.currencyCode,
          onConfirmDeposit: _confirmDeposit,
          onRejectDeposit: _rejectDeposit,
        ),
      ),
    );
  }

  void _openMemberDashboard(GroupMember member, List<LedgerEntry> entries) {
    showModalBottomSheet<void>(
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
    );
  }

  void _openPeopleDirectory(List<LedgerEntry> entries) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0x229B8EFF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child:
                    const Icon(Icons.groups_rounded, color: Color(0xFFB7AEFF)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('People & balances',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w900)),
                      Text('${group.members.length} active members',
                          style: TextStyle(
                              color: Theme.of(sheetContext)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 11)),
                    ]),
              ),
              IconButton(
                onPressed: () => Navigator.pop(sheetContext),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.separated(
                itemCount: orderedMembers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final member = orderedMembers[index];
                  final currentMemberRole =
                      member.uid == group.ownerId ? 'Admin' : 'Member';
                  final deposits =
                      _confirmedDepositCreditFor(entries, member.uid);
                  final settlements =
                      _confirmedSettlementCreditFor(entries, member.uid);
                  final share = entries
                      .where((entry) => entry.type == 'expense')
                      .fold<double>(
                          0,
                          (sum, entry) =>
                              sum + (entry.splitAmong[member.uid] ?? 0));
                  final personalPaid = entries
                      .where((entry) =>
                          entry.type == 'expense' && entry.paidBy == member.uid)
                      .fold<double>(
                          0, (sum, entry) => sum + entry.personalPaid);
                  final netCredit = math.max(
                      0.0, deposits + personalPaid - share + settlements);
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 5),
                      leading: _MemberAvatar(member: member),
                      title: Text(member.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                        member.uid == currentUid
                            ? 'You • $currentMemberRole'
                            : member.email.isEmpty
                                ? 'Member'
                                : member.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Net credit',
                                  style: TextStyle(
                                      color: Theme.of(sheetContext)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      fontSize: 9)),
                              Text(formatMoney(netCredit, group.currencyCode),
                                  style: const TextStyle(
                                      color: Color(0xFF65DDBA),
                                      fontWeight: FontWeight.w900)),
                            ]),
                        const SizedBox(width: 5),
                        const Icon(Icons.chevron_right_rounded),
                      ]),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _openMemberDashboard(member, entries);
                      },
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
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

  Future<void> _confirmDeposit(LedgerEntry entry) async {
    if (!entry.isPendingDeposit) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.verified_rounded,
            color: Color(0xFF65DDBA), size: 38),
        title: const Text('Confirm deposit?'),
        content: Text(
          '${formatMoney(entry.amount, group.currencyCode)} will be included in the confirmed balances.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await database.reviewDeposit(
      groupId: group.id,
      entry: entry,
      approve: true,
      reviewerName: group.members[currentUid]?.name ?? 'Admin',
      senderName: group.members[entry.paidBy]?.name ?? 'Member',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(milliseconds: 2500),
        content: Text('Deposit confirmed.'),
      ));
    }
  }

  Future<void> _rejectDeposit(LedgerEntry entry) async {
    if (!entry.isPendingDeposit) return;
    final reason = TextEditingController();
    final rejectionReason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        icon: const Icon(Icons.cancel_outlined,
            color: Color(0xFFFF837A), size: 38),
        title: const Text('Reject deposit?'),
        content: TextField(
          controller: reason,
          autofocus: true,
          maxLength: 120,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            hintText: 'Example: Amount not received',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD64D54)),
            onPressed: () => Navigator.pop(dialogContext, reason.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    reason.dispose();
    if (rejectionReason == null || !mounted) return;
    await database.reviewDeposit(
      groupId: group.id,
      entry: entry,
      approve: false,
      reviewerName: group.members[currentUid]?.name ?? 'Admin',
      senderName: group.members[entry.paidBy]?.name ?? 'Member',
      rejectionReason: rejectionReason,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(milliseconds: 2500),
        content: Text('Deposit rejected and the sender was mentioned.'),
      ));
    }
  }

  Future<void> _requestExpenseSettlement(
      LedgerEntry entry, String memberUid) async {
    final amount = entry.splitAmong[memberUid] ?? 0;
    if (amount <= 0 || memberUid != currentUid) return;
    final payer =
        group.members[entry.paidBy] ?? group.formerMembers[entry.paidBy];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.handshake_rounded,
            color: Color(0xFF9B8EFF), size: 38),
        title: const Text('Mark as settled?'),
        content: Text(
          '${formatMoney(amount, group.currencyCode)} settlement request will be sent to ${payer?.name ?? 'the payer'} for confirmation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await database.requestExpenseSettlement(
      groupId: group.id,
      entry: entry,
      debtorName: group.members[currentUid]?.name ?? 'Member',
      payerName: payer?.name ?? 'Payer',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(milliseconds: 2500),
        content: Text('Settlement request sent to the payer.'),
      ));
    }
  }

  Future<void> _confirmExpenseSettlement(
      LedgerEntry entry, String memberUid) async {
    final amount = entry.splitAmong[memberUid] ?? 0;
    final debtor = group.members[memberUid] ?? group.formerMembers[memberUid];
    if (amount <= 0 || debtor == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.verified_rounded,
            color: Color(0xFF65DDBA), size: 38),
        title: const Text('Confirm settlement?'),
        content: Text(
          '${debtor.name}’s ${formatMoney(amount, group.currencyCode)} share will be marked as settled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await database.confirmExpenseSettlement(
      groupId: group.id,
      entry: entry,
      debtorUid: memberUid,
      debtorName: debtor.name,
      confirmerName: group.members[currentUid]?.name ?? 'Admin',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(milliseconds: 2500),
        content: Text('Expense share marked as settled.'),
      ));
    }
  }

  Future<void> _remindExpenseSettlement(
      LedgerEntry entry, String memberUid) async {
    final amount = entry.splitAmong[memberUid] ?? 0;
    final debtor = group.members[memberUid] ?? group.formerMembers[memberUid];
    if (amount <= 0 || debtor == null) return;
    await database.remindExpenseSettlement(
      groupId: group.id,
      entry: entry,
      debtorName: debtor.name,
      payerName: group.members[currentUid]?.name ?? 'Admin',
      amount: amount,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 2500),
        content: Text('Reminder sent to ${debtor.name}.'),
      ));
    }
  }

  Future<void> _editTransaction(BuildContext context, LedgerEntry entry) async {
    final title = TextEditingController(text: entry.title);
    final amount = TextEditingController(text: entry.amount.toString());
    var category = entry.category;
    var paymentSource = entry.paymentSource;
    var depositTargetValue =
        entry.isMemberDeposit ? 'member:${entry.depositTo}' : 'wallet';
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
              20,
              4,
              20,
              math.max(
                    MediaQuery.viewInsetsOf(context).bottom,
                    MediaQuery.viewPaddingOf(context).bottom,
                  ) +
                  16,
            ),
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
                          items: _expenseCategoriesFor(group, include: category)
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
                        decoration:
                            _amountDecoration(context, group.currencyCode),
                      ),
                      const SizedBox(height: 12),
                      _transactionDateTimeField(context, occurredAt, () async {
                        final picked =
                            await _pickTransactionDateTime(context, occurredAt);
                        if (picked != null) {
                          setLocalState(() => occurredAt = picked);
                        }
                      }),
                      const SizedBox(height: 12),
                      if (entry.type == 'contribution')
                        _FriendlyDropdown(
                          value: depositTargetValue,
                          label: 'Deposit to',
                          leadingIcon: Icons.savings_rounded,
                          items: _depositTargetChoices(
                            includeMemberUid:
                                entry.isMemberDeposit ? entry.depositTo : null,
                            senderUid: entry.paidBy,
                          ),
                          onChanged: (value) =>
                              setLocalState(() => depositTargetValue = value!),
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
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
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
      final memberTarget = depositTargetValue.startsWith('member:');
      await database.updateDeposit(
        groupId: group.id,
        transactionId: entry.id,
        depositTarget: memberTarget ? 'member' : 'wallet',
        depositTo:
            memberTarget ? depositTargetValue.substring('member:'.length) : '',
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
    String paymentSource = isAdmin ? 'wallet' : 'personal';
    String depositTargetValue = 'wallet';
    var occurredAt = DateTime.now();
    final selected = group.members.keys.toSet();
    final title = TextEditingController();
    final amount = TextEditingController();
    final description = TextEditingController();
    final membersScrollController = ScrollController();
    var paymentMethod = 'manual';
    var paymentReference = '';
    var paymentAppStatus = '';
    var paymentDescription = '';
    var paymentLaunching = false;

    String? validateInput() {
      final enteredAmount = double.tryParse(amount.text.trim());
      if (type == 'expense' && title.text.trim().isEmpty) {
        return 'Enter the expense name';
      }
      if (enteredAmount == null || enteredAmount <= 0) {
        return 'Enter a valid amount';
      }
      if (type == 'expense' && selected.isEmpty) {
        return 'Select at least one member for the split';
      }
      return null;
    }

    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).brightness == Brightness.light
          ? const Color(0xFFFAF7FE)
          : const Color(0xFF030A13),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.92,
        child: StatefulBuilder(
          builder: (context, setLocalState) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              4,
              20,
              math.max(
                    MediaQuery.viewInsetsOf(context).bottom,
                    MediaQuery.viewPaddingOf(context).bottom,
                  ) +
                  16,
            ),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                  color: (type == 'expense'
                                          ? AppColors.primary
                                          : AppColors.success)
                                      .withValues(alpha: .14),
                                  borderRadius: BorderRadius.circular(14)),
                              child: Icon(
                                  type == 'expense'
                                      ? Icons.receipt_long_rounded
                                      : Icons.savings_rounded,
                                  color: type == 'expense'
                                      ? const Color(0xFF9B8EFF)
                                      : const Color(0xFF65DDBA)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        type == 'expense'
                                            ? 'Add expense'
                                            : 'Add deposit',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w900)),
                                    Text(
                                        type == 'expense'
                                            ? 'Record and split a group expense'
                                            : 'Move money securely',
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                            fontSize: 11)),
                                  ]),
                            ),
                          ]),
                          const SizedBox(height: 18),
                          _TransactionTypeSelector(
                            value: type,
                            onChanged: (value) =>
                                setLocalState(() => type = value),
                          ),
                          const SizedBox(height: 16),
                          if (type == 'expense') ...[
                            TextField(
                                controller: title,
                                decoration: _transactionTextDecoration(context,
                                    'What was it for?', Icons.edit_rounded)),
                            const SizedBox(height: 10),
                            _FriendlyDropdown(
                                value: category,
                                label: 'Category',
                                leadingIcon: Icons.category_rounded,
                                items: _expenseCategoriesFor(group)
                                    .map((value) => _DropdownChoice(
                                        value: value, label: value))
                                    .toList(),
                                onChanged: (value) =>
                                    setLocalState(() => category = value!)),
                            const SizedBox(height: 10),
                          ],
                          TextField(
                              controller: amount,
                              onChanged: type == 'contribution'
                                  ? (_) => setLocalState(() {})
                                  : null,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: _amountDecoration(
                                  context, group.currencyCode)),
                          const SizedBox(height: 10),
                          _transactionDateTimeField(context, occurredAt,
                              () async {
                            final picked = await _pickTransactionDateTime(
                                context, occurredAt);
                            if (picked != null) {
                              setLocalState(() => occurredAt = picked);
                            }
                          }),
                          const SizedBox(height: 10),
                          if (type == 'contribution')
                            _FriendlyDropdown(
                              value: depositTargetValue,
                              label: 'Deposit to',
                              leadingIcon: Icons.savings_rounded,
                              items: _depositTargetChoices(),
                              onChanged: (value) => setLocalState(
                                  () => depositTargetValue = value!),
                            ),
                          if (type == 'contribution') ...[
                            const SizedBox(height: 10),
                            TextField(
                              controller: description,
                              maxLength: 80,
                              decoration: _transactionTextDecoration(
                                context,
                                'Payment note (optional)',
                                Icons.notes_rounded,
                              ),
                            ),
                          ],
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
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
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
                                color: Theme.of(context).brightness ==
                                        Brightness.light
                                    ? Colors.white
                                    : const Color(0xFF061321),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: Theme.of(context).brightness ==
                                            Brightness.light
                                        ? AppColors.border
                                        : const Color(0xFF24527A)),
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
                                      secondary: _MemberAvatar(
                                          member: member, radius: 15),
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
                if (type == 'expense')
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: () {
                        final warning = validateInput();
                        if (warning != null) {
                          _showWarningToast(context, warning);
                          return;
                        }
                        Navigator.pop(context, true);
                      },
                      child: const Text('Add expense'),
                    ),
                  )
                else ...[
                  if (group.currencyCode != 'INR')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'UPI payments support INR groups only. You can still submit this deposit manually.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: paymentLaunching
                            ? null
                            : () {
                                final warning = validateInput();
                                if (warning != null) {
                                  _showWarningToast(context, warning);
                                  return;
                                }
                                Navigator.pop(context, true);
                              },
                        child: const Text('Submit manually'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: paymentLaunching ||
                                group.currencyCode != 'INR'
                            ? null
                            : () async {
                                final warning = validateInput();
                                if (warning != null) {
                                  _showWarningToast(context, warning);
                                  return;
                                }
                                setLocalState(() => paymentLaunching = true);
                                try {
                                  final memberTarget =
                                      depositTargetValue.startsWith('member:');
                                  final targetUid = memberTarget
                                      ? depositTargetValue
                                          .substring('member:'.length)
                                      : '';
                                  final targetName = memberTarget
                                      ? (group.members[targetUid]?.name ??
                                          'Group member')
                                      : group.name;
                                  final upiId = memberTarget
                                      ? await database.getMemberUpiId(
                                          group.id, targetUid)
                                      : await database
                                          .getGroupWalletUpiId(group.id);
                                  if (upiId.isEmpty) {
                                    if (context.mounted) {
                                      _showWarningToast(
                                        context,
                                        memberTarget
                                            ? '$targetName has not added a UPI ID yet'
                                            : 'The admin has not added a group wallet UPI ID yet',
                                      );
                                    }
                                    return;
                                  }
                                  final requestReference =
                                      'BROSPLIT${const Uuid().v4().replaceAll('-', '').substring(0, 20).toUpperCase()}';
                                  final note = description.text.trim().isEmpty
                                      ? 'BroSplit deposit to $targetName'
                                      : description.text.trim();
                                  final result = await UpiPaymentService().pay(
                                    payeeUpiId: upiId,
                                    payeeName: targetName,
                                    amount: double.parse(amount.text.trim()),
                                    transactionReference: requestReference,
                                    description: note,
                                  );
                                  if (!context.mounted) return;
                                  if (!result.canCreatePendingDeposit) {
                                    _showWarningToast(
                                      context,
                                      result.wasCancelled
                                          ? 'UPI payment cancelled. No deposit was created.'
                                          : result.status == 'failed'
                                              ? 'UPI payment failed. No deposit was created.'
                                              : 'Payment status was not returned. Check your payment app, then submit manually if money was debited.',
                                    );
                                    return;
                                  }
                                  paymentMethod = 'upi';
                                  paymentReference =
                                      result.transactionId.isNotEmpty
                                          ? result.transactionId
                                          : result.reference.isNotEmpty
                                              ? result.reference
                                              : requestReference;
                                  paymentAppStatus = result.status;
                                  paymentDescription = note;
                                  Navigator.pop(context, true);
                                } on PlatformException catch (error) {
                                  if (context.mounted) {
                                    _showWarningToast(
                                      context,
                                      error.code == 'NO_UPI_APP'
                                          ? 'Install a UPI payment app to continue'
                                          : 'Could not open UPI payment: ${error.message ?? error.code}',
                                    );
                                  }
                                } finally {
                                  if (context.mounted) {
                                    setLocalState(
                                        () => paymentLaunching = false);
                                  }
                                }
                              },
                        icon: paymentLaunching
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.open_in_new_rounded),
                        label: Text(() {
                          final value = double.tryParse(amount.text.trim());
                          return value == null || value <= 0
                              ? 'Pay with UPI'
                              : 'Pay ₹${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2)}';
                        }()),
                      ),
                    ),
                  ]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    membersScrollController.dispose();
    description.dispose();
    final value = double.tryParse(amount.text.trim());
    if (save != true || value == null || value <= 0) return;
    if (type == 'contribution') {
      final memberTarget = depositTargetValue.startsWith('member:');
      await database.addDeposit(
        groupId: group.id,
        depositTarget: memberTarget ? 'member' : 'wallet',
        depositTo:
            memberTarget ? depositTargetValue.substring('member:'.length) : '',
        amount: value,
        occurredAt: occurredAt.millisecondsSinceEpoch,
        paymentMethod: paymentMethod,
        paymentReference: paymentReference,
        paymentAppStatus: paymentAppStatus,
        paymentDescription: paymentDescription,
      );
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
  String walletUpiId = '';
  bool walletUpiLoading = true;
  bool get isAdmin => group.ownerId == widget.currentUid;

  @override
  void initState() {
    super.initState();
    _loadWalletUpiId();
  }

  Future<void> _loadWalletUpiId() async {
    try {
      final value = await widget.database.getGroupWalletUpiId(group.id);
      if (mounted) setState(() => walletUpiId = value);
    } catch (_) {
      if (mounted) setState(() => walletUpiId = '');
    } finally {
      if (mounted) setState(() => walletUpiLoading = false);
    }
  }

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
                gradient: LinearGradient(
                    colors: Theme.of(context).brightness == Brightness.light
                        ? const [
                            Color(0xFFEEEAFE),
                            Color(0xFFF3F1FF),
                            Color(0xFFEAF6F5)
                          ]
                        : const [Color(0xFF302A62), Color(0xFF172E3A)]),
              ),
              child: Row(children: [
                Text(group.emoji, style: const TextStyle(fontSize: 38)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(group.name,
                            style: TextStyle(
                                color: Theme.of(context).brightness ==
                                        Brightness.light
                                    ? AppColors.textPrimary
                                    : Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w900)),
                        Text(
                            isAdmin
                                ? 'Admin controls enabled'
                                : 'View-only group information',
                            style: TextStyle(
                                color: Theme.of(context).brightness ==
                                        Brightness.light
                                    ? const Color(0xFF626675)
                                    : Colors.white60)),
                      ]),
                ),
                Icon(isAdmin ? Icons.admin_panel_settings : Icons.lock_outline,
                    color: Theme.of(context).brightness == Brightness.light
                        ? AppColors.success
                        : const Color(0xFF65DDBA)),
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
              color: Theme.of(context).brightness == Brightness.light
                  ? AppColors.surface
                  : null,
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
              color: Theme.of(context).brightness == Brightness.light
                  ? AppColors.surface
                  : null,
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
            Card(
              color: Theme.of(context).brightness == Brightness.light
                  ? AppColors.surface
                  : null,
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined,
                    color: Color(0xFF65DDBA)),
                title: const Text('Group wallet UPI ID'),
                subtitle: Text(walletUpiLoading
                    ? 'Loading...'
                    : walletUpiId.isEmpty
                        ? 'Not set - UPI payment is unavailable'
                        : walletUpiId),
                trailing: isAdmin
                    ? const Icon(Icons.edit_rounded)
                    : const Icon(Icons.visibility_outlined),
                onTap: isAdmin && !walletUpiLoading ? _editWalletUpiId : null,
              ),
            ),
            const SizedBox(height: 12),
            _expenseCategoriesCard(),
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
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
              color: Theme.of(context).brightness == Brightness.light
                  ? AppColors.surface
                  : null,
              child: Column(
                children: group.members.values.map((member) {
                  final isOwner = member.uid == group.ownerId;
                  return Column(children: [
                    ListTile(
                      leading: _MemberAvatar(member: member),
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
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
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
              Text('Former members',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: group.formerMembers.values
                      .map((member) => ListTile(
                            leading: _MemberAvatar(member: member),
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

  Widget _expenseCategoriesCard() {
    final categories = _expenseCategoriesFor(group);
    return Card(
      color: Theme.of(context).brightness == Brightness.light
          ? AppColors.surface
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 12, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.category_rounded, color: Color(0xFFFFB45E)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Expense categories',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  Text('Available only inside this group',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12)),
                ],
              ),
            ),
            if (isAdmin)
              IconButton.filledTonal(
                onPressed: _addExpenseCategory,
                tooltip: 'Add category',
                icon: const Icon(Icons.add_rounded),
              )
            else
              Icon(Icons.visibility_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
          ]),
          const SizedBox(height: 13),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: categories
                .map((category) => Chip(
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFFF7F7FA)
                              : null,
                      side: Theme.of(context).brightness == Brightness.light
                          ? const BorderSide(color: Color(0xFFDFE1E8))
                          : null,
                      avatar: group.customExpenseCategories.any((item) =>
                              item.toLowerCase() == category.toLowerCase())
                          ? const Icon(Icons.star_rounded,
                              size: 16, color: Color(0xFFFFB45E))
                          : null,
                      label: Text(category),
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
        ]),
      ),
    );
  }

  Widget _accessCodeCard() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.light
              ? const Color(0xFFF4F1FF)
              : const Color(0xFF181827),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: Theme.of(context).brightness == Brightness.light
                  ? const Color(0xFFDCD6FF)
                  : const Color(0xFF3D3862)),
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.light
                    ? const Color(0xFFE8E4FF)
                    : const Color(0xFF2C2948),
                borderRadius: BorderRadius.circular(15)),
            child: const Icon(Icons.key_rounded, color: Color(0xFF9B8EFF)),
          ),
          const SizedBox(width: 13),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('GROUP ACCESS CODE',
                  style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.light
                          ? AppColors.textMuted
                          : Colors.white54,
                      fontSize: 11,
                      letterSpacing: 1.2)),
              const SizedBox(height: 4),
              Text(
                  group.accessCode.isEmpty
                      ? 'Not created yet'
                      : group.accessCode,
                  style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.light
                          ? const Color(0xFF252034)
                          : Colors.white,
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
                        Text('Used everywhere in this group',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 12)),
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

  Future<void> _editWalletUpiId() async {
    final controller = TextEditingController(text: walletUpiId);
    String? validation;
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Group wallet UPI ID'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'Deposits paid to the group wallet will open this UPI ID. Only the admin can change it.'),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'UPI ID',
                hintText: 'group@bank',
                errorText: validation,
                prefixIcon: const Icon(Icons.alternate_email_rounded),
              ),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            if (walletUpiId.isNotEmpty)
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, ''),
                  child: const Text('Remove')),
            FilledButton(
              onPressed: () {
                final draft = controller.text.trim();
                if (!DatabaseService.isValidUpiId(draft)) {
                  setDialogState(() => validation = 'Enter a valid UPI ID');
                  return;
                }
                Navigator.pop(dialogContext, draft);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value == null) return;
    try {
      await widget.database.updateGroupWalletUpiId(group.id, value);
      if (!mounted) return;
      setState(() => walletUpiId = value);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(value.isEmpty
            ? 'Group wallet UPI ID removed'
            : 'Group wallet UPI ID saved'),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save UPI ID: $error')));
    }
  }

  Future<void> _addExpenseCategory() async {
    var draft = '';
    final category = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Add expense category'),
        content: TextField(
          autofocus: true,
          maxLength: 30,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Category name',
            hintText: 'Example: Medical',
            prefixIcon: Icon(Icons.category_rounded),
          ),
          onChanged: (value) => draft = value,
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty) Navigator.pop(dialogContext, trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              final value = draft.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add'),
          ),
        ],
      ),
    );
    if (category == null || !mounted) return;
    final exists = _expenseCategoriesFor(group)
        .any((item) => item.toLowerCase() == category.toLowerCase());
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(milliseconds: 2500),
        content: Text('This category already exists in the group.'),
      ));
      return;
    }
    try {
      await widget.database.addExpenseCategory(group.id, category);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(milliseconds: 2500),
        content: Text('Could not add the category. Please try again.'),
      ));
      return;
    }
    if (!mounted) return;
    setState(() => group = group.copyWith(
          customExpenseCategories: [
            ...group.customExpenseCategories,
            category,
          ],
        ));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 2500),
      content: Text('$category added for ${group.name}.'),
    ));
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

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.member, this.radius = 20});

  final GroupMember? member;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final photoUri = Uri.tryParse(member?.photoUrl.trim() ?? '');
    final hasPhoto = photoUri != null &&
        (photoUri.scheme == 'https' || photoUri.scheme == 'http');
    final image = hasPhoto ? NetworkImage(photoUri.toString()) : null;
    final name = member?.name ?? '';
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).brightness == Brightness.light
          ? AppColors.primary
          : const Color(0xFF514987),
      foregroundColor: Colors.white,
      foregroundImage: image,
      onForegroundImageError: image == null ? null : (_, __) {},
      child: Text(name.isEmpty ? '?' : name[0]),
    );
  }
}

class _SimpleMoneySummary extends StatelessWidget {
  const _SimpleMoneySummary({
    required this.currencyCode,
    required this.walletBalance,
    required this.totalExpenses,
    required this.youPaid,
    required this.youReceive,
  });

  final String currencyCode;
  final double walletBalance;
  final double totalExpenses;
  final double youPaid;
  final double youReceive;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final border = isLight ? AppColors.border : const Color(0xFF343746);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity,
        height: 205,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          image: DecorationImage(
            image: AssetImage(isLight
                ? 'assets/branding/wallet_hero_light.png'
                : 'assets/branding/wallet_hero_dark.png'),
            fit: BoxFit.cover,
          ),
          border: Border.all(
              color:
                  isLight ? const Color(0xFFD9CEFF) : const Color(0xFF873DFF)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6B43EE).withValues(alpha: .22),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Stack(children: [
            if (!isLight)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      const Color(0xFF020617).withValues(alpha: .30),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 27, 145, 22),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Group balance',
                        style: TextStyle(
                            color: isLight
                                ? const Color(0xFF44445A)
                                : Colors.white70,
                            fontSize: 14)),
                    const SizedBox(height: 7),
                    Text(formatMoney(walletBalance, currencyCode),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: isLight
                                ? const Color(0xFF11152A)
                                : Colors.white,
                            fontSize: 35,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isLight
                            ? Colors.white.withValues(alpha: .84)
                            : const Color(0xFF0D3452).withValues(alpha: .88),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                            color:
                                const Color(0xFF36D89A).withValues(alpha: .28)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                                color: Color(0xFF2FD396),
                                shape: BoxShape.circle)),
                        const SizedBox(width: 7),
                        Text('Available to spend',
                            style: TextStyle(
                                color: isLight
                                    ? const Color(0xFF159C67)
                                    : Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Container(
        constraints: const BoxConstraints(minHeight: 118),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        decoration: BoxDecoration(
          color: isLight ? AppColors.surface : const Color(0xFF061321),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isLight ? border : const Color(0xFF1764A4)),
          boxShadow: isLight
              ? [
                  BoxShadow(
                      color: const Color(0xFF252A4A).withValues(alpha: .06),
                      blurRadius: 18,
                      offset: const Offset(0, 7))
                ]
              : null,
        ),
        child: Row(children: [
          Expanded(
            child: _SimpleMoneyMetric(
              icon: Icons.receipt_long_rounded,
              label: 'Total expense',
              value: formatMoney(totalExpenses, currencyCode),
              color: isLight ? AppColors.primary : const Color(0xFFB7AEFF),
            ),
          ),
          SizedBox(height: 88, child: VerticalDivider(color: border)),
          Expanded(
            child: _SimpleMoneyMetric(
              icon: Icons.payments_outlined,
              label: 'You paid',
              value: formatMoney(youPaid, currencyCode),
              color: isLight ? AppColors.expense : const Color(0xFFFF837A),
            ),
          ),
          SizedBox(height: 88, child: VerticalDivider(color: border)),
          Expanded(
            child: _SimpleMoneyMetric(
              icon: Icons.south_west_rounded,
              label: 'You get',
              value: formatMoney(youReceive, currencyCode),
              color: isLight ? AppColors.success : const Color(0xFF65DDBA),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _SimpleMoneyMetric extends StatelessWidget {
  const _SimpleMoneyMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .13),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: .20)),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.3,
                ),
              ),
            ),
          ),
        ]),
      );
}

class _HomeQuickActions extends StatelessWidget {
  const _HomeQuickActions({required this.onAddExpense, required this.onSettle});

  final VoidCallback onAddExpense;
  final VoidCallback onSettle;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: _HomeQuickAction(
            icon: Icons.add_rounded,
            title: 'Add expense',
            subtitle: 'Track any expense',
            color: AppColors.primary,
            onTap: onAddExpense,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _HomeQuickAction(
            icon: Icons.handshake_rounded,
            title: 'Settle up',
            subtitle: 'Clear balances',
            color: AppColors.success,
            onTap: onSettle,
          ),
        ),
      ]);
}

class _HomeQuickAction extends StatelessWidget {
  const _HomeQuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isLight
              ? [color.withValues(alpha: .09), Colors.white]
              : [color.withValues(alpha: .22), const Color(0xFF06101E)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: isLight ? .24 : .78)),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: isLight ? .10 : .22),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [color, color.withValues(alpha: .72)]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: color.withValues(alpha: .35), blurRadius: 10)
                    ]),
                child: Icon(icon, color: Colors.white, size: 23),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 9)),
                    ]),
              ),
              const Icon(Icons.chevron_right_rounded, size: 16),
            ]),
          ),
        ),
      ),
    );
  }
}

class _HomeRecentActivity extends StatelessWidget {
  const _HomeRecentActivity({
    required this.entries,
    required this.currentUid,
    required this.isAdmin,
    required this.members,
    required this.currencyCode,
    required this.onViewAll,
  });

  final List<LedgerEntry> entries;
  final String currentUid;
  final bool isAdmin;
  final Map<String, GroupMember> members;
  final String currencyCode;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final visible = isAdmin
        ? entries
        : entries.where((entry) {
            if (entry.type == 'contribution') {
              return entry.paidBy == currentUid ||
                  entry.depositTo == currentUid;
            }
            return entry.createdBy == currentUid ||
                entry.paidBy == currentUid ||
                entry.splitAmong.containsKey(currentUid);
          }).toList();
    final preview = visible.take(3).toList();
    final border = isLight ? AppColors.border : const Color(0xFF223B58);

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 8),
      decoration: BoxDecoration(
        color: isLight ? AppColors.surface : const Color(0xFF061321),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border),
      ),
      child: Column(children: [
        Row(children: [
          Text('Recent activity',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const Spacer(),
          TextButton.icon(
            onPressed: onViewAll,
            icon: const Text('View all'),
            label: const Icon(Icons.chevron_right_rounded, size: 18),
          ),
        ]),
        if (preview.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Text('No activity yet',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          )
        else
          for (var index = 0; index < preview.length; index++) ...[
            _HomeActivityRow(
              entry: preview[index],
              memberName: members[preview[index].paidBy]?.name ??
                  members[preview[index].createdBy]?.name ??
                  'Former member',
              currencyCode: currencyCode,
              onTap: onViewAll,
            ),
            if (index != preview.length - 1)
              Divider(height: 1, indent: 54, color: border),
          ],
      ]),
    );
  }
}

class _HomeActivityRow extends StatelessWidget {
  const _HomeActivityRow({
    required this.entry,
    required this.memberName,
    required this.currencyCode,
    required this.onTap,
  });

  final LedgerEntry entry;
  final String memberName;
  final String currencyCode;
  final VoidCallback onTap;

  IconData get icon => switch (entry.category.toLowerCase()) {
        'food' => Icons.restaurant_rounded,
        'travel' => Icons.airplanemode_active_rounded,
        'stay' => Icons.hotel_rounded,
        'shopping' => Icons.shopping_bag_rounded,
        'bills' => Icons.receipt_long_rounded,
        _ => entry.type == 'contribution'
            ? Icons.savings_rounded
            : Icons.payments_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final income = entry.type == 'contribution';
    final color = income ? AppColors.success : AppColors.primary;
    final date = DateFormat('d MMM, h:mm a')
        .format(DateTime.fromMillisecondsSinceEpoch(entry.createdAt));
    final subtitle = income
        ? 'Paid by $memberName'
        : entry.paymentSource == 'personal'
            ? 'Paid personally  •  by $memberName'
            : 'Paid from group wallet';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: color.withValues(alpha: .13), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 11),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
                '${income ? '+' : ''}${formatMoney(entry.amount, currencyCode)}',
                style: TextStyle(
                    color: income
                        ? AppColors.success
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(date,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 9)),
          ]),
        ]),
      ),
    );
  }
}

class _MemberQuickStrip extends StatelessWidget {
  const _MemberQuickStrip({
    required this.members,
    required this.currentUid,
    required this.onSelected,
    required this.onViewAll,
  });

  final List<GroupMember> members;
  final String currentUid;
  final ValueChanged<GroupMember> onSelected;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: isLight ? AppColors.surface : const Color(0xFF061321),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: isLight ? AppColors.border : const Color(0xFF223B58)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Members',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const Spacer(),
          TextButton.icon(
              onPressed: onViewAll,
              icon: const Text('View all'),
              label: const Icon(Icons.chevron_right_rounded, size: 18)),
        ]),
        const SizedBox(height: 4),
        SizedBox(
          height: 82,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: members.length > 3 ? 4 : members.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index == 3) {
                return InkWell(
                  onTap: onViewAll,
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 72,
                    child: Column(children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                        child: Center(
                          child: Text('+${members.length - 3}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 14)),
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text('More',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                );
              }
              final member = members[index];
              final isMe = member.uid == currentUid;
              return InkWell(
                onTap: () => onSelected(member),
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 72,
                  child: Column(children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isMe
                              ? (isLight
                                  ? AppColors.primary
                                  : const Color(0xFFB7AEFF))
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: _MemberAvatar(member: member, radius: 22),
                    ),
                    const SizedBox(height: 5),
                    Text(isMe ? 'You' : member.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: isMe
                                ? (isLight
                                    ? AppColors.primary
                                    : const Color(0xFFB7AEFF))
                                : Theme.of(context).colorScheme.onSurface,
                            fontSize: 10,
                            fontWeight:
                                isMe ? FontWeight.w900 : FontWeight.w600)),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// Kept as a reusable expanded analytics card for future dashboard views.
class ExpandedWalletAnalyticsCard extends StatelessWidget {
  const ExpandedWalletAnalyticsCard({
    super.key,
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
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final ink = isLight ? AppColors.textPrimary : Colors.white;
    final muted = isLight ? const Color(0xFF6E7280) : Colors.white54;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: isLight ? AppColors.border : const Color(0xFF315164)),
          boxShadow: [
            BoxShadow(
                color:
                    isLight ? const Color(0x145B4BE8) : const Color(0x241CA8A0),
                blurRadius: 24,
                spreadRadius: -12)
          ],
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isLight
                  ? const [
                      Color(0xFFF7F6FF),
                      Color(0xFFF3F7FF),
                      Color(0xFFF0FBF8)
                    ]
                  : const [Color(0xFF20374C), Color(0xFF102A30)])),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: (isLight ? AppColors.success : const Color(0xFF65DDBA))
                    .withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.account_balance_wallet_rounded,
                color: isLight ? AppColors.success : const Color(0xFF65DDBA),
                size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('AVAILABLE IN WALLET',
                  style: TextStyle(
                      letterSpacing: 1.2, fontSize: 10, color: muted)),
              Text(formatMoney(balance, currencyCode),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: ink,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1)),
            ]),
          ),
        ]),
        const SizedBox(height: 15),
        Row(children: [
          Expanded(
              child: _ExpandedWalletMiniStat(
                  currencyCode: currencyCode,
                  icon: Icons.south_west_rounded,
                  label: 'Added',
                  value: contributed,
                  color:
                      isLight ? AppColors.success : const Color(0xFF65DDBA))),
          Expanded(
              child: _ExpandedWalletMiniStat(
                  currencyCode: currencyCode,
                  icon: Icons.north_east_rounded,
                  label: 'Spent',
                  value: spent,
                  color: isLight ? AppColors.expense : const Color(0xFFFF837A)))
        ]),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Divider(
              height: 1, color: isLight ? AppColors.divider : Colors.white12),
        ),
        Row(children: [
          Expanded(
            child: _ExpandedWalletInsight(
              icon: Icons.account_balance_rounded,
              label: 'Your credit',
              value: formatMoney(currentNetCredit, currencyCode),
              caption: 'Net balance',
              color: isLight ? AppColors.success : const Color(0xFF65DDBA),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _ExpandedWalletInsight(
              icon: Icons.auto_graph_rounded,
              label: 'This month',
              value: formatMoney(currentMonthSpend, currencyCode),
              caption: topCategory == null
                  ? 'No spend yet'
                  : '$topCategory • ${monthChange <= 0 ? '↓' : '↑'}${monthChange.abs().toStringAsFixed(0)}%',
              color: isLight ? AppColors.warning : const Color(0xFFFFB45E),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _ExpandedWalletInsight extends StatelessWidget {
  const _ExpandedWalletInsight({
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
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color:
            isLight ? AppColors.surface : Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isLight ? AppColors.border : Colors.white10),
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
                style: TextStyle(
                    color: isLight ? AppColors.textSecondary : Colors.white60,
                    fontSize: 11)),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontSize: 15, fontWeight: FontWeight.w900)),
            Text(caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: isLight ? AppColors.textMuted : Colors.white38,
                    fontSize: 10)),
          ]),
        ),
      ]),
    );
  }
}

class _ExpandedWalletMiniStat extends StatelessWidget {
  const _ExpandedWalletMiniStat(
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
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Row(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                color: isLight ? AppColors.textSecondary : Colors.white54,
                fontSize: 12)),
        Text(formatMoney(value, currencyCode),
            style: TextStyle(
                color: isLight ? AppColors.textPrimary : Colors.white,
                fontWeight: FontWeight.w800))
      ])
    ]);
  }
}

class _SettlementOverview extends StatelessWidget {
  const _SettlementOverview({
    required this.entries,
    required this.currentUid,
    required this.isAdmin,
    required this.members,
    required this.currencyCode,
    required this.onRequestSettlement,
    required this.onConfirmSettlement,
    required this.onRemindSettlement,
  });

  final List<LedgerEntry> entries;
  final String currentUid;
  final bool isAdmin;
  final Map<String, GroupMember> members;
  final String currencyCode;
  final _ExpenseSettlementAction onRequestSettlement;
  final _ExpenseSettlementAction onConfirmSettlement;
  final _ExpenseSettlementAction onRemindSettlement;

  @override
  Widget build(BuildContext context) {
    final openObligations = <_ExpenseObligation>[];
    for (final entry in entries.where((entry) =>
        entry.type == 'expense' &&
        entry.paymentSource == 'personal' &&
        entry.personalPaid > 0)) {
      for (final share in entry.splitAmong.entries) {
        if (share.key == entry.paidBy ||
            share.value <= 0 ||
            entry.settlements[share.key]?.isConfirmed == true) {
          continue;
        }
        openObligations
            .add((entry: entry, debtorUid: share.key, amount: share.value));
      }
    }
    final outgoing = openObligations
        .where((item) =>
            item.debtorUid == currentUid && item.entry.paidBy != currentUid)
        .toList();
    final incoming = openObligations
        .where((item) =>
            item.entry.paidBy == currentUid && item.debtorUid != currentUid)
        .toList();
    final groupOversight = isAdmin
        ? openObligations
            .where((item) =>
                item.entry.paidBy != currentUid && item.debtorUid != currentUid)
            .toList()
        : <_ExpenseObligation>[];
    if (outgoing.isEmpty && incoming.isEmpty && groupOversight.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('How to settle',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0x2265DDBA),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: const Icon(Icons.handshake_outlined,
                      color: Color(0xFF65DDBA)),
                ),
                const SizedBox(height: 12),
                const Text('Everything is clear',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('No pending payments. Everyone is settled up.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12)),
              ]),
            ),
          ),
        ),
      ]);
    }

    final outgoingByPayer = <String, List<_ExpenseObligation>>{};
    for (final item in outgoing) {
      outgoingByPayer.putIfAbsent(item.entry.paidBy, () => []).add(item);
    }
    final incomingByDebtor = <String, List<_ExpenseObligation>>{};
    for (final item in incoming) {
      incomingByDebtor.putIfAbsent(item.debtorUid, () => []).add(item);
    }
    final oversightByPair = <String, List<_ExpenseObligation>>{};
    for (final item in groupOversight) {
      oversightByPair
          .putIfAbsent('${item.entry.paidBy}|${item.debtorUid}', () => [])
          .add(item);
    }

    final searchableObligations = isAdmin
        ? openObligations
        : <_ExpenseObligation>[...outgoing, ...incoming];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text('How to settle',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
        ),
        IconButton.filledTonal(
          onPressed: () =>
              _openSettlementFinder(context, searchableObligations),
          icon: const Icon(Icons.manage_search_rounded),
          tooltip: 'Find settlement',
        ),
      ]),
      const SizedBox(height: 3),
      Text('See who should pay whom, then settle in a few taps.',
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11)),
      const SizedBox(height: 10),
      if (outgoing.isNotEmpty)
        _settlementSection(
          context: context,
          title: 'You need to pay',
          emptyMessage: 'You do not owe anyone',
          icon: Icons.north_east_rounded,
          color: const Color(0xFFFFB45E),
          obligations: outgoing,
          rows: outgoingByPayer.entries.map((row) {
            return _settlementMemberRow(
              context: context,
              name: members[row.key]?.name ?? 'Former member',
              obligations: row.value,
              payerUid: row.key,
              debtorUid: currentUid,
              statusLabel: 'You pay',
            );
          }).toList(),
        ),
      if (outgoing.isNotEmpty && incoming.isNotEmpty) const SizedBox(height: 9),
      if (incoming.isNotEmpty)
        _settlementSection(
          context: context,
          title: 'Others owe you',
          emptyMessage: 'No one owes you right now',
          icon: Icons.south_west_rounded,
          color: const Color(0xFF65DDBA),
          obligations: incoming,
          rows: incomingByDebtor.entries.map((row) {
            return _settlementMemberRow(
              context: context,
              name: members[row.key]?.name ?? 'Former member',
              obligations: row.value,
              payerUid: currentUid,
              debtorUid: row.key,
              statusLabel: 'Pays you',
            );
          }).toList(),
        ),
      if (isAdmin && groupOversight.isNotEmpty) ...[
        const SizedBox(height: 9),
        _settlementSection(
          context: context,
          title: 'Group oversight',
          emptyMessage: 'No other member payments need attention',
          icon: Icons.admin_panel_settings_outlined,
          color: const Color(0xFF9B8EFF),
          obligations: groupOversight,
          rows: oversightByPair.values.map((obligations) {
            final payerUid = obligations.first.entry.paidBy;
            final debtorUid = obligations.first.debtorUid;
            return _settlementMemberRow(
              context: context,
              name:
                  '${members[debtorUid]?.name ?? 'Member'} → ${members[payerUid]?.name ?? 'Member'}',
              obligations: obligations,
              payerUid: payerUid,
              debtorUid: debtorUid,
              statusLabel: 'Manage',
            );
          }).toList(),
        ),
      ],
    ]);
  }

  Widget _settlementSection({
    required BuildContext context,
    required String title,
    required String emptyMessage,
    required IconData icon,
    required Color color,
    required List<_ExpenseObligation> obligations,
    required List<Widget> rows,
  }) {
    final total = obligations.fold<double>(0, (sum, item) => sum + item.amount);
    final pending = obligations
        .where(
            (item) => item.entry.settlements[item.debtorUid]?.isPending == true)
        .length;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 10),
        child: Column(children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text(
                      obligations.isEmpty
                          ? emptyMessage
                          : '${obligations.length} payment${obligations.length == 1 ? '' : 's'}${pending > 0 ? ' • $pending pending' : ''}',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11),
                    ),
                  ]),
            ),
            Text(formatMoney(total, currencyCode),
                style: TextStyle(color: color, fontWeight: FontWeight.w900)),
          ]),
          if (rows.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 9),
              child: Divider(height: 1),
            ),
            ...rows,
          ],
        ]),
      ),
    );
  }

  Widget _settlementMemberRow({
    required BuildContext context,
    required String name,
    required List<_ExpenseObligation> obligations,
    required String payerUid,
    required String debtorUid,
    required String statusLabel,
  }) {
    final total = obligations.fold<double>(0, (sum, item) => sum + item.amount);
    final pending = obligations
        .where(
            (item) => item.entry.settlements[item.debtorUid]?.isPending == true)
        .length;
    final isOutgoing = statusLabel == 'You pay';
    final isIncoming = statusLabel == 'Pays you';
    final title = isOutgoing
        ? 'You pay $name'
        : isIncoming
            ? '$name pays you'
            : name;
    return InkWell(
      onTap: () =>
          _openMemberDetails(context, payerUid, debtorUid, obligations),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        child: Row(children: [
          CircleAvatar(
            radius: 17,
            child: Text(name.isEmpty ? '?' : name[0]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                '${obligations.length} expense${obligations.length == 1 ? '' : 's'}${pending > 0 ? ' • $pending pending' : ''}',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(formatMoney(total, currencyCode),
                style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(isOutgoing ? 'Settle' : 'Review',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(width: 2),
          const Icon(Icons.chevron_right_rounded, size: 20),
        ]),
      ),
    );
  }

  Future<void> _openSettlementFinder(
      BuildContext context, List<_ExpenseObligation> obligations) async {
    var queryText = '';
    var filter = 'all';
    final selected = await showModalBottomSheet<_ExpenseObligation>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .88,
        child: StatefulBuilder(
          builder: (sheetContext, setLocalState) {
            final query = queryText.trim().toLowerCase();
            final filtered = obligations.where((item) {
              final payerName = members[item.entry.paidBy]?.name ?? '';
              final debtorName = members[item.debtorUid]?.name ?? '';
              final matchesType = switch (filter) {
                'pay' => item.debtorUid == currentUid,
                'receive' => item.entry.paidBy == currentUid,
                'group' => item.debtorUid != currentUid &&
                    item.entry.paidBy != currentUid,
                _ => true,
              };
              if (!matchesType) return false;
              if (query.isEmpty) return true;
              return payerName.toLowerCase().contains(query) ||
                  debtorName.toLowerCase().contains(query) ||
                  item.entry.title.toLowerCase().contains(query) ||
                  item.entry.category.toLowerCase().contains(query);
            }).toList()
              ..sort((a, b) => b.entry.createdAt.compareTo(a.entry.createdAt));
            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Find settlement',
                        style: TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text('Search by member, expense or category.',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 11)),
                    const SizedBox(height: 13),
                    TextField(
                      autofocus: true,
                      onChanged: (value) {
                        queryText = value;
                        setLocalState(() {});
                      },
                      decoration: const InputDecoration(
                        hintText: 'Search settlements',
                        prefixIcon: Icon(Icons.search_rounded),
                        suffixIcon: Icon(Icons.tune_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        _settlementFilterChip(
                            label: 'All',
                            value: 'all',
                            selected: filter,
                            onSelected: (value) =>
                                setLocalState(() => filter = value)),
                        _settlementFilterChip(
                            label: 'You pay',
                            value: 'pay',
                            selected: filter,
                            onSelected: (value) =>
                                setLocalState(() => filter = value)),
                        _settlementFilterChip(
                            label: 'You receive',
                            value: 'receive',
                            selected: filter,
                            onSelected: (value) =>
                                setLocalState(() => filter = value)),
                        if (isAdmin)
                          _settlementFilterChip(
                              label: 'Group',
                              value: 'group',
                              selected: filter,
                              onSelected: (value) =>
                                  setLocalState(() => filter = value)),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    Text('${filtered.length} matching open settlements',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 10)),
                    const SizedBox(height: 7),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text('No matching settlements',
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 7),
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                final payer = members[item.entry.paidBy];
                                final debtor = members[item.debtorUid];
                                final pending = item
                                        .entry
                                        .settlements[item.debtorUid]
                                        ?.isPending ==
                                    true;
                                return Card(
                                  margin: EdgeInsets.zero,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                    leading: _MemberAvatar(member: debtor),
                                    title: Text(
                                      '${debtor?.name ?? 'Member'} → ${payer?.name ?? 'Member'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800),
                                    ),
                                    subtitle: Text(
                                      '${item.entry.title} • ${item.entry.category} • ${pending ? 'Pending' : 'Unpaid'}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                              formatMoney(
                                                  item.amount, currencyCode),
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w900)),
                                          const Icon(
                                              Icons.chevron_right_rounded),
                                        ]),
                                    onTap: () {
                                      FocusScope.of(sheetContext).unfocus();
                                      Navigator.pop(sheetContext, item);
                                    },
                                  ),
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
    if (selected == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!context.mounted) return;
    await _openMemberDetails(
        context, selected.entry.paidBy, selected.debtorUid, [selected]);
  }

  Widget _settlementFilterChip({
    required String label,
    required String value,
    required String selected,
    required ValueChanged<String> onSelected,
  }) =>
      Padding(
        padding: const EdgeInsets.only(right: 7),
        child: ChoiceChip(
          label: Text(label),
          selected: selected == value,
          onSelected: (_) => onSelected(value),
        ),
      );

  Future<void> _openMemberDetails(BuildContext context, String payerUid,
      String debtorUid, List<_ExpenseObligation> obligations) {
    final payer = members[payerUid];
    final debtor = members[debtorUid];
    final canManage = isAdmin || currentUid == payerUid;
    final isDebtor = currentUid == debtorUid;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${debtor?.name ?? 'Member'} → ${payer?.name ?? 'Payer'}',
                style: Theme.of(sheetContext)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('Expense settlement details',
                style: TextStyle(
                    color:
                        Theme.of(sheetContext).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.separated(
                itemCount: obligations.length,
                separatorBuilder: (_, __) => const SizedBox(height: 9),
                itemBuilder: (context, index) {
                  final obligation = obligations[index];
                  final settlement =
                      obligation.entry.settlements[obligation.debtorUid];
                  final settled = settlement?.isConfirmed == true;
                  final pending = settlement?.isPending == true;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: Column(children: [
                        Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(obligation.entry.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800)),
                                Text(
                                  DateFormat('d MMM, h:mm a').format(
                                      DateTime.fromMillisecondsSinceEpoch(
                                          obligation.entry.createdAt)),
                                  style: TextStyle(
                                      color: Theme.of(sheetContext)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                    formatMoney(
                                        obligation.amount, currencyCode),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900)),
                                Text(
                                  settled
                                      ? 'Settled'
                                      : pending
                                          ? 'Pending'
                                          : 'Unpaid',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: settled
                                        ? (Theme.of(sheetContext).brightness ==
                                                Brightness.light
                                            ? AppColors.success
                                            : const Color(0xFF65DDBA))
                                        : pending
                                            ? (Theme.of(sheetContext)
                                                        .brightness ==
                                                    Brightness.light
                                                ? AppColors.warning
                                                : const Color(0xFFFFB45E))
                                            : Theme.of(sheetContext)
                                                .colorScheme
                                                .onSurfaceVariant,
                                  ),
                                ),
                              ]),
                        ]),
                        if (!settled && (isDebtor || canManage)) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(spacing: 7, runSpacing: 5, children: [
                              if (isDebtor && !pending)
                                TextButton.icon(
                                  onPressed: () {
                                    Navigator.pop(sheetContext);
                                    onRequestSettlement(
                                        obligation.entry, obligation.debtorUid);
                                  },
                                  icon: const Icon(Icons.handshake_outlined,
                                      size: 17),
                                  label: const Text('Settle'),
                                ),
                              if (canManage)
                                TextButton.icon(
                                  onPressed: () {
                                    Navigator.pop(sheetContext);
                                    onRemindSettlement(
                                        obligation.entry, obligation.debtorUid);
                                  },
                                  icon: const Icon(
                                      Icons.notifications_active_outlined,
                                      size: 17),
                                  label: const Text('Remind'),
                                ),
                              if (canManage && (pending || isAdmin))
                                FilledButton.icon(
                                  onPressed: () {
                                    Navigator.pop(sheetContext);
                                    onConfirmSettlement(
                                        obligation.entry, obligation.debtorUid);
                                  },
                                  icon:
                                      const Icon(Icons.check_rounded, size: 17),
                                  label: Text(pending ? 'Confirm' : 'Settle'),
                                ),
                            ]),
                          ),
                        ],
                      ]),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
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
    this.onConfirmDeposit,
    this.onRejectDeposit,
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
  final ValueChanged<LedgerEntry>? onConfirmDeposit;
  final ValueChanged<LedgerEntry>? onRejectDeposit;

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
              return entry.paidBy == widget.currentUid ||
                  entry.depositTo == widget.currentUid;
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
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        )
      else
        ...preview.map((entry) {
          final canModify = widget.isAdmin ||
              (entry.isPendingDeposit && entry.createdBy == widget.currentUid);
          final canReview = entry.isPendingDeposit &&
              (widget.isAdmin ||
                  (entry.isMemberDeposit &&
                      entry.depositTo == widget.currentUid));
          return _TransactionTile(
            entry: entry,
            canEdit:
                widget.onEdit != null && canModify && widget.canDelete != false,
            canDelete: (widget.canDelete ?? canModify) && canModify,
            canReview: canReview,
            onEdit: widget.onEdit == null ? null : () => widget.onEdit!(entry),
            onDelete: () => widget.onDelete(entry),
            onConfirm: widget.onConfirmDeposit == null
                ? null
                : () => widget.onConfirmDeposit!(entry),
            onReject: widget.onRejectDeposit == null
                ? null
                : () => widget.onRejectDeposit!(entry),
            database: widget.database,
            groupId: widget.groupId,
            members: widget.members,
            currencyCode: widget.currencyCode,
          );
        }),
      if (hasMore) ...[
        const SizedBox(height: 3),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _openFullHistory,
            icon: const Icon(Icons.history_rounded),
            label: const Text('View all transactions'),
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
            onConfirmDeposit: widget.onConfirmDeposit,
            onRejectDeposit: widget.onRejectDeposit,
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
    this.onConfirmDeposit,
    this.onRejectDeposit,
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
  final ValueChanged<LedgerEntry>? onConfirmDeposit;
  final ValueChanged<LedgerEntry>? onRejectDeposit;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Transaction history',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: SafeArea(
          top: false,
          child: database != null && groupId != null
              ? StreamBuilder<List<LedgerEntry>>(
                  stream: database!.watchTransactions(groupId!),
                  initialData: entries,
                  builder: (context, snapshot) =>
                      _historyList(snapshot.data ?? entries),
                )
              : _historyList(entries),
        ),
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
            onConfirmDeposit: onConfirmDeposit,
            onRejectDeposit: onRejectDeposit,
          ),
        ],
      );
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.entry,
    required this.canEdit,
    required this.canDelete,
    required this.canReview,
    required this.onDelete,
    required this.currencyCode,
    this.onEdit,
    this.onConfirm,
    this.onReject,
    this.database,
    this.groupId,
    this.members = const {},
  });
  static const _reactions = ['👍', '❤️', '😂', '😮', '😢', '🔥'];
  final LedgerEntry entry;
  final bool canEdit;
  final bool canDelete;
  final bool canReview;
  final VoidCallback onDelete;
  final String currencyCode;
  final VoidCallback? onEdit;
  final VoidCallback? onConfirm;
  final VoidCallback? onReject;
  final DatabaseService? database;
  final String? groupId;
  final Map<String, GroupMember> members;
  @override
  Widget build(BuildContext context) {
    final isIncome = entry.type == 'contribution';
    final contributor = members[entry.paidBy];
    final creator = members[entry.createdBy];
    final recipient = members[entry.depositTo];
    final senderName = contributor?.name ?? 'Former member';
    final depositRoute = entry.isMemberDeposit
        ? '$senderName → ${recipient?.name ?? 'Former member'}'
        : '$senderName → Group wallet';
    final depositStatus = entry.isPendingDeposit
        ? 'Pending confirmation'
        : entry.isRejectedDeposit
            ? 'Rejected'
            : 'Confirmed';
    final contributionNote =
        '$depositRoute • $depositStatus${entry.isRejectedDeposit && entry.rejectionReason.isNotEmpty ? ' • ${entry.rejectionReason}' : ''}';
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
            onTap: () => _showTransactionDetails(context),
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${isIncome ? contributionNote : '${entry.category}$paymentNote • Added by ${creator?.name ?? 'Former member'}'} • ${DateFormat('d MMM, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(entry.createdAt))}',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                  '${isIncome ? (entry.isMemberDeposit ? '↗ ' : '+') : '-'}${formatMoney(entry.amount, currencyCode)}',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: isIncome
                          ? entry.isRejectedDeposit
                              ? _surfaceAccent(context, const Color(0xFFFF837A))
                              : entry.isPendingDeposit
                                  ? _surfaceAccent(
                                      context, const Color(0xFFFFB45E))
                                  : _surfaceAccent(
                                      context, const Color(0xFF65DDBA))
                          : Theme.of(context).colorScheme.onSurface)),
              if (canEdit || canDelete)
                PopupMenuButton<String>(
                    itemBuilder: (_) => [
                          if (canEdit)
                            const PopupMenuItem(
                                height: 44,
                                padding: EdgeInsets.symmetric(horizontal: 14),
                                value: 'edit',
                                child: Row(children: [
                                  Icon(Icons.edit_rounded, size: 20),
                                  SizedBox(width: 10),
                                  Text('Edit'),
                                ])),
                          if (canDelete)
                            const PopupMenuItem(
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
          if (canReview && onConfirm != null && onReject != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF837A)),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onConfirm,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Confirm'),
                  ),
                ),
              ]),
            ),
          if (database != null && groupId != null) _reactionBar(context),
        ])));
  }

  Future<void> _showTransactionDetails(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isDeposit = entry.isDeposit;
    final payer = members[entry.paidBy];
    final creator = members[entry.createdBy];
    final recipient = members[entry.depositTo];
    final reviewer = members[entry.reviewedBy];
    final date = DateTime.fromMillisecondsSinceEpoch(entry.createdAt);
    final accent = isLight
        ? isDeposit
            ? entry.isRejectedDeposit
                ? AppColors.expense
                : entry.isPendingDeposit
                    ? AppColors.warning
                    : AppColors.success
            : AppColors.warning
        : isDeposit
            ? entry.isRejectedDeposit
                ? const Color(0xFFFF837A)
                : entry.isPendingDeposit
                    ? const Color(0xFFFFB45E)
                    : const Color(0xFF65DDBA)
            : const Color(0xFFFFD75E);
    return showModalBottomSheet<void>(
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
                child: Icon(
                  isDeposit
                      ? Icons.handshake_rounded
                      : Icons.receipt_long_rounded,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isDeposit ? 'Deposit details' : 'Expense details',
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
                      Text(isDeposit ? 'AMOUNT' : 'TOTAL EXPENSE',
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
                      Text(formatMoney(entry.amount, currencyCode),
                          style: TextStyle(
                              color: _surfaceAccent(sheetContext, accent),
                              fontSize: 32,
                              fontWeight: FontWeight.w900)),
                      if (!isDeposit) ...[
                        const SizedBox(height: 5),
                        Text(
                          entry.paymentSource == 'wallet'
                              ? 'Group wallet ${formatMoney(entry.walletUsed, currencyCode)}${entry.personalPaid > 0 ? ' + personal ${formatMoney(entry.personalPaid, currencyCode)}' : ''}'
                              : '${payer?.name ?? 'Former member'} paid personally',
                          style: TextStyle(
                              color: Theme.of(sheetContext)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        children: isDeposit
                            ? [
                                _detailRow(
                                    'Paid by', payer?.name ?? 'Former member'),
                                _detailRow(
                                    'Paid to',
                                    entry.isWalletDeposit
                                        ? 'Group wallet'
                                        : recipient?.name ?? 'Former member'),
                                _detailRow(
                                    'Status',
                                    entry.isPendingDeposit
                                        ? 'Pending confirmation'
                                        : entry.isRejectedDeposit
                                            ? 'Rejected'
                                            : 'Confirmed',
                                    valueColor:
                                        _surfaceAccent(sheetContext, accent)),
                                _detailRow(
                                    'Payment method',
                                    entry.paymentMethod == 'upi'
                                        ? 'UPI app'
                                        : 'Manual confirmation'),
                                if (entry.paymentReference.isNotEmpty)
                                  _detailRow(
                                      'UPI reference', entry.paymentReference),
                                if (entry.paymentDescription.isNotEmpty)
                                  _detailRow(
                                      'Payment note', entry.paymentDescription),
                                if (reviewer != null)
                                  _detailRow('Reviewed by', reviewer.name),
                                if (entry.rejectionReason.isNotEmpty)
                                  _detailRow(
                                      'Rejection reason', entry.rejectionReason,
                                      valueColor: const Color(0xFFFF837A)),
                                _detailRow('Date',
                                    DateFormat('d MMM yyyy').format(date)),
                                _detailRow(
                                    'Time', DateFormat('h:mm a').format(date),
                                    showDivider: false),
                              ]
                            : [
                                _detailRow('Category', entry.category),
                                _detailRow(
                                    'Paid by', payer?.name ?? 'Former member'),
                                _detailRow('Added by',
                                    creator?.name ?? 'Former member'),
                                _detailRow(
                                    'Payment source',
                                    entry.paymentSource == 'wallet'
                                        ? 'Group wallet'
                                        : 'Personal money'),
                                if (entry.personalPaid > 0)
                                  _detailRow(
                                      'Outside wallet',
                                      formatMoney(
                                          entry.personalPaid, currencyCode),
                                      valueColor: const Color(0xFF62B8FF)),
                                _detailRow('Date',
                                    DateFormat('d MMM yyyy').format(date)),
                                _detailRow(
                                    'Time', DateFormat('h:mm a').format(date),
                                    showDivider: false),
                              ]),
                  ),
                ),
                if (!isDeposit && entry.splitAmong.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Split shares',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Card(
                    color: Theme.of(context).brightness == Brightness.light
                        ? AppColors.surface
                        : null,
                    child: Column(
                      children: entry.splitAmong.entries.map((share) {
                        final member = members[share.key];
                        final settlement = entry.settlements[share.key];
                        final isPayer = share.key == entry.paidBy;
                        final status = isPayer
                            ? 'Paid the expense'
                            : settlement?.isConfirmed == true
                                ? 'Settled'
                                : settlement?.isPending == true
                                    ? 'Pending confirmation'
                                    : 'Unpaid';
                        return ListTile(
                          leading: _MemberAvatar(member: member),
                          title: Text(member?.name ?? 'Former member'),
                          subtitle: Text(status),
                          trailing: Text(formatMoney(share.value, currencyCode),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900)),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ]),
            ),
            if (!isDeposit &&
                database != null &&
                groupId != null &&
                entry.createdBy != database!.user.uid) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _questionExpense(
                      sheetContext, creator?.name ?? 'Former member'),
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text('Discuss in group'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFB45E),
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ),
            ],
            if (canReview && onConfirm != null && onReject != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      onReject?.call();
                    },
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF837A),
                        minimumSize: const Size.fromHeight(52)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      onConfirm?.call();
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Confirm'),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                  ),
                ),
              ]),
            ],
            if (canEdit || canDelete) ...[
              const SizedBox(height: 10),
              Row(children: [
                if (canDelete)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        onDelete();
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFF837A),
                          minimumSize: const Size.fromHeight(52)),
                    ),
                  ),
                if (canDelete && canEdit) const SizedBox(width: 10),
                if (canEdit)
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        onEdit?.call();
                      },
                      icon: const Icon(Icons.edit_rounded),
                      label: const Text('Edit'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52)),
                    ),
                  ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Future<void> _questionExpense(
      BuildContext sheetContext, String creatorName) async {
    var draft = '';
    String? error;
    final reason = await showModalBottomSheet<String>(
      context: sheetContext,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              20, 4, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0x22FFB45E),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.report_problem_outlined,
                    color: Color(0xFFFFB45E)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Discuss this expense',
                          style: TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w900)),
                      Text('The member who added it will be mentioned.',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 11)),
                    ]),
              ),
            ]),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.light
                    ? AppColors.primaryTint
                    : const Color(0xFF171925),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Theme.of(context).brightness == Brightness.light
                        ? AppColors.primaryBorder
                        : const Color(0xFF303345)),
              ),
              child: Text('@$creatorName  •  ${entry.title}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.light
                          ? AppColors.primary
                          : const Color(0xFFBEB5FF),
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              maxLength: 600,
              onChanged: (value) {
                draft = value;
                if (error != null && value.trim().isNotEmpty) {
                  setLocalState(() => error = null);
                }
              },
              decoration: InputDecoration(
                hintText: 'Explain what looks wrong with this expense',
                errorText: error,
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    final value = draft.trim();
                    if (value.isEmpty) {
                      setLocalState(
                          () => error = 'Enter a short reason or question.');
                      return;
                    }
                    Navigator.pop(context, value);
                  },
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Send'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
    if (reason == null || reason.isEmpty) return;
    if (!sheetContext.mounted) return;

    final messenger = ScaffoldMessenger.of(sheetContext);
    try {
      await database!.sendExpenseDiscussion(
        groupId: groupId!,
        entry: entry,
        creatorName: creatorName,
        reason: reason,
      );
      if (sheetContext.mounted) Navigator.pop(sheetContext);
      messenger.showSnackBar(const SnackBar(
        content: Text('Expense discussion sent to the group.'),
        duration: Duration(milliseconds: 2500),
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Could not send the discussion. Please try again.'),
        duration: Duration(milliseconds: 2500),
      ));
    }
  }

  Widget _detailRow(String label, String value,
          {Color? valueColor, bool showDivider = true}) =>
      Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 116,
              child: Builder(
                builder: (context) => Text(label,
                    style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.light
                            ? AppColors.textMuted
                            : const Color(0xFF858896))),
              ),
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
                    ? Text('Be the first to react',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 11))
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
                                      color: Theme.of(context).brightness ==
                                              Brightness.light
                                          ? AppColors.primaryTint
                                          : const Color(0xFF242638),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                          color: Theme.of(context).brightness ==
                                                  Brightness.light
                                              ? AppColors.border
                                              : const Color(0xFF3A3D54)),
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
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
            const SizedBox(height: 12),
            ...reactedMembers.map((member) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _MemberAvatar(member: member),
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
    final deposits = _confirmedDepositCreditFor(entries, member.uid);
    final settlements = _confirmedSettlementCreditFor(entries, member.uid);
    final share = entries
        .where((e) => e.type == 'expense')
        .fold<double>(0, (s, e) => s + (e.splitAmong[member.uid] ?? 0));
    final paid = entries
        .where((e) => e.type == 'expense' && e.paidBy == member.uid)
        .fold<double>(0, (s, e) => s + e.personalPaid);
    final score = math.max(0.0, deposits + paid - share + settlements);
    return SafeArea(
        child: FractionallySizedBox(
            heightFactor: .88,
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        _MemberAvatar(member: member, radius: 26),
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
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant))
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
                                label: 'Deposit credit',
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
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12)),
        const SizedBox(height: 5),
        Text(formatMoney(value, currencyCode),
            style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 18, color: color))
      ]));
}
