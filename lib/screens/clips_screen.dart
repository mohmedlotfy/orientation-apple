import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' as getx;
import '../models/clip_model.dart';
import '../reels/reels_screen.dart';
import '../services/dio_client.dart';
import '../services/clip_service.dart';
import '../services/cache_service.dart';

/// Simple Clip API without caching - Pure network calls
/// Best for: Real-time data, small datasets, or when server handles caching
///
/// Features:
/// - Direct API calls with no caching
/// - Simple and straightforward
/// - Always fetches fresh data
/// - Minimal memory footprint
/// - Easy to understand and maintain
class ClipApi {
  final DioClient _dioClient = DioClient();

  // Singleton pattern (optional - remove if using dependency injection)
  static ClipApi? _instance;

  factory ClipApi() {
    _instance ??= ClipApi._internal();
    return _instance!;
  }

  ClipApi._internal() {
    _dioClient.init();
  }

  /// Get all clips with pagination support
  Future<List<ClipModel>> getAllClips({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      debugPrint('🌐 ClipApi: Fetching clips (page $page, limit $limit)');

      final response = await _dioClient.dio.get(
        '/reels',
        queryParameters: {
          'page': page,
          'limit': limit,
        },
      );

      // Handle various response formats
      List<dynamic> list = [];

      if (response.data is List) {
        list = response.data as List;
      } else if (response.data is Map<String, dynamic>) {
        final map = response.data as Map<String, dynamic>;
        // Try different common field names
        list = (map['reels'] as List<dynamic>?) ??
            (map['data'] as List<dynamic>?) ??
            (map['clips'] as List<dynamic>?) ??
            (map['items'] as List<dynamic>?) ??
            [];
      }

      // Parse clips
      final clips = list
          .map((e) => ClipModel.fromJson(e as Map<String, dynamic>))
          .toList();

      debugPrint('✅ ClipApi: Loaded ${clips.length} clips');
      return clips;
    } on DioException catch (e) {
      debugPrint('❌ ClipApi: Network error fetching clips: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ ClipApi: Unexpected error: $e');
      rethrow;
    }
  }

