import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:simple_pip_mode/simple_pip.dart';
import 'package:simple_pip_mode/pip_widget.dart';

class VideoPlayerScreen extends StatefulWidget {
  final File videoFile;
  final VideoPlayerController? controller;
  final bool isFullscreen;

  const VideoPlayerScreen({
    super.key,
    required this.videoFile,
    this.controller,
    this.isFullscreen = false,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _hasError = false;
  bool _showControls = true;
  Timer? _hideTimer;
  bool _isPlaying = false;
  double _currentPosition = 0.0;
  bool _isLocked = false;
  String _doubleTapDirection = 'none';
  Timer? _doubleTapTimer;

  @override
  void initState() {
    super.initState();
    // Allow auto-rotation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (widget.controller == null) {
      _initializePlayer();
    } else {
      _controller = widget.controller!;
      _setupListeners();
      _startHideTimer();
    }
  }

  Future<void> _initializePlayer() async {
    try {
      _controller = VideoPlayerController.file(widget.videoFile);
      await _controller.initialize();
      await _controller.play();
      _setupListeners();
      _startHideTimer();
      setState(() {});
    } catch (e) {
      setState(() {
        _hasError = true;
      });
    }
  }

  void _setupListeners() {
    _controller.addListener(() {
      if (!mounted) return;
      setState(() {
        _isPlaying = _controller.value.isPlaying;
        _currentPosition = _controller.value.position.inMilliseconds.toDouble();
      });
    });
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    if (_isLocked) return;
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _togglePlayPause() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _showControls = true;
        _hideTimer?.cancel();
      } else {
        _controller.play();
        _startHideTimer();
      }
    });
  }

  void _toggleFullscreen() {
    if (widget.isFullscreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      Navigator.pop(context);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(
            videoFile: widget.videoFile,
            controller: _controller,
            isFullscreen: true,
          ),
        ),
      ).then((_) {
        // Reset orientation when returning
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      });
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _handleDoubleTap(TapDownDetails details) {
    if (!_controller.value.isInitialized || _isLocked) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final tapPosition = details.localPosition.dx;
    
    if (tapPosition < screenWidth / 2) {
      // Seek back 5 seconds
      final newPos = _controller.value.position - const Duration(seconds: 5);
      _controller.seekTo(newPos < Duration.zero ? Duration.zero : newPos);
      setState(() => _doubleTapDirection = 'left');
    } else {
      // Seek forward 5 seconds
      final maxPos = _controller.value.duration;
      final newPos = _controller.value.position + const Duration(seconds: 5);
      _controller.seekTo(newPos > maxPos ? maxPos : newPos);
      setState(() => _doubleTapDirection = 'right');
    }

    _doubleTapTimer?.cancel();
    _doubleTapTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _doubleTapDirection = 'none');
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _doubleTapTimer?.cancel();
    
    // Always reset orientations when leaving the player screen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    if (!widget.isFullscreen) {
      _controller.dispose();
    }
    super.dispose();
  }

  bool _isZoomedToFill = false;

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount != 2) return;
    if (details.scale > 1.1 && !_isZoomedToFill) {
      setState(() => _isZoomedToFill = true);
    } else if (details.scale < 0.9 && _isZoomedToFill) {
      setState(() => _isZoomedToFill = false);
    }
  }

  Widget _buildVideo() {
    if (_hasError) {
      return const Center(
        child: Text('Error loading video', style: TextStyle(color: Colors.white)),
      );
    }

    if (!_controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.red));
    }

    return SizedBox.expand(
      child: GestureDetector(
        onScaleUpdate: _handleScaleUpdate,
        child: FittedBox(
          fit: _isZoomedToFill ? BoxFit.cover : BoxFit.contain,
          child: SizedBox(
            width: _controller.value.size.width,
            height: _controller.value.size.height,
            child: VideoPlayer(_controller),
          ),
        ),
      ),
    );
  }

  Widget _buildRippleOverlay() {
    if (_doubleTapDirection == 'none') return const SizedBox.shrink();

    final isLeft = _doubleTapDirection == 'left';
    return Positioned.fill(
      child: IgnorePointer(
        child: Row(
          children: [
            Expanded(
              child: isLeft
                  ? Container(
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.horizontal(right: Radius.circular(100)),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fast_rewind, color: Colors.white, size: 40),
                          Text('-5 Seconds', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    )
                  : const SizedBox(),
            ),
            Expanded(
              child: !isLeft
                  ? Container(
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.horizontal(left: Radius.circular(100)),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fast_forward, color: Colors.white, size: 40),
                          Text('+5 Seconds', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    )
                  : const SizedBox(),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Settings', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.speed, color: Colors.white),
                    title: const Text('Playback Speed', style: TextStyle(color: Colors.white)),
                    trailing: DropdownButton<double>(
                      value: _controller.value.playbackSpeed,
                      dropdownColor: Colors.grey[800],
                      style: const TextStyle(color: Colors.white),
                      underline: const SizedBox(),
                      items: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
                        return DropdownMenuItem(value: speed, child: Text('${speed}x'));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          _controller.setPlaybackSpeed(val);
                          setSheetState(() {});
                          setState(() {});
                        }
                      },
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.loop, color: Colors.white),
                    title: const Text('Loop Video', style: TextStyle(color: Colors.white)),
                    trailing: Switch(
                      value: _controller.value.isLooping,
                      activeThumbColor: Colors.red,
                      onChanged: (val) {
                        _controller.setLooping(val);
                        setSheetState(() {});
                      },
                    ),
                  ),
                ],
              ),
            );
          }
        );
      }
    );
  }

  Widget _buildControls() {
    if (!_controller.value.isInitialized) return const SizedBox.shrink();

    if (_isLocked) {
      return Positioned(
        bottom: 30,
        left: 0,
        right: 0,
        child: Center(
          child: IconButton(
            icon: const Icon(Icons.lock, color: Colors.white54, size: 32),
            onPressed: () {
              setState(() {
                _isLocked = false;
                _showControls = true;
                _startHideTimer();
              });
            },
          ),
        ),
      );
    }

    final maxPos = _controller.value.duration.inMilliseconds.toDouble();
    final clampedPos = _currentPosition.clamp(0.0, maxPos);

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_showControls,
        child: AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Stack(
          children: [
            IgnorePointer(
              child: Container(color: Colors.black45),
            ),
            SafeArea(
              child: Stack(
                children: [
                  // Top Bar
                  if (!widget.isFullscreen)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                          Expanded(
                            child: Text(
                              widget.videoFile.path.split(Platform.pathSeparator).last,
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.picture_in_picture_alt, color: Colors.white),
                            onPressed: () {
                              SimplePip().enterPipMode(
                                aspectRatio: (16, 9),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.settings, color: Colors.white),
                            onPressed: _showSettingsSheet,
                          ),
                          IconButton(
                            icon: const Icon(Icons.lock_open, color: Colors.white),
                            onPressed: () {
                              setState(() {
                                _isLocked = true;
                                _showControls = false;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  // Play/Pause Button
                  Center(
                    child: IconButton(
                      iconSize: 64,
                      icon: Icon(
                        _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                        color: Colors.white,
                      ),
                      onPressed: _showControls ? _togglePlayPause : null,
                    ),
                  ),
                  // Bottom Bar
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        children: [
                          Text(
                            _formatDuration(Duration(milliseconds: clampedPos.toInt())),
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                activeTrackColor: Colors.red,
                                inactiveTrackColor: Colors.white30,
                                thumbColor: Colors.red,
                                overlayColor: Colors.red.withValues(alpha: 0.2),
                              ),
                              child: Slider(
                                value: clampedPos,
                                max: maxPos == 0 ? 1 : maxPos,
                                onChanged: _showControls
                                    ? (val) {
                                        setState(() {
                                          _currentPosition = val;
                                        });
                                        _controller.seekTo(Duration(milliseconds: val.toInt()));
                                        _startHideTimer();
                                      }
                                    : null,
                              ),
                            ),
                          ),
                          Text(
                            _formatDuration(_controller.value.duration),
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          IconButton(
                            icon: Icon(
                              widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                              color: Colors.white,
                            ),
                            onPressed: _showControls ? _toggleFullscreen : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final playerUI = Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _toggleControls,
        onDoubleTapDown: _handleDoubleTap,
        onDoubleTap: () {},
        child: Stack(
          children: [
            _buildVideo(),
            _buildRippleOverlay(),
            _buildControls(),
          ],
        ),
      ),
    );

    if (widget.isFullscreen) {
      return playerUI;
    }

    return PipWidget(
      pipBuilder: (context) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: _buildVideo(),
        );
      },
      builder: (context) {
        return playerUI;
      },
    );
  }
}
