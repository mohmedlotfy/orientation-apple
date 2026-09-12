import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

class SocialAuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _isGoogleSignInInitialized = false;

  Future<void> _initGoogleSignIn() async {
    if (_isGoogleSignInInitialized) return;
    debugPrint('🔑 [GoogleSignIn] Initializing...');
    debugPrint('🔑 [GoogleSignIn] serverClientId: 745396676629-2nkvgpsu6df4pp4b9tldnkq9r9sh0hec.apps.googleusercontent.com');
    debugPrint('🔑 [GoogleSignIn] Platform: ${Platform.operatingSystem}');
    try {
      await _googleSignIn.initialize(
        serverClientId: '745396676629-2nkvgpsu6df4pp4b9tldnkq9r9sh0hec.apps.googleusercontent.com',
        clientId: Platform.isIOS ? '745396676629-5ltfp049tk8sp6nbbt1vfd0u4r12ala8.apps.googleusercontent.com' : null,
      );
      _isGoogleSignInInitialized = true;
      debugPrint('✅ [GoogleSignIn] Initialization SUCCESS');
    } catch (e, stackTrace) {
      debugPrint('❌ [GoogleSignIn] Initialization FAILED: $e');
      debugPrint('❌ [GoogleSignIn] Init StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Returns Google ID Token if successful, null if canceled
  Future<String?> signInWithGoogle() async {
    try {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('🔑 [GoogleSignIn] signInWithGoogle() started');
      debugPrint('═══════════════════════════════════════════');

      await _initGoogleSignIn();

      debugPrint('🔑 [GoogleSignIn] Calling _googleSignIn.authenticate()...');
      final GoogleSignInAccount? account = await _googleSignIn.authenticate();
      debugPrint('🔑 [GoogleSignIn] authenticate() returned: ${account != null ? "Account(${account.email})" : "null"}');

      if (account == null) {
        debugPrint('⚠️ [GoogleSignIn] account is null (canceled or dismissed by user)');
        return null;
      }

      debugPrint('🔑 [GoogleSignIn] Account: displayName=${account.displayName}, email=${account.email}, id=${account.id}');

      debugPrint('🔑 [GoogleSignIn] Getting authentication tokens...');
      final GoogleSignInAuthentication auth = account.authentication;
      final String? idToken = auth.idToken;
      debugPrint('🔑 [GoogleSignIn] idToken: ${idToken != null ? "${idToken.substring(0, idToken.length > 25 ? 25 : idToken.length)}..." : "NULL"}');

      if (idToken == null || idToken.isEmpty) {
        throw Exception('Google sign-in succeeded but returned an empty idToken. Please ensure the Web Client ID is configured correctly.');
      }

      return idToken;
    } catch (e, stackTrace) {
      debugPrint('❌❌❌ [GoogleSignIn] ERROR: $e');
      debugPrint('❌❌❌ [GoogleSignIn] ERROR TYPE: ${e.runtimeType}');
      debugPrint('❌❌❌ [GoogleSignIn] STACK TRACE: $stackTrace');

      if (e is GoogleSignInException) {
        debugPrint('❌❌❌ [GoogleSignIn] Code: ${e.code}');
        debugPrint('❌❌❌ [GoogleSignIn] Description: ${e.description}');
        debugPrint('❌❌❌ [GoogleSignIn] Details: ${e.details}');

        // If there's an underlying description or details, surface them explicitly
        final detailMsg = e.description ?? e.details?.toString() ?? e.code.name;
        if (e.code != GoogleSignInExceptionCode.canceled) {
          throw Exception('Google Sign-In failed: $detailMsg');
        }
      }

      final errorStr = e.toString().toLowerCase();
      // Only treat as silent cancel if it was purely a user dismissal with no error payload
      if (errorStr.contains('12501') || errorStr == 'googlesigninexception(code: canceled)') {
        debugPrint('🔑 [GoogleSignIn] User canceled account selection');
        return null;
      }
      rethrow;
    }
  }

  /// Returns Facebook Access Token if successful, null if canceled
  Future<String?> signInWithFacebook() async {
    try {
      // Temporarily disabled. Fails gracefully to allow Google testing.
      throw Exception('Facebook login is currently disabled.');
      /*
      final LoginResult result = await FacebookAuth.instance.login(
        permissions: ['email', 'public_profile'],
      );

      if (result.status == LoginStatus.success) {
        return result.accessToken?.token;
      } else if (result.status == LoginStatus.cancelled) {
        return null;
      } else {
        throw Exception(result.message ?? 'Facebook sign-in failed');
      }
      */
    } catch (e) {
      throw Exception('Facebook sign-in failed: $e');
    }
  }

  /// Optional: Sign out from both
  Future<void> signOut() async {
    try {
      await _initGoogleSignIn();
      await _googleSignIn.signOut();
      await FacebookAuth.instance.logOut();
    } catch (e) {
      print('Social SignOut Error: $e');
    }
  }
}
