import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../dio_client.dart';
import '../../models/project_model.dart';
import '../../models/episode_model.dart';
import '../../models/clip_model.dart';
import '../../models/pdf_file_model.dart';
import '../../models/watch_history_model.dart';
import '../../utils/cache_manager.dart';
import 'watch_history_api.dart';

class ProjectApi {
  final DioClient _dioClient = DioClient();
  final WatchHistoryApi _watchHistoryApi = WatchHistoryApi();

  // In-memory cache for reels (fastest access)
  static List<ClipModel>? _reelsMemoryCache;
  static DateTime? _reelsCacheTime;
  static const Duration _reelsCacheDuration = Duration(minutes: 5);

  // In-memory cache for saved reels
  static Set<String>? _savedReelIdsCache;
  static DateTime? _savedReelsCacheTime;
  static const Duration _savedReelsCacheDuration = Duration(minutes: 2);

  // In-memory catalog caches for PDF and Inventory files
  static List<dynamic>? _pdfCatalogCache;
  static DateTime? _pdfCatalogCacheTime;
  static List<dynamic>? _inventoryCatalogCache;
  static DateTime? _inventoryCatalogCacheTime;
  static const Duration _filesCacheDuration = Duration(minutes: 2);

  // In-flight request deduplication for saved lists
  static Future<List<ProjectModel>>? _savedProjectsInFlight;
  static Future<List<ClipModel>>? _savedReelsInFlight;

  ProjectApi() {
    _dioClient.init();
  }

  /// Clear all reels caches (memory + local storage)
  static Future<void> clearReelsCache() async {
    _reelsMemoryCache = null;
    _reelsCacheTime = null;
    _savedReelIdsCache = null;
    _savedReelsCacheTime = null;
    await CacheManager.clear('all_reels');
    print('🗑️ Cleared all reels caches');
  }

  // In-flight request coalescing maps
  static final Map<String, Future<Map<String, dynamic>?>> _projectRawInFlight = {};
  static final Map<String, Future<List<ProjectModel>>> _developerProjectsInFlight = {};

  /// GET /projects/:id — Fetches raw project JSON with in-flight coalescing and 5-min CacheManager TTL
  Future<Map<String, dynamic>?> getProjectRawJson(String id, {bool forceRefresh = false}) async {
    final cacheKey = 'project_raw_json_$id';
    if (!forceRefresh) {
      final cached = await CacheManager.get<Map<String, dynamic>>(cacheKey);
      if (cached != null) return cached;
    }

    if (_projectRawInFlight.containsKey(id)) {
      return _projectRawInFlight[id];
    }

    final future = _fetchProjectRawJson(id, cacheKey).whenComplete(() {
      _projectRawInFlight.remove(id);
    });
    _projectRawInFlight[id] = future;
    return future;
  }

