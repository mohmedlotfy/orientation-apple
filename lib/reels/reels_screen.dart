import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../models/clip_model.dart';
import '../services/clip_service.dart';
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

  int _currentIndex = 0;
  final Map<String, bool> _savedReelIds = {};

  static const Color brandRed = Color(0xFFE50914);

  @override
  void initState() {
    super.initState();
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
    _onPageChanged(widget.initialIndex);
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
  void didPushNext() {
    _videoManager.setVisible(false);
  }

  @override
  void didPopNext() {
    _videoManager.setVisible(true);
  }

  void setVisible(bool visible) {
    _videoManager.setVisible(visible);
    if (visible && mounted && _currentClip != null) {
      final c = _currentClip!;
      if (c.videoUrl.isNotEmpty) {
        _videoManager.play(_currentIndex, c.videoUrl, isAsset: c.isAsset);
      }
      setState(() {});
    }
  }

  ClipModel? get _currentClip {
    if (_currentIndex < 0 || _currentIndex >= widget.clips.length) {
      return null;
    }
    return widget.clips[_currentIndex];
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
    if (index < 0 || index >= widget.clips.length) return;

    _videoManager.pauseAll();
    _videoManager.disposeFar(index, widget.clips.length);

    final clip = widget.clips[index];
    if (clip.videoUrl.isNotEmpty) {
      _videoManager.play(index, clip.videoUrl, isAsset: clip.isAsset).then((_) {
        if (mounted && _currentIndex == index) {
          _videoManager.setMuted(index, false);
        }
        if (mounted) setState(() {});
      });
    }

    if (index + 1 < widget.clips.length) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && _currentIndex == index) {
          final next = widget.clips[index + 1];
          if (next.videoUrl.isNotEmpty) {
            _videoManager.preload(index + 1, next.videoUrl,
                isAsset: next.isAsset);
          }
        }
      });
    }
    if (index - 1 >= 0) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _currentIndex == index) {
          final prev = widget.clips[index - 1];
          if (prev.videoUrl.isNotEmpty) {
            _videoManager.preload(index - 1, prev.videoUrl,
                isAsset: prev.isAsset);
          }
        }
      });
    }

    setState(() => _currentIndex = index);
  }

  void _onVideoTap() async {
    final c = _videoManager.controllerAt(_currentIndex);
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      await c.play();
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _videoManager.pauseAll();
    } else if (state == AppLifecycleState.resumed) {
      final c = _videoManager.controllerAt(_currentIndex);
      if (c != null &&
          c.value.isInitialized &&
          !c.value.isPlaying &&
          _videoManager.controllerAt(_currentIndex) != null) {
        c.play();
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _toggleSave(int index) async {
    debugPrint('💾 _toggleSave called for index: $index');
    if (!mounted || _clipService == null) {
      debugPrint('❌ Widget not mounted or clipService is null');
      return;
    }
    if (index < 0 || index >= widget.clips.length) {
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

    final clip = widget.clips[index];
    final saved = _savedReelIds[clip.id] ?? false;
    debugPrint('💾 Current saved status: $saved for clip: ${clip.id}');

    try {
      if (saved) {
        debugPrint('🗑️ Unsaving reel...');
        await _clipService!.unsaveReel(clip.id);
        _savedReelIds[clip.id] = false;
        debugPrint('✅ Reel unsaved');
      } else {
        debugPrint('💾 Saving reel...');
        await _clipService!.saveReel(clip.id);
        _savedReelIds[clip.id] = true;
        debugPrint('✅ Reel saved');
      }
      if (mounted) {
        setState(() {});
        debugPrint('✅ State updated');
      }
    } catch (e) {
      debugPrint('❌ Error in _toggleSave: $e');
    }
  }

  Future<void> _openProject(String? projectId) async {
    debugPrint('🚀 _openProject called with projectId: "$projectId"');
    
    if (projectId == null || projectId.isEmpty) {
      debugPrint('❌ projectId is null or empty');
      // Show a message to user if projectId is missing
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
    
    // Check authentication first
    debugPrint('🔐 Checking authentication...');
    final ok = await AuthHelper.requireAuth(context);
    debugPrint('🔐 Auth result: $ok');
    
    if (!ok) {
      debugPrint('❌ User is not authenticated or cancelled login');
      // User is not authenticated and didn't want to login
      return;
    }
    
    if (!mounted) {
      debugPrint('❌ Widget not mounted');
      return;
    }
    
    debugPrint('⏸️ Pausing video...');
    // Pause video before navigating
    _videoManager.pauseAll();
    
    debugPrint('🧭 Navigating to ProjectDetailsScreen...');
    // Navigate to project details
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
    // Pause video before navigating to prevent audio from continuing
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
    _videoManager.disposeAll();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.clips.isEmpty) {
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
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        onPageChanged: _onPageChanged,
        itemCount: widget.clips.length,
        itemBuilder: (context, index) {
          return _ReelPage(
            clip: widget.clips[index],
            index: index,
            videoManager: _videoManager,
            isSaved: _savedReelIds[widget.clips[index].id] ?? false,
            onTap: _onVideoTap,
            onSaveTap: () => _toggleSave(index),
            onProjectTap: () {
              debugPrint('🔘 Project icon tapped for clip at index $index');
              debugPrint('📱 clip.projectId: "${widget.clips[index].projectId}"');
              _openProject(widget.clips[index].projectId);
            },
            onEpisodesTap: () => _openEpisodes(widget.clips[index]),
            onShareTap: () => _shareClip(widget.clips[index]),
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
    );
  }
}

class _ReelPage extends StatelessWidget {
  final ClipModel clip;
  final int index;
  final VideoControllerManager videoManager;
  final bool isSaved;
  final VoidCallback onTap;
  final VoidCallback onSaveTap;
  final VoidCallback onProjectTap;
  final VoidCallback onEpisodesTap;
  final VoidCallback onShareTap;
  final VoidCallback onBack;

  const _ReelPage({
    required this.clip,
    required this.index,
    required this.videoManager,
    required this.isSaved,
    required this.onTap,
    required this.onSaveTap,
    required this.onProjectTap,
    required this.onEpisodesTap,
    required this.onShareTap,
    required this.onBack,
  });

  static const Color brandRed = Color(0xFFE50914);

  @override
  Widget build(BuildContext context) {
    final controller = videoManager.controllerAt(index);
    final failed = videoManager.isFailed(index);
    final canPop = Navigator.canPop(context);
    final safeAreaTop = MediaQuery.of(context).padding.top;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Fullscreen video background
        if (failed)
          _buildErrorPlaceholder()
        else if (controller == null || !controller.value.isInitialized)
          _buildLoading()
        else
          GestureDetector(
            onTap: onTap,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                ),
                ListenableBuilder(
                  listenable: controller,
                  builder: (_, __) {
                    if (controller.value.isPlaying) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
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

        // Black gradient overlay bottom only
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
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

        // Back button
        if (canPop)
          Positioned(
            top: safeAreaTop + 8,
            left: 8,
            child: GestureDetector(
              onTap: onBack,
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
                onTap: onProjectTap,
              ),
              const SizedBox(height: 20),
              _LabeledActionButton(
                iconPath: isSaved 
                    ? 'assets/icons_clips/save 5.png' 
                    : 'assets/icons_clips/Frame 2609297.png',
                label: 'Save',
                onTap: onSaveTap,
                isSaved: isSaved,
              ),
              const SizedBox(height: 20),
              _LabeledActionButton(
                iconPath: 'assets/icons_clips/Frame 2609297 (1).png',
                label: 'Share',
                onTap: onShareTap,
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
              Row(
                children: [
                  // Small circular avatar - smaller (clickable)
                  GestureDetector(
                    onTap: onProjectTap,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A), // Dark grey background
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3), // Light grey border
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.person_outline,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Username beside avatar - limited width to prevent pushing button away (clickable)
                  Flexible(
                    child: GestureDetector(
                      onTap: onProjectTap,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.35,
                        ),
                        child: Text(
                          clip.developerName.isNotEmpty
                              ? clip.developerName
                              : (clip.title.isNotEmpty ? clip.title : 'User'),
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
                  const SizedBox(width: 4),
                  // Watch Orientation button - smaller, next to username
                  GestureDetector(
                    onTap: onEpisodesTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: brandRed,
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
              ),
              const SizedBox(height: 6),
              // Text caption under username
              if (clip.title.isNotEmpty || clip.description.isNotEmpty)
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.65,
                  child: Text(
                    clip.title.isNotEmpty ? clip.title : clip.description,
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
  }

  Widget _buildLoading() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            color: brandRed,
            strokeWidth: 3,
          ),
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
        debugPrint('🔘 onTap is null: ${onTap == null}');
        if (onTap != null) {
          onTap();
        } else {
          debugPrint('❌ onTap is null!');
        }
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
