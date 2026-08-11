import 'package:flutter/material.dart';

import '../models/app_update_model.dart';
import '../services/app_update_service.dart';

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    super.key,
    required this.update,
    required this.service,
  });

  final AvailableAppUpdate update;
  final AppUpdateService service;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog>
    with WidgetsBindingObserver {
  double? _progress;
  bool _downloading = false;
  bool _awaitingPermission = false;
  String? _downloadedApkPath;
  String? _error;

  bool get _forceUpdate => widget.update.info.forceUpdate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingPermission) {
      _continueAfterPermission();
    }
  }

  Future<void> _startUpdate() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });

    try {
      final path = _downloadedApkPath ??
          await widget.service.downloadApk(
            widget.update,
            onProgress: (progress) {
              if (mounted) setState(() => _progress = progress);
            },
          );
      _downloadedApkPath = path;
      if (!mounted) return;

      if (await widget.service.canInstallPackages()) {
        await _launchInstaller(path);
      } else {
        setState(() {
          _downloading = false;
          _awaitingPermission = true;
          _error =
              'Allow “Install unknown apps” for BroSplit, then return here.';
        });
        await widget.service.openInstallPermissionSettings();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = error is AppUpdateException
            ? error.message
            : 'Unable to start the update. Please retry.';
      });
    }
  }

  Future<void> _continueAfterPermission() async {
    _awaitingPermission = false;
    try {
      if (!await widget.service.canInstallPackages()) {
        if (mounted) {
          setState(() {
            _error =
                'Installation permission was not enabled. Tap Update Now to try again.';
          });
        }
        return;
      }
      final path = _downloadedApkPath;
      if (path != null) await _launchInstaller(path);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Could not verify installation permission. Please retry.');
      }
    }
  }

  Future<void> _launchInstaller(String path) async {
    setState(() {
      _downloading = false;
      _error = null;
    });
    await widget.service.launchInstaller(path);
  }

  @override
  Widget build(BuildContext context) {
    final latest = widget.update.info;
    final percent =
        _progress == null ? null : (_progress! * 100).clamp(0, 100).round();

    return PopScope(
      canPop: !_forceUpdate && !_downloading,
      child: AlertDialog(
        icon: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8B7CFF), Color(0xFF35D6B4)],
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Icon(Icons.system_update_alt_rounded, size: 34),
        ),
        title: Text(latest.updateTitle, textAlign: TextAlign.center),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                latest.updateMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.45),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1C28),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                        child: _Version(
                            label: 'Current',
                            value:
                                '${widget.update.installedVersion} (${widget.update.installedVersionCode})')),
                    const Icon(Icons.arrow_forward_rounded,
                        color: Colors.white38),
                    Expanded(
                        child: _Version(
                            label: 'Latest',
                            value:
                                '${latest.latestVersion} (${latest.latestVersionCode})',
                            highlight: true)),
                  ],
                ),
              ),
              if (_downloading) ...[
                const SizedBox(height: 20),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Text(
                  percent == null
                      ? 'Downloading update…'
                      : 'Downloading… $percent%',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Color(0xFFFF9B92), fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          if (!_forceUpdate && !_downloading)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later'),
            ),
          FilledButton.icon(
            onPressed: _downloading ? null : _startUpdate,
            icon: const Icon(Icons.download_rounded),
            label: Text(
                _downloadedApkPath == null ? 'Update Now' : 'Continue Update'),
          ),
        ],
      ),
    );
  }
}

class _Version extends StatelessWidget {
  const _Version(
      {required this.label, required this.value, this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: highlight ? const Color(0xFF65DDBA) : Colors.white,
            ),
          ),
        ],
      );
}