  Future<Map<String, dynamic>?> _fetchProjectRawJson(String id, String cacheKey) async {
    try {
      final response = await _dioClient.dio.get('/projects/$id');
      if (response.data is Map<String, dynamic>) {
        final rawData = response.data as Map<String, dynamic>;
        await CacheManager.set(cacheKey, rawData, duration: const Duration(minutes: 5));
        return rawData;
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// GET /projects/:id — Get ProjectModel by ID
  Future<ProjectModel?> getProjectById(String id, {bool forceRefresh = false}) async {
    final rawJson = await getProjectRawJson(id, forceRefresh: forceRefresh);
    if (rawJson == null) return null;
    return ProjectModel.fromJson(rawJson);
  }

  /// GET /episode, then filter by projectId
  Future<List<EpisodeModel>> getEpisodes(String projectId) async {
    try {
      final response = await _dioClient.dio.get('/episode');
      List<dynamic> list;
      final responseData = response.data;
      if (responseData is List) {
        list = responseData;
      } else if (responseData is Map && responseData['value'] is List) {
        list = responseData['value'] as List;
      } else {
        list = <dynamic>[];
      }
      final out = <EpisodeModel>[];
      for (final e in list) {
        final m = e as Map<String, dynamic>?;
        if (m == null) continue;
        final pid = _resolveId(m['projectId']);
        if (pid == projectId) out.add(EpisodeModel.fromJson(m));
      }
      out.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
      return out;
    } on DioException catch (_) {
      return [];
    }
  }

  String? _resolveId(dynamic v) {
    if (v == null) return null;
    if (v is Map) return v['_id']?.toString() ?? v['id']?.toString();
    return v.toString();
  }

  static const String _episodeContentPrefix = 'episode__';

  /// Creates a stable, URL-safe contentId for Watch History that still encodes projectId + episodeId.
  /// Example: episode__<projectId>__<episodeId>
  static String makeEpisodeContentId(String projectId, String episodeId) {
    return '${_episodeContentPrefix}${projectId}__$episodeId';
  }

  static ({String projectId, String episodeId})? parseEpisodeContentId(
      String contentId) {
    String s = contentId;
    if (s.startsWith(_episodeContentPrefix)) {
      s = s.substring(_episodeContentPrefix.length);
    } else if (s.startsWith('episode_')) {
      s = s.substring('episode_'.length);
    }

    if (s.contains(r'\_\_')) {
      final p = s.split(r'\_\_');
      if (p.length == 2 && p[0].isNotEmpty) return (projectId: p[0], episodeId: p[1]);
    }
    if (s.contains('__')) {
      final p = s.split('__');
      if (p.length == 2 && p[0].isNotEmpty) return (projectId: p[0], episodeId: p[1]);
    }
    if (s.contains('_')) {
      final idx = s.lastIndexOf('_');
      if (idx > 0 && idx < s.length - 1) {
        return (projectId: s.substring(0, idx), episodeId: s.substring(idx + 1));
      }
    }
    if (s.isNotEmpty) {
      return (projectId: s, episodeId: '');
    }
    return null;
  }

  Future<bool> _hasAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return token != null && token.isNotEmpty;
  }

  /// Uses local cache (updated on save/unsave). PATCH /projects/:id/save-project does not return savedProjects.
  Future<bool> isProjectSaved(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('saved_projects') ?? [];
    return ids.contains(projectId);
  }

  /// PATCH /projects/:id/save-project — no body. On success, add to local cache.
  Future<void> saveProject(String projectId) async {
    await _dioClient.dio.patch('/projects/$projectId/save-project');
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('saved_projects') ?? [];
    if (!ids.contains(projectId)) {
      ids.add(projectId);
      await prefs.setStringList('saved_projects', ids);
    }
  }

  /// PATCH /projects/:id/unsave-project — no body. On success, remove from local cache.
  Future<void> unsaveProject(String projectId) async {
    await _dioClient.dio.patch('/projects/$projectId/unsave-project');
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('saved_projects') ?? [];
    ids.remove(projectId);
    await prefs.setStringList('saved_projects', ids);
  }

  /// Get saved projects (GET /users/saved-projects or GET /projects/saved)
  /// Deduplicates in-flight requests and returns valid empty list without falling back to secondary endpoint.
  Future<List<ProjectModel>> getSavedProjects() {
    if (_savedProjectsInFlight != null) {
      print('⚡ Returning in-flight getSavedProjects request');
      return _savedProjectsInFlight!;
    }
    _savedProjectsInFlight = _fetchSavedProjects().whenComplete(() {
      _savedProjectsInFlight = null;
    });
    return _savedProjectsInFlight!;
  }

  Future<List<ProjectModel>> _fetchSavedProjects() async {
    try {
      if (await _hasAuthToken()) {
        // Try GET /users/saved-projects first (returns { message, savedProjects: [...] })
        try {
          print('📡 Fetching saved projects from /users/saved-projects...');
          final response = await _dioClient.dio.get('/users/saved-projects');
          final data = response.data;

          List<dynamic>? projectsList;
          if (data is Map<String, dynamic>) {
            // Handle { message, savedProjects: [...] } format
            projectsList = data['savedProjects'] as List<dynamic>?;
          } else if (data is List) {
            // Handle direct array format
            projectsList = data;
          }

          if (projectsList != null) {
            final projects = projectsList
                .map((e) {
                  try {
                    // Handle both full project objects and IDs
                    if (e is Map<String, dynamic>) {
                      return ProjectModel.fromJson(e);
                    } else if (e is String) {
                      // If it's just an ID, we'll need to fetch it
                      return null;
                    }
                    return null;
                  } catch (e) {
                    print('⚠️ Error parsing saved project: $e');
                    return null;
                  }
                })
                .whereType<ProjectModel>()
                .toList();

            // If we got IDs instead of full objects, fetch them in parallel
            if (projects.isEmpty && projectsList.isNotEmpty) {
              final ids = projectsList
                  .map((e) => e.toString())
                  .where((id) => id.isNotEmpty)
                  .toList();
              final projectFutures = ids.map((id) => getProjectById(id));
              final fetchedProjects = await Future.wait(projectFutures);
              projects.addAll(fetchedProjects.whereType<ProjectModel>());
            }

            // Update local cache
            final prefs = await SharedPreferences.getInstance();
            final ids = projects.map((p) => p.id).toList();
            await prefs.setStringList('saved_projects', ids);

            print(
                '✅ Loaded ${projects.length} saved projects from /users/saved-projects');
            return projects;
          }
        } catch (e) {
          print(
              '⚠️ /users/saved-projects failed: $e, trying /projects/saved...');
        }

        // Fallback: Try GET /projects/saved (returns array directly)
        try {
          print('📡 Fetching saved projects from /projects/saved...');
          final response = await _dioClient.dio.get('/projects/saved');
          final data = response.data;

          List<dynamic> projectsList;
          if (data is List) {
            projectsList = data;
          } else if (data is Map<String, dynamic> && data['projects'] is List) {
            projectsList = data['projects'] as List;
          } else {
            projectsList = <dynamic>[];
          }

          final projects = projectsList
              .map((e) {
                try {
                  return ProjectModel.fromJson(e as Map<String, dynamic>);
                } catch (e) {
                  print('⚠️ Error parsing saved project: $e');
                  return null;
                }
              })
              .whereType<ProjectModel>()
              .toList();

          // Update local cache
          final prefs = await SharedPreferences.getInstance();
          final ids = projects.map((p) => p.id).toList();
          await prefs.setStringList('saved_projects', ids);

          print(
              '✅ Loaded ${projects.length} saved projects from /projects/saved');
          return projects;
        } catch (e) {
          print('⚠️ /projects/saved also failed: $e');
        }
      }
    } catch (e) {
      print('⚠️ Error fetching saved projects from backend: $e');
    }

    // Fallback to local cache - fetch projects in parallel
    print('📦 Using local cache for saved projects...');
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('saved_projects') ?? [];
    final projectFutures = ids.map((id) => getProjectById(id));
    final projects = await Future.wait(projectFutures);
    final out = projects.whereType<ProjectModel>().toList();
    print('✅ Loaded ${out.length} saved projects from local cache');
    return out;
  }

  /// Progress stored locally (0ms latency, 0 network calls).
  Future<void> trackWatching(
      String projectId, String episodeId, double progress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('watch_progress_${projectId}_$episodeId', progress);
    } catch (_) {}
  }

  /// Save playback progress strictly to local storage without network calls.
  Future<void> saveLocalWatchProgress({
    required String projectId,
    required String episodeId,
    required double currentTimeSeconds,
    required double durationSeconds,
  }) async {
    final frac = durationSeconds > 0
        ? (currentTimeSeconds / durationSeconds).clamp(0.0, 1.0)
        : 0.0;
    await trackWatching(projectId, episodeId, frac);
  }

  /// Read watch progress strictly from local storage (0 network requests).
  Future<double> getWatchingProgress(String projectId, String episodeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble('watch_progress_${projectId}_$episodeId') ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  /// Sync episode watch progress to backend (POST /watch-history/progress).
  /// Should ONLY be called ONCE when exiting/closing an episode.
  Future<void> syncEpisodeWatchProgress({
    required String projectId,
    required EpisodeModel episode,
    required String projectTitle,
    required double currentTimeSeconds,
    required double durationSeconds,
  }) async {
    final frac = durationSeconds > 0
        ? (currentTimeSeconds / durationSeconds).clamp(0.0, 1.0)
        : 0.0;
    await trackWatching(projectId, episode.id, frac);

    try {
      if (!await _hasAuthToken()) return;
      final contentId = makeEpisodeContentId(projectId, episode.id);
      await _watchHistoryApi.upsertProgress(
        contentId: contentId,
        contentTitle: projectTitle.isNotEmpty
            ? projectTitle
            : (episode.title.isNotEmpty
                ? episode.title
                : 'Episode ${episode.episodeNumber}'),
        contentThumbnail:
            episode.thumbnail.isNotEmpty ? episode.thumbnail : null,
        currentTimeSeconds: currentTimeSeconds,
        durationSeconds: durationSeconds,
        contentType: 'episode',
        episode: episode.episodeNumber,
      );
    } catch (_) {
      // Ignore backend sync errors; local cache still works.
    }
  }

  /// Legacy helper - delegates to syncEpisodeWatchProgress
  Future<void> updateEpisodeWatchProgress({
    required String projectId,
    required EpisodeModel episode,
    required String projectTitle,
    required double currentTimeSeconds,
    required double durationSeconds,
  }) async {
    await syncEpisodeWatchProgress(
      projectId: projectId,
      episode: episode,
      projectTitle: projectTitle,
      currentTimeSeconds: currentTimeSeconds,
      durationSeconds: durationSeconds,
    );
  }

  /// Returns the last watched episodeId for a given project using backend watch-history if available.
  Future<String?> getLastWatchedEpisodeId(String projectId) async {
    try {
      if (!await _hasAuthToken()) return null;
      final items = await _watchHistoryApi.getContinueWatching(limit: 100);
      WatchHistoryModel? best;
      for (final w in items) {
        final parsed = parseEpisodeContentId(w.contentId);
        if (parsed == null) continue;
        if (parsed.projectId != projectId) continue;
        if (best == null || w.lastWatchedAt.isAfter(best.lastWatchedAt)) {
          best = w;
        }
      }
      return best == null
          ? null
          : parseEpisodeContentId(best.contentId)?.episodeId;
    } catch (_) {
      return null;
    }
  }

  Future<List<ProjectModel>>? _continueWatchingInFlight;

  /// Continue watching list:
  /// - If logged in: derived from /watch-history/continue-watching
  /// - Otherwise: derived from local progress cache
  Future<List<ProjectModel>> getContinueWatchingProjects() {
    if (_continueWatchingInFlight != null) {
      print('⚡ Coalescing in-flight getContinueWatchingProjects request in ProjectApi');
      return _continueWatchingInFlight!;
    }
    _continueWatchingInFlight = _fetchContinueWatchingProjects().whenComplete(() {
      _continueWatchingInFlight = null;
    });
    return _continueWatchingInFlight!;
  }

  Future<List<ProjectModel>> _fetchContinueWatchingProjects() async {
    final Map<String, ({double progress, DateTime lastWatchedAt})> byProject = {};

    // 1. Try backend watch history if logged in
    try {
      if (await _hasAuthToken()) {
        print('📺 Fetching continue watching from backend...');
        final items = await _watchHistoryApi.getContinueWatching(limit: 100);
        print('📺 Got ${items.length} items from watch history API');

        for (final w in items) {
          String? pid = w.projectId;
          if (pid == null || pid.isEmpty) {
            final parsed = parseEpisodeContentId(w.contentId);
            pid = parsed?.projectId;
          }
          if (pid == null || pid.isEmpty) {
            print('⚠️ Could not parse contentId: ${w.contentId}');
            continue;
          }
          double frac = (w.progressPercentage / 100.0).clamp(0.0, 1.0);
          if (frac <= 0 && w.duration > 0 && w.currentTime > 0) {
            frac = (w.currentTime / w.duration).clamp(0.0, 1.0);
          }
          if (frac <= 0.01 || frac >= 0.95) {
            continue;
          }

          final existing = byProject[pid];
          if (existing == null ||
              w.lastWatchedAt.isAfter(existing.lastWatchedAt)) {
            byProject[pid] = (progress: frac, lastWatchedAt: w.lastWatchedAt);
            print(
                '✅ Added backend continue watching for project $pid: progress=${(frac * 100).toStringAsFixed(1)}%');
          }
        }
      } else {
        print('ℹ️ User not logged in, using local cache for continue watching');
      }
    } catch (e) {
      print('❌ Error fetching continue watching from backend: $e');
    }

    // 2. Merge local cache progress (for recently watched / offline / fast UI updates)
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('watch_progress_'));
      for (final k in keys) {
        final rest = k.replaceFirst('watch_progress_', '');
        final i = rest.lastIndexOf('_');
        if (i <= 0 || i >= rest.length - 1) continue;
        final pid = rest.substring(0, i);
        final prog = prefs.getDouble(k) ?? 0.0;
        if (prog > 0.01 && prog < 0.95) {
          final existing = byProject[pid];
          if (existing == null) {
            byProject[pid] = (progress: prog, lastWatchedAt: DateTime.now());
            print('✅ Added local continue watching for project $pid: progress=${(prog * 100).toStringAsFixed(1)}%');
          }
        }
      }
    } catch (e) {
      print('⚠️ Error reading local watch progress: $e');
    }

    if (byProject.isEmpty) {
      print('ℹ️ No continue watching items found');
      return [];
    }

    // Fetch all projects in parallel for better performance
    final projectIds = byProject.keys.toList();
    final projectFutures = projectIds.map((id) => getProjectById(id));
    final projects = await Future.wait(projectFutures);

    final out = <ProjectModel>[];
    for (var i = 0; i < projectIds.length; i++) {
      final p = projects[i];
      if (p != null) {
        final e = byProject[projectIds[i]]!;
        out.add(p.copyWith(watchProgress: e.progress));
      } else {
        print('⚠️ Project ${projectIds[i]} not found');
      }
    }

    out.sort((a, b) {
      final aT = byProject[a.id]?.lastWatchedAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bT = byProject[b.id]?.lastWatchedAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bT.compareTo(aT);
    });

    print('✅ Returning ${out.length} continue watching projects');
    return out;
  }

