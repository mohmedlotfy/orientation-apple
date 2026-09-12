import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import '../models/clip_model.dart';
import '../services/cache_managers.dart';

/// Centralized video controller manager for TikTok-style reels.
///
/// Features:
/// - Strict 3-controller sliding window: [currentIndex - 1, currentIndex, currentIndex + 1]
/// - Immediate disposal of controllers outside the 3-controller window to avoid OOM & decoder limits
/// - Local disk caching via CacheManagerReels for 0ms instant playback
/// - Pre-initialization and pre-buffering of next & previous reels in background (muted)
/// - Single audio active at a time (unmuted for current reel, muted for prebuffered)
class VideoControllerManager extends ChangeNotifier {
  static const Duration _initTimeout = Duration(seconds: 12);

  final Map<int, VideoPlayerController> _controllers = {};
  final Set<int> _failedIndices = {};
  final Set<int> _initializing = {};

  int _currentIndex = 0;
  bool _isVisible = true;

  int get currentIndex => _currentIndex;
  bool get isVisible => _isVisible;

  VideoPlayerController? controllerAt(int index) => _controllers[index];
  bool isFailed(int index) => _failedIndices.contains(index);
  bool isInitializing(int index) => _initializing.contains(index);

  void setVisible(bool visible) {
    _isVisible = visible;
    if (!visible) {
      pauseAll();
    } else {
      final current = _controllers[_currentIndex];
      if (current != null && current.value.isInitialized && !current.value.isPlaying) {
        current.setVolume(1.0);
        current.play().catchError((e) {
          debugPrint('VideoControllerManager: play on setVisible error: $e');
        });
      }
    }
    notifyListeners();
  }

  /// Called whenever the PageView scrolls to a new reel index.
  /// Enforces the strict 3-controller memory pool and immediate audio isolation.
  Future<void> onPageChanged(int newIndex, List<ClipModel> clips) async {
    _currentIndex = newIndex;

    // 1. Immediately mute and pause ANY other controller synchronously so no audio leaks!
    for (final entry in _controllers.entries) {
      if (entry.key != newIndex) {
        try {
          final c = entry.value;
          c.setVolume(0.0);
          if (c.value.isInitialized && c.value.isPlaying) {
            c.pause();
          }
        } catch (_) {}
      }
    }

    // 2. Immediately dispose & evict any controllers outside [newIndex - 1, newIndex + 1]
    _evictFarControllers(newIndex);

    if (newIndex < 0 || newIndex >= clips.length) return;

    // 3. Manage CURRENT index (newIndex): Play and unmute
    final currentClip = clips[newIndex];
    final existingController = _controllers[newIndex];

    if (existingController != null && existingController.value.isInitialized) {
      // Controller was already pre-buffered!
      pauseAllExcept(newIndex);
      existingController.setLooping(true);
      existingController.setVolume(1.0);
      if (_isVisible) {
        existingController.play().catchError((e) {
          debugPrint('VideoControllerManager: play existing error: $e');
        });
      }
      notifyListeners();
    } else if (!_initializing.contains(newIndex) && !_failedIndices.contains(newIndex)) {
      // Need to initialize current controller now
      _initController(
        index: newIndex,
        url: currentClip.videoUrl,
        isAsset: currentClip.isAsset,
      );
    }

    // 4. Preload NEXT index (newIndex + 1) in background (muted & paused)
    if (newIndex + 1 < clips.length) {
      final nextClip = clips[newIndex + 1];
      if (!_controllers.containsKey(newIndex + 1) &&
          !_initializing.contains(newIndex + 1) &&
          !_failedIndices.contains(newIndex + 1)) {
        _initController(
          index: newIndex + 1,
          url: nextClip.videoUrl,
          isAsset: nextClip.isAsset,
        );
      }
    }

    // 5. Preload PREVIOUS index (newIndex - 1) in background (muted & paused)
    if (newIndex - 1 >= 0) {
      final prevClip = clips[newIndex - 1];
      if (!_controllers.containsKey(newIndex - 1) &&
          !_initializing.contains(newIndex - 1) &&
          !_failedIndices.contains(newIndex - 1)) {
        _initController(
          index: newIndex - 1,
          url: prevClip.videoUrl,
          isAsset: prevClip.isAsset,
        );
      }
    }
  }

