import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../core/api_client.dart';

class DioClient {
  static final DioClient _instance = DioClient._internal();
  factory DioClient() => _instance;
  DioClient._internal() {
    _baseUrl = _sanitizeUrl(ApiConfig.baseUrl);
  }
  
  // Cached SharedPreferences instance for faster token access
  static SharedPreferences? _cachedPrefs;

  // Active base URL — resolved from ApiConfig (supports --dart-define override).
  // Call setBaseUrl() only if you need a runtime override (e.g. a debug menu).
  late String _baseUrl;
  late Dio dio;
  bool _isRefreshing = false;

  static String _sanitizeUrl(String url) {
    var sanitized = url.trim();
    if (sanitized.isEmpty) return sanitized;
    if (sanitized.endsWith('/')) {
      sanitized = sanitized.substring(0, sanitized.length - 1);
    }
    if (!sanitized.endsWith('/api/v1')) {
      sanitized = '$sanitized/api/v1';
    }
    return sanitized;
  }

  /// Set the base URL dynamically
  void setBaseUrl(String url) {
    _baseUrl = _sanitizeUrl(url);
    init(); // Reinitialize with new URL
  }

  // Helper to get cached SharedPreferences (faster than getInstance each time)
  static Future<SharedPreferences> _getPrefs() async {
    _cachedPrefs ??= await SharedPreferences.getInstance();
    return _cachedPrefs!;
  }

  Future<bool> _refreshToken() async {
    if (_isRefreshing) return false; // Already refreshing
    
    try {
      _isRefreshing = true;
      final prefs = await _getPrefs();
      final refreshToken = prefs.getString('refresh_token');
      
      if (refreshToken == null || refreshToken.isEmpty) {
        print('⚠️ No refresh token available');
        return false;
      }
      
      print('🔄 Attempting to refresh access token...');
      final response = await dio.post('/auth/refresh', data: {'refreshToken': refreshToken});
      final data = response.data as Map<String, dynamic>;
      
      final newAccessToken = data['accessToken']?.toString() ?? '';
      final newRefreshToken = data['refreshToken']?.toString() ?? '';
      
      if (newAccessToken.isNotEmpty) {
        await prefs.setString('auth_token', newAccessToken);
        print('✅ Token refreshed successfully');
        if (newRefreshToken.isNotEmpty) {
          await prefs.setString('refresh_token', newRefreshToken);
        }
        // Sync tokens to ApiClient
        try {
          await ApiClient.saveTokens(
            accessToken: newAccessToken,
            refreshToken: newRefreshToken.isNotEmpty ? newRefreshToken : refreshToken,
          );
        } catch (_) {}
        return true;
      }
      
      return false;
    } on DioException catch (e) {
      print('❌ Failed to refresh token: $e');
      final statusCode = e.response?.statusCode;
      if (statusCode == 401 || statusCode == 403) {
        // Clear tokens ONLY if server explicitly rejected the refresh token
        final prefs = await _getPrefs();
        await prefs.remove('auth_token');
        await prefs.remove('refresh_token');
      }
      return false;
    } catch (e) {
      print('❌ Unexpected error refreshing token: $e');
      return false;
    } finally {
      _isRefreshing = false;
    }
  }

  void init() {
    dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        sendTimeout: ApiConfig.sendTimeout,
        headers: Map<String, dynamic>.from(ApiConfig.defaultHeaders),
      ),
    );

    // Add interceptors for logging, token handling, and auto-refresh
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // For FormData (multipart), do not force JSON Content-Type; Dio sets multipart/form-data
          if (options.data is FormData) {
            options.headers.remove('Content-Type');
          }
          
          // Add auth token to requests if available
          final prefs = await _getPrefs();
          final token = prefs.getString('auth_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          
          return handler.next(options);
        },
        onResponse: (response, handler) {
          return handler.next(response);
        },
        onError: (error, handler) async {
          // Log errors for debugging
          print('DioError: ${error.message}');
          if (error.response != null) {
            print('Response: ${error.response?.data}');
            print('Status: ${error.response?.statusCode}');
          }
          
          // Auto-refresh token on 401 (except for auth endpoints)
          if (error.response?.statusCode == 401) {
            final requestPath = error.requestOptions.path;
            
            // Don't refresh for auth endpoints (login, register, refresh, etc.)
            if (!requestPath.startsWith('/auth/')) {
              print('🔄 401 Unauthorized - attempting token refresh...');
              
              final refreshed = await _refreshToken();
              if (refreshed) {
                // Retry the original request with new token
                final prefs = await _getPrefs();
                final newToken = prefs.getString('auth_token');
                
                if (newToken != null) {
                  error.requestOptions.headers['Authorization'] = 'Bearer $newToken';
                  print('🔄 Retrying request with new token...');
                  
                  try {
                    final opts = error.requestOptions;
                    final response = await dio.fetch(opts);
                    return handler.resolve(response);
                  } catch (e) {
                    return handler.next(error);
                  }
                }
              }
            }
          }
          
          return handler.next(error);
        },
      ),
    );
  }
}
