import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';

/// Google sign-in, and nothing else. Who the signed-in user *is* inside a
/// company is [SessionService]'s job.
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _google = GoogleSignIn.instance;

  final ValueNotifier<bool> busy = ValueNotifier<bool>(false);
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  bool _initialized = false;

  User? get currentUser => _auth.currentUser;

  Future<void> initialize() async {
    if (!AppConfig.isGoogleSignInConfigured) {
      // Calling initialize with a placeholder id throws, and the thrown error
      // is far less clear than saying so on the sign-in screen.
      debugPrint('offixia: Google server client id not configured yet.');
      return;
    }
    await _google.initialize(serverClientId: AppConfig.googleServerClientId);
    _initialized = true;
  }

  Future<void> signInWithGoogle() async {
    if (!AppConfig.isGoogleSignInConfigured) {
      error.value =
          'Google sign-in is not configured yet. Enable Google as a sign-in '
          'provider in the Firebase console, then rebuild with the web client '
          'id in --dart-define=GOOGLE_SERVER_CLIENT_ID.';
      return;
    }

    busy.value = true;
    error.value = null;
    try {
      if (!_initialized) await initialize();

      final account = await _google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw Exception(
          'Google did not return an ID token. Check that the SHA-1 of the '
          'signing key is registered on the Firebase Android app.',
        );
      }
      await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    } on GoogleSignInException catch (e) {
      // Backing out of the account picker is not an error worth showing.
      if (e.code != GoogleSignInExceptionCode.canceled) {
        error.value = e.description ?? 'Google sign-in failed.';
      }
    } catch (e) {
      error.value = e.toString().replaceFirst('Exception: ', '');
    } finally {
      busy.value = false;
    }
  }

  Future<void> signOut() async {
    busy.value = true;
    error.value = null;
    try {
      await _auth.signOut();
      if (_initialized) await _google.signOut();
    } catch (e) {
      error.value = e.toString().replaceFirst('Exception: ', '');
    } finally {
      busy.value = false;
    }
  }
}
