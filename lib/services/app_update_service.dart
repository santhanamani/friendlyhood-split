import 'dart:async';
import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_update_model.dart';

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AppUpdateService {
  AppUpdateService({FirebaseDatabase? database})
      : _database = database ?? FirebaseDatabase.instance;

  static const _installerChannel = MethodChannel('com.friendlyhood.split/app_update');
  final FirebaseDatabase _database;

  Future<AvailableAppUpdate?> checkForUpdate() async {
    final results = await Future.wait([
      _database.ref('app_update').get().timeout(const Duration(seconds: 12)),
      PackageInfo.fromPlatform(),
    ]);
    final snapshot = results[0] as DataSnapshot;
    final package = results[1] as PackageInfo;
    if (!snapshot.exists || snapshot.value is! Map) return null;

    final update = AppUpdateInfo.fromMap(
      Map<dynamic, dynamic>.from(snapshot.value! as Map),
    );
    final installedCode = int.tryParse(package.buildNumber) ?? 0;
    if (update.latestVersionCode <= installedCode) return null;

    return AvailableAppUpdate(
      info: update,
      installedVersion: package.version,
      installedVersionCode: installedCode,
    );
  }

  Future<String> downloadApk(
    AvailableAppUpdate update, {
    required void Function(double? progress) onProgress,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    File? destination;
    IOSink? sink;
    try {
      final request = await client.getUrl(update.info.apkUrl).timeout(const Duration(seconds: 20));
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.android.package-archive,*/*');
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AppUpdateException('Download server returned ${response.statusCode}.');
      }
      if (response.redirects.any((redirect) => redirect.location.scheme != 'https')) {
        throw const AppUpdateException('The update URL redirected to an insecure location.');
      }

      final directory = await getTemporaryDirectory();
      destination = File('${directory.path}${Platform.pathSeparator}friendlyhood-${update.info.latestVersionCode}.apk');
      if (await destination.exists()) await destination.delete();
      sink = destination.openWrite();
      final total = response.contentLength;
      var received = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 45))) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(total > 0 ? received / total : null);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final header = await destination.openRead(0, 2).fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
      if (header.length < 2 || header[0] != 0x50 || header[1] != 0x4B) {
        await destination.delete();
        throw const AppUpdateException('The downloaded file is not a valid APK.');
      }
      onProgress(1);
      return destination.path;
    } on SocketException {
      if (destination != null && await destination.exists()) await destination.delete();
      throw const AppUpdateException('No internet connection. Check your network and retry.');
    } on TimeoutException {
      if (destination != null && await destination.exists()) await destination.delete();
      throw const AppUpdateException('The update download timed out. Please retry.');
    } on AppUpdateException {
      rethrow;
    } catch (_) {
      if (destination != null && await destination.exists()) await destination.delete();
      throw const AppUpdateException('Unable to download the update. Please retry.');
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  Future<bool> canInstallPackages() async {
    return await _installerChannel.invokeMethod<bool>('canInstallPackages') ?? false;
  }

  Future<void> openInstallPermissionSettings() {
    return _installerChannel.invokeMethod<void>('openInstallPermissionSettings');
  }

  Future<void> launchInstaller(String apkPath) {
    return _installerChannel.invokeMethod<void>('launchInstaller', {'path': apkPath});
  }
}