  /// GET /reels, filter by projectId, map to ClipModel (reels used as clips)
  /// Reuses cached reels from getAllClips for better performance
  Future<List<ClipModel>> getClipsByProject(String projectId) async {
    try {
      // Use getAllClips with cache to avoid duplicate API calls
      final allClips = await getAllClips();
      return allClips.where((clip) => clip.projectId == projectId).toList();
    } catch (_) {
      return [];
    }
  }

  /// GET /reels (with two-layer caching: in-memory + local storage)
  /// Supports optional pagination; omit page/limit to fetch all (backward compatible)
  Future<List<ClipModel>> getAllClips({
    bool useCache = true,
    int? page,
    int? limit,
  }) async {
    final cacheKey =
        'all_reels${page != null ? '_page_${page}_limit_$limit' : ''}';

    // Layer 1: Check in-memory cache first (only for non-paginated "all" request)
    if (page == null &&
        limit == null &&
        useCache &&
        _reelsMemoryCache != null &&
        _reelsCacheTime != null) {
      if (DateTime.now().difference(_reelsCacheTime!) < _reelsCacheDuration) {
        print(
            '⚡ Returning ${_reelsMemoryCache!.length} reels from memory cache');
        return _reelsMemoryCache!;
      }
    }

    // Layer 2: Try local cache
    if (useCache) {
      try {
        final cached = await CacheManager.get<List<dynamic>>(cacheKey);
        if (cached != null && cached.isNotEmpty) {
          print('📦 Returning ${cached.length} reels from local cache');
          final clips = cached
              .map((e) => ClipModel.fromJson(e as Map<String, dynamic>))
              .toList();
          // Update memory cache
          _reelsMemoryCache = clips;
          _reelsCacheTime = DateTime.now();
          return clips;
        }
      } catch (e) {
        print('⚠️ Error reading reels from local cache: $e');
        // Continue to fetch from API
      }
    }

    // Layer 3: Fetch from API
    try {
      print('📡 Fetching reels from API...');
      final queryParams = <String, dynamic>{};
      if (page != null) queryParams['page'] = page;
      if (limit != null) queryParams['limit'] = limit;
      final response = await _dioClient.dio.get(
        '/reels',
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );
      print('📡 Response status: ${response.statusCode}');
      print('📡 Response data type: ${response.data.runtimeType}');

      // Handle both response formats:
      // 1. Direct array: [...]
      // 2. Object with reels: { reels: [...], Count: 71 }
      List<dynamic> list;
      if (response.data is List) {
        list = response.data as List;
        print('📡 Response is direct array with ${list.length} items');
      } else if (response.data is Map<String, dynamic>) {
        final map = response.data as Map<String, dynamic>;
        // Try 'reels' key first, then 'data', then fall back to empty
        list = (map['reels'] as List<dynamic>?) ??
            (map['data'] as List<dynamic>?) ??
            <dynamic>[];
        print(
            '📡 Response is object, found ${list.length} reels in "reels" key');
      } else {
        list = <dynamic>[];
        print('⚠️ Unexpected response format: ${response.data.runtimeType}');
      }

      print('📡 Parsing ${list.length} reels...');
      final clips = <ClipModel>[];
      for (var i = 0; i < list.length; i++) {
        try {
          final item = list[i];
          if (item is Map) {
            final clip = ClipModel.fromJson(Map<String, dynamic>.from(item));
            clips.add(clip);
          }
        } catch (e) {
          print('⚠️ Error parsing reel $i: $e');
          // Skip this reel but continue with others
        }
      }
      print('✅ Successfully parsed ${clips.length} reels');

      // Update caches (memory cache only for non-paginated)
      if (clips.isNotEmpty) {
        if (page == null && limit == null) {
          _reelsMemoryCache = clips;
          _reelsCacheTime = DateTime.now();
        }
        await CacheManager.set(cacheKey, list,
            duration: const Duration(minutes: 10));
        print('💾 Cached ${clips.length} reels');
      }

      return clips;
    } on DioException catch (e) {
      print('❌ DioException in getAllClips: ${e.type} - ${e.message}');
      if (e.response != null) {
        print('   Status: ${e.response?.statusCode}');
        print('   Data: ${e.response?.data}');
      }
      // Return memory cache if available, even if expired
      if (_reelsMemoryCache != null) {
        print('⚠️ API failed, returning stale memory cache');
        return _reelsMemoryCache!;
      }
      return [];
    } catch (e) {
      print('❌ Unexpected error in getAllClips: $e');
      // Return memory cache if available
      if (_reelsMemoryCache != null) {
        return _reelsMemoryCache!;
      }
      return [];
    }
  }

