import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/app_models.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import 'about_screen.dart';

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

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
                        Text('Your circles', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const Spacer(),
                        Text('${groups.length} groups', style: const TextStyle(color: Colors.white54)),
                      ],
                    ),
                  ),
                ),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
                else if (groups.isEmpty)
                  SliverFillRemaining(hasScrollBody: false, child: _emptyState())
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
        onPressed: _createGroup,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New group'),
      ),
    );
  }

  Widget _header() => Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: const Color(0xFF29263F),
            backgroundImage: widget.user.photoURL == null ? null : NetworkImage(widget.user.photoURL!),
            child: widget.user.photoURL == null ? Text((widget.user.displayName ?? 'F')[0]) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Good to see you', style: TextStyle(color: Colors.white54)),
                Text(widget.user.displayName ?? 'Friend', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
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
            tooltip: 'About friendlyhood-split',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
            icon: const Icon(Icons.info_outline_rounded),
          ),
          IconButton(onPressed: AuthService().signOut, icon: const Icon(Icons.logout_rounded)),
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
          boxShadow: const [BoxShadow(color: Color(0x445F4AE3), blurRadius: 35, offset: Offset(0, 15))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CONNECTED MONEY', style: TextStyle(fontSize: 11, letterSpacing: 1.6, color: Colors.white70)),
                  const SizedBox(height: 10),
                  Text('${groups.length}', style: const TextStyle(fontSize: 38, height: 1, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  const Text('active money circles', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), shape: BoxShape.circle),
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
              const Icon(Icons.group_add_rounded, size: 68, color: Color(0xFF8B7CFF)),
              const SizedBox(height: 18),
              Text('Start your first circle', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Create a group for a trip, flat, food or anything you share.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      );

  Future<void> _createGroup() async {
    final name = TextEditingController();
    String emoji = '✈️';
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Create a money circle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                children: ['✈️', '🍕', '🏠', '🎉', '🏏'].map((item) => ChoiceChip(
                      label: Text(item, style: const TextStyle(fontSize: 20)),
                      selected: emoji == item,
                      onSelected: (_) => setLocalState(() => emoji = item),
                    )).toList(),
              ),
              const SizedBox(height: 18),
              TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Group name', hintText: 'Goa getaway')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (created == true && name.text.trim().isNotEmpty) {
      await database.createGroup(name.text.trim(), emoji);
      _message('Group created — you are the admin');
    }
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.database, required this.currentUid});
  final SplitGroup group;
  final DatabaseService database;
  final String currentUid;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => GroupScreen(group: group, database: database, currentUid: currentUid),
          )),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFF242137), borderRadius: BorderRadius.circular(18)),
                  child: Text(group.emoji, style: const TextStyle(fontSize: 27)),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(child: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
                        if (group.ownerId == currentUid) ...[
                          const SizedBox(width: 7),
                          const Icon(Icons.verified_rounded, size: 16, color: Color(0xFF65DDBA)),
                        ],
                      ]),
                      const SizedBox(height: 5),
                      Text('${group.members.length} members • ${group.ownerId == currentUid ? 'Admin' : 'View only'}', style: const TextStyle(color: Colors.white54)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: Colors.white38),
              ],
            ),
          ),
        ),
      );
}

class GroupScreen extends StatelessWidget {
  const GroupScreen({super.key, required this.group, required this.database, required this.currentUid});
  final SplitGroup group;
  final DatabaseService database;
  final String currentUid;

