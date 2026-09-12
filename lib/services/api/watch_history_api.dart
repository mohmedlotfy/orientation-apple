import 'package:dio/dio.dart';
import '../dio_client.dart';
import '../../models/watch_history_model.dart';

class WatchHistoryApi {
  final DioClient _dioClient = DioClient();

  static List<WatchHistoryModel>? _continueWatchingCache;
  static DateTime? _continueWatchingCacheTime;
  static const Duration _cacheDuration = Duration(seconds: 30);

  static void invalidateCache() {
    _continueWatchingCache = null;
    _continueWatchingCacheTime = null;
  }

  WatchHistoryApi() {
    _dioClient.init();
  }

  /// POST /watch-history/progress
  Future<WatchHistoryModel> upsertProgress({
    required String contentId,
    required String contentTitle,
    String? contentThumbnail,
    required double currentTimeSeconds,
    required double durationSeconds,
    String? contentType,
    int? season,
    int? episode,
  }) async {
    invalidateCache();

    // Sanitize parameters to conform strictly to backend DTO specs:
    // currentTime >= 0, duration >= 1
    final sanitizedCurrentTime = currentTimeSeconds < 0 ? 0.0 : currentTimeSeconds;
    final sanitizedDuration = durationSeconds < 1.0 ? 1.0 : durationSeconds;

    // Filter contentThumbnail to only include valid HTTP/HTTPS URLs
    final isValidUrl = contentThumbnail != null &&
        contentThumbnail.isNotEmpty &&
        (contentThumbnail.startsWith('http://') || contentThumbnail.startsWith('https://'));

    final effectiveType = (contentType != null && contentType.isNotEmpty) ? contentType : 'episode';
    final effectiveSeason = season ?? (effectiveType == 'episode' ? 1 : null);
    final effectiveEpisode = (episode != null && episode > 0) ? episode : (effectiveType == 'episode' ? 1 : null);

    final payload = <String, dynamic>{
      'contentId': contentId,
      'contentTitle': contentTitle,
      if (isValidUrl) 'contentThumbnail': contentThumbnail,
      'currentTime': sanitizedCurrentTime,
      'duration': sanitizedDuration,
      'contentType': effectiveType,
      if (effectiveSeason != null) 'season': effectiveSeason,
      if (effectiveEpisode != null) 'episode': effectiveEpisode,
    };

    try {
      final response = await _dioClient.dio.post(
        '/watch-history/progress',
        data: payload,
      );

      final data = response.data as Map<String, dynamic>?;
      final watchHistory = data?['watchHistory'];
      if (watchHistory is Map<String, dynamic>) {
        return WatchHistoryModel.fromJson(watchHistory);
      }
      // Some backends may return the model directly
      if (data != null && data['contentId'] != null) {
        return WatchHistoryModel.fromJson(data);
      }
      throw Exception('Invalid watch history response');
    } on DioException catch (e) {
      print('❌ DioException in upsertProgress:');
      print('   Status: ${e.response?.statusCode}');
      print('   Response data: ${e.response?.data}');
      print('   Payload sent: $payload');
      throw _handleError(e);
    }
  }

  /// GET /watch-history/continue-watching?limit=
  Future<List<WatchHistoryModel>> getContinueWatching({int limit = 10, bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _continueWatchingCache != null &&
        _continueWatchingCacheTime != null &&
        DateTime.now().difference(_continueWatchingCacheTime!) < _cacheDuration) {
      print('⚡ Returning continue-watching from 30s in-memory cache');
      return _continueWatchingCache!;
    }

    try {
      print('📡 Calling GET /watch-history/continue-watching?limit=$limit');
      final response = await _dioClient.dio.get(
        '/watch-history/continue-watching',
        queryParameters: {'limit': limit},
      );

      print('📡 Response status: ${response.statusCode}');
      print('📡 Response data type: ${response.data.runtimeType}');

      List<WatchHistoryModel> results = [];

      if (response.data is Map) {
        final map = response.data as Map<String, dynamic>;
        print('📡 Response keys: ${map.keys.toList()}');
        final items = map['items'];
        if (items is List) {
          print('📡 Found ${items.length} items in response.items');
          results = items.map((e) {
            try {
              return WatchHistoryModel.fromJson(e as Map<String, dynamic>);
            } catch (err) {
              print('❌ Error parsing watch history item: $err');
              print('   Item data: $e');
              rethrow;
            }
          }).toList();
        } else {
          print('⚠️ Response.items is not a List: ${items.runtimeType}');
        }
      } else if (response.data is List) {
        final list = response.data as List;
        print('📡 Response is a List with ${list.length} items');
        results = list.map((e) {
          try {
            return WatchHistoryModel.fromJson(e as Map<String, dynamic>);
          } catch (err) {
            print('❌ Error parsing watch history item: $err');
            rethrow;
          }
        }).toList();
      }

      if (results.isNotEmpty) {
        _continueWatchingCache = results;
        _continueWatchingCacheTime = DateTime.now();
      }

      return results;
    } on DioException catch (e) {
      print('❌ DioException in getContinueWatching:');
      print('   Type: ${e.type}');
      print('   Status: ${e.response?.statusCode}');
      print('   Message: ${e.message}');
      print('   Response data: ${e.response?.data}');
      throw _handleError(e);
    } catch (e) {
      print('❌ Unexpected error in getContinueWatching: $e');
      rethrow;
    }
  }

