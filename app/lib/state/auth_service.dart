import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart';

/// A sign-in failure with the REAL code and a plain meaning.
class AuthFailure implements Exception {
  final String code;
  final String meaning;
  final String raw;
  AuthFailure(this.code, this.meaning, [this.raw = '']);
  @override
  String toString() => '$code: $meaning';
}

class AuthService {
  static final _auth = FirebaseAuth.instance;

  /// One shared GoogleSignIn object: Google remembers the account on the phone,
  /// so the next sign-in can happen silently without asking again.
  static GoogleSignIn? _google;
  static GoogleSignIn get _googleIn {
    const web = DefaultFirebaseOptions.googleWebClientId;
    return _google ??= GoogleSignIn(serverClientId: web.isEmpty ? null : web);
  }

  static Future<void> signInEmail(String email, String pass) =>
      _wrap(() => _auth.signInWithEmailAndPassword(email: email.trim(), password: pass));

  static Future<void> register(String name, String email, String pass) => _wrap(() async {
        final c = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: pass);
        if (name.trim().isNotEmpty) await c.user?.updateDisplayName(name.trim());
      });

  static Future<void> resetPassword(String email) =>
      _wrap(() => _auth.sendPasswordResetEmail(email: email.trim()));

 static Future<void> signInGoogle() => _wrap(() async {
        final g = _googleIn;
        // Try the account Google already saved on this phone first: no prompt.
        GoogleSignInAccount? acc = await g.signInSilently();
        acc ??= await g.signIn();
        if (acc == null) throw AuthFailure('cancelled', 'Sign-in was cancelled.');
        final a = await acc.authentication;
        if (a.idToken == null) {
          throw AuthFailure('no-id-token',
              'Google returned no ID token. The Google provider or the web client ID is not set up - tell the app owner (START-HERE option 6 fixes it).');
        }
        await _auth.signInWithCredential(
            GoogleAuthProvider.credential(idToken: a.idToken, accessToken: a.accessToken));
      });

  /// Quietly signs back in with the Google account already saved on the phone
  /// (no prompt, no button). Returns true when a Firebase user is signed in
  /// afterwards. Used at app start so the user only signs in once.
  static Future<bool> signInGoogleSilently() async {
    if (_auth.currentUser != null) return true;
    try {
      final acc = await _googleIn.signInSilently();
      if (acc == null) return false;
      final a = await acc.authentication;
      final idToken = a.idToken;
      if (idToken == null) return false;
      await _auth.signInWithCredential(
          GoogleAuthProvider.credential(idToken: idToken, accessToken: a.accessToken));
      return true;
    } catch (_) {
      return false;
    }
  }

 static Future<void> signOut() async {
    try {
      await _googleIn.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  static Future<T> _wrap<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on AuthFailure {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(e.code, _firebaseMeaning(e.code), e.message ?? '');
    } on PlatformException catch (e) {
      throw _googleFailure(e);
    } catch (e) {
      throw AuthFailure('unknown', 'Unexpected error.', '$e');
    }
  }

  static String _firebaseMeaning(String code) {
    switch (code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Email or password is wrong.';
      case 'user-not-found':
        return 'No account with this email.';
      case 'email-already-in-use':
        return 'An account with this email already exists - sign in instead.';
      case 'weak-password':
        return 'Password is too weak (use at least 6 characters).';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'network-request-failed':
        return 'No internet connection, or Google services are blocked on this network.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a few minutes and try again.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled in Firebase. Tell the app owner (START-HERE option 3, Health check).';
      case 'user-disabled':
        return 'This account was disabled in the Firebase console.';
      case 'account-exists-with-different-credential':
        return 'This email already uses another sign-in method (email/password). Sign in with that.';
      case 'app-not-authorized':
      case 'invalid-api-key':
        return 'The app is not authorized for this Firebase project (wrong config or SHA-1). Tell the app owner (START-HERE option 6 fixes it).';
      default:
        return 'Firebase error.';
    }
  }

  /// google_sign_in reports `ApiException: n` inside the message.
  static AuthFailure _googleFailure(PlatformException e) {
    final text = '${e.code} ${e.message ?? ''} ${e.details ?? ''}';
    final m = RegExp(r'ApiException:\s*(\d+)').firstMatch(text);
    final n = m?.group(1);
    const meanings = {
      '10': 'DEVELOPER_ERROR - this app\'s SHA-1 fingerprint or package name is not registered in Firebase, or the Google provider is off. Tell the app owner (START-HERE option 6 fixes it).',
      '12500': 'SIGN_IN_FAILED - Google provider is not fully configured (support email missing?). Tell the app owner (START-HERE option 6 fixes it).',
      '12501': 'Sign-in was cancelled.',
      '16': 'Sign-in was cancelled.',
      '7': 'NETWORK_ERROR - no internet, or Google services are blocked on this network.',
      '8': 'INTERNAL_ERROR - Google Play services problem. Update Play services and retry.',
      '4': 'SIGN_IN_REQUIRED - pick an account and try again.',
    };
    if (n != null) {
      return AuthFailure('google-$n', meanings[n] ?? 'Google Sign-In error $n.', text);
    }
    if (e.code == 'network_error') {
      return AuthFailure('google-network_error', meanings['7']!, text);
    }
    return AuthFailure('google-${e.code}', 'Google Sign-In failed.', text);
  }
}