  bool get isAdmin => group.ownerId == currentUid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${group.emoji}  ${group.name}', style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (isAdmin) IconButton(onPressed: () => _addMember(context), icon: const Icon(Icons.person_add_alt_1_rounded), tooltip: 'Add member'),
        ],
      ),
      body: StreamBuilder<List<LedgerEntry>>(
        stream: database.watchTransactions(group.id),
        builder: (context, snapshot) {
          final entries = snapshot.data ?? [];
          final contributed = entries.where((e) => e.type == 'contribution').fold<double>(0, (sum, e) => sum + e.amount);
          final spent = entries.where((e) => e.type == 'expense').fold<double>(0, (sum, e) => sum + e.amount);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
            children: [
              _WalletCard(balance: contributed - spent, contributed: contributed, spent: spent),
              const SizedBox(height: 22),
              _MySnapshot(entries: entries, uid: currentUid),
              const SizedBox(height: 26),
              Row(children: [
                Text('Members', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                Text('${group.members.length}', style: const TextStyle(color: Colors.white54)),
              ]),
              const SizedBox(height: 10),
              SizedBox(
                height: 83,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: group.members.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final member = group.members.values.elementAt(index);
                    return InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => _MemberDashboard(member: member, entries: entries),
                      ),
                      child: Container(
                        width: 112,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFF151721), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF252836))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [CircleAvatar(radius: 13, child: Text(member.name.isEmpty ? '?' : member.name[0])), const Spacer(), if (member.role == 'admin') const Icon(Icons.shield_rounded, size: 15, color: Color(0xFF65DDBA))]),
                          const Spacer(),
                          Text(member.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 26),
              Text('Activity', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              if (entries.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(28), child: Center(child: Text('No activity yet', style: TextStyle(color: Colors.white54)))))
              else
                ...entries.map((entry) => _TransactionTile(
                      entry: entry,
                      canDelete: isAdmin,
                      onDelete: () => database.deleteTransaction(group.id, entry.id),
                    )),
            ],
          );
        },
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _addTransaction(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add transaction'),
            )
          : null,
    );
  }

  Future<void> _addMember(BuildContext context) async {
    final uid = TextEditingController();
    final name = TextEditingController();
    final email = TextEditingController();
    final save = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Add a viewer'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Ask your friend to copy their Member ID from the home screen.', style: TextStyle(color: Colors.white60)),
        const SizedBox(height: 16),
        TextField(controller: uid, decoration: const InputDecoration(labelText: 'Member ID')),
        const SizedBox(height: 10),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 10),
        TextField(controller: email, decoration: const InputDecoration(labelText: 'Email (optional)')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add'))],
    ));
    if (save == true && uid.text.trim().isNotEmpty && name.text.trim().isNotEmpty) {
      await database.addMember(group.id, uid.text.trim(), name.text.trim(), email.text.trim());
    }
  }

  Future<void> _addTransaction(BuildContext context) async {
    String type = 'expense';
    String category = 'Food';
    String paidBy = group.members.keys.first;
    final selected = group.members.keys.toSet();
    final title = TextEditingController();
    final amount = TextEditingController();
    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(builder: (context, setLocalState) => Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('New transaction', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 18),
          SegmentedButton<String>(segments: const [ButtonSegment(value: 'expense', label: Text('Expense'), icon: Icon(Icons.receipt_long_rounded)), ButtonSegment(value: 'contribution', label: Text('Deposit'), icon: Icon(Icons.savings_rounded))], selected: {type}, onSelectionChanged: (value) => setLocalState(() => type = value.first)),
          const SizedBox(height: 16),
          if (type == 'expense') ...[
            TextField(controller: title, decoration: const InputDecoration(labelText: 'What was it for?')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(initialValue: category, decoration: const InputDecoration(labelText: 'Category'), items: ['Food', 'Travel', 'Stay', 'Shopping', 'Bills', 'Other'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(), onChanged: (value) => category = value!),
            const SizedBox(height: 10),
          ],
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(initialValue: paidBy, decoration: InputDecoration(labelText: type == 'expense' ? 'Paid from / by' : 'Contributed by'), items: group.members.values.map((member) => DropdownMenuItem(value: member.uid, child: Text(member.name))).toList(), onChanged: (value) => paidBy = value!),
          if (type == 'expense') ...[
            const SizedBox(height: 18),
            const Text('Split equally between', style: TextStyle(fontWeight: FontWeight.w700)),
            ...group.members.values.map((member) => CheckboxListTile(contentPadding: EdgeInsets.zero, title: Text(member.name), value: selected.contains(member.uid), onChanged: (checked) => setLocalState(() => checked == true ? selected.add(member.uid) : selected.remove(member.uid)))),
          ],
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, height: 54, child: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save transaction'))),
        ])),
      )),
    );
    final value = double.tryParse(amount.text.trim());
    if (save != true || value == null || value <= 0) return;
    if (type == 'contribution') {
      await database.addContribution(groupId: group.id, memberId: paidBy, amount: value);
    } else if (title.text.trim().isNotEmpty && selected.isNotEmpty) {
      await database.addExpense(groupId: group.id, title: title.text.trim(), category: category, amount: value, paidBy: paidBy, memberIds: selected.toList());
    }
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.balance, required this.contributed, required this.spent});
  final double balance;
  final double contributed;
  final double spent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: const LinearGradient(colors: [Color(0xFF23354A), Color(0xFF132B31)])),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('GROUP WALLET', style: TextStyle(letterSpacing: 1.5, fontSize: 11, color: Colors.white60)),
      const SizedBox(height: 8),
      Text(_money.format(balance), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1)),
      const SizedBox(height: 22),
      Row(children: [Expanded(child: _MiniStat(icon: Icons.south_west_rounded, label: 'Added', value: contributed, color: const Color(0xFF65DDBA))), Expanded(child: _MiniStat(icon: Icons.north_east_rounded, label: 'Spent', value: spent, color: const Color(0xFFFF837A)))]),
    ]),
  );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(children: [Icon(icon, color: color, size: 20), const SizedBox(width: 8), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)), Text(_money.format(value), style: const TextStyle(fontWeight: FontWeight.w800))])]);
}

