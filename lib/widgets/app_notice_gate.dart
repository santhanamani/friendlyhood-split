import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class AppNoticeGate extends StatelessWidget {
  const AppNoticeGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => StreamBuilder<DatabaseEvent>(
        stream: FirebaseDatabase.instance.ref('app_notice').onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return const _NoticeScreen(
              type: 'server_down',
              title: 'Server unavailable',
              message:
                  'We cannot connect to BroSplit right now. Please try again shortly.',
            );
          }
          final raw = snapshot.data?.snapshot.value;
          final data = raw is Map ? Map<dynamic, dynamic>.from(raw) : const {};
          final enabled = data['enabled'] == true;
          if (!enabled) return child;
          return _NoticeScreen(
            type: data['type']?.toString() ?? 'maintenance',
            title: data['title']?.toString() ?? 'We’ll be right back',
            message: data['message']?.toString() ??
                'BroSplit is temporarily unavailable for maintenance.',
          );
        },
      );
}

class _NoticeScreen extends StatelessWidget {
  const _NoticeScreen({
    required this.type,
    required this.title,
    required this.message,
  });

  final String type;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final serverDown = type == 'server_down' || type == 'outage';
    final color =
        serverDown ? const Color(0xFFFF837A) : const Color(0xFFFFB45E);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: .35)),
                  ),
                  child: Icon(
                    serverDown
                        ? Icons.cloud_off_rounded
                        : Icons.engineering_rounded,
                    size: 54,
                    color: color,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  serverDown ? 'SERVER STATUS' : 'MAINTENANCE MODE',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    letterSpacing: 1.8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 16, height: 1.5)),
                const SizedBox(height: 28),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171925),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFF2D3040)),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Checking service status automatically'),
                  ]),
                ),
                const SizedBox(height: 14),
                const Text('Changes are temporarily disabled',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
