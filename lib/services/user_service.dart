import 'api/auth_api.dart';

/// Service responsible for user-related API operations, such as fetching user profile data.
class UserService {
  final AuthApi _authApi = AuthApi();

  /// Fetches the authenticated user profile from the backend (GET /users/profile).
  /// Returns a Map containing user fields: 'firstName', 'lastName', 'username', 'email', 'phoneNumber'.
  Future<Map<String, String?>> getProfile() async {
    return await _authApi.getUserProfile();
  }
}