  /// Check if a reel is saved (optimized - doesn't fetch full list)
  Future<bool> isReelSaved(String reelId) async {
    try {
      if (!await _hasAuthToken()) {
        return false;
      }

      // Quick check: Try to get saved reels from API
      // But don't wait too long - use timeout
      try {
        final response = await _dioClient.dio.get('/reels/saved').timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            throw TimeoutException('Request timeout');
          },
        );

        final data = response.data;
        List<dynamic> reelsList;

        if (data is List) {
          reelsList = data;
        } else if (data is Map<String, dynamic>) {
          reelsList = data['reels'] as List<dynamic>? ??
              data['savedReels'] as List<dynamic>? ??
              <dynamic>[];
        } else {
          reelsList = <dynamic>[];
        }

        // Check if reelId exists in the list
        for (final reel in reelsList) {
          if (reel is Map<String, dynamic>) {
            final id = _resolveId(reel['_id']) ?? _resolveId(reel['id']);
            if (id == reelId) {
              return true;
            }
          } else if (reel is String && reel == reelId) {
            return true;
          }
        }

        return false;
      } catch (e) {
        // If API call fails, return false (not saved)
        print('⚠️ Error checking if reel is saved: $e');
        return false;
      }
    } catch (e) {
      print('⚠️ Error in isReelSaved: $e');
      return false;
    }
  }

  /// POST /reels/:id/save — Save a reel to user's saved reels
  Future<bool> saveReel(String reelId) async {
    try {
      if (reelId.isEmpty) {
        print('⚠️ Cannot save reel: reelId is empty');
        return false;
      }

      final response = await _dioClient.dio.post('/reels/$reelId/save').timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Save reel request timeout');
        },
      );

      final success = response.statusCode == 200 || response.statusCode == 201;

      // Update cache on success
      if (success && _savedReelIdsCache != null) {
        _savedReelIdsCache!.add(reelId);
      }

      return success;
    } on TimeoutException catch (e) {
      print('⚠️ Timeout saving reel: $e');
      return false;
    } on DioException catch (e) {
      print('⚠️ Error saving reel: ${e.message}');
      if (e.response != null) {
        print('   Status: ${e.response?.statusCode}');
        print('   Data: ${e.response?.data}');
      }
      return false;
    } catch (e) {
      print('⚠️ Unexpected error saving reel: $e');
      return false;
    }
  }

  /// POST /reels/:id/unsave — Remove a reel from user's saved reels
  Future<bool> unsaveReel(String reelId) async {
    try {
      if (reelId.isEmpty) {
        print('⚠️ Cannot unsave reel: reelId is empty');
        return false;
      }

      final response =
          await _dioClient.dio.post('/reels/$reelId/unsave').timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Unsave reel request timeout');
        },
      );

      final success = response.statusCode == 200 || response.statusCode == 201;

      // Update cache on success
      if (success && _savedReelIdsCache != null) {
        _savedReelIdsCache!.remove(reelId);
      }

      return success;
    } on TimeoutException catch (e) {
      print('⚠️ Timeout unsaving reel: $e');
      return false;
    } on DioException catch (e) {
      print('⚠️ Error unsaving reel: ${e.message}');
      if (e.response != null) {
        print('   Status: ${e.response?.statusCode}');
        print('   Data: ${e.response?.data}');
      }
      return false;
    } catch (e) {
      print('⚠️ Unexpected error unsaving reel: $e');
      return false;
    }
  }

  /// Get saved reels (with in-memory caching and in-flight deduplication)
  Future<List<ClipModel>> getSavedReels({bool useCache = true}) {
    if (_savedReelsInFlight != null) {
      print('⚡ Returning in-flight getSavedReels request');
      return _savedReelsInFlight!;
    }
    _savedReelsInFlight = _fetchSavedReels(useCache: useCache).whenComplete(() {
      _savedReelsInFlight = null;
    });
    return _savedReelsInFlight!;
  }

  Future<List<ClipModel>> _fetchSavedReels({bool useCache = true}) async {
    // Check in-memory cache first
    if (useCache &&
        _savedReelIdsCache != null &&
        _savedReelsCacheTime != null) {
      if (DateTime.now().difference(_savedReelsCacheTime!) <
          _savedReelsCacheDuration) {
        // Use cached reels from memory + filter by saved IDs
        if (_reelsMemoryCache != null) {
          final savedReels = _reelsMemoryCache!
              .where((clip) => _savedReelIdsCache!.contains(clip.id))
              .toList();
          print(
              '⚡ Returning ${savedReels.length} saved reels from memory cache');
          return savedReels;
        }
      }
    }

    try {
      if (await _hasAuthToken()) {
        // Try GET /users/saved-reels first (returns { message, savedReels: [...] })
        try {
          print('📡 Fetching saved reels from /users/saved-reels...');
          final response = await _dioClient.dio.get('/users/saved-reels');
          final data = response.data;

          List<dynamic>? reelsList;
          if (data is Map<String, dynamic>) {
            // Handle { message, savedReels: [...] } format
            reelsList = data['savedReels'] as List<dynamic>?;
          } else if (data is List) {
            // Handle direct array format
            reelsList = data;
          }

          if (reelsList != null) {
            final reels = reelsList
                .map((e) {
                  try {
                    return ClipModel.fromJson(e as Map<String, dynamic>);
                  } catch (e) {
                    print('⚠️ Error parsing saved reel: $e');
                    return null;
                  }
                })
                .whereType<ClipModel>()
                .toList();

            // Update cache
            _savedReelIdsCache = reels.map((r) => r.id).toSet();
            _savedReelsCacheTime = DateTime.now();

            print(
                '✅ Loaded ${reels.length} saved reels from /users/saved-reels');
            return reels;
          }
        } catch (e) {
          print('⚠️ /users/saved-reels failed: $e, trying /reels/saved...');
        }

        // Fallback: Try GET /reels/saved (returns { message, reels: [...] })
        try {
          print('📡 Fetching saved reels from /reels/saved...');
          final response = await _dioClient.dio.get('/reels/saved');
          final data = response.data;

          List<dynamic> reelsList;
          if (data is List) {
            // Handle direct array format
            reelsList = data;
          } else if (data is Map<String, dynamic>) {
            // Handle { message, reels: [...] } format
            reelsList = data['reels'] as List<dynamic>? ?? <dynamic>[];
          } else {
            reelsList = <dynamic>[];
          }

          final reels = reelsList
              .map((e) {
                try {
                  return ClipModel.fromJson(e as Map<String, dynamic>);
                } catch (e) {
                  print('⚠️ Error parsing saved reel: $e');
                  return null;
                }
              })
              .whereType<ClipModel>()
              .toList();

          // Update cache
          _savedReelIdsCache = reels.map((r) => r.id).toSet();
          _savedReelsCacheTime = DateTime.now();

          print(
              '✅ Loaded ${reels.length} saved reels from /reels/saved');
          return reels;
        } catch (e) {
          print('⚠️ /reels/saved also failed: $e');
        }
      }

      // Return empty list if not authenticated or all methods failed
      _savedReelIdsCache = {};
      _savedReelsCacheTime = DateTime.now();
      return [];
    } on DioException catch (e) {
      print('❌ Error getting saved reels: ${e.message}');
      return [];
    } catch (e) {
      print('❌ Unexpected error getting saved reels: $e');
      return [];
    }
  }

  /// Backend reels have no like; always false.
  Future<bool> isClipLiked(String clipId) async => false;

  /// No backend for reel like; no-op.
  Future<void> likeClip(String clipId) async {}

  /// No backend for reel like; no-op.
  Future<void> unlikeClip(String clipId) async {}

  /// POST /reels — multipart: title, description?, projectId?, file (video), thumbnail (required by backend).
  /// thumbnailPath optional; if null, backend may 400.
  Future<bool> addReel({
    required String title,
    required String description,
    required String? videoPath,
    required String? projectId,
    required bool hasWhatsApp,
    String? developerId,
    String? developerName,
    String? developerLogo,
    String? thumbnailPath,
  }) async {
    if (videoPath == null || videoPath.isEmpty) return false;
    try {
      final form = <String, dynamic>{
        'title': title,
        'description': description,
        if (projectId != null && projectId.isNotEmpty) 'projectId': projectId,
        'file': await MultipartFile.fromFile(videoPath),
      };
      if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
        form['thumbnail'] = await MultipartFile.fromFile(thumbnailPath);
      }
      final res =
          await _dioClient.dio.post('/reels', data: FormData.fromMap(form));
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// GET /projects/developer?developer=ID — Get projects by developer ID
  /// OR GET /developer/me/projects — Get projects for authenticated developer (if developerId is empty)
  Future<List<ProjectModel>> getDeveloperProjects(String developerId, {bool forceRefresh = false}) async {
    final cacheKey = 'developer_projects_${developerId.trim()}';

    if (!forceRefresh) {
      final cached = await CacheManager.get<List<dynamic>>(cacheKey);
      if (cached != null) {
        print('⚡ Loaded ${cached.length} developer projects from CacheManager ($cacheKey)');
        return cached
            .map((e) => ProjectModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }

    if (_developerProjectsInFlight.containsKey(cacheKey)) {
      print('⚡ Joining existing in-flight request for $cacheKey');
      return _developerProjectsInFlight[cacheKey]!;
    }

    final future = _fetchDeveloperProjects(developerId, cacheKey).whenComplete(() {
      _developerProjectsInFlight.remove(cacheKey);
    });
    _developerProjectsInFlight[cacheKey] = future;
    return future;
  }

  Future<List<ProjectModel>> _fetchDeveloperProjects(String developerId, String cacheKey) async {
    try {
      print('═══════════════════════════════════════════════════════════');
      print('📡 GET DEVELOPER PROJECTS - START');
      print('═══════════════════════════════════════════════════════════');
      print('🔍 DeveloperId: "$developerId"');

      Response response;

      if (developerId.isNotEmpty && developerId.trim().isNotEmpty) {
        // Use /projects/developer?developer=ID to get projects for specific developer
        print('📡 Calling: GET /projects/developer?developer=$developerId');
        response = await _dioClient.dio.get(
          '/projects/developer',
          queryParameters: {'developer': developerId.trim()},
        );
      } else {
        // Use /developer/me/projects to get projects for authenticated developer
        print(
            '📡 Calling: GET /developer/me/projects (authenticated developer)');
        response = await _dioClient.dio.get('/developer/me/projects');
      }

      print('✅ Response Status: ${response.statusCode}');
      print('📦 Response Data Type: ${response.data.runtimeType}');
      print('');

      List<dynamic> projectsList = [];

      if (response.data is List) {
        // /projects/developer returns array directly
        projectsList = response.data as List;
        print('📋 Response is directly a List (from /projects/developer)');
      } else if (response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        if (data.containsKey('projects')) {
          projectsList =
              data['projects'] is List ? data['projects'] as List : <dynamic>[];
          print(
              '📋 Found "projects" key in response (from /developer/me/projects)');
        } else if (data.containsKey('data')) {
          final dataValue = data['data'];
          if (dataValue is List) {
            projectsList = dataValue;
            print('📋 Found "data" key in response');
          }
        }
      }

      print('📊 Parsed Projects List Length: ${projectsList.length}');
      print('');

      // Parse projects
      final projects = <ProjectModel>[];
      final rawList = <Map<String, dynamic>>[];
      for (var i = 0; i < projectsList.length; i++) {
        try {
          final projectData = projectsList[i] as Map<String, dynamic>;
          final project = ProjectModel.fromJson(projectData);
          projects.add(project);
          rawList.add(projectData);
          print(
              '✅ [$i] Parsed: ${project.title} (ID: ${project.id}, DevID: ${project.developerId})');
        } catch (parseError) {
          print('⚠️ Error parsing project at index $i: $parseError');
        }
      }

      print('═══════════════════════════════════════════════════════════');
      print('📡 GET DEVELOPER PROJECTS - END');
      print('═══════════════════════════════════════════════════════════');

      if (rawList.isNotEmpty) {
        await CacheManager.set(cacheKey, rawList, duration: const Duration(minutes: 5));
      }

      return projects;
    } on DioException catch (e) {
      print('❌ ERROR GETTING DEVELOPER PROJECTS: ${e.message}');
      return [];
    } catch (e) {
      print('❌ UNEXPECTED ERROR GETTING DEVELOPER PROJECTS: $e');
      return [];
    }
  }

  /// GET /projects?limit= (using the newly available backend endpoint)
  Future<List<ProjectModel>> getProjects(
      {int limit = 20, String? excludeId}) async {
    try {
      final response = await _dioClient.dio.get('/projects',
          queryParameters: {'limit': limit.toString()});
      final list = response.data is List ? response.data as List : <dynamic>[];
      var items = list
          .map((e) => ProjectModel.fromJson(e as Map<String, dynamic>))
          .toList();
      if (excludeId != null)
        items = items.where((p) => p.id != excludeId).toList();
      return items;
    } on DioException catch (e) {
      print('❌ Error getting projects: ${e.message}');
      return [];
    }
  }

  /// GET /projects/location?location= — for "projects by area"
  Future<List<ProjectModel>> getProjectsByArea(String location) async {
    try {
      // Use correct endpoint: GET /projects/location?location=
      final response = await _dioClient.dio
          .get('/projects/location', queryParameters: {'location': location});
      final list = response.data is List ? response.data as List : <dynamic>[];
      return list
          .map((e) => ProjectModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      print('❌ Error getting projects by area ($location): ${e.message}');
      return [];
    }
  }

  /// No direct “set inventory URL” in backend; /files/upload/inventory requires a file. No-op.
  Future<bool> updateInventory(String projectId, String inventoryUrl) async =>
      false;

  /// POST /files/upload/inventory — multipart: projectId, title, inventory (file). Backend requires title. Requires ADMIN.
  Future<bool> uploadInventoryFile(String projectId, String filePath,
      {String? title}) async {
    try {
      final form = FormData.fromMap({
        'projectId': projectId,
        'title': title?.trim().isNotEmpty == true ? title!.trim() : 'Inventory',
        'inventory': await MultipartFile.fromFile(filePath),
      });
      final res =
          await _dioClient.dio.post('/files/upload/inventory', data: form);
      if (res.statusCode == 200 || res.statusCode == 201) {
        _inventoryCatalogCache = null;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// GET /files/get/inventory (auth) — returns { message, inventories }. Filter by projectId.
  /// Inventory has project (not projectId) and inventoryUrl (not fileUrl).
  Future<String?> getInventoryUrl(String projectId) async {
    try {
      List<dynamic> list;
      if (_inventoryCatalogCache != null &&
          _inventoryCatalogCacheTime != null &&
          DateTime.now().difference(_inventoryCatalogCacheTime!) < _filesCacheDuration) {
        list = _inventoryCatalogCache!;
      } else {
        // New route (docs): GET /files/inventory -> List
        Response response;
        try {
          response = await _dioClient.dio.get('/files/inventory');
        } on DioException catch (e) {
          // Backwards-compatible fallback
          if (e.response?.statusCode == 404) {
            response = await _dioClient.dio.get('/files/get/inventory');
          } else {
            rethrow;
          }
        }

        final dynamic raw = response.data;
        list = raw is List
            ? raw
            : (raw is Map<String, dynamic>
                ? ((raw['inventories'] as List?) ?? <dynamic>[])
                : <dynamic>[]);
        _inventoryCatalogCache = list;
        _inventoryCatalogCacheTime = DateTime.now();
      }

      for (final e in list) {
        final m = e as Map<String, dynamic>?;
        if (m == null) continue;
        final pid = _resolveId(m['project']) ?? _resolveId(m['projectId']);
        if (pid == projectId) {
          final url = m['inventoryUrl']?.toString() ?? m['fileUrl']?.toString();
          if (url != null && url.isNotEmpty) return url;
        }
      }
      return null;
    } on DioException catch (_) {
      return null;
    }
  }

  /// GET /files/get/pdf (auth) — returns { message, pdfs }. Filter by projectId.
  /// File has project (not projectId) and pdfUrl (not fileUrl).
  Future<List<PdfFileModel>> getPdfFiles(String projectId) async {
    try {
      List<dynamic> list;
      if (_pdfCatalogCache != null &&
          _pdfCatalogCacheTime != null &&
          DateTime.now().difference(_pdfCatalogCacheTime!) < _filesCacheDuration) {
        list = _pdfCatalogCache!;
      } else {
        // New route (docs): GET /files/pdf -> List
        Response response;
        try {
          response = await _dioClient.dio.get('/files/pdf');
        } on DioException catch (e) {
          // Backwards-compatible fallback
          if (e.response?.statusCode == 404) {
            response = await _dioClient.dio.get('/files/get/pdf');
          } else {
            rethrow;
          }
        }

        final dynamic raw = response.data;
        list =
            raw is List ? raw : ((raw as Map?)?['pdfs'] as List? ?? <dynamic>[]);
        _pdfCatalogCache = list;
        _pdfCatalogCacheTime = DateTime.now();
      }

      return list
          .map((e) => e as Map<String, dynamic>)
          .where((m) =>
              (_resolveId(m['project']) ?? _resolveId(m['projectId'])) ==
              projectId)
          .map(PdfFileModel.fromJson)
          .toList();
    } on DioException catch (_) {
      return [];
    }
  }

  /// PATCH /files/update/inventory/:id — Update an inventory file
  Future<bool> updateInventoryFile(String inventoryId,
      {String? title, String? filePath}) async {
    try {
      final form = <String, dynamic>{};
      if (title != null && title.isNotEmpty) {
        form['title'] = title;
      }
      if (filePath != null && filePath.isNotEmpty) {
        form['inventory'] = await MultipartFile.fromFile(filePath);
      }
      Response res;
      try {
        res = await _dioClient.dio.patch('/files/inventory/$inventoryId',
            data: FormData.fromMap(form));
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          res = await _dioClient.dio.patch(
              '/files/update/inventory/$inventoryId',
              data: FormData.fromMap(form));
        } else {
          rethrow;
        }
      }
      final success = res.statusCode == 200 || res.statusCode == 201;
      if (success) _inventoryCatalogCache = null;
      return success;
    } catch (_) {
      return false;
    }
  }

  /// PATCH /files/update/pdf/:id — Update a PDF file
  Future<bool> updatePdfFile(String pdfId,
      {String? title, String? filePath}) async {
    try {
      final form = <String, dynamic>{};
      if (title != null && title.isNotEmpty) {
        form['title'] = title;
      }
      if (filePath != null && filePath.isNotEmpty) {
        form['PDF'] = await MultipartFile.fromFile(filePath);
      }
      Response res;
      try {
        res = await _dioClient.dio
            .patch('/files/pdf/$pdfId', data: FormData.fromMap(form));
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          res = await _dioClient.dio
              .patch('/files/update/pdf/$pdfId', data: FormData.fromMap(form));
        } else {
          rethrow;
        }
      }
      final success = res.statusCode == 200 || res.statusCode == 201;
      if (success) _pdfCatalogCache = null;
      return success;
    } catch (_) {
      return false;
    }
  }

  /// DELETE /files/delete/inventory/:id — Delete an inventory file
  Future<bool> deleteInventoryFile(String inventoryId) async {
    try {
      Response res;
      try {
        res = await _dioClient.dio.delete('/files/inventory/$inventoryId');
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          res = await _dioClient.dio
              .delete('/files/delete/inventory/$inventoryId');
        } else {
          rethrow;
        }
      }
      final success = res.statusCode == 200 || res.statusCode == 204;
      if (success) _inventoryCatalogCache = null;
      return success;
    } catch (_) {
      return false;
    }
  }

  /// DELETE /files/delete/pdf/:id — Delete a PDF file
  Future<bool> deletePdfFile(String pdfId) async {
    try {
      Response res;
      try {
        res = await _dioClient.dio.delete('/files/pdf/$pdfId');
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          res = await _dioClient.dio.delete('/files/delete/pdf/$pdfId');
        } else {
          rethrow;
        }
      }
      final success = res.statusCode == 200 || res.statusCode == 204;
      if (success) _pdfCatalogCache = null;
      return success;
    } catch (_) {
      return false;
    }
  }

  /// PATCH /projects/:id — Update project script
  /// Request: { "script": string }
  Future<bool> updateProjectScript(String projectId, String script) async {
    try {
      final response = await _dioClient.dio.patch(
        '/projects/$projectId',
        data: {'script': script},
      );
      final success = response.statusCode == 200 || response.statusCode == 201;
      if (success) {
        await CacheManager.clear('project_raw_json_$projectId');
        await CacheManager.clear('developer_projects_');
      }
      return success;
    } on DioException catch (e) {
      print('⚠️ Error updating project script: ${e.message}');
      if (e.response != null) {
        print('   Status: ${e.response?.statusCode}');
        print('   Data: ${e.response?.data}');
      }
      return false;
    } catch (e) {
      print('⚠️ Unexpected error updating project script: $e');
      return false;
    }
  }
}
