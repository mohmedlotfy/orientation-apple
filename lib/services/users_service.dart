import '../core/api_client.dart';
import '../models/user_model.dart';
import '../models/project_model.dart';
import '../models/clip_model.dart';
import 'in_memory_cache_service.dart';

/// Users Service handling all /users/* routes with in-memory caching and invalidation.
class UsersService {
  final InMemoryCacheService _cache = InMemoryCacheService();

  /// GET /users/profile
  Future<UserModel> getProfile({bool forceRefresh = false}) async {
    return _cache.getCached<UserModel>(
      key: 'users:profile',
      forceRefresh: forceRefresh,
      ttl: const Duration(minutes: 15),
      fetcher: () async {
        final response = await ApiClient.dio.get('/users/profile');
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return UserModel.fromJson(data);
        } else if (data is Map) {
          return UserModel.fromJson(Map<String, dynamic>.from(data));
        }
        throw Exception('Invalid profile response format');
      },
    );
  }

  /// PATCH /users/profile
  /// Body: { username, email, phoneNumber, password }
  Future<UserModel> updateProfile({
    String? username,
    String? email,
    String? phoneNumber,
    String? password,
  }) async {
    final response = await ApiClient.dio.patch(
      '/users/profile',
      data: {
        if (username != null && username.isNotEmpty) 'username': username,
        if (email != null && email.isNotEmpty) 'email': email,
        if (phoneNumber != null && phoneNumber.isNotEmpty) 'phoneNumber': phoneNumber,
        if (password != null && password.isNotEmpty) 'password': password,
      },
    );

    // Evict cached profile on mutation
    _cache.invalidate('users:profile');

    final data = response.data;
    if (data is Map) {
      return UserModel.fromJson(Map<String, dynamic>.from(data));
    }
    return getProfile(forceRefresh: true);
  }

  /// GET /users/saved-projects
  Future<List<ProjectModel>> getSavedProjects({bool forceRefresh = false}) async {
    return _cache.getCached<List<ProjectModel>>(
      key: 'users:saved-projects',
      forceRefresh: forceRefresh,
      ttl: const Duration(minutes: 5),
      fetcher: () async {
        final response = await ApiClient.dio.get('/users/saved-projects');
        final data = response.data;
        List<dynamic> list = [];
        if (data is List) {
          list = data;
        } else if (data is Map) {
          list = (data['projects'] as List<dynamic>?) ??
              (data['data'] as List<dynamic>?) ??
              (data['savedProjects'] as List<dynamic>?) ??
              [];
        }

        return list.map((item) {
          if (item is Map) {
            return ProjectModel.fromJson(Map<String, dynamic>.from(item));
          }
          return ProjectModel.fromJson({});
        }).toList();
      },
    );
  }

  /// GET /users/saved-reels
  Future<List<ClipModel>> getSavedReels({bool forceRefresh = false}) async {
    return _cache.getCached<List<ClipModel>>(
      key: 'users:saved-reels',
      forceRefresh: forceRefresh,
      ttl: const Duration(minutes: 5),
      fetcher: () async {
        final response = await ApiClient.dio.get('/users/saved-reels');
        final data = response.data;
        List<dynamic> list = [];
        if (data is List) {
          list = data;
        } else if (data is Map) {
          list = (data['reels'] as List<dynamic>?) ??
              (data['data'] as List<dynamic>?) ??
              (data['savedReels'] as List<dynamic>?) ??
              [];
        }

        return list.map((item) {
          if (item is Map) {
            return ClipModel.fromJson(Map<String, dynamic>.from(item));
          }
          return ClipModel.fromJson({});
        }).toList();
      },
    );
  }
}
