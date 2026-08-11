import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

class SignInFailure implements Exception {
  const SignInFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _database = FirebaseDatabase.instance;

  Future<void> signInWithGoogle() async {
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final result = await _auth.signInWithCredential(credential);
      final user = result.user!;
      await _database.ref('users/${user.uid}').update({
        'displayName': user.displayName ?? 'Friend',
        'email': user.email ?? '',
        'photoUrl': user.photoURL ?? '',
        'lastSeenAt': ServerValue.timestamp,
      });
    } on PlatformException catch (error) {
      final details = '${error.code} ${error.message} ${error.details}';
      if (details.contains('10') || details.contains('DEVELOPER_ERROR')) {
        throw const SignInFailure(
          'Google Sign-In setup incomplete. Add this app’s SHA fingerprint '
          'in Firebase, then install the latest google-services.json.',
        );
      }
      throw SignInFailure(error.message ?? 'Google Sign-In failed.');
    } on FirebaseAuthException catch (error) {
      throw SignInFailure(error.message ?? 'Firebase sign-in failed.');
    }
  }

  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }
}
