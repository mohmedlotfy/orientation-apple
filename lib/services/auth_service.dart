import '../core/api_client.dart';
import '../models/user_model.dart';
import '../utils/api_error_extractor.dart';
import 'in_memory_cache_service.dart';

class AuthResult {
  final bool success;
  final String? message;
  final String? accessToken;
  final String? refreshToken;
  final UserModel? user;

  AuthResult({
    required this.success,
    this.message,
    this.accessToken,
    this.refreshToken,
    this.user,
  });
}

/// Authentication Service handling all /auth/* NestJS routes.
class AuthService {
  /// POST /auth/register
  /// Body: { username, email, password, phoneNumber }
  static Future<AuthResult> register({
    required String username,
    required String email,
    required String password,
    String? phoneNumber,
  }) async {
    try {
      final response = await ApiClient.dio.post(
        '/auth/register',
        data: {
          'username': username,
          'email': email,
          'password': password,
          if (phoneNumber != null && phoneNumber.isNotEmpty) 'phoneNumber': phoneNumber,
        },
      );

      return _handleAuthSuccess(response.data, email);
    } catch (e) {
      return AuthResult(
        success: false,
        message: ApiErrorExtractor.getErrorMessage(e),
      );
    }
  }

  /// POST /auth/verify-email
  /// Body: { email, otp }
  static Future<AuthResult> verifyEmail({
    required String email,
    required String otp,
  }) async {
    try {
      final response = await ApiClient.dio.post(
        '/auth/verify-email',
        data: {
          'email': email,
          'otp': otp,
        },
      );

      return _handleAuthSuccess(response.data, email);
    } catch (e) {
      return AuthResult(
        success: false,
        message: ApiErrorExtractor.getErrorMessage(e),
      );
    }
  }

  /// POST /auth/resend-verification
  /// Body: { email }
  static Future<AuthResult> resendVerification({
    required String email,
  }) async {
    try {
      final response = await ApiClient.dio.post(
        '/auth/resend-verification',
        data: {'email': email},
      );

      final msg = response.data is Map ? response.data['message']?.toString() : null;
      return AuthResult(
        success: true,
        message: msg ?? 'Verification code sent successfully.',
      );
    } catch (e) {
      return AuthResult(
        success: false,
        message: ApiErrorExtractor.getErrorMessage(e),
      );
    }
  }

  /// POST /auth/login
  /// Body: { email, password }
  /// Returns: { id, accessToken, refreshToken }
  static Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await ApiClient.dio.post(
        '/auth/login',
        data: {
          'email': email,
          'password': password,
        },
      );

