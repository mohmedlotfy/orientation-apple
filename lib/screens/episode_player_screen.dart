import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'dart:async';
import '../models/episode_model.dart';
import '../services/api/project_api.dart';

class EpisodePlayerScreen extends StatefulWidget {
  final EpisodeModel episode;
  final String projectTitle;

  const EpisodePlayerScreen({
    super.key,
    required this.episode,
    this.projectTitle = '',
  });

  @override
  State<EpisodePlayerScreen> createState() => _EpisodePlayerScreenState();
}

class _EpisodePlayerScreenState extends State<EpisodePlayerScreen> with WidgetsBindingObserver {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _errorMessage;
  final ProjectApi _projectApi = ProjectApi();
  String? _projectId;
  bool _wasPlaying = false;
  Duration _lastPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Set landscape orientation for video
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    _initializeVideo();
  }

  bool _hasSyncedBackend = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive) {
      _videoController?.pause();
      _saveLocalProgressOnly();
    }
  }

  Future<void> _initializeVideo() async {
    try {
      _projectId = widget.episode.projectId;
      print('🎬 Initializing video for project: $_projectId, episode: ${widget.episode.id}');
      if (_projectId == null || _projectId!.isEmpty) {
        print('❌ ERROR: projectId is null or empty!');
        return;
      }
      
      // For demo, use a sample video URL
      // In production, use: widget.episode.videoUrl
      final videoUrl = widget.episode.videoUrl.isNotEmpty &&
              !widget.episode.videoUrl.contains('example.com')
          ? widget.episode.videoUrl
          : 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';

      _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl));

      await _videoController!.initialize();

      // Load saved progress from local cache (0 network calls)
      if (_projectId != null) {
        final savedProgress = await _projectApi.getWatchingProgress(
          _projectId!,
          widget.episode.id,
        );
        if (savedProgress > 0 && savedProgress < 1.0) {
          final position = Duration(
            milliseconds: (savedProgress * _videoController!.value.duration.inMilliseconds).toInt(),
          );
          await _videoController!.seekTo(position);
        }
      }

      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: true,
        looping: false,
        showControls: true,
        allowFullScreen: true,
        allowMuting: true,
        showOptions: false,
        placeholder: Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(
              color: Color(0xFFE50914),
            ),
          ),
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.white,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error loading video',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  errorMessage,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
        materialProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFFE50914),
          handleColor: const Color(0xFFE50914),
          backgroundColor: Colors.white24,
          bufferedColor: Colors.white38,
        ),
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // Listen to player events (local progress tracking only - 0 network calls)
        _videoController!.addListener(_onPlayerStateChanged);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Duration _lastDuration = Duration.zero;

  void _onPlayerStateChanged() {
    if (_videoController == null || !_videoController!.value.isInitialized) return;

    final isPlaying = _videoController!.value.isPlaying;
    final currentPos = _videoController!.value.position;
    final currentDur = _videoController!.value.duration;
    if (currentDur.inMilliseconds > 0) {
      _lastDuration = currentDur;
    }

    // 1. Save locally on Pause event (0 network calls)
    if (_wasPlaying && !isPlaying) {
      print('⏸️ Video paused — saving local watch progress');
      _saveLocalProgressOnly();
    }
    _wasPlaying = isPlaying;

    // 2. Save locally on Seek event (0 network calls)
    final diff = (currentPos - _lastPosition).inMilliseconds.abs();
    if (diff > 2000 && _lastPosition != Duration.zero) {
      print('⏩ Video seeked (${_lastPosition.inSeconds}s -> ${currentPos.inSeconds}s) — saving local watch progress');
      _saveLocalProgressOnly();
    }
    _lastPosition = currentPos;
  }

  /// Saves playback progress strictly to local storage / memory with 0 network calls.
  Future<void> _saveLocalProgressOnly() async {
    if (_projectId == null || _projectId!.isEmpty) return;

    final duration = (_videoController != null && _videoController!.value.isInitialized)
        ? _videoController!.value.duration
        : _lastDuration;
    final position = (_videoController != null && _videoController!.value.isInitialized)
        ? _videoController!.value.position
        : _lastPosition;
    if (duration.inMilliseconds <= 0) return;

    final progress = position.inMilliseconds / duration.inMilliseconds;

    print('💾 Saving local progress (0 network calls): projectId=$_projectId, episodeId=${widget.episode.id}, progress=${(progress * 100).toStringAsFixed(1)}%');
    await _projectApi.saveLocalWatchProgress(
      projectId: _projectId!,
      episodeId: widget.episode.id,
      currentTimeSeconds: position.inMilliseconds / 1000.0,
      durationSeconds: duration.inMilliseconds / 1000.0,
    );
  }

  /// Syncs watch progress to backend (POST /watch-history/progress) ONCE upon closing/disposing episode.
  Future<void> _syncBackendProgressOnce() async {
    if (_hasSyncedBackend) return;
    _hasSyncedBackend = true;

    if (_projectId == null || _projectId!.isEmpty) return;

    final duration = (_videoController != null && _videoController!.value.isInitialized)
        ? _videoController!.value.duration
        : _lastDuration;
    final position = (_videoController != null && _videoController!.value.isInitialized)
        ? _videoController!.value.position
        : _lastPosition;
    if (duration.inMilliseconds <= 0) return;

    print('📡 Syncing watch progress to backend ONCE on exit: projectId=$_projectId, episodeId=${widget.episode.id}');
    await _projectApi.syncEpisodeWatchProgress(
      projectId: _projectId!,
      episode: widget.episode,
      projectTitle: widget.projectTitle,
      currentTimeSeconds: position.inMilliseconds / 1000.0,
      durationSeconds: duration.inMilliseconds / 1000.0,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Remove listener
    _videoController?.removeListener(_onPlayerStateChanged);
    // Sync backend progress ONCE when exiting
    print('🔄 Disposing - syncing backend progress once...');
    _syncBackendProgressOnce();
    _videoController?.pause();
    // Reset to portrait
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Video Player
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFE50914),
                      ),
                    )
                  : _errorMessage != null
                      ? _buildErrorWidget()
                      : _chewieController != null
                          ? Chewie(controller: _chewieController!)
                          : _buildErrorWidget(),
            ),
            // Episode Info
            _buildEpisodeInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.white54,
            size: 60,
          ),
          const SizedBox(height: 16),
          Text(
            'Could not load video',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Unknown error',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true), // Return true to indicate progress was updated
            icon: const Icon(Icons.arrow_back),
            label: const Text('Go Back'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.pop(context, true), // Return true to indicate progress was updated
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.episode.title.isNotEmpty
                      ? widget.episode.title
                      : 'Episode ${widget.episode.episodeNumber}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (widget.projectTitle.isNotEmpty) ...[
                      Text(
                        widget.projectTitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        ' • ',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                        ),
                      ),
                    ],
                    Text(
                      widget.episode.duration,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

