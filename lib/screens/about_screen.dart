import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_update_model.dart';
import '../services/app_update_service.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final Future<_AboutData> _data = _loadData();

  Future<_AboutData> _loadData() async {
    final package = await PackageInfo.fromPlatform();
    AppUpdateInfo? release;
    try {
      release = await AppUpdateService().getLatestRelease();
    } catch (_) {
      // About must remain available even when Firebase or the network is down.
    }
    return _AboutData(package: package, release: release);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('About',
              style: TextStyle(fontWeight: FontWeight.w800))),
      body: FutureBuilder<_AboutData>(
        future: _data,
        builder: (context, snapshot) {
          final data = snapshot.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
            children: [
              const _BrandHero(),
              const SizedBox(height: 18),
              _VersionCard(
                  data: data,
                  loading: snapshot.connectionState == ConnectionState.waiting),
              const SizedBox(height: 26),
              const _SectionTitle(
                  title: 'Who we are', icon: Icons.people_alt_rounded),
              const SizedBox(height: 10),
              const _StoryCard(
                text:
                    'We are friends building for friends. BroSplit is a simple, transparent shared-money companion made for trips, food, homes and every moment a group enjoys together.',
              ),
              const SizedBox(height: 22),
              const _SectionTitle(
                  title: 'Our vision', icon: Icons.visibility_rounded),
              const SizedBox(height: 10),
              const _StoryCard(
                text:
                    'Life is Simple. Our vision is a world where money never creates awkwardness between friends—every shared expense is clear, fair and easy to understand.',
                accent: Color(0xFF65DDBA),
              ),
              const SizedBox(height: 22),
              const _SectionTitle(
                  title: 'Our mission', icon: Icons.rocket_launch_rounded),
              const SizedBox(height: 10),
              const _StoryCard(
                text:
                    'To make group spending effortless through secure shared wallets, instant splits and useful personal insights, while keeping every member informed.',
                accent: Color(0xFFFFB45E),
              ),
              const SizedBox(height: 30),
              Center(
                child: Text(
                  'Built with care for every friendlyhood  •  Made in India',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BrandHero extends StatelessWidget {
  const _BrandHero();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF745CFF), Color(0xFF372B86), Color(0xFF173C3A)],
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x445F4AE3),
                blurRadius: 34,
                offset: Offset(0, 14)),
          ],
        ),
        child: const Column(
          children: [
            _AppMark(),
            SizedBox(height: 18),
            Text(
              'BroSplit',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.8),
            ),
            SizedBox(height: 7),
            Text(
              'Spend together. Settle smarter.',
              style:
                  TextStyle(color: Colors.white70, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
}

class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) => Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: Colors.white24),
        ),
        child: const Icon(Icons.hub_rounded, size: 36),
      );
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({required this.data, required this.loading});
  final _AboutData? data;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final installed = data == null
        ? '—'
        : '${data!.package.version} (${data!.package.buildNumber})';
    final release = data?.release;
    final latest = release == null
        ? 'Unavailable'
        : '${release.latestVersion} (${release.latestVersionCode})';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            if (loading) const LinearProgressIndicator(minHeight: 2),
            _InfoRow(
                icon: Icons.phone_android_rounded,
                label: 'Installed version',
                value: installed),
            const Divider(height: 25),
            _InfoRow(
                icon: Icons.new_releases_rounded,
                label: 'Latest release',
                value: latest,
                highlight: true),
            if (release != null && release.updateMessage.isNotEmpty) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(release.updateMessage,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.highlight = false});
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon,
              color: highlight
                  ? const Color(0xFF65DDBA)
                  : const Color(0xFF9B8EFF)),
          const SizedBox(width: 13),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: highlight
                      ? const Color(0xFF26A884)
                      : Theme.of(context).colorScheme.onSurface)),
        ],
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF9B8EFF)),
          const SizedBox(width: 9),
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
        ],
      );
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({required this.text, this.accent = const Color(0xFF9B8EFF)});
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(19),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(21),
          border: Border(
              left: BorderSide(color: accent, width: 3),
              top: BorderSide(color: Theme.of(context).dividerColor),
              right: BorderSide(color: Theme.of(context).dividerColor),
              bottom: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Text(text,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.55,
                fontSize: 14)),
      );
}

class _AboutData {
  const _AboutData({required this.package, required this.release});
  final PackageInfo package;
  final AppUpdateInfo? release;
}
