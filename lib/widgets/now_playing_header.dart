import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../main.dart';
import '../models/download_item.dart';

class NowPlayingHeader extends StatelessWidget {
  final String playlistName;
  final List<DownloadItem> playlistItems;
  final VideoPlayerController? videoController;
  final DownloadItem? videoItem;
  final VoidCallback? onSkipNext;
  final VoidCallback? onSkipPrev;
  final VoidCallback? onFullscreen;

  const NowPlayingHeader({
    super.key, 
    required this.playlistName,
    required this.playlistItems,
    this.videoController,
    this.videoItem,
    this.onSkipNext,
    this.onSkipPrev,
    this.onFullscreen,
  });

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isVideoMode = videoController != null && videoItem != null;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: isVideoMode
          ? ValueListenableBuilder<VideoPlayerValue>(
              key: const ValueKey('video_player'),
              valueListenable: videoController!,
              builder: (context, value, _) {
                return _buildHeaderContent(
                  context: context,
                  currentItem: videoItem!,
                  isPlaying: value.isPlaying,
                  position: value.position,
                  duration: value.duration,
                  isLoop: value.isLooping,
                  isShuffle: false,
                  isVideo: true,
                  onPlayPause: () {
                    if (value.isPlaying) {
                      videoController!.pause();
                    } else {
                      videoController!.play();
                    }
                  },
                  onSkipNext: () {},
                  onSkipPrev: () {},
                  onToggleLoop: () {
                    videoController!.setLooping(!value.isLooping);
                  },
                  onToggleShuffle: () {},
                  onSeek: (val) {
                    videoController!.seekTo(Duration(milliseconds: val.toInt()));
                  },
                );
              },
            )
          : StreamBuilder<MediaItem?>(
              key: const ValueKey('audio_player'),
              stream: audioHandler.mediaItem,
              builder: (context, mediaSnapshot) {
                final mediaItem = mediaSnapshot.data;
                DownloadItem? currentItem;
                if (mediaItem != null) {
                  try {
                    currentItem = playlistItems.firstWhere((i) => i.id.toString() == mediaItem.id);
                  } catch (e) {
                    currentItem = playlistItems.isNotEmpty ? playlistItems.first : null;
                  }
                } else {
                  currentItem = playlistItems.isNotEmpty ? playlistItems.first : null;
                }

                if (currentItem == null) return const SizedBox.shrink();

                return StreamBuilder<Duration>(
                  stream: audioHandler.player.positionStream,
                  builder: (context, posSnapshot) {
                    final position = posSnapshot.data ?? Duration.zero;
                    final duration = audioHandler.player.duration ?? Duration.zero;

                    return StreamBuilder<bool>(
                      stream: audioHandler.player.playingStream,
                      builder: (context, playSnapshot) {
                        final isPlaying = playSnapshot.data ?? false;
                        final isShuffle = audioHandler.isShuffle;
                        final isLoop = audioHandler.isLoop;

                        return _buildHeaderContent(
                          context: context,
                          currentItem: currentItem!,
                          isPlaying: isPlaying,
                          position: position,
                          duration: duration,
                          isLoop: isLoop,
                          isShuffle: isShuffle,
                          isVideo: false,
                          onPlayPause: () {
                            if (isPlaying) {
                              audioHandler.pause();
                            } else {
                              if (audioHandler.mediaItem.value == null && playlistItems.isNotEmpty) {
                                audioHandler.playQueue(playlistItems.where((i) => i.type == 'audio').toList());
                              } else {
                                audioHandler.play();
                              }
                            }
                          },
                          onSkipNext: () => audioHandler.skipToNext(),
                          onSkipPrev: () => audioHandler.skipToPrevious(),
                          onToggleLoop: () => audioHandler.toggleLoop(),
                          onToggleShuffle: () => audioHandler.toggleShuffle(),
                          onSeek: (val) {
                            audioHandler.seek(Duration(milliseconds: val.toInt()));
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildHeaderContent({
    required BuildContext context,
    required DownloadItem currentItem,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
    required bool isLoop,
    required bool isShuffle,
    required bool isVideo,
    required VoidCallback onPlayPause,
    required VoidCallback onSkipNext,
    required VoidCallback onSkipPrev,
    required VoidCallback onToggleLoop,
    required VoidCallback onToggleShuffle,
    required void Function(double) onSeek,
  }) {
    final localThumbPath = '${currentItem.localFilePath}.jpg';
    
    double sliderValue = position.inMilliseconds.toDouble();
    double maxSliderValue = duration.inMilliseconds.toDouble();
    if (sliderValue > maxSliderValue) sliderValue = maxSliderValue;
    if (maxSliderValue == 0) maxSliderValue = 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.blueGrey.shade800,
            Theme.of(context).scaffoldBackgroundColor,
          ],
          stops: const [0.0, 1.0],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              Column(
                children: [
                  const Text(
                    'PLAYING FROM PLAYLIST',
                    style: TextStyle(fontSize: 10, color: Colors.white70, letterSpacing: 1.2),
                  ),
                  Text(
                    playlistName,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Artwork or Video
          GestureDetector(
            onTap: isVideo ? onFullscreen : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: (isVideo && videoController != null && videoController!.value.isInitialized) 
                    ? videoController!.value.aspectRatio 
                    : 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (isVideo && videoController != null && videoController!.value.isInitialized)
                      VideoPlayer(videoController!)
                    else
                      Image.file(
                        File(localThumbPath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Image.network(
                          currentItem.thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade800,
                            child: const Center(child: Icon(Icons.music_note, size: 64, color: Colors.white54)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentItem.title,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isVideo ? 'Downloaded Video' : 'Downloaded Audio',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Progress Bar
          Column(
            children: [
              SliderTheme(
                data: const SliderThemeData(
                  trackHeight: 4,
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  overlayColor: Color(0x1AFFFFFF),
                ),
                child: Slider(
                  value: sliderValue,
                  max: maxSliderValue,
                  onChanged: onSeek,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDuration(position), style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                    Text(_formatDuration(duration), style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                  ],
                ),
              ),
            ],
          ),
          
          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(Icons.shuffle, color: isShuffle ? Colors.green : Colors.white),
                onPressed: isVideo ? null : onToggleShuffle,
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous, color: Colors.white, size: 36),
                onPressed: onSkipPrev,
              ),
              Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: IconButton(
                  icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.black, size: 36),
                  onPressed: onPlayPause,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, color: Colors.white, size: 36),
                onPressed: onSkipNext,
              ),
              IconButton(
                icon: Icon(isLoop ? Icons.repeat_one : Icons.repeat, color: isLoop ? Colors.green : Colors.white),
                onPressed: onToggleLoop,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