  /// Get clips by project ID with pagination
  Future<List<ClipModel>> getClipsByProject(
    String projectId, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      debugPrint('🌐 ClipApi: Fetching clips for project $projectId');

      // Try server-side filtering first
      final response = await _dioClient.dio.get(
        '/reels',
        queryParameters: {
          'projectId': projectId,
          'page': page,
          'limit': limit,
        },
      );

      List<dynamic> list = [];

      if (response.data is List) {
        list = response.data as List;
      } else if (response.data is Map<String, dynamic>) {
        final map = response.data as Map<String, dynamic>;
        list = (map['reels'] as List<dynamic>?) ??
            (map['data'] as List<dynamic>?) ??
            (map['clips'] as List<dynamic>?) ??
            (map['items'] as List<dynamic>?) ??
            [];
      }

      final clips = list
          .map((e) => ClipModel.fromJson(e as Map<String, dynamic>))
          .toList();

      // If server-side filtering worked, return results
      if (clips.isNotEmpty) {
        debugPrint(
            '✅ ClipApi: Fetched ${clips.length} clips for project $projectId (server-side)');
        return clips;
      }

      // Fallback: fetch all and filter client-side
      debugPrint(
          '⚠️ ClipApi: Server-side filtering not supported, using client-side');
      final allClips = await getAllClips(page: 1, limit: 1000);
      final filtered =
          allClips.where((clip) => clip.projectId == projectId).toList();

      // Apply pagination
      final skip = (page - 1) * limit;
      final paginated = filtered.skip(skip).take(limit).toList();

      debugPrint(
          '✅ ClipApi: Filtered ${paginated.length} clips for project $projectId (client-side)');
      return paginated;
    } on DioException catch (e) {
      debugPrint(
          '❌ ClipApi: Network error getting clips by project: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ ClipApi: Error getting clips by project: $e');
      rethrow;
    }
  }

  /// Get a single clip by ID
  Future<ClipModel?> getClipById(String clipId) async {
    try {
      debugPrint('🌐 ClipApi: Fetching clip $clipId');

      final response = await _dioClient.dio.get('/reels/$clipId');

      Map<String, dynamic> data;
      if (response.data is Map<String, dynamic>) {
        data = response.data as Map<String, dynamic>;
      } else {
        throw Exception('Invalid response format');
      }

      final clip = ClipModel.fromJson(data);

      debugPrint('✅ ClipApi: Fetched clip $clipId');
      return clip;
    } on DioException catch (e) {
      debugPrint(
          '❌ ClipApi: Network error fetching clip $clipId: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('❌ ClipApi: Error fetching clip $clipId: $e');
      return null;
    }
  }

  /// Like a clip
  /// Note: Update this when backend implements like endpoint
  Future<ClipModel?> likeClip(String clipId) async {
    try {
      debugPrint('❤️ ClipApi: Liking clip $clipId');

      // TODO: Uncomment when backend implements like endpoint
      // await _dioClient.dio.post('/reels/$clipId/like');

      // For now, just refetch the clip to get updated data
      final clip = await getClipById(clipId);

      if (clip != null) {
        debugPrint('✅ ClipApi: Liked clip $clipId');
        // Return optimistic update until backend is ready
        return clip.copyWith(
          likes: clip.likes + 1,
          isLiked: true,
        );
      }

      return null;
    } on DioException catch (e) {
      debugPrint('❌ ClipApi: Error liking clip: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ ClipApi: Error liking clip: $e');
      rethrow;
    }
  }

  /// Unlike a clip
  /// Note: Update this when backend implements unlike endpoint
  Future<ClipModel?> unlikeClip(String clipId) async {
    try {
      debugPrint('💔 ClipApi: Unliking clip $clipId');

      // TODO: Uncomment when backend implements unlike endpoint
      // await _dioClient.dio.delete('/reels/$clipId/like');
      // or
      // await _dioClient.dio.post('/reels/$clipId/unlike');

      // For now, just refetch the clip
      final clip = await getClipById(clipId);

      if (clip != null) {
        debugPrint('✅ ClipApi: Unliked clip $clipId');
        // Return optimistic update until backend is ready
        return clip.copyWith(
          likes: (clip.likes - 1).clamp(0, double.infinity).toInt(),
          isLiked: false,
        );
      }

      return null;
    } on DioException catch (e) {
      debugPrint('❌ ClipApi: Error unliking clip: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ ClipApi: Error unliking clip: $e');
      rethrow;
    }
  }

  /// Add a new reel with upload progress tracking
  Future<ClipModel?> addReel({
    required String title,
    required String description,
    required String? videoPath,
    String? projectId,
    required bool hasWhatsApp,
    String? developerId,
    String? developerName,
    String? developerLogo,
    String? thumbnailPath,
    Function(int sent, int total)? onUploadProgress,
  }) async {
    if (videoPath == null || videoPath.isEmpty) {
      throw Exception('Video path is required');
    }

    // Validate file exists
    final file = File(videoPath);
    if (!await file.exists()) {
      throw Exception('Video file not found: $videoPath');
    }

    try {
      debugPrint('📤 ClipApi: Uploading reel: $title');

      final formData = <String, dynamic>{
        'title': title,
        'description': description,
        'hasWhatsApp': hasWhatsApp.toString(),
      };

      // Add video file
      formData['file'] = await MultipartFile.fromFile(
        videoPath,
        filename: videoPath.split('/').last,
      );

      // Add optional fields
      if (projectId != null && projectId.isNotEmpty) {
        formData['projectId'] = projectId;
      }

      if (developerId != null && developerId.isNotEmpty) {
        formData['developerId'] = developerId;
      }

      if (developerName != null && developerName.isNotEmpty) {
        formData['developerName'] = developerName;
      }

      if (developerLogo != null && developerLogo.isNotEmpty) {
        formData['developerLogo'] = developerLogo;
      }

      // Add thumbnail if provided
      if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
        final thumbnailFile = File(thumbnailPath);
        if (await thumbnailFile.exists()) {
          formData['thumbnail'] = await MultipartFile.fromFile(
            thumbnailPath,
            filename: thumbnailPath.split('/').last,
          );
        }
      }

      final response = await _dioClient.dio.post(
        '/reels',
        data: FormData.fromMap(formData),
        onSendProgress: (sent, total) {
          onUploadProgress?.call(sent, total);
          final percent = (sent / total * 100).toStringAsFixed(1);
          debugPrint('📤 Upload progress: $percent%');
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : (response.data as Map)['data'] as Map<String, dynamic>;

        final clip = ClipModel.fromJson(data);

        debugPrint('✅ ClipApi: Reel uploaded successfully: ${clip.id}');
        return clip;
      }

      debugPrint('⚠️ ClipApi: Upload returned status ${response.statusCode}');
      return null;
    } on DioException catch (e) {
      debugPrint('❌ ClipApi: Upload failed: ${e.message}');
      if (e.response != null) {
        debugPrint('Response data: ${e.response?.data}');
      }
      rethrow;
    } catch (e) {
      debugPrint('❌ ClipApi: Unexpected upload error: $e');
      rethrow;
    }
  }

  /// Delete a reel
  Future<bool> deleteReel(String clipId) async {
    try {
      debugPrint('🗑️ ClipApi: Deleting reel $clipId');

      final response = await _dioClient.dio.delete('/reels/$clipId');

      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('✅ ClipApi: Reel deleted successfully');
        return true;
      }

      return false;
    } on DioException catch (e) {
      debugPrint('❌ ClipApi: Error deleting reel: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ ClipApi: Error deleting reel: $e');
      rethrow;
    }
  }

  /// Update a reel
  Future<ClipModel?> updateReel({
    required String clipId,
    String? title,
    String? description,
    String? projectId,
  }) async {
    try {
      debugPrint('✏️ ClipApi: Updating reel $clipId');

      final data = <String, dynamic>{};

      if (title != null) data['title'] = title;
      if (description != null) data['description'] = description;
      if (projectId != null) data['projectId'] = projectId;

      final response = await _dioClient.dio.put(
        '/reels/$clipId',
        data: data,
      );

      if (response.statusCode == 200) {
        final updatedClip = ClipModel.fromJson(
          response.data as Map<String, dynamic>,
        );

        debugPrint('✅ ClipApi: Reel updated successfully');
        return updatedClip;
      }

      return null;
    } on DioException catch (e) {
      debugPrint('❌ ClipApi: Error updating reel: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ ClipApi: Error updating reel: $e');
      rethrow;
    }
  }

  /// Search reels by query
  Future<List<ClipModel>> searchReels({
    required String query,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      debugPrint('🔍 ClipApi: Searching reels with query: $query');

      final response = await _dioClient.dio.get(
        '/reels/search',
        queryParameters: {
          'q': query,
          'page': page,
          'limit': limit,
        },
      );

      List<dynamic> list = [];

      if (response.data is List) {
        list = response.data as List;
      } else if (response.data is Map<String, dynamic>) {
        final map = response.data as Map<String, dynamic>;
        list = (map['reels'] as List<dynamic>?) ??
            (map['data'] as List<dynamic>?) ??
            (map['clips'] as List<dynamic>?) ??
            (map['results'] as List<dynamic>?) ??
            [];
      }

      final clips = list
          .map((e) => ClipModel.fromJson(e as Map<String, dynamic>))
          .toList();

      debugPrint('✅ ClipApi: Found ${clips.length} clips for query: $query');
      return clips;
    } on DioException catch (e) {
      debugPrint('❌ ClipApi: Search error: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ ClipApi: Search error: $e');
      rethrow;
    }
  }

  /// Get trending reels
  Future<List<ClipModel>> getTrendingReels({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      debugPrint('🔥 ClipApi: Fetching trending reels');

      final response = await _dioClient.dio.get(
        '/reels/trending',
        queryParameters: {
          'page': page,
          'limit': limit,
        },
      );

      List<dynamic> list = [];

      if (response.data is List) {
        list = response.data as List;
      } else if (response.data is Map<String, dynamic>) {
        final map = response.data as Map<String, dynamic>;
        list = (map['reels'] as List<dynamic>?) ??
            (map['data'] as List<dynamic>?) ??
            (map['clips'] as List<dynamic>?) ??
            [];
      }

      final clips = list
          .map((e) => ClipModel.fromJson(e as Map<String, dynamic>))
          .toList();

      debugPrint('✅ ClipApi: Loaded ${clips.length} trending reels');
      return clips;
    } on DioException catch (e) {
      debugPrint('❌ ClipApi: Error fetching trending reels: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ ClipApi: Error fetching trending reels: $e');
      rethrow;
    }
  }

  /// Get user's liked reels
  /// Note: Requires authentication
  Future<List<ClipModel>> getLikedReels({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      debugPrint('❤️ ClipApi: Fetching liked reels');

      final response = await _dioClient.dio.get(
        '/reels/liked',
        queryParameters: {
          'page': page,
          'limit': limit,
        },
      );

      List<dynamic> list = [];

      if (response.data is List) {
        list = response.data as List;
      } else if (response.data is Map<String, dynamic>) {
        final map = response.data as Map<String, dynamic>;
        list = (map['reels'] as List<dynamic>?) ??
            (map['data'] as List<dynamic>?) ??
            (map['clips'] as List<dynamic>?) ??
            [];
      }

      final clips = list
          .map((e) => ClipModel.fromJson(e as Map<String, dynamic>))
          .toList();

      debugPrint('✅ ClipApi: Loaded ${clips.length} liked reels');
      return clips;
    } on DioException catch (e) {
      debugPrint('❌ ClipApi: Error fetching liked reels: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ ClipApi: Error fetching liked reels: $e');
      rethrow;
    }
  }

  /// Dispose resources (optional - currently no cleanup needed)
  void dispose() {
    debugPrint('👋 ClipApi: Disposed');
  }
}

