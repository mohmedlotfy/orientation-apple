import '../core/api_client.dart';
import '../models/project_model.dart';
import 'in_memory_cache_service.dart';

/// Service handling all /projects/* NestJS routes with in-memory caching and request de-duplication.
class ProjectsService {
  final InMemoryCacheService _cache = InMemoryCacheService();

  List<ProjectModel> _parseList(dynamic data) {
    List<dynamic> list = [];
    if (data is List) {
      list = data;
    } else if (data is Map) {
      if (data['data'] is List) {
        list = data['data'];
      } else if (data['projects'] is List) {
        list = data['projects'];
      }
    }
    return list.map((item) {
      if (item is Map) {
        return ProjectModel.fromJson(Map<String, dynamic>.from(item));
      }
      return ProjectModel.fromJson({});
    }).toList();
  }

  /// GET /projects/featured?limit=3
  /// Directly computes hasAccess and isFree backend-side.
  Future<List<ProjectModel>> getFeaturedProjects({int limit = 3, bool forceRefresh = false}) async {
    return _cache.getCached<List<ProjectModel>>(
      key: 'featured:$limit',
      forceRefresh: forceRefresh,
      ttl: const Duration(hours: 1),
      fetcher: () async {
        final response = await ApiClient.dio.get(
          '/projects/featured',
          queryParameters: {'limit': limit},
        );
        return _parseList(response.data);
      },
    );
  }

  /// GET /projects/latest?limit=10
  /// Returns latest projects excluding PLANNING status.
  Future<List<ProjectModel>> getLatestProjects({int limit = 10, bool forceRefresh = false}) async {
    return _cache.getCached<List<ProjectModel>>(
      key: 'latest:$limit',
      forceRefresh: forceRefresh,
      ttl: const Duration(hours: 1),
      fetcher: () async {
        final response = await ApiClient.dio.get(
          '/projects/latest',
          queryParameters: {'limit': limit},
        );
        return _parseList(response.data);
      },
    );
  }

  /// GET /projects/upcoming?limit=10
  /// Returns projects strictly with PLANNING status.
  Future<List<ProjectModel>> getUpcomingProjects({int limit = 10, bool forceRefresh = false}) async {
    return _cache.getCached<List<ProjectModel>>(
      key: 'upcoming:$limit',
      forceRefresh: forceRefresh,
      ttl: const Duration(hours: 1),
      fetcher: () async {
        final response = await ApiClient.dio.get(
          '/projects/upcoming',
          queryParameters: {'limit': limit},
        );
        return _parseList(response.data);
      },
    );
  }

  /// GET /projects/free?limit=10&page=1
  /// Returns projects older than 30 days accessible without subscription.
  Future<List<ProjectModel>> getFreeProjects({
    int limit = 10,
    int page = 1,
    bool forceRefresh = false,
  }) async {
    return _cache.getCached<List<ProjectModel>>(
      key: 'free:$limit:$page',
      forceRefresh: forceRefresh,
      ttl: const Duration(hours: 1),
      fetcher: () async {
        final response = await ApiClient.dio.get(
          '/projects/free',
          queryParameters: {'limit': limit, 'page': page},
        );
        return _parseList(response.data);
      },
    );
  }

  /// GET /projects/top10?limit=10
  /// Returns projects sorted by trendingScore.
  Future<List<ProjectModel>> getTop10Projects({int limit = 10, bool forceRefresh = false}) async {
    return _cache.getCached<List<ProjectModel>>(
      key: 'trending:$limit',
      forceRefresh: forceRefresh,
      ttl: const Duration(hours: 1),
      fetcher: () async {
        final response = await ApiClient.dio.get(
          '/projects/top10',
          queryParameters: {'limit': limit},
        );
        return _parseList(response.data);
      },
    );
  }

  /// GET /projects/location?location=$location&limit=10
  /// Case-insensitive location search.
  Future<List<ProjectModel>> getProjectsByLocation(
    String location, {
    int limit = 10,
    bool forceRefresh = false,
  }) async {
    return _cache.getCached<List<ProjectModel>>(
      key: 'location:$location',
      forceRefresh: forceRefresh,
      ttl: const Duration(hours: 1),
      fetcher: () async {
        final response = await ApiClient.dio.get(
          '/projects/location',
          queryParameters: {'location': location, 'limit': limit},
        );
        return _parseList(response.data);
      },
    );
  }

  /// GET /projects/developer?developer=$id
  Future<List<ProjectModel>> getProjectsByDeveloper(
    String developerId, {
    int limit = 20,
    bool forceRefresh = false,
  }) async {
    return _cache.getCached<List<ProjectModel>>(
      key: 'developer:$developerId:$limit',
      forceRefresh: forceRefresh,
      ttl: const Duration(hours: 1),
      fetcher: () async {
        final response = await ApiClient.dio.get(
          '/projects/developer',
          queryParameters: {'developer': developerId, 'limit': limit},
        );
        return _parseList(response.data);
      },
    );
  }

  /// GET /projects?limit=...&page=...
  Future<List<ProjectModel>> getProjects({
    int limit = 10,
    int page = 1,
    String? search,
    String? location,
    bool forceRefresh = false,
  }) async {
    final queryStr = 'limit=$limit&page=$page&s=${search ?? ""}&loc=${location ?? ""}';
    return _cache.getCached<List<ProjectModel>>(
      key: 'projects:$queryStr',
      forceRefresh: forceRefresh,
      ttl: const Duration(hours: 1),
      fetcher: () async {
        final response = await ApiClient.dio.get(
          '/projects',
          queryParameters: {
            'limit': limit,
            'page': page,
            if (search != null && search.isNotEmpty) 'search': search,
            if (location != null && location.isNotEmpty) 'location': location,
          },
        );
        return _parseList(response.data);
      },
    );
  }

  /// GET /projects/:id
  /// Short TTL: 2 minutes to reflect dynamic bookmark/access changes.
  Future<ProjectModel> getProjectById(String id, {bool forceRefresh = false}) async {
    return _cache.getCached<ProjectModel>(
      key: 'project:$id',
      forceRefresh: forceRefresh,
      ttl: const Duration(minutes: 2),
      fetcher: () async {
        final response = await ApiClient.dio.get('/projects/$id');
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return ProjectModel.fromJson(data);
        } else if (data is Map) {
          return ProjectModel.fromJson(Map<String, dynamic>.from(data));
        }
        throw Exception('Project $id not found');
      },
    );
  }

  /// PATCH /projects/:id/save-project
  Future<bool> saveProject(String id) async {
    try {
      final response = await ApiClient.dio.patch('/projects/$id/save-project');
      _cache.invalidate('project:$id');
      _cache.invalidatePrefix('users:saved-projects');
      _cache.invalidatePrefix('featured');
      _cache.invalidatePrefix('latest');
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  /// PATCH /projects/:id/unsave-project
  Future<bool> unsaveProject(String id) async {
    try {
      final response = await ApiClient.dio.patch('/projects/$id/unsave-project');
      _cache.invalidate('project:$id');
      _cache.invalidatePrefix('users:saved-projects');
      _cache.invalidatePrefix('featured');
      _cache.invalidatePrefix('latest');
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }
}
