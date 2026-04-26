import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import '../main.dart';

class GlobalMiniPlayer extends StatefulWidget {
  final TabController? tabController;

  const GlobalMiniPlayer({super.key, this.tabController});

  @override
  State<GlobalMiniPlayer> createState() => _GlobalMiniPlayerState();
}

class _GlobalMiniPlayerState extends State<GlobalMiniPlayer> {
  MediaItem? _currentMediaItem;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();

    widget.tabController?.addListener(_onTabChanged);

    // Listen to media item
    audioHandler.mediaItem.listen((item) {
      if (mounted) setState(() => _currentMediaItem = item);
    });

    // Listen to playback state
    audioHandler.playbackState.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
      }
    });

    // Listen to position and duration directly from player
    audioHandler.player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    audioHandler.player.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });
    
    // Listen to queue state changes (shuffle/loop)
    audioHandler.queueStateStream.listen((_) {
      if (mounted) setState(() {}); // Trigger rebuild to update toggle buttons
    });
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.tabController?.removeListener(_onTabChanged);
    super.dispose();
  }

  String _formatDuration(Duration d) {
    String pad(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '${pad(h)}:${pad(m)}:${pad(s)}' : '${pad(m)}:${pad(s)}';
  }

  Color _colorFromString(String s) {
    final hue = (s.codeUnits.fold(0, (a, b) => a + b) % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.5, 0.4).toColor();
  }

  Widget _colorAvatar(Color color, String letter, double w, double h) {
    return Container(
      width: w,
      height: h,
      color: color,
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: Colors.white.withAlpha(80),
            fontSize: h * 0.7,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentMediaItem == null) return const SizedBox.shrink();

    final bool isCompact = widget.tabController != null && 
        (widget.tabController!.index == 0 || widget.tabController!.index == 1);

    final maxSec = _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1.0;
    final posSec = _position.inSeconds.toDouble().clamp(0.0, maxSec);

    final title = _currentMediaItem!.title;
    final letter = title.isNotEmpty ? title[0].toUpperCase() : '?';
    final avatarColor = _colorFromString(title);

    final isShuffle = audioHandler.isShuffle;
    final isLoop = audioHandler.isLoop;

    final localFilePath = _currentMediaItem!.extras?['localFilePath'] as String?;
    final imagePath = localFilePath ?? _currentMediaItem!.id;
    final thumbFile = File('$imagePath.jpg');
    final networkUrl = _currentMediaItem!.artUri?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(50),
            blurRadius: 15,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Track info row ──
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: Image.file(
                      thumbFile,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => networkUrl.isNotEmpty
                          ? Image.network(
                              networkUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _colorAvatar(avatarColor, letter, 60, 60),
                            )
                          : _colorAvatar(avatarColor, letter, 60, 60),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isPlaying ? 'Playing Audio' : 'Paused',
                        style: TextStyle(
                          color: _isPlaying ? Theme.of(context).colorScheme.primary : (Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCompact)
                  IconButton(
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Theme.of(context).colorScheme.primary,
                      size: 32,
                    ),
                    onPressed: () {
                      if (_isPlaying) {
                        audioHandler.pause();
                      } else {
                        audioHandler.play();
                      }
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    try {
                      await audioHandler.stop();
                      if (mounted) setState(() => _currentMediaItem = null);
                    } catch (_) {}
                  },
                ),
              ],
            ),

            if (!isCompact) ...[
              const SizedBox(height: 8),

              // ── Controls row ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Shuffle
                  IconButton(
                    icon: Icon(
                      Icons.shuffle,
                      color: isShuffle ? Theme.of(context).colorScheme.primary : (Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey),
                    ),
                    onPressed: () => audioHandler.toggleShuffle(),
                  ),
                  // Previous
                  IconButton(
                    icon: const Icon(Icons.skip_previous, size: 32),
                    onPressed: () => audioHandler.skipToPrevious(),
                  ),
                  // Play / Pause
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Theme.of(context).colorScheme.onPrimary,
                        size: 36,
                      ),
                      onPressed: () {
                        if (_isPlaying) {
                          audioHandler.pause();
                        } else {
                          audioHandler.play();
                        }
                      },
                    ),
                  ),
                  // Next
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 32),
                    onPressed: () => audioHandler.skipToNext(),
                  ),
                  // Loop
                  IconButton(
                    icon: Icon(
                      isLoop ? Icons.repeat_one : Icons.repeat,
                      color: isLoop ? Theme.of(context).colorScheme.primary : (Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey),
                    ),
                    onPressed: () => audioHandler.toggleLoop(),
                  ),
                ],
              ),

              // ── Seek bar ──
              Row(
                children: [
                  Text(_formatDuration(_position), style: const TextStyle(fontSize: 11)),
                  Expanded(
                    child: Slider(
                      value: posSec,
                      min: 0,
                      max: maxSec,
                      activeColor: Theme.of(context).colorScheme.primary,
                      inactiveColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                      onChanged: (v) => audioHandler.seek(Duration(seconds: v.toInt())),
                    ),
                  ),
                  Text(_formatDuration(_duration), style: const TextStyle(fontSize: 11)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