  /// GET /watch-history?includeCompleted=&limit=
  Future<List<WatchHistoryModel>> getHistory({bool includeCompleted = true, int limit = 50}) async {
    try {
      final response = await _dioClient.dio.get(
        '/watch-history',
        queryParameters: {'includeCompleted': includeCompleted, 'limit': limit},
      );

      if (response.data is Map) {
        final map = response.data as Map<String, dynamic>;
        final items = map['items'];
        if (items is List) {
          return items.map((e) => WatchHistoryModel.fromJson(e as Map<String, dynamic>)).toList();
        }
      }

      if (response.data is List) {
        final list = response.data as List;
        return list.map((e) => WatchHistoryModel.fromJson(e as Map<String, dynamic>)).toList();
      }

      return [];
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// GET /watch-history/recent?limit=
  Future<List<WatchHistoryModel>> getRecent({int limit = 10}) async {
    try {
      final response = await _dioClient.dio.get(
        '/watch-history/recent',
        queryParameters: {'limit': limit},
      );

      if (response.data is Map) {
        final map = response.data as Map<String, dynamic>;
        final items = map['items'];
        if (items is List) {
          return items.map((e) => WatchHistoryModel.fromJson(e as Map<String, dynamic>)).toList();
        }
      }

      if (response.data is List) {
        final list = response.data as List;
        return list.map((e) => WatchHistoryModel.fromJson(e as Map<String, dynamic>)).toList();
      }

      return [];
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// GET /watch-history/content/:contentId
  Future<WatchHistoryModel?> getContentProgress(String contentId) async {
    try {
      final encoded = Uri.encodeComponent(contentId);
      final response = await _dioClient.dio.get('/watch-history/content/$encoded');
      final data = response.data as Map<String, dynamic>?;
      final watchHistory = data?['watchHistory'];
      if (watchHistory is Map<String, dynamic>) {
        return WatchHistoryModel.fromJson(watchHistory);
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw _handleError(e);
    }
  }

  /// POST /watch-history/content/:contentId/complete
  Future<WatchHistoryModel?> markComplete(String contentId) async {
    invalidateCache();
    try {
      final encoded = Uri.encodeComponent(contentId);
      final response = await _dioClient.dio.post('/watch-history/content/$encoded/complete');
      final data = response.data as Map<String, dynamic>?;
      final watchHistory = data?['watchHistory'];
      if (watchHistory is Map<String, dynamic>) {
        return WatchHistoryModel.fromJson(watchHistory);
      }
      return null;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// DELETE /watch-history/content/:contentId
  Future<void> deleteContent(String contentId) async {
    invalidateCache();
    try {
      final encoded = Uri.encodeComponent(contentId);
      await _dioClient.dio.delete('/watch-history/content/$encoded');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// DELETE /watch-history/clear
  Future<void> clear() async {
    invalidateCache();
    try {
      await _dioClient.dio.delete('/watch-history/clear');
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
        final message = e.response?.data?['message'];
        if (message is List) return message.join('\n');
        return message?.toString() ?? 'An error occurred. Please try again.';
      default:
        return 'An unexpected error occurred. Please try again.';
    }
  }
}