/// Clips tab screen - loads reels and displays ReelsScreen.
class ClipsScreen extends StatefulWidget {
  const ClipsScreen({super.key});

  @override
  ClipsScreenState createState() => ClipsScreenState();
}

class ClipsScreenState extends State<ClipsScreen> {
  final GlobalKey<ReelsScreenState> _reelsKey = GlobalKey<ReelsScreenState>();
  List<ClipModel> _clips = [];
  bool _isLoading = true;
  bool _hasLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    // Pre-fetch clips in the background immediately so the tab is ready when opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadClips(forceRefresh: false);
    });
  }

  Future<void> _loadClips({bool forceRefresh = false}) async {
    try {
      debugPrint('🎬 [ClipsScreen] Loading clips (forceRefresh: $forceRefresh)...');
      if (!getx.Get.isRegistered<ClipService>()) {
        debugPrint('❌ [ClipsScreen] ClipService is not registered');
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final clipService = getx.Get.find<ClipService>();
      // Use limit 50 instead of 5 so newly added reels in the database are not cut off
      final clips = await clipService.getClips(
        page: 1,
        limit: 50,
        forceRefresh: forceRefresh,
      );
      debugPrint('🎬 [ClipsScreen] Received ${clips.length} clips from ClipService');
      if (mounted) {
        setState(() {
          _clips = clips;
          _isLoading = false;
          _hasLoadedOnce = true;
        });
      }

      // Pre-cache thumbnails and initial video files in the background
      if (clips.isNotEmpty) {
        CacheService().cacheReelsContent(clips);
      }
    } catch (e, st) {
      debugPrint('❌ [ClipsScreen] Error loading clips: $e\n$st');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> refresh() async {
    setState(() => _isLoading = true);
    await _loadClips(forceRefresh: true);
  }

  void setVisible(bool visible) {
    _reelsKey.currentState?.setVisible(visible);
    if (visible && (!_hasLoadedOnce || _clips.isEmpty)) {
      _hasLoadedOnce = true;
      _loadClips(forceRefresh: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
            child: CircularProgressIndicator(color: Color(0xFFE50914))),
      );
    }
    if (_clips.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.video_library_outlined,
                  color: Colors.white54, size: 54),
              const SizedBox(height: 16),
              Text(
                'No Clips Available',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.7), fontSize: 18),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: refresh,
                icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
                label: const Text('Refresh Clips',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ReelsScreen(
      key: _reelsKey,
      clips: _clips,
      initialIndex: 0,
      initialVisible: true,
    );
  }
}

