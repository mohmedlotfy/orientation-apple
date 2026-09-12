import '../core/api_client.dart';
import '../models/clip_model.dart';
import 'in_memory_cache_service.dart';

/// Service handling all /reels/* NestJS routes with in-memory caching and save/unsave mutation invalidation.
class ReelsService {
  final InMemoryCacheService _cache = InMemoryCacheService();

  List<ClipModel> _parseList(dynamic data) {
    List<dynamic> list = [];
    if (data is List) {
      list = data;
    } else if (data is Map) {
      list = (data['reels'] as List<dynamic>?) ??
          (data['data'] as List<dynamic>?) ??
          (data['items'] as List<dynamic>?) ??
          [];
    }
    return list.map((item) {
      if (item is Map) {
        return ClipModel.fromJson(Map<String, dynamic>.from(item));
      }
      return ClipModel.fromJson({});
    }).toList();
  }

  /// GET /reels
  /// TTL: 30 minutes in RAM.
  Future<List<ClipModel>> getReels({
    int page = 1,
    int limit = 20,
    bool forceRefresh = false,
  }) async {
    return _cache.getCached<List<ClipModel>>(
      key: 'reels:all:$page:$limit',
      forceRefresh: forceRefresh,
      ttl: const Duration(minutes: 30),
      fetcher: () async {
        final response = await ApiClient.dio.get(
          '/reels',
          queryParameters: {'page': page, 'limit': limit},
        );
        return _parseList(response.data);
      },
    );
  }

  /// GET /reels/saved
  Future<List<ClipModel>> getSavedReels({bool forceRefresh = false}) async {
    return _cache.getCached<List<ClipModel>>(
      key: 'reels:saved',
      forceRefresh: forceRefresh,
      ttl: const Duration(minutes: 5),
      fetcher: () async {
        final response = await ApiClient.dio.get('/reels/saved');
        return _parseList(response.data);
      },
    );
  }

  /// GET /reels/:id
  Future<ClipModel> getReelById(String id, {bool forceRefresh = false}) async {
    return _cache.getCached<ClipModel>(
      key: 'reels:$id',
      forceRefresh: forceRefresh,
      ttl: const Duration(minutes: 10),
      fetcher: () async {
        final response = await ApiClient.dio.get('/reels/$id');
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return ClipModel.fromJson(data);
        } else if (data is Map) {
          return ClipModel.fromJson(Map<String, dynamic>.from(data));
        }
        throw Exception('Reel $id not found');
      },
    );
  }

  /// POST /reels/:id/save
  Future<bool> saveReel(String id) async {
    try {
      final response = await ApiClient.dio.post('/reels/$id/save');
      _cache.invalidate('reels:$id');
      _cache.invalidatePrefix('reels:saved');
      _cache.invalidatePrefix('users:saved-reels');
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// POST /reels/:id/unsave
  Future<bool> unsaveReel(String id) async {
    try {
      final response = await ApiClient.dio.post('/reels/$id/unsave');
      _cache.invalidate('reels:$id');
      _cache.invalidatePrefix('reels:saved');
      _cache.invalidatePrefix('users:saved-reels');
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }
}
