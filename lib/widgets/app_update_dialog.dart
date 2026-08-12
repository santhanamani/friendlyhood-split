import 'package:flutter/material.dart';

import '../models/app_update_model.dart';
import '../services/app_update_service.dart';
import '../theme/app_colors.dart';

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
    final isLight = Theme.of(context).brightness == Brightness.light;
    final colors = Theme.of(context).colorScheme;
    final percent =
        _progress == null ? null : (_progress! * 100).clamp(0, 100).round();

    return PopScope(
      canPop: !_forceUpdate && !_downloading,
      child: AlertDialog(
        backgroundColor: isLight ? AppColors.surface : null,
        surfaceTintColor: Colors.transparent,
        shadowColor: isLight ? AppColors.primary.withValues(alpha: 0.16) : null,
        icon: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isLight
                  ? const [AppColors.primaryLight, AppColors.primaryTint]
                  : const [Color(0xFF8B7CFF), Color(0xFF35D6B4)],
            ),
            borderRadius: BorderRadius.circular(22),
            border: isLight ? Border.all(color: AppColors.border) : null,
          ),
          child: Icon(Icons.system_update_alt_rounded,
              size: 34, color: isLight ? AppColors.primary : Colors.white),
        ),
        title: Text(
          latest.updateTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isLight ? AppColors.textPrimary : colors.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                latest.updateMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isLight
                      ? AppColors.textSecondary
                      : colors.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:
                      isLight ? AppColors.surfaceSoft : const Color(0xFF1A1C28),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color:
                          isLight ? AppColors.border : const Color(0xFF2D3040)),
                ),
                child: Row(
                  children: [
                    Expanded(
                        child: _Version(
                            label: 'Current',
                            value:
                                '${widget.update.installedVersion} (${widget.update.installedVersionCode})')),
                    Icon(Icons.arrow_forward_rounded,
                    color: isLight
                        ? AppColors.textMuted
                        : colors.onSurfaceVariant),
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
                  style: TextStyle(
                    color: isLight
                        ? AppColors.textSecondary
                        : colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isLight
                        ? AppColors.expense
                        : const Color(0xFFFF9B92),
                    fontSize: 13,
                  ),
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Column(children: [
      Text(label,
          style: TextStyle(
            color: isLight ? AppColors.textMuted : colors.onSurfaceVariant,
            fontSize: 11,
          )),
      const SizedBox(height: 4),
      Text(
        value,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: highlight
              ? _updateAccent(context)
              : (isLight ? AppColors.textPrimary : colors.onSurface),
        ),
      ),
    ]);
  }

  Color _updateAccent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? AppColors.success
          : const Color(0xFF65DDBA);
}
