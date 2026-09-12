import 'package:dio/dio.dart';
import '../dio_client.dart';
import '../../models/project_model.dart';
import '../../models/developer_model.dart';
import '../../models/area_model.dart';
import '../../utils/cache_manager.dart';
import 'project_api.dart';

class HomeApi {
  final DioClient _dioClient = DioClient();
  final ProjectApi _projectApi = ProjectApi();

  HomeApi() {
    _dioClient.init();
  }

  /// GET /projects/featured?limit= (with caching)
  Future<List<ProjectModel>> getFeaturedProjects({bool useCache = true}) async {
    const cacheKey = 'featured_projects';
    
    // Try to get from cache first
    if (useCache) {
      final cached = await CacheManager.get<List<dynamic>>(cacheKey);
      if (cached != null) {
        final projects = cached.map((e) => ProjectModel.fromJson(e as Map<String, dynamic>)).toList();
        print('📦 Cached featured projects: ${projects.length}');
        return projects;
      }
    }
    
    try {
      // Use the correct endpoint: GET /projects/featured?limit=3
      print('📡 Calling GET /projects/featured?limit=3...');
      final response = await _dioClient.dio.get('/projects/featured', queryParameters: {'limit': '3'});
      print('📡 Response status: ${response.statusCode}');
      print('📡 Response data type: ${response.data.runtimeType}');
      
      List<dynamic> list;
      final responseData = response.data;
      if (responseData is List) {
        list = responseData;
      } else if (responseData is Map && responseData['value'] is List) {
        list = responseData['value'] as List;
      } else {
        list = <dynamic>[];
      }
      print('📡 Parsed list length: ${list.length}');
      
      if (list.isEmpty) {
        print('⚠️ Empty list returned from API');
        return [];
      }
      
      final projects = <ProjectModel>[];
      for (var i = 0; i < list.length; i++) {
        try {
          final item = list[i] as Map<String, dynamic>;
          final project = ProjectModel.fromJson(item);
          projects.add(project);
        } catch (e) {
          print('⚠️ Error parsing project at index $i: $e');
          print('   Data: ${list[i]}');
        }
      }
      
      print('✅ Got ${projects.length} featured projects from API (parsed ${projects.length}/${list.length})');
      
      // Cache the results (increased duration to reduce API calls)
      if (useCache && list.isNotEmpty) {
        await CacheManager.set(cacheKey, list, duration: const Duration(minutes: 30));
        print('💾 Cached ${list.length} featured projects');
      }
      
      return projects;
    } on DioException catch (e) {
      print('❌ DioException getting featured projects: ${e.message}');
      print('   Type: ${e.type}');
      if (e.response != null) {
        print('   Status: ${e.response?.statusCode}');
        print('   Data: ${e.response?.data}');
      }
      return [];
    } catch (e, stackTrace) {
      print('❌ Unexpected error getting featured projects: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }

  /// GET /projects/latest?limit= (with caching)
  Future<List<ProjectModel>> getLatestProjects({bool useCache = true}) async {
    const cacheKey = 'latest_projects';
    
    // Try to get from cache first
    if (useCache) {
      final cached = await CacheManager.get<List<dynamic>>(cacheKey);
      if (cached != null) {
        return cached.map((e) => ProjectModel.fromJson(e as Map<String, dynamic>)).toList();
      }
    }
    
    try {
      // Use correct endpoint: GET /projects/latest?limit=
      print('📡 Calling GET /projects/latest?limit=10...');
      final response = await _dioClient.dio.get('/projects/latest', queryParameters: {'limit': '10'});
      print('📡 Response status: ${response.statusCode}');
      
      List<dynamic> list;
      final responseData = response.data;
      if (responseData is List) {
        list = responseData;
      } else if (responseData is Map && responseData['value'] is List) {
        list = responseData['value'] as List;
      } else {
        list = <dynamic>[];
      }
      print('📡 Parsed list length: ${list.length}');
      
      if (list.isEmpty) {
        print('⚠️ Empty list returned from API');
        return [];
      }
      
      final projects = <ProjectModel>[];
      for (var i = 0; i < list.length; i++) {
        try {
          final item = list[i] as Map<String, dynamic>;
          // Debug: Print image fields from API
          if (i < 3) { // Print first 3 projects for debugging
            print('📸 Project $i image fields:');
            print('   projectThumbnailUrl: ${item['projectThumbnailUrl']}');
            print('   image: ${item['image']}');
            print('   logo: ${item['logo']}');
            print('   logoUrl: ${item['logoUrl']}');
          }
          final project = ProjectModel.fromJson(item);
          // Debug: Print parsed values
          if (i < 3) {
            print('📸 Project $i parsed values:');
            print('   projectThumbnailUrl: "${project.projectThumbnailUrl}"');
            print('   image: "${project.image}"');
            print('   logo: "${project.logo}"');
          }
          projects.add(project);
        } catch (e) {
          print('⚠️ Error parsing project at index $i: $e');
        }
      }
      
      print('✅ Got ${projects.length} latest projects from API (parsed ${projects.length}/${list.length})');
      
      // Cache the results (increased duration to reduce API calls)
      if (useCache && list.isNotEmpty) {
        await CacheManager.set(cacheKey, list, duration: const Duration(minutes: 30));
      }
      
      return projects;
    } on DioException catch (e) {
      print('❌ DioException getting latest projects: ${e.message}');
      if (e.response != null) {
        print('   Status: ${e.response?.statusCode}, Data: ${e.response?.data}');
      }
      return [];
    } catch (e, stackTrace) {
      print('❌ Unexpected error getting latest projects: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }

  Future<List<ProjectModel>>? _continueWatchingInFlight;

  /// Uses ProjectApi.getContinueWatchingProjects (backend watch-history + local fallback)
  Future<List<ProjectModel>> getContinueWatching() {
    if (_continueWatchingInFlight != null) {
      print('⚡ Coalescing in-flight GET continue-watching request in HomeApi');
      return _continueWatchingInFlight!;
    }
    _continueWatchingInFlight = _fetchContinueWatching().whenComplete(() {
      _continueWatchingInFlight = null;
    });
    return _continueWatchingInFlight!;
  }

  Future<List<ProjectModel>> _fetchContinueWatching() async {
    try {
      print('🏠 HomeApi: Fetching continue watching...');
      final projects = await _projectApi.getContinueWatchingProjects();
      print('🏠 HomeApi: Got ${projects.length} continue watching projects');
      return projects;
    } catch (e) {
      print('❌ HomeApi: Error in getContinueWatching: $e');
      return [];
    }
  }

  /// GET /projects/top10?limit=10 (with caching)
  Future<List<ProjectModel>> getTop10Projects({bool useCache = true}) async {
    const cacheKey = 'top10_projects';
    
    // Try to get from cache first
    if (useCache) {
      final cached = await CacheManager.get<List<dynamic>>(cacheKey);
      if (cached != null) {
        return cached.map((e) => ProjectModel.fromJson(e as Map<String, dynamic>)).toList();
      }
    }
    
    try {
      final response = await _dioClient.dio.get('/projects/top10', queryParameters: {'limit': '10'});
      List<dynamic> list;
      final responseData = response.data;
      if (responseData is List) {
        list = responseData;
      } else if (responseData is Map && responseData['value'] is List) {
        list = responseData['value'] as List;
      } else {
        list = <dynamic>[];
      }
      final projects = list.map((e) => ProjectModel.fromJson(e as Map<String, dynamic>)).toList();
      
      // Cache the results (increased duration to reduce API calls)
      if (useCache && list.isNotEmpty) {
        await CacheManager.set(cacheKey, list, duration: const Duration(minutes: 30));
      }
      
      return projects;
    } on DioException catch (e) {
      print('❌ Error getting top 10: ${e.message}');
      return [];
    }
  }

  /// GET /projects/location?location= (with caching)
  Future<List<ProjectModel>> getProjectsByArea(String area, {bool useCache = true}) async {
    final cacheKey = 'projects_area_$area';
    
    // Try to get from cache first
    if (useCache) {
      final cached = await CacheManager.get<List<dynamic>>(cacheKey);
      if (cached != null) {
        return cached.map((e) => ProjectModel.fromJson(e as Map<String, dynamic>)).toList();
      }
    }
    
    try {
      // Use correct endpoint: GET /projects/location?location=
      final response = await _dioClient.dio.get('/projects/location', queryParameters: {'location': area});
      List<dynamic> list;
      final responseData = response.data;
      if (responseData is List) {
        list = responseData;
      } else if (responseData is Map && responseData['value'] is List) {
        list = responseData['value'] as List;
      } else {
        list = <dynamic>[];
      }
      final projects = list.map((e) => ProjectModel.fromJson(e as Map<String, dynamic>)).toList();
      
      // Cache the results (increased duration to reduce API calls)
      if (useCache && list.isNotEmpty) {
        await CacheManager.set(cacheKey, list, duration: const Duration(minutes: 30));
      }
      
      return projects;
    } on DioException catch (e) {
      print('❌ Error getting projects by area ($area): ${e.message}');
      if (e.response != null) {
        print('   Status: ${e.response?.statusCode}, Data: ${e.response?.data}');
      }
      return [];
    }
  }

  /// GET /projects/upcoming (with caching)
  Future<List<ProjectModel>> getUpcomingProjects({bool useCache = true}) async {
    const cacheKey = 'upcoming_projects';
    
    // Try to get from cache first
    if (useCache) {
      final cached = await CacheManager.get<List<dynamic>>(cacheKey);
      if (cached != null) {
        return cached.map((e) => ProjectModel.fromJson(e as Map<String, dynamic>)).toList();
      }
    }
    
    try {
      print('📡 Fetching upcoming projects (limit=5)...');
      final response = await _dioClient.dio.get('/projects/upcoming', queryParameters: {'limit': '5'});
      List<dynamic> list;
      final responseData = response.data;
      if (responseData is List) {
        list = responseData;
      } else if (responseData is Map && responseData['value'] is List) {
        list = responseData['value'] as List;
      } else {
        list = <dynamic>[];
      }
      final projects = list.map((e) => ProjectModel.fromJson(e as Map<String, dynamic>)).toList();
      
      print('✅ Got ${projects.length} upcoming projects from API');
      
      // Cache the results
      if (useCache && list.isNotEmpty) {
        await CacheManager.set(cacheKey, list, duration: const Duration(minutes: 30));
      }
      
      return projects;
    } on DioException catch (e) {
      print('❌ Error getting upcoming projects: ${e.message}');
      return [];
    }
  }

  Future<List<ProjectModel>> getProjectsByCategory(String category) async {
    try {
      if (category == 'Upcoming') {
        final response = await _dioClient.dio.get('/projects/upcoming', queryParameters: {'limit': '50'});
        List<dynamic> list;
        final responseData = response.data;
        if (responseData is List) {
          list = responseData;
        } else if (responseData is Map && responseData['value'] is List) {
          list = responseData['value'] as List;
        } else {
          list = <dynamic>[];
        }
        return list.map((e) => ProjectModel.fromJson(e as Map<String, dynamic>)).toList();
      } else {
        // For other categories, use top10
        final response = await _dioClient.dio.get('/projects/top10', queryParameters: {'limit': '50'});
        List<dynamic> list;
        final responseData = response.data;
        if (responseData is List) {
          list = responseData;
        } else if (responseData is Map && responseData['value'] is List) {
          list = responseData['value'] as List;
        } else {
          list = <dynamic>[];
        }
        return list.map((e) => ProjectModel.fromJson(e as Map<String, dynamic>)).toList();
      }
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// /developer endpoint requires ADMIN/SUPERADMIN on backend; return empty for mobile users to prevent 403.
  Future<List<DeveloperModel>> getDevelopers() async {
    return [];
  }

  /// No /areas in backend; return empty.
  Future<List<AreaModel>> getAreas() async {
    return [];
  }

  String _handleError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timeout. Please check your internet connection.';
      case DioExceptionType.connectionError:
        return 'Unable to connect to server.';
      case DioExceptionType.badResponse:
        return e.response?.data?['message'] ?? 'An error occurred. Please try again.';
      default:
        return 'An unexpected error occurred.';
    }
  }
}
