import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/in_memory_cache_service.dart';

/// Interceptor managing Bearer token injection and Mutex-locked 401 token refresh.
class AuthInterceptor extends QueuedInterceptor {
  final Dio _dio;
  final FlutterSecureStorage _storage;

  // Callback when authentication fails and cannot be recovered
  static VoidCallback? onAuthFailure;

  // Mutex lock for token refresh: holds in-flight refresh so concurrent 401s wait
  static Completer<bool>? _refreshCompleter;

  AuthInterceptor({
    required Dio dio,
    FlutterSecureStorage storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  })  : _dio = dio,
        _storage = storage;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Attach token if not already present
    if (!options.headers.containsKey('Authorization')) {
      final token = await _getAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    return handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final requestOptions = err.requestOptions;

    // Check if error is 401 and not an auth route
    final path = requestOptions.path.toLowerCase();
    final isAuthRoute = path.contains('/auth/login') ||
        path.contains('/auth/refresh') ||
        path.contains('/auth/register') ||
        path.contains('/auth/verify');

    final isRetry = requestOptions.extra['_isRetry'] == true;
    final hadAuthHeader = requestOptions.headers.containsKey('Authorization') &&
        (requestOptions.headers['Authorization']?.toString().isNotEmpty ?? false);

    // If request failed with 401 on an unauthenticated/guest request, do not trigger auth failure redirect
    if (response?.statusCode == 401 && !isAuthRoute && !isRetry) {
      if (!hadAuthHeader) {
        debugPrint('ℹ️ [AuthInterceptor] 401 on unauthenticated/guest request (${requestOptions.path}). Skipping token refresh.');
        return handler.next(err);
      }

      final refreshToken = await _getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        debugPrint('ℹ️ [AuthInterceptor] No refresh token found. User is guest or logged out.');
        return handler.next(err);
      }

      debugPrint('🔒 [401 Unauthorized] Intercepted on ${requestOptions.path}. Initiating token refresh mutex.');

      bool refreshSuccess = false;
      bool isPermanentAuthFailure = false;

      // Mutex lock logic: if a refresh is already in progress, await it
      if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
        debugPrint('⏳ [Mutex] Waiting for existing token refresh in progress...');
        refreshSuccess = await _refreshCompleter!.future;
      } else {
        // Start new refresh mutex
        _refreshCompleter = Completer<bool>();
        try {
          final result = await _performTokenRefresh();
          refreshSuccess = result.success;
          isPermanentAuthFailure = result.isPermanentAuthFailure;
          _refreshCompleter!.complete(refreshSuccess);
        } catch (e) {
          _refreshCompleter!.complete(false);
          refreshSuccess = false;
        } finally {
          _refreshCompleter = null;
        }
      }

      if (refreshSuccess) {
        // Token refreshed successfully: retry original request
        try {
          final newToken = await _getAccessToken();
          requestOptions.headers['Authorization'] = 'Bearer $newToken';
          requestOptions.extra['_isRetry'] = true;

          debugPrint('🔁 [401 Retry] Retrying ${requestOptions.path} with new access token.');
          final retryResponse = await _dio.fetch(requestOptions);
          return handler.resolve(retryResponse);
        } catch (retryError) {
          if (retryError is DioException) {
            return handler.reject(retryError);
          }
          return handler.reject(
            DioException(
              requestOptions: requestOptions,
              error: retryError,
            ),
          );
        }
      } else if (isPermanentAuthFailure) {
        // Token refresh explicitly rejected by server (401/403) -> Clear session
        debugPrint('🚫 [Auth Failure] Refresh token rejected by server. Clearing session.');
        await _clearAllTokens();
        InMemoryCacheService().clearAllCache();
        onAuthFailure?.call();
        return handler.reject(err);
      } else {
        // Refresh failed due to network error/timeout; do NOT wipe local user session
        debugPrint('⚠️ [Auth Refresh] Refresh failed (network/offline). Keeping stored session.');
        return handler.next(err);
      }
    }

    return handler.next(err);
  }

  /// Dispatches POST /auth/refresh with the stored refreshToken.
  Future<({bool success, bool isPermanentAuthFailure})> _performTokenRefresh() async {
    final refreshToken = await _getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      debugPrint('⚠️ [Auth Refresh] No refresh token found in storage.');
      return (success: false, isPermanentAuthFailure: true);
    }

    try {
      // Use a clean Dio instance to avoid recursive interceptor loops
      final refreshDio = Dio(
        BaseOptions(
          baseUrl: _dio.options.baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      );

      debugPrint('🔄 [Auth Refresh] Sending POST /auth/refresh...');
      final response = await refreshDio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        String? newAccessToken;
        String? newRefreshToken;

        if (data is Map) {
          newAccessToken = data['accessToken']?.toString() ?? data['token']?.toString();
          newRefreshToken = data['refreshToken']?.toString();
        }

        if (newAccessToken != null && newAccessToken.isNotEmpty) {
          await _saveTokens(
            accessToken: newAccessToken,
            refreshToken: (newRefreshToken != null && newRefreshToken.isNotEmpty)
                ? newRefreshToken
                : refreshToken,
          );
          debugPrint('✅ [Auth Refresh] Tokens rotated and stored successfully.');
          return (success: true, isPermanentAuthFailure: false);
        }
      }
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 401 || statusCode == 403) {
        debugPrint('🚫 [Auth Refresh] Refresh token rejected with status $statusCode');
        return (success: false, isPermanentAuthFailure: true);
      }
      debugPrint('⚠️ [Auth Refresh] Non-auth error during token refresh: $e');
      return (success: false, isPermanentAuthFailure: false);
    } catch (e) {
      debugPrint('❌ [Auth Refresh] Unexpected error during token refresh: $e');
      return (success: false, isPermanentAuthFailure: false);
    }

    return (success: false, isPermanentAuthFailure: false);
  }

  Future<String?> _getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final prefsToken = prefs.getString('auth_token');
    if (prefsToken != null && prefsToken.isNotEmpty) return prefsToken;

    try {
      final token = await _storage.read(key: 'accessToken');
      if (token != null && token.isNotEmpty) {
        await prefs.setString('auth_token', token);
        return token;
      }
    } catch (_) {}

    return null;
  }

  Future<String?> _getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    final prefsToken = prefs.getString('refresh_token');
    if (prefsToken != null && prefsToken.isNotEmpty) return prefsToken;

    try {
      final token = await _storage.read(key: 'refreshToken');
      if (token != null && token.isNotEmpty) {
        await prefs.setString('refresh_token', token);
        return token;
      }
    } catch (_) {}

    return null;
  }

  Future<void> _saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', accessToken);
    await prefs.setString('refresh_token', refreshToken);

    try {
      await _storage.write(key: 'accessToken', value: accessToken);
      await _storage.write(key: 'refreshToken', value: refreshToken);
    } catch (_) {}
  }

  Future<void> _clearAllTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_data');
    await prefs.remove('user_id');
    await prefs.remove('user_email');
    await prefs.remove('user_name');
    await prefs.remove('user_role');
    await prefs.remove('user_phone');
    await prefs.remove('user_first_name');
    await prefs.remove('user_last_name');
    await prefs.remove('user_profile_picture');

    try {
      await _storage.deleteAll();
    } catch (_) {}
  }
}
