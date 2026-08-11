import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/app_update_service.dart';
import 'app_update_dialog.dart';

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.child});
  final Widget child;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (_checked || kIsWeb || !Platform.isAndroid || !mounted) return;
    _checked = true;
    final service = AppUpdateService();
    try {
      final update = await service.checkForUpdate();
      if (update == null || !mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: !update.info.forceUpdate,
        builder: (_) => AppUpdateDialog(update: update, service: service),
      );
    } catch (_) {
      // Update checks must never prevent normal app startup. A later launch retries.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
