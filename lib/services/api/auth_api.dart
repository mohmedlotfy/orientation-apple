import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../dio_client.dart';
import '../subscription_service.dart';
import '../../core/api_client.dart';
import '../../models/user_model.dart';

class AuthApi {
  final DioClient _dioClient = DioClient();

  AuthApi() {
    _dioClient.init();
  }

  void setBaseUrl(String url) {
    _dioClient.setBaseUrl(url);
  }

  /// Login — POST /auth/login
  /// Request: { email, password }
  Future<AuthResponse> login(String email, String password) async {
    try {
      final response = await _dioClient.dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      
      final data = response.data as Map<String, dynamic>;
      final accessToken = data['accessToken']?.toString() ?? data['token']?.toString() ?? '';
      final refreshToken = data['refreshToken']?.toString() ?? '';
      final userId = data['id']?.toString() ?? '';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', accessToken);
      await prefs.setString('refresh_token', refreshToken);

      // Fetch profile to get full user model details
      UserModel user;
      try {
        final profileResponse = await _dioClient.dio.get('/users/profile');
        final responseData = profileResponse.data;
        Map<String, dynamic> profileMap = {};
        if (responseData is Map<String, dynamic>) {
          if (responseData.containsKey('user') && responseData['user'] is Map) {
            profileMap = Map<String, dynamic>.from(responseData['user'] as Map);
          } else if (responseData.containsKey('value') && responseData['value'] is Map) {
            profileMap = Map<String, dynamic>.from(responseData['value'] as Map);
          } else if (responseData.containsKey('data') && responseData['data'] is Map) {
            profileMap = Map<String, dynamic>.from(responseData['data'] as Map);
          } else {
            profileMap = responseData;
          }
        }
        user = UserModel.fromJson(profileMap);
        // Store firstName/lastName/profilePicture from the profile response
        final pFirstName = profileMap['firstName']?.toString() ?? '';
        final pLastName = profileMap['lastName']?.toString() ?? '';
        final pProfilePicture = profileMap['profilePicture']?.toString()
            ?? profileMap['avatar']?.toString()
            ?? profileMap['photo']?.toString()
            ?? '';
        if (pFirstName.isNotEmpty) await prefs.setString('user_first_name', pFirstName);
        if (pLastName.isNotEmpty) await prefs.setString('user_last_name', pLastName);
        if (pProfilePicture.isNotEmpty) await prefs.setString('user_profile_picture', pProfilePicture);
      } catch (e) {
        // Fallback: construct skeleton UserModel
        user = UserModel(
          id: userId,
          username: email.split('@').first,
          email: email,
          role: 'user',
        );
      }

      final authResponse = AuthResponse(
        user: user,
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

      await prefs.setString('user_id', user.id);
      await prefs.setString('user_email', user.email);
      await prefs.setString('user_name', user.username);
      await prefs.setString('user_role', user.role);
      if (user.phoneNumber != null) {
        await prefs.setString('user_phone', user.phoneNumber!);
      }

      // Sync tokens to ApiClient for global subscription and project calls
      try {
        await ApiClient.saveTokens(accessToken: accessToken, refreshToken: refreshToken);
      } catch (e) {
        debugPrint('⚠️ [AuthApi] Error saving tokens to ApiClient: $e');
      }

      // If user profile returned active subscription, cache it immediately
      if (user.isSubscribed) {
        await SubscriptionService.cacheSubscriptionStatus(
          UserSubscriptionStatus(
            hasAccess: true,
            status: user.subscriptionStatus,
            planName: user.planName,
          ),
        );
      }

      // Trigger subscription check in the background to guarantee freshest status
      SubscriptionService.checkMySubscription(forceRefresh: true)
          .catchError((_) => UserSubscriptionStatus(hasAccess: false));

      return authResponse;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Sign in with Apple — POST /auth/apple/mobile
  Future<AuthResponse> loginWithApple({
    required String identityToken,
    required String userIdentifier,
    String? authorizationCode,
    String? email,
    String? firstName,
    String? lastName,
  }) async {
    try {
      final payload = <String, dynamic>{
        'identityToken': identityToken,
        'userIdentifier': userIdentifier,
        if (authorizationCode != null) 'authorizationCode': authorizationCode,
        if (email != null) 'email': email,
        if (firstName != null) 'firstName': firstName,
        if (lastName != null) 'lastName': lastName,
        if (firstName != null || lastName != null)
          'name': {
            if (firstName != null) 'firstName': firstName,
            if (lastName != null) 'lastName': lastName,
          },
      };

      Response response;
      try {
        response = await _dioClient.dio.post(
          '/auth/apple/mobile',
          data: payload,
        );
      } catch (_) {
        response = await _dioClient.dio.post(
          '/auth/apple-login',
          data: payload,
        );
      }

      final data = response.data as Map<String, dynamic>;
      final accessToken = data['accessToken']?.toString() ?? data['token']?.toString() ?? '';
      final refreshToken = data['refreshToken']?.toString() ?? '';
      final userId = data['id']?.toString() ?? '';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', accessToken);
      await prefs.setString('refresh_token', refreshToken);

      // Fetch profile to get full user model details
      UserModel user;
      try {
        final profileResponse = await _dioClient.dio.get('/users/profile');
        final responseData = profileResponse.data;
        Map<String, dynamic> profileMap = {};
        if (responseData is Map<String, dynamic>) {
          if (responseData.containsKey('value') && responseData['value'] is Map) {
            profileMap = Map<String, dynamic>.from(responseData['value'] as Map);
          } else if (responseData.containsKey('data') && responseData['data'] is Map) {
            profileMap = Map<String, dynamic>.from(responseData['data'] as Map);
          } else {
            profileMap = responseData;
          }
        }
        user = UserModel.fromJson(profileMap);
      } catch (e) {
        user = UserModel(
          id: userId,
          username: firstName ?? (email?.split('@').first ?? 'User'),
          email: email ?? '',
          role: 'user',
        );
      }

      final authResponse = AuthResponse(
        user: user,
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

      await prefs.setString('user_id', user.id);
      await prefs.setString('user_email', user.email);
      await prefs.setString('user_name', user.username);
      await prefs.setString('user_role', user.role);
      if (user.phoneNumber != null) {
        await prefs.setString('user_phone', user.phoneNumber!);
      }
      if (firstName != null) await prefs.setString('user_first_name', firstName);
      if (lastName != null) await prefs.setString('user_last_name', lastName);

      // Sync tokens to ApiClient for global subscription and project calls
      try {
        await ApiClient.saveTokens(accessToken: accessToken, refreshToken: refreshToken);
      } catch (e) {
        debugPrint('⚠️ [AuthApi] Error saving tokens to ApiClient: $e');
      }

      // If user profile returned active subscription, cache it immediately
      if (user.isSubscribed) {
        await SubscriptionService.cacheSubscriptionStatus(
          UserSubscriptionStatus(
            hasAccess: true,
            status: user.subscriptionStatus,
            planName: user.planName,
          ),
        );
      }

      // Trigger subscription check in the background to guarantee freshest status
      SubscriptionService.checkMySubscription(forceRefresh: true)
          .catchError((_) => UserSubscriptionStatus(hasAccess: false));

      return authResponse;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Register — POST /auth/register
  /// Request: { username, email, phoneNumber, password }
  /// Response: { success: true, message: string, email: string }
  /// Note: User cannot login until email is verified via OTP
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String phoneNumber,
    required String password,
  }) async {
    try {
      final response = await _dioClient.dio.post(
        '/auth/register',
        data: {
          'username': username,
          'email': email,
          'phoneNumber': phoneNumber,
          'password': password,
        },
      );
      // Register response: { success: true, message: string, email: string }
      final data = response.data as Map<String, dynamic>;
      return {
        'success': data['success'] ?? true,
        'message': data['message'] ?? 'Registration successful',
        'email': data['email'] ?? email,
      };
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// POST /auth/logout — Request: { refreshToken }
  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      try {
        await _dioClient.dio.post('/auth/signout');
      } catch (e) {
        // If logout fails, still clear local storage
        print('Logout API call failed: $e');
      }
      
      // Clear all local storage
      await prefs.remove('auth_token');
      await prefs.remove('refresh_token');
      await prefs.remove('user_id');
      await prefs.remove('user_email');
      await prefs.remove('user_name');
      await prefs.remove('user_role');
      await prefs.remove('user_phone');
      await prefs.remove('user_first_name');
      await prefs.remove('user_last_name');
      await prefs.remove('user_profile_picture');
      await prefs.remove('saved_project_ids');
      await SubscriptionService.clearSubscriptionCache();
      await ApiClient.clearTokens();
    } catch (e) {
      // Clear local storage even if API call fails
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await SubscriptionService.clearSubscriptionCache();
      await ApiClient.clearTokens();
    }
  }
  
  /// POST /auth/logout-all — Logout from all devices
  Future<void> logoutAll() async {
    try {
      await _dioClient.dio.post('/auth/logout-all');
      // Clear all local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await SubscriptionService.clearSubscriptionCache();
      await ApiClient.clearTokens();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }
  
  /// POST /auth/refresh — Refresh tokens
  Future<void> refreshTokens() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refresh_token');
      
      if (refreshToken == null || refreshToken.isEmpty) {
        throw Exception('No refresh token available');
      }
      
      final response = await _dioClient.dio.post('/auth/refresh', data: {'refreshToken': refreshToken});
      final data = response.data as Map<String, dynamic>;
      
      final newAccessToken = data['accessToken']?.toString() ?? '';
      final newRefreshToken = data['refreshToken']?.toString() ?? '';
      
      if (newAccessToken.isNotEmpty) {
        await prefs.setString('auth_token', newAccessToken);
      }
      if (newRefreshToken.isNotEmpty) {
        await prefs.setString('refresh_token', newRefreshToken);
      }
    } on DioException catch (e) {
      // If refresh fails, clear tokens and force re-login
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      await prefs.remove('refresh_token');
      throw _handleError(e);
    }
  }
  
  /// GET /auth/sessions — Get all active sessions
  Future<List<Map<String, dynamic>>> getSessions() async {
    try {
      final response = await _dioClient.dio.get('/auth/sessions');
      final list = response.data is List ? response.data as List : <dynamic>[];
      return list.map((e) => e as Map<String, dynamic>).toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return token != null && token.isNotEmpty;
  }

  Future<Map<String, String?>> getStoredUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'token': prefs.getString('auth_token'),
      'userId': prefs.getString('user_id'),
      'email': prefs.getString('user_email'),
      'username': prefs.getString('user_name'),
      'role': prefs.getString('user_role') ?? 'user',
      'firstName': prefs.getString('user_first_name'),
      'lastName': prefs.getString('user_last_name'),
      'profilePicture': prefs.getString('user_profile_picture'),
    };
  }

  /// POST /auth/forgot-password — Request: { email }
  /// Note: Implement when backend adds this route. Stores reset_email for resetPassword.
  Future<bool> forgotPassword(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('reset_email', email);
      await _dioClient.dio.post('/auth/forgot-password', data: {'email': email});
      return true;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// POST /auth/verify-email — Request: { email, otp }
  /// Verify email with 4-digit OTP after registration
  Future<bool> verifyEmail(String email, String otp) async {
    try {
      await _dioClient.dio.post('/auth/verify-email', data: {'email': email, 'otp': otp});
      return true;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }
  
  /// POST /auth/resend-verification — Request: { email }
  /// Resend verification OTP to email
  Future<bool> resendVerification(String email) async {
    try {
      await _dioClient.dio.post('/auth/resend-verification', data: {'email': email});
      return true;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }
  
  /// POST /auth/verify-reset-otp — Request: { email, otp }
  /// Verify password reset OTP (optional step before reset)
  Future<bool> verifyResetOTP(String email, String otp) async {
    try {
      await _dioClient.dio.post('/auth/verify-reset-otp', data: {'email': email, 'otp': otp});
      return true;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// POST /auth/reset-password — Request: { email, otp, newPassword }
  /// Reset password using email and OTP
  Future<bool> resetPassword(String email, String otp, String newPassword) async {
    try {
      await _dioClient.dio.post('/auth/reset-password', data: {
        'email': email,
        'otp': otp,
        'newPassword': newPassword,
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('reset_email');
      await prefs.remove('reset_otp');
      await prefs.remove('otp_verified');
      return true;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  static Future<Map<String, String?>>? _getUserProfileInFlight;

  /// Get user profile. Tries GET /users/profile; on failure returns cached
  /// values from SharedPreferences (from login/register).
  Future<Map<String, String?>> getUserProfile() {
    if (_getUserProfileInFlight != null) {
      print('⚡ Coalescing in-flight GET /users/profile request');
      return _getUserProfileInFlight!;
    }
    _getUserProfileInFlight = _fetchUserProfile().whenComplete(() {
      _getUserProfileInFlight = null;
    });
    return _getUserProfileInFlight!;
  }

  Future<Map<String, String?>> _fetchUserProfile() async {
    try {
      final response = await _dioClient.dio.get('/users/profile');
      final responseData = response.data;
      debugPrint('═══════════════════════════════════════════');
      debugPrint('📋 GET /users/profile — STATUS: ${response.statusCode}');
      debugPrint('📋 RAW RESPONSE TYPE: ${responseData.runtimeType}');
      debugPrint('📋 RAW RESPONSE DATA: $responseData');
      debugPrint('═══════════════════════════════════════════');

      Map<String, dynamic> d = {};
      if (responseData is Map<String, dynamic>) {
        if (responseData.containsKey('user') && responseData['user'] is Map) {
          d = Map<String, dynamic>.from(responseData['user'] as Map);
          debugPrint('📋 Unwrapped from "user" key');
        } else if (responseData.containsKey('value') && responseData['value'] is Map) {
          d = Map<String, dynamic>.from(responseData['value'] as Map);
          debugPrint('📋 Unwrapped from "value" key');
        } else if (responseData.containsKey('data') && responseData['data'] is Map) {
          d = Map<String, dynamic>.from(responseData['data'] as Map);
          debugPrint('📋 Unwrapped from "data" key');
        } else {
          d = responseData;
          debugPrint('📋 Using response directly (no wrapper key)');
        }
      } else {
        debugPrint('⚠️ Response is NOT a Map — falling back to cache');
        return _getCachedProfile();
      }

      debugPrint('📋 UNWRAPPED MAP KEYS: ${d.keys.toList()}');
      debugPrint('📋 UNWRAPPED MAP DATA: $d');

      final firstName = d['firstName']?.toString() ?? '';
      final lastName = d['lastName']?.toString() ?? '';
      final email = d['email']?.toString() ?? '';
      final phoneNumber = d['phoneNumber']?.toString() ?? '';
      final username = d['username']?.toString() ?? '';
      final profilePicture = d['profilePicture']?.toString()
          ?? d['avatar']?.toString()
          ?? d['photo']?.toString()
          ?? '';

      debugPrint('📋 PARSED → firstName="$firstName", lastName="$lastName", username="$username"');
      debugPrint('📋 PARSED → email="$email", phone="$phoneNumber"');
      debugPrint('📋 PARSED → profilePicture="$profilePicture"');

      // Parse and log subscription fields from user profile
      debugPrint('💳 [AuthApi] Profile Subscription Fields -> isSubscribed: ${d['isSubscribed']}, subscription: ${d['subscription']}, hasAccess: ${d['hasAccess']}, hasActivePlan: ${d['hasActivePlan']}');
      final userObj = UserModel.fromJson(d);
      debugPrint('💳 [AuthApi] UserModel Subscription Result -> isSubscribed: ${userObj.isSubscribed}, status: "${userObj.subscriptionStatus}", plan: "${userObj.planName}"');
      if (userObj.isSubscribed) {
        await SubscriptionService.cacheSubscriptionStatus(
          UserSubscriptionStatus(
            hasAccess: true,
            status: userObj.subscriptionStatus,
            planName: userObj.planName,
            rawData: d,
          ),
        );
      }

      final prefs = await SharedPreferences.getInstance();
      if (firstName.isNotEmpty) await prefs.setString('user_first_name', firstName);
      if (lastName.isNotEmpty) await prefs.setString('user_last_name', lastName);
      if (email.isNotEmpty) await prefs.setString('user_email', email);
      if (phoneNumber.isNotEmpty) await prefs.setString('user_phone', phoneNumber);
      if (profilePicture.isNotEmpty) await prefs.setString('user_profile_picture', profilePicture);
      if (firstName.isNotEmpty || lastName.isNotEmpty) {
        await prefs.setString('user_name', '$firstName $lastName'.trim());
      } else if (username.isNotEmpty) {
        await prefs.setString('user_name', username);
      }

      return {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phoneNumber': phoneNumber,
        'username': username,
        'profilePicture': profilePicture,
      };
    } on DioException catch (e) {
      debugPrint('❌ GET /users/profile FAILED: ${e.type} — ${e.message}');
      debugPrint('❌ Status: ${e.response?.statusCode}, Body: ${e.response?.data}');
      return _getCachedProfile();
    }
  }

  Future<Map<String, String?>> _getCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final f = prefs.getString('user_first_name') ?? '';
    final l = prefs.getString('user_last_name') ?? '';
    return {
      'firstName': f,
      'lastName': l,
      'email': prefs.getString('user_email') ?? '',
      'phoneNumber': prefs.getString('user_phone') ?? '',
      'username': prefs.getString('user_name') ?? (f.isNotEmpty || l.isNotEmpty ? '$f $l'.trim() : ''),
      'profilePicture': prefs.getString('user_profile_picture') ?? '',
    };
  }

  /// Update profile — PATCH /users/:id
  /// Request: { username, email, phoneNumber } (backend UpdateUserDto; username used for display name)
  Future<bool> updateProfile({
    required String firstName,
    required String lastName,
    required String email,
    required String phoneNumber,
  }) async {
    try {
      final username = '$firstName $lastName'.trim();
      if (username.isEmpty) throw Exception('Name is required');
      if (!email.contains('@')) throw Exception('Email must contain @');

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId == null || userId.isEmpty) {
        throw Exception('Missing user id. Please login again.');
      }

      await _dioClient.dio.patch('/users/profile', data: {
        'username': username,
        'email': email,
        'phoneNumber': phoneNumber,
      });

      await prefs.setString('user_first_name', firstName);
      await prefs.setString('user_last_name', lastName);
      await prefs.setString('user_email', email);
      await prefs.setString('user_phone', phoneNumber);
      await prefs.setString('user_name', username);
      return true;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Update password — PATCH /users/:id with { password }
  Future<bool> updatePassword({required String newPassword}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId == null || userId.isEmpty) {
        throw Exception('Missing user id. Please login again.');
      }

      await _dioClient.dio.patch('/users/profile', data: {'password': newPassword});
      return true;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  String _handleError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timeout. Please check your internet connection.';
      case DioExceptionType.connectionError:
        return 'Unable to connect to server. Please check your internet connection.';
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final message = e.response?.data?['message'];

        if (statusCode == 401) {
          return message ?? 'Invalid email or password.';
        } else if (statusCode == 409) {
          return message ?? 'User already exists.';
        } else if (statusCode == 400) {
          if (message is List) return message.join('\n');
          return message ?? 'Invalid input. Please check your data.';
        }
        return message ?? 'An error occurred. Please try again.';
      default:
        return 'An unexpected error occurred. Please try again.';
    }
  }
}
