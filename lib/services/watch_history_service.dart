import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../models/watch_history_model.dart';
import 'in_memory_cache_service.dart';

/// Watch History Service implementing local-first progress storage and backend synchronization.
class WatchHistoryService {
  final InMemoryCacheService _cache = InMemoryCacheService();

  static const String _localProgressPrefix = 'local_watch_progress_';

  /// Save playback progress locally first (0ms latency)
  Future<void> saveLocalProgress({
    required String contentId,
    required String projectId,
    required double currentTime,
    required double duration,
    String? contentTitle,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'contentId': contentId,
        'projectId': projectId,
        'currentTime': currentTime,
        'duration': duration,
        'contentTitle': contentTitle ?? '',
        'timestamp': DateTime.now().toIso8601String(),
      };
      await prefs.setString('$_localProgressPrefix$contentId', jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ [WatchHistory] Error saving local progress: $e');
    }
  }

  /// Get local progress for an episode/content
  Future<double> getLocalProgress(String contentId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_localProgressPrefix$contentId');
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return (map['currentTime'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {}
    return 0.0;
  }

  /// POST /watch-history/progress
  /// Sends HTTP sync when user pauses, exits player, or completes an episode
  Future<bool> syncProgress({
    required String contentId,
    required String contentTitle,
    required double currentTime,
    required double duration,
    String? projectId,
    String? projectTitle,
    String? contentThumbnail,
    String? episodeUrl,
    String contentType = 'episode',
    int? season,
    int? episode,
  }) async {
    // 1. Save locally immediately
    await saveLocalProgress(
      contentId: contentId,
      projectId: projectId ?? '',
      currentTime: currentTime,
      duration: duration,
      contentTitle: contentTitle,
    );

    // 2. Sync to backend if logged in
    final loggedIn = await ApiClient.isLoggedIn();
    if (!loggedIn) return true;

    try {
      final response = await ApiClient.dio.post(
        '/watch-history/progress',
        data: {
          'contentId': contentId,
          'contentTitle': contentTitle,
          'currentTime': currentTime < 0 ? 0.0 : currentTime,
          'duration': duration < 1.0 ? 1.0 : duration,
          'contentType': contentType,
          if (season != null) 'season': season,
          if (episode != null) 'episode': episode,
          if (projectId != null && projectId.isNotEmpty) 'projectId': projectId,
          if (projectTitle != null && projectTitle.isNotEmpty) 'projectTitle': projectTitle,
          if (contentThumbnail != null && contentThumbnail.isNotEmpty) 'contentThumbnail': contentThumbnail,
          if (episodeUrl != null && episodeUrl.isNotEmpty) 'episodeUrl': episodeUrl,
        },
      );

      // Invalidate continue watching cache
      _cache.invalidate('watch-history:continue');
      _cache.invalidatePrefix('watch-history');

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('❌ [WatchHistory] Sync progress error: $e');
      return false;
    }
  }

  List<WatchHistoryModel> _parseList(dynamic data) {
    List<dynamic> list = [];
    if (data is List) {
      list = data;
    } else if (data is Map) {
      list = (data['items'] as List<dynamic>?) ??
          (data['history'] as List<dynamic>?) ??
          (data['data'] as List<dynamic>?) ??
          [];
    }
    return list.map((item) {
      if (item is Map) {
        return WatchHistoryModel.fromJson(Map<String, dynamic>.from(item));
      }
      return WatchHistoryModel.fromJson({});
    }).toList();
  }

  /// GET /watch-history/continue-watching?limit=10
  /// Returns items where 0 < progress < 90%. Short cache (30s).
  Future<List<WatchHistoryModel>> getContinueWatching({int limit = 10, bool forceRefresh = false}) async {
    return _cache.getCached<List<WatchHistoryModel>>(
      key: 'watch-history:continue:$limit',
      forceRefresh: forceRefresh,
      ttl: const Duration(seconds: 30),
      fetcher: () async {
        final response = await ApiClient.dio.get(
          '/watch-history/continue-watching',
          queryParameters: {'limit': limit},
        );
        return _parseList(response.data);
      },
    );
  }

  /// GET /watch-history?includeCompleted=true&limit=50
  Future<List<WatchHistoryModel>> getWatchHistory({
    bool includeCompleted = true,
    int limit = 50,
    bool forceRefresh = false,
  }) async {
    return _cache.getCached<List<WatchHistoryModel>>(
      key: 'watch-history:all:$includeCompleted:$limit',
      forceRefresh: forceRefresh,
      ttl: const Duration(minutes: 1),
      fetcher: () async {
        final response = await ApiClient.dio.get(
          '/watch-history',
          queryParameters: {
            'includeCompleted': includeCompleted,
            'limit': limit,
          },
        );
        return _parseList(response.data);
      },
    );
  }

  /// GET /watch-history/recent?limit=10
  Future<List<WatchHistoryModel>> getRecent({int limit = 10, bool forceRefresh = false}) async {
    return _cache.getCached<List<WatchHistoryModel>>(
      key: 'watch-history:recent:$limit',
      forceRefresh: forceRefresh,
      ttl: const Duration(seconds: 30),
      fetcher: () async {
        final response = await ApiClient.dio.get(
          '/watch-history/recent',
          queryParameters: {'limit': limit},
        );
        return _parseList(response.data);
      },
    );
  }

  /// DELETE /watch-history/content/:contentId
  Future<bool> deleteItem(String contentId) async {
    try {
      final response = await ApiClient.dio.delete('/watch-history/content/$contentId');
      _cache.invalidatePrefix('watch-history');
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  /// DELETE /watch-history/clear
  Future<bool> clearHistory() async {
    try {
      final response = await ApiClient.dio.delete('/watch-history/clear');
      _cache.invalidatePrefix('watch-history');
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }
}
