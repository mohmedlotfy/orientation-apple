import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../models/clip_model.dart';
import '../models/project_model.dart';
import '../services/clip_service.dart';
import '../services/projects_service.dart';
import '../services/in_memory_cache_service.dart';
import '../utils/auth_helper.dart';
import '../screens/main_screen.dart';
import '../screens/project_details_screen.dart';
import 'video_controller_manager.dart';
import '../main.dart'; // Added for routeObserver

class ReelsScreen extends StatefulWidget {
  final List<ClipModel> clips;
  final int initialIndex;
  final bool initialVisible;

  const ReelsScreen({
    super.key,
    required this.clips,
    this.initialIndex = 0,
    this.initialVisible = true,
  });

  @override
  State<ReelsScreen> createState() => ReelsScreenState();
}

class ReelsScreenState extends State<ReelsScreen>
    with WidgetsBindingObserver, RouteAware {
  late PageController _pageController;
  late VideoControllerManager _videoManager;
  ClipService? _clipService;

  late List<ClipModel> _clips;
  int _currentIndex = 0;
  int _currentPage = 1;
  static const int _pageSize = 20;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  final Map<String, bool> _savedReelIds = {};

  static const Color brandRed = Color(0xFFE50914);

  @override
  void initState() {
    super.initState();
    _clips = List<ClipModel>.from(widget.clips);
    _videoManager = VideoControllerManager();
    _videoManager.setVisible(widget.initialVisible);
    _pageController = PageController(initialPage: widget.initialIndex);
    _currentIndex = widget.initialIndex;

    try {
      if (Get.isRegistered<ClipService>()) {
        _clipService = Get.find<ClipService>();
      }
    } catch (_) {}

    WidgetsBinding.instance.addObserver(this);
    _loadSavedStatus();

    // Trigger initial page playback & pre-buffering
    if (_clips.isNotEmpty) {
      _videoManager.onPageChanged(widget.initialIndex, _clips);
    } else {
      _loadInitialClips();
    }
  }

  Future<void> _loadInitialClips() async {
    if (_clipService == null) return;
    try {
      final initial = await _clipService!.getClips(page: 1, limit: _pageSize);
      if (!mounted) return;
      if (initial.isNotEmpty) {
        setState(() {
          _clips = initial;
          _currentPage = 1;
          _hasMore = initial.length >= _pageSize;
        });
        _videoManager.onPageChanged(_currentIndex, _clips);
      }
    } catch (e) {
      debugPrint('ReelsScreen: Error loading initial clips: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final modalRoute = ModalRoute.of(context);
    if (modalRoute != null) {
      routeObserver.subscribe(this, modalRoute);
    }
  }

  @override
  void didUpdateWidget(covariant ReelsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clips != widget.clips) {
      _loadSavedStatus();
      if (widget.clips.isNotEmpty) {
        _clips = List<ClipModel>.from(widget.clips);
      }
      if (_currentIndex >= _clips.length) {
        _currentIndex = (_clips.length - 1).clamp(0, double.infinity).toInt();
      }
      if (mounted) setState(() {});
    }
  }

  @override
  void didPushNext() {
    _videoManager.setVisible(false);
  }

  @override
  void didPopNext() {
    _videoManager.setVisible(true);
  }

  void setVisible(bool visible) {
    _videoManager.setVisible(visible);
    if (visible && mounted && _clips.isNotEmpty) {
      _videoManager.onPageChanged(_currentIndex, _clips);
      setState(() {});
    }
  }

  ClipModel? get _currentClip {
    if (_currentIndex < 0 || _currentIndex >= _clips.length) {
      return null;
    }
    return _clips[_currentIndex];
  }

  Future<void> _loadSavedStatus() async {
    if (!mounted || _clipService == null) return;
    try {
      final saved = await _clipService!.getSavedReels();
      if (mounted) {
        setState(() {
          _savedReelIds.clear();
          for (final r in saved) {
            _savedReelIds[r.id] = true;
          }
        });
      }
    } catch (_) {}
  }

  void _onPageChanged(int index) {
    if (index < 0 || index >= _clips.length) return;

    setState(() => _currentIndex = index);

    // Enforce 3-controller memory pool & preloading (video buffers only, no UI metadata fetches)
    _videoManager.onPageChanged(index, _clips);

    // Infinite Pagination: When user is within 3 reels of the end, load next page
    if (index >= _clips.length - 3 && !_isLoadingMore && _hasMore) {
      _loadMoreClips();
    }
  }

  Future<void> _loadMoreClips() async {
    if (_isLoadingMore || !_hasMore || _clipService == null) return;
    _isLoadingMore = true;

    try {
      final nextPage = _currentPage + 1;
      debugPrint('🎬 [ReelsScreen] Fetching page $nextPage for infinite scroll...');
      final newClips = await _clipService!.getClips(
        page: nextPage,
        limit: _pageSize,
      );

      if (!mounted) return;

      if (newClips.isEmpty) {
        _hasMore = false;
        debugPrint('🎬 [ReelsScreen] Reached end of feed (no more clips)');
      } else {
        // De-duplicate newly fetched clips
        final existingIds = _clips.map((c) => c.id).toSet();
        final uniqueNew = newClips.where((c) => !existingIds.contains(c.id)).toList();

        if (uniqueNew.isEmpty) {
          _hasMore = false;
        } else {
          _currentPage = nextPage;
          _clips.addAll(uniqueNew);
          debugPrint('🎬 [ReelsScreen] Appended ${uniqueNew.length} clips. Total: ${_clips.length}');
          setState(() {});
        }
      }
    } catch (e) {
      debugPrint('❌ [ReelsScreen] Error loading more clips: $e');
    } finally {
      _isLoadingMore = false;
    }
  }

  Future<void> _onRefresh() async {
    if (_clipService == null) return;
    try {
      debugPrint('🔄 [ReelsScreen] Pull-to-refresh triggered...');
      final freshClips = await _clipService!.getClips(
        page: 1,
        limit: _pageSize,
        forceRefresh: true,
      );

      if (!mounted) return;

      if (freshClips.isNotEmpty) {
        setState(() {
          _clips = freshClips;
          _currentPage = 1;
          _hasMore = true;
          _currentIndex = 0;
        });

        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
        _loadSavedStatus();
        _videoManager.onPageChanged(0, _clips);
      }
    } catch (e) {
      debugPrint('❌ [ReelsScreen] Error during pull-to-refresh: $e');
    }
  }

  void _onVideoTap(int index) {
    _videoManager.togglePlayPause(index);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _videoManager.pauseAll();
    } else if (state == AppLifecycleState.resumed) {
      if (_videoManager.isVisible && _clips.isNotEmpty) {
        _videoManager.onPageChanged(_currentIndex, _clips);
      }
    }
  }

  Future<void> _toggleSave(int index) async {
    debugPrint('💾 _toggleSave called for index: $index');
    if (!mounted || _clipService == null) {
      debugPrint('❌ Widget not mounted or clipService is null');
      return;
    }
    if (index < 0 || index >= _clips.length) {
      debugPrint('❌ Invalid index: $index');
      return;
    }

    debugPrint('🔐 Checking authentication...');
    final ok = await AuthHelper.requireAuth(context);
    debugPrint('🔐 Auth result: $ok');
    if (!ok || !mounted) {
      debugPrint('❌ Auth failed or widget not mounted');
      return;
    }

    final clip = _clips[index];
    final saved = _savedReelIds[clip.id] ?? false;
    debugPrint('💾 Current saved status: $saved for clip: ${clip.id}');

    // Optimistic UI update
    _savedReelIds[clip.id] = !saved;
    if (mounted) setState(() {});

    try {
      bool success = false;
      if (saved) {
        debugPrint('🗑️ Unsaving reel...');
        success = await _clipService!.unsaveReel(clip.id);
      } else {
        debugPrint('💾 Saving reel...');
        success = await _clipService!.saveReel(clip.id);
      }

      if (!success) {
        // Revert on API failure
        _savedReelIds[clip.id] = saved;
        if (mounted) setState(() {});
        debugPrint('⚠️ Save/unsave API returned false — reverted local state');
      }
    } catch (e) {
      debugPrint('❌ Error in _toggleSave: $e');
      _savedReelIds[clip.id] = saved;
      if (mounted) setState(() {});
    }
  }

  Future<void> _openProject(String? projectId) async {
    debugPrint('🚀 _openProject called with projectId: "$projectId"');
    
    if (projectId == null || projectId.isEmpty) {
      debugPrint('❌ projectId is null or empty');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Project information not available'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    
    debugPrint('✅ projectId is valid: "$projectId"');
    
    debugPrint('🔐 Checking authentication...');
    final ok = await AuthHelper.requireAuth(context);
    debugPrint('🔐 Auth result: $ok');
    
    if (!ok) {
      debugPrint('❌ User is not authenticated or cancelled login');
      return;
    }
    
    if (!mounted) {
      debugPrint('❌ Widget not mounted');
      return;
    }
    
    debugPrint('⏸️ Pausing video...');
    _videoManager.pauseAll();
    
    debugPrint('🧭 Navigating to ProjectDetailsScreen...');
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProjectDetailsScreen(
            projectId: projectId,
            initialTabIndex: 0, // Project tab
          ),
        ),
      );
      debugPrint('✅ Navigation completed');
    }
  }

  Future<void> _openEpisodes(ClipModel clip) async {
    final ok = await AuthHelper.requireAuth(context);
    if (!ok || !mounted) return;
    _videoManager.pauseAll();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProjectDetailsScreen(
          projectId: clip.projectId,
          initialTabIndex: 1, // Episodes tab
        ),
      ),
    );
  }

  Future<void> _shareClip(ClipModel clip) async {
    final ok = await AuthHelper.requireAuth(context);
    if (!ok || !mounted) return;
    try {
      await Share.share(
        clip.videoUrl,
        subject: clip.title,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _clipService?.flush();
    _videoManager.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_clips.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'No reels available',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: RefreshIndicator(
        color: brandRed,
        backgroundColor: Colors.black,
        onRefresh: _onRefresh,
        child: PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          physics: const PageScrollPhysics(),
          onPageChanged: _onPageChanged,
          itemCount: _clips.length,
          itemBuilder: (context, index) {
            final clip = _clips[index];
            return _ReelPage(
              key: ValueKey(clip.id), // CRITICAL: Prevents unmounting and state loss during swipe
              clip: clip,
              index: index,
              isActive: index == _currentIndex,
              videoManager: _videoManager,
              isSaved: _savedReelIds[clip.id] ?? false,
              onTap: () => _onVideoTap(index),
              onSaveTap: () => _toggleSave(index),
              onProjectTap: () {
                debugPrint('🔘 Project icon tapped for clip at index $index');
                debugPrint('📱 clip.projectId: "${clip.projectId}"');
                _openProject(clip.projectId);
              },
              onEpisodesTap: () => _openEpisodes(clip),
              onShareTap: () => _shareClip(clip),
              onBack: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const MainScreen()),
                  (_) => false,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ReelPage extends StatefulWidget {
  final ClipModel clip;
  final int index;
  final bool isActive;
  final VideoControllerManager videoManager;
  final bool isSaved;
  final VoidCallback onTap;
  final VoidCallback onSaveTap;
  final VoidCallback onProjectTap;
  final VoidCallback onEpisodesTap;
  final VoidCallback onShareTap;
  final VoidCallback onBack;

  const _ReelPage({
    super.key,
    required this.clip,
    required this.index,
    required this.isActive,
    required this.videoManager,
    required this.isSaved,
    required this.onTap,
    required this.onSaveTap,
    required this.onProjectTap,
    required this.onEpisodesTap,
    required this.onShareTap,
    required this.onBack,
  });

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> with AutomaticKeepAliveClientMixin {
  static const Color brandRed = Color(0xFFE50914);

  @override
  bool get wantKeepAlive => true; // Prevents unmounting & render object swap during swipe

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final canPop = Navigator.canPop(context);
    final safeAreaTop = MediaQuery.of(context).padding.top;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;

    return AnimatedBuilder(
      animation: widget.videoManager,
      builder: (context, _) {
        final controller = widget.videoManager.controllerAt(widget.index);
        final failed = widget.videoManager.isFailed(widget.index);
        final isVideoReady = !failed && controller != null && controller.value.isInitialized;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Solid black background container (no thumbnail underlayer)
            Container(color: Colors.black),

            // Video Player Layer / Error Placeholder
            if (failed)
              _buildErrorPlaceholder()
            else if (isVideoReady)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: AspectRatio(
                        aspectRatio: controller.value.aspectRatio > 0
                            ? controller.value.aspectRatio
                            : (9 / 16),
                        child: VideoPlayer(controller),
                      ),
                    ),
                    // Centered Play icon overlay when paused
                    ListenableBuilder(
                      listenable: controller,
                      builder: (_, __) {
                        if (controller.value.isPlaying || controller.value.isBuffering || !widget.isActive) {
                          return const SizedBox.shrink();
                        }
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            color: Colors.black45,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 40,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

            // Loading / Buffering indicators
            if (!failed && !isVideoReady)
              _buildLoadingOverlay()
            else if (!failed && controller != null && controller.value.isInitialized)
              ListenableBuilder(
                listenable: controller,
                builder: (_, __) {
                  if (controller.value.isBuffering) {
                    return _buildBufferingIndicator();
                  }
                  return const SizedBox.shrink();
                },
              ),

            // Black gradient overlay bottom only
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  height: 250,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.black.withOpacity(0.3),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Back button
            if (canPop)
              Positioned(
                top: safeAreaTop + 8,
                left: 8,
                child: GestureDetector(
                  onTap: widget.onBack,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    child: const Icon(
                      Icons.arrow_back_ios,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),

            // Right side action buttons with labels
            Positioned(
              right: 16,
              bottom: safeAreaBottom + 90,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LabeledActionButton(
                    iconPath: 'assets/icons_clips/Frame 2609297 (2).png',
                    label: 'Wha App',
                    onTap: widget.onProjectTap,
                  ),
                  const SizedBox(height: 20),
                  _LabeledActionButton(
                    iconPath: widget.isSaved
                        ? 'assets/icons_clips/save 5.png'
                        : 'assets/icons_clips/Frame 2609297.png',
                    label: 'Save',
                    onTap: widget.onSaveTap,
                    isSaved: widget.isSaved,
                  ),
                  const SizedBox(height: 20),
                  _LabeledActionButton(
                    iconPath: 'assets/icons_clips/Frame 2609297 (1).png',
                    label: 'Share',
                    onTap: widget.onShareTap,
                  ),
                ],
              ),
            ),

            // Bottom left: Avatar, username, caption, and Watch Orientation button
            Positioned(
              left: 16,
              bottom: safeAreaBottom + 90,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ProjectInfoBar(
                    clip: widget.clip,
                    isActive: widget.isActive,
                    onProjectTap: widget.onProjectTap,
                    onEpisodesTap: widget.onEpisodesTap,
                  ),
                  const SizedBox(height: 6),
                  // Text caption under username
                  if (widget.clip.title.isNotEmpty || widget.clip.description.isNotEmpty)
                    SizedBox(
                      width: MediaQuery.of(context).size.width * 0.65,
                      child: Text(
                        widget.clip.title.isNotEmpty ? widget.clip.title : widget.clip.description,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }


  Widget _buildLoadingOverlay() {
    return const Center(
      child: SizedBox(
        width: 40,
        height: 40,
        child: CircularProgressIndicator(
          color: brandRed,
          strokeWidth: 2.5,
        ),
      ),
    );
  }

  Widget _buildBufferingIndicator() {
    return const Center(
      child: SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          color: Colors.white70,
          strokeWidth: 2,
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.white54, size: 48),
            SizedBox(height: 12),
            Text(
              'Video unavailable',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledActionButton extends StatelessWidget {
  final String iconPath;
  final String label;
  final VoidCallback onTap;
  final bool? isSaved;

  const _LabeledActionButton({
    required this.iconPath,
    required this.label,
    required this.onTap,
    this.isSaved,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        debugPrint('🔘 _LabeledActionButton tapped: $label');
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Image.asset(
                iconPath,
                width: label == 'Save' && isSaved == true ? 24 : 30,
                height: label == 'Save' && isSaved == true ? 24 : 30,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    label == 'Save'
                        ? (isSaved == true ? Icons.bookmark : Icons.bookmark_border)
                        : Icons.error_outline,
                    color: Colors.white,
                    size: label == 'Save' && isSaved == true ? 24 : 30,
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dynamic Project Info Bar that displays the Project Name and Project Logo
class _ProjectInfoBar extends StatefulWidget {
  final ClipModel clip;
  final bool isActive;
  final VoidCallback onProjectTap;
  final VoidCallback onEpisodesTap;

  const _ProjectInfoBar({
    required this.clip,
    required this.isActive,
    required this.onProjectTap,
    required this.onEpisodesTap,
  });

  @override
  State<_ProjectInfoBar> createState() => _ProjectInfoBarState();
}

class _ProjectInfoBarState extends State<_ProjectInfoBar> {
  final InMemoryCacheService _cache = InMemoryCacheService();
  final ProjectsService _projectsService = ProjectsService();
  ProjectModel? _resolvedProject;

  @override
  void initState() {
    super.initState();
    _checkOrResolveProject();
  }

  @override
  void didUpdateWidget(covariant _ProjectInfoBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip.id != widget.clip.id ||
        oldWidget.clip.projectId != widget.clip.projectId ||
        oldWidget.isActive != widget.isActive) {
      _checkOrResolveProject();
    }
  }

  void _checkOrResolveProject() {
    // 1. Direct Binding: If clip already contains both project name and logo (from populated reel payload),
    // we make 0 network requests!
    if (widget.clip.projectName.isNotEmpty && widget.clip.projectLogo.isNotEmpty) {
      return;
    }

    final pid = widget.clip.projectId;
    if (pid.isEmpty) return;

    // 2. Check in-memory RAM cache first
    final cached = _cache.get<ProjectModel>('project:$pid');
    if (cached != null) {
      _resolvedProject = cached;
      return;
    }

    // 3. Strict Deferral: Do NOT fetch from network for adjacent/prebuffered reels
    if (!widget.isActive) {
      return;
    }

    // 4. Fetch with InMemoryCacheService de-duplication & TTL (Fallback only)
    _projectsService.getProjectById(pid).then((p) {
      if (mounted) {
        setState(() {
          _resolvedProject = p;
        });
      }
    }).catchError((e) {
      debugPrint('⚠️ _ProjectInfoBar: Failed to load project $pid: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    // 1. Resolve Project Name:
    // Priority: clip.projectName -> _resolvedProject.title -> clip.developerName (if not 'User')
    String name = widget.clip.projectName.isNotEmpty
        ? widget.clip.projectName
        : (_resolvedProject != null && _resolvedProject!.title.isNotEmpty
            ? _resolvedProject!.title
            : (widget.clip.developerName.isNotEmpty && widget.clip.developerName != 'User'
                ? widget.clip.developerName
                : ''));

    // 2. Resolve Project Logo:
    // Priority: clip.projectLogo -> _resolvedProject.logo -> _resolvedProject.projectThumbnailUrl -> clip.developerLogo
    String logo = widget.clip.projectLogo.isNotEmpty
        ? widget.clip.projectLogo
        : (_resolvedProject?.logo != null && _resolvedProject!.logo!.isNotEmpty
            ? _resolvedProject!.logo!
            : (_resolvedProject != null && _resolvedProject!.projectThumbnailUrl.isNotEmpty
                ? _resolvedProject!.projectThumbnailUrl
                : widget.clip.developerLogo));

    return Row(
      children: [
        // Small circular avatar - uses project logo with fallback
        GestureDetector(
          onTap: widget.onProjectTap,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: ClipOval(
              child: logo.isNotEmpty
                  ? Image.network(
                      logo,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(
                            Icons.apartment_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        );
                      },
                    )
                  : const Center(
                      child: Icon(
                        Icons.apartment_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
            ),
          ),
        ),
        if (name.isNotEmpty) ...[
          const SizedBox(width: 8),
          // Project name beside logo (clickable)
          Flexible(
            child: GestureDetector(
              onTap: widget.onProjectTap,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.38,
                ),
                child: Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(width: 6),
        // Watch Orientation button
        GestureDetector(
          onTap: widget.onEpisodesTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFE50914),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 12,
                ),
                SizedBox(width: 3),
                Text(
                  'Watch Orientation',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}