class _MySnapshot extends StatelessWidget {
  const _MySnapshot({required this.entries, required this.uid});
  final List<LedgerEntry> entries;
  final String uid;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final thisMonth = entries.where((e) { final d = DateTime.fromMillisecondsSinceEpoch(e.createdAt); return d.year == now.year && d.month == now.month; }).toList();
    final lastDate = DateTime(now.year, now.month - 1);
    final lastMonth = entries.where((e) { final d = DateTime.fromMillisecondsSinceEpoch(e.createdAt); return d.year == lastDate.year && d.month == lastDate.month; }).toList();
    double owed(List<LedgerEntry> list) => list.where((e) => e.type == 'expense').fold(0, (sum, e) => sum + (e.splitAmong[uid] ?? 0));
    final current = owed(thisMonth);
    final previous = owed(lastMonth);
    final change = previous == 0 ? 0.0 : ((current - previous) / previous) * 100;
    final categories = <String, double>{};
    for (final e in thisMonth.where((e) => e.type == 'expense' && e.splitAmong.containsKey(uid))) { categories[e.category] = (categories[e.category] ?? 0) + (e.splitAmong[uid] ?? 0); }
    final top = categories.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Card(child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [
      Container(width: 46, height: 46, decoration: BoxDecoration(color: const Color(0xFF2C2948), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.auto_graph_rounded, color: Color(0xFF9B8EFF))),
      const SizedBox(width: 13),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Your month', style: TextStyle(color: Colors.white54, fontSize: 12)), Text('${_money.format(current)} spent', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)), Text(top.isEmpty ? 'No category insights yet' : 'Most on ${top.first.key}', style: const TextStyle(color: Colors.white54, fontSize: 12))])),
      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: (change <= 0 ? const Color(0xFF65DDBA) : const Color(0xFFFF837A)).withValues(alpha: .12), borderRadius: BorderRadius.circular(12)), child: Text('${change <= 0 ? '↓' : '↑'} ${change.abs().toStringAsFixed(0)}%', style: TextStyle(color: change <= 0 ? const Color(0xFF65DDBA) : const Color(0xFFFF837A), fontWeight: FontWeight.w800))),
    ])));
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.entry, required this.canDelete, required this.onDelete});
  final LedgerEntry entry;
  final bool canDelete;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) {
    final isIncome = entry.type == 'contribution';
    return Padding(padding: const EdgeInsets.only(bottom: 9), child: Card(child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
      leading: CircleAvatar(backgroundColor: (isIncome ? const Color(0xFF65DDBA) : const Color(0xFFFF837A)).withValues(alpha: .12), child: Icon(isIncome ? Icons.savings_rounded : _categoryIcon(entry.category), color: isIncome ? const Color(0xFF65DDBA) : const Color(0xFFFF837A))),
      title: Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${entry.category} • ${DateFormat('d MMM, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(entry.createdAt))}'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text('${isIncome ? '+' : '-'}${_money.format(entry.amount)}', style: TextStyle(fontWeight: FontWeight.w900, color: isIncome ? const Color(0xFF65DDBA) : Colors.white)), if (canDelete) PopupMenuButton(itemBuilder: (_) => [const PopupMenuItem(value: true, child: Text('Delete'))], onSelected: (_) => onDelete())]),
    )));
  }
  IconData _categoryIcon(String value) => switch (value) { 'Food' => Icons.restaurant_rounded, 'Travel' => Icons.directions_car_rounded, 'Stay' => Icons.bed_rounded, 'Shopping' => Icons.shopping_bag_rounded, 'Bills' => Icons.receipt_rounded, _ => Icons.payments_rounded };
}

class _MemberDashboard extends StatelessWidget {
  const _MemberDashboard({required this.member, required this.entries});
  final GroupMember member;
  final List<LedgerEntry> entries;
  @override
  Widget build(BuildContext context) {
    final deposits = entries.where((e) => e.type == 'contribution' && e.paidBy == member.uid).fold<double>(0, (s, e) => s + e.amount);
    final share = entries.where((e) => e.type == 'expense').fold<double>(0, (s, e) => s + (e.splitAmong[member.uid] ?? 0));
    final paid = entries.where((e) => e.type == 'expense' && e.paidBy == member.uid).fold<double>(0, (s, e) => s + e.amount);
    final score = math.max(0.0, deposits + paid - share);
    return SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [CircleAvatar(radius: 26, child: Text(member.name.isEmpty ? '?' : member.name[0], style: const TextStyle(fontSize: 20))), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(member.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)), Text(member.email, style: const TextStyle(color: Colors.white54))]))]),
      const SizedBox(height: 26),
      Text('Personal dashboard', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      Row(children: [Expanded(child: _Metric(label: 'Deposited', value: deposits, color: const Color(0xFF65DDBA))), const SizedBox(width: 10), Expanded(child: _Metric(label: 'Own share', value: share, color: const Color(0xFFFFB45E)))]),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: _Metric(label: 'Paid bills', value: paid, color: const Color(0xFF9B8EFF))), const SizedBox(width: 10), Expanded(child: _Metric(label: 'Net credit', value: score, color: const Color(0xFF62B8FF)))]),
      const SizedBox(height: 14),
    ])));
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)), const SizedBox(height: 5), Text(_money.format(value), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: color))]));
}