  /// Initializes a single VideoPlayerController with disk caching support.
  Future<void> _initController({
    required int index,
    required String url,
    required bool isAsset,
  }) async {
    if (url.isEmpty) return;
    if (_controllers.containsKey(index)) return;
    if (_initializing.contains(index)) return;
    _initializing.add(index);


    try {
      // 1. Check local disk cache first for instant 0ms buffering
      File? cachedFile;
      if (!isAsset) {
        try {
          final fileInfo = await CacheManagerReels.instance.getFileFromCache(url);
          if (fileInfo != null && await fileInfo.file.exists()) {
            cachedFile = fileInfo.file;
            debugPrint('⚡ [VideoControllerManager] Using cached video for index $index');
          }
        } catch (_) {}
      }

      // 2. Instantiate controller (from local cache file, asset, or streaming network URL)
      final VideoPlayerController controller = isAsset
          ? VideoPlayerController.asset(url)
          : (cachedFile != null
              ? VideoPlayerController.file(
                  cachedFile,
                  videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
                )
              : VideoPlayerController.networkUrl(
                  Uri.parse(url),
                  videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
                ));

      await controller.initialize().timeout(
        _initTimeout,
        onTimeout: () {
          try {
            controller.dispose();
          } catch (_) {}
          throw TimeoutException('Video init timeout for index $index');
        },
      );

      // Verify index is still within active sliding window [currentIndex - 1, currentIndex + 1]
      if ((index - _currentIndex).abs() > 1) {
        // User has already scrolled far away while this was initializing; dispose immediately
        _disposeSingleController(controller);
        return;
      }

      controller.setLooping(true);

      if (index == _currentIndex) {
        // This is the active reel! Unmute, pause others, and auto-play immediately!
        controller.setVolume(1.0);
        _controllers[index] = controller;
        pauseAllExcept(index);
        if (_isVisible) {
          await controller.play();
        }
      } else {
        // Pre-buffered adjacent reel: keep muted & paused!
        controller.setVolume(0.0);
        controller.pause();
        _controllers[index] = controller;
      }

      // 3. If streaming from network, cache to disk in background for subsequent swipes
      if (cachedFile == null && !isAsset) {
        CacheManagerReels.instance.downloadFile(url).then((_) {
          debugPrint('📥 [VideoControllerManager] Cached reel to disk: $url');
        }).catchError((_) {});
      }

      notifyListeners();
    } catch (e) {
      debugPrint('❌ [VideoControllerManager] Init failed for index=$index: $e');
      _failedIndices.add(index);
      notifyListeners();
    } finally {
      _initializing.remove(index);
    }
  }

  /// Explicit play helper
  Future<void> play(int index, String url, {bool isAsset = false}) async {
    final c = _controllers[index];
    if (c != null && c.value.isInitialized) {
      pauseAllExcept(index);
      c.setVolume(1.0);
      if (_isVisible) {
        await c.play();
      }
      notifyListeners();
      return;
    }

    if (!_initializing.contains(index)) {
      await _initController(
        index: index,
        url: url,
        isAsset: isAsset,
      );
    }
  }

  /// Preload helper
  Future<void> preload(int index, String url, {bool isAsset = false}) async {
    if ((index - _currentIndex).abs() > 1) return;
    if (_controllers.containsKey(index)) return;
    if (_initializing.contains(index)) return;

    await _initController(
      index: index,
      url: url,
      isAsset: isAsset,
    );
  }

  /// Toggle play/pause for current reel
  Future<void> togglePlayPause(int index) async {
    final c = _controllers[index];
    if (c == null || !c.value.isInitialized) return;

    if (c.value.isPlaying) {
      await c.pause();
    } else {
      pauseAllExcept(index);
      c.setVolume(1.0);
      await c.play();
    }
    notifyListeners();
  }


  void pause(int index) {
    final c = _controllers[index];
    if (c != null && c.value.isInitialized && c.value.isPlaying) {
      c.pause();
      notifyListeners();
    }
  }

  void pauseAll() {
    for (final c in _controllers.values) {
      try {
        c.setVolume(0.0);
        if (c.value.isInitialized && c.value.isPlaying) {
          c.pause();
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  void pauseAllExcept(int keepIndex) {
    for (final entry in _controllers.entries) {
      if (entry.key == keepIndex) continue;
      try {
        final c = entry.value;
        c.setVolume(0.0);
        if (c.value.isInitialized && c.value.isPlaying) {
          c.pause();
        }
      } catch (_) {}
    }
  }


  /// Evicts any controller outside [centerIndex - 1, centerIndex + 1]
  void _evictFarControllers(int centerIndex) {
    final toRemove = <int>[];
    for (final index in _controllers.keys) {
      if ((index - centerIndex).abs() > 1) {
        toRemove.add(index);
      }
    }

    for (final index in toRemove) {
      final c = _controllers.remove(index);
      if (c != null) {
        _disposeSingleController(c);
      }
    }
  }

  void _disposeSingleController(VideoPlayerController c) {
    try {
      if (c.value.isInitialized && c.value.isPlaying) {
        c.pause();
      }
      c.dispose();
    } catch (e) {
      debugPrint('VideoControllerManager: dispose error: $e');
    }
  }

  void disposeAll() {
    for (final c in _controllers.values) {
      _disposeSingleController(c);
    }
    _controllers.clear();
    _failedIndices.clear();
    _initializing.clear();
  }

  @override
  void dispose() {
    disposeAll();
    super.dispose();
  }
}

