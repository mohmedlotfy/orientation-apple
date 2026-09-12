import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import 'auth_interceptor.dart';

/// Central API Client configuring Dio with timeouts, headers, and authentication interceptors.
class ApiClient {
  static const String baseUrl = ApiConfig.baseUrl;
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static final Dio dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      sendTimeout: ApiConfig.sendTimeout,
      headers: ApiConfig.defaultHeaders,
    ),
  );

  static bool _initialized = false;

  /// Initializes the Dio instance with the AuthInterceptor.
  static void init() {
    if (_initialized) return;
    _initialized = true;

    dio.interceptors.add(
      AuthInterceptor(
        dio: dio,
        storage: _storage,
      ),
    );
  }

  /// Checks if the user is authenticated.
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final prefsToken = prefs.getString('auth_token');
    if (prefsToken != null && prefsToken.isNotEmpty) {
      return true;
    }

    try {
      final secureToken = await _storage.read(key: 'accessToken');
      if (secureToken != null && secureToken.isNotEmpty) {
        await prefs.setString('auth_token', secureToken);
        return true;
      }
    } catch (_) {}

    return false;
  }

  /// Retrieves the current access token.
  static Future<String?> getAccessToken() async {
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

  /// Retrieves the current refresh token.
  static Future<String?> getRefreshToken() async {
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

  /// Saves the authenticated session tokens securely.
  static Future<void> saveTokens({
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

  /// Clears all stored authentication tokens.
  static Future<void> clearTokens() async {
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
