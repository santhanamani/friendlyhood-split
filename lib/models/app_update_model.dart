class AppUpdateInfo {
  const AppUpdateInfo({
    required this.latestVersion,
    required this.latestVersionCode,
    required this.apkUrl,
    required this.forceUpdate,
    required this.updateTitle,
    required this.updateMessage,
  });

  final String latestVersion;
  final int latestVersionCode;
  final Uri apkUrl;
  final bool forceUpdate;
  final String updateTitle;
  final String updateMessage;

  factory AppUpdateInfo.fromMap(Map<dynamic, dynamic> data) {
    final url = Uri.tryParse(data['apkUrl']?.toString() ?? '');
    final versionCode =
        int.tryParse(data['latestVersionCode']?.toString() ?? '');
    if (url == null || url.scheme != 'https' || versionCode == null) {
      throw const FormatException('Invalid app update configuration.');
    }

    return AppUpdateInfo(
      latestVersion:
          data['latestVersion']?.toString() ?? versionCode.toString(),
      latestVersionCode: versionCode,
      apkUrl: url,
      forceUpdate: data['forceUpdate'] == true,
      updateTitle: data['updateTitle']?.toString().trim().isNotEmpty == true
          ? data['updateTitle'].toString()
          : 'New update available',
      updateMessage: data['updateMessage']?.toString().trim().isNotEmpty == true
          ? data['updateMessage'].toString()
          : 'A newer version of FrenSplit is ready.',
    );
  }
}

class AvailableAppUpdate {
  const AvailableAppUpdate({
    required this.info,
    required this.installedVersion,
    required this.installedVersionCode,
  });

  final AppUpdateInfo info;
  final String installedVersion;
  final int installedVersionCode;
}