      return _handleAuthSuccess(response.data, email);
    } catch (e) {
      return AuthResult(
        success: false,
        message: ApiErrorExtractor.getErrorMessage(e),
      );
    }
  }

  static Future<AuthResult> _handleAuthSuccess(dynamic responseData, String email) async {
    if (responseData is! Map) {
      return AuthResult(success: true);
    }

    final data = responseData as Map<String, dynamic>;
    final accessToken = data['accessToken']?.toString() ?? data['token']?.toString() ?? '';
    final refreshToken = data['refreshToken']?.toString() ?? '';
    final userId = data['id']?.toString() ?? data['_id']?.toString() ?? '';

    if (accessToken.isNotEmpty) {
      await ApiClient.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

      // Invalidate all stale cache upon fresh login
      InMemoryCacheService().clearAllCache();

      UserModel? user;
      if (data['user'] is Map) {
        user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
      } else {
        user = UserModel(
          id: userId,
          username: email.split('@').first,
          email: email,
          role: data['role']?.toString() ?? 'user',
        );
      }

      return AuthResult(
        success: true,
        accessToken: accessToken,
        refreshToken: refreshToken,
        user: user,
      );
    }

    return AuthResult(
      success: false,
      message: 'Failed to retrieve access token',
    );
  }

  /// POST /auth/refresh
  /// Body: { refreshToken }
  static Future<bool> refreshTokens() async {
    final refreshToken = await ApiClient.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;

    try {
      final response = await ApiClient.dio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        if (data is Map) {
          final newAccess = data['accessToken']?.toString() ?? data['token']?.toString();
          final newRefresh = data['refreshToken']?.toString() ?? refreshToken;

          if (newAccess != null && newAccess.isNotEmpty) {
            await ApiClient.saveTokens(
              accessToken: newAccess,
              refreshToken: newRefresh,
            );
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  /// POST /auth/signout
  static Future<bool> signout() async {
    try {
      await ApiClient.dio.post('/auth/signout');
    } catch (_) {
      // Proceed with local logout regardless of server errors
    } finally {
      await ApiClient.clearTokens();
      InMemoryCacheService().clearAllCache();
    }
    return true;
  }

  /// POST /auth/forgot-password
  /// Body: { email }
  static Future<AuthResult> forgotPassword({
    required String email,
  }) async {
    try {
      final response = await ApiClient.dio.post(
        '/auth/forgot-password',
        data: {'email': email},
      );

      final msg = response.data is Map ? response.data['message']?.toString() : null;
      return AuthResult(
        success: true,
        message: msg ?? 'Password reset OTP sent to email.',
      );
    } catch (e) {
      return AuthResult(
        success: false,
        message: ApiErrorExtractor.getErrorMessage(e),
      );
    }
  }

  /// POST /auth/verify-reset-otp
  /// Body: { email, otp }
  static Future<AuthResult> verifyResetOtp({
    required String email,
    required String otp,
  }) async {
    try {
      final response = await ApiClient.dio.post(
        '/auth/verify-reset-otp',
        data: {
          'email': email,
          'otp': otp,
        },
      );

      final msg = response.data is Map ? response.data['message']?.toString() : null;
      return AuthResult(
        success: true,
        message: msg ?? 'OTP verified successfully.',
      );
    } catch (e) {
      return AuthResult(
        success: false,
        message: ApiErrorExtractor.getErrorMessage(e),
      );
    }
  }

  /// POST /auth/reset-password
  /// Body: { email, newPassword } (or { email, otp, newPassword })
  static Future<AuthResult> resetPassword({
    required String email,
    required String newPassword,
    String? otp,
  }) async {
    try {
      final response = await ApiClient.dio.post(
        '/auth/reset-password',
        data: {
          'email': email,
          'newPassword': newPassword,
          'password': newPassword,
          if (otp != null && otp.isNotEmpty) 'otp': otp,
        },
      );

      final msg = response.data is Map ? response.data['message']?.toString() : null;
      return AuthResult(
        success: true,
        message: msg ?? 'Password has been reset successfully.',
      );
    } catch (e) {
      return AuthResult(
        success: false,
        message: ApiErrorExtractor.getErrorMessage(e),
      );
    }
  }

  /// POST /auth/google/mobile
  /// Body: { idToken }
  static Future<AuthResult> googleMobileSignIn({
    required String idToken,
  }) async {
    try {
      final response = await ApiClient.dio.post(
        '/auth/google/mobile',
        data: {'idToken': idToken},
      );

      return _handleAuthSuccess(response.data, 'google_user@gmail.com');
    } catch (e) {
      return AuthResult(
        success: false,
        message: ApiErrorExtractor.getErrorMessage(e),
      );
    }
  }

  /// POST /auth/apple/mobile
  /// Body: { identityToken, firstName, lastName, email }
  static Future<AuthResult> appleMobileSignIn({
    required String identityToken,
    String? firstName,
    String? lastName,
    String? email,
  }) async {
    try {
      final response = await ApiClient.dio.post(
        '/auth/apple/mobile',
        data: {
          'identityToken': identityToken,
          if (firstName != null) 'firstName': firstName,
          if (lastName != null) 'lastName': lastName,
          if (email != null) 'email': email,
        },
      );

      return _handleAuthSuccess(response.data, email ?? 'apple_user@icloud.com');
    } catch (e) {
      return AuthResult(
        success: false,
        message: ApiErrorExtractor.getErrorMessage(e),
      );
    }
  }
}
