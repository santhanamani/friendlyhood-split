import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase values that are safe to commit can be injected with --dart-define.
/// For Android/iOS, running `flutterfire configure` is the recommended setup.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return const FirebaseOptions(
        apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
        appId: String.fromEnvironment('FIREBASE_APP_ID'),
        messagingSenderId: '196126657592',
        projectId: 'friends-split-up',
        authDomain: 'friends-split-up.firebaseapp.com',
        databaseURL: 'https://friends-split-up-default-rtdb.firebaseio.com',
        storageBucket: 'friends-split-up.firebasestorage.app',
      );
    }
    return const FirebaseOptions(
      apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
      appId: String.fromEnvironment('FIREBASE_APP_ID'),
      messagingSenderId: '196126657592',
      projectId: 'friends-split-up',
      databaseURL: 'https://friends-split-up-default-rtdb.firebaseio.com',
      storageBucket: 'friends-split-up.firebasestorage.app',
      iosBundleId: 'com.friendlyhood.split',
    );
  }
}
