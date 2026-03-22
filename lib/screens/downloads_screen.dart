import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'video_player_screen.dart';
import 'qr_share_screen.dart';
import '../main.dart'; // To access isarService
import '../models/download_item.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  DownloadItem? _currentlyPlayingItem;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  bool _isShuffle = false;
  bool _isLoop = false;
  List<DownloadItem> _currentPlaylist = [];

  /// Cached stream so it doesn't reset on every rebuild
  late final Stream<List<DownloadItem>> _downloadsStream;

  @override
  void initState() {
    super.initState();
    _downloadsStream = isarService.listenToDownloads();

    // Listen to player state OUTSIDE setState to avoid calling async methods inside setState
    _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;

      final isPlaying = state.playing;
      final isCompleted = state.processingState == ProcessingState.completed;

      setState(() => _isPlaying = isPlaying);

      // When a track finishes naturally, advance to next (honours shuffle & loop)
      if (isCompleted) {
        _playNext();
      }
    });

    _audioPlayer.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });

    _audioPlayer.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
  }

  // ──────────────────────────── Playback ────────────────────────────

  Future<void> _playAudio(DownloadItem item) async {
    final file = File(item.localFilePath);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File not found! It may have been deleted.')),
        );
      }
      return;
    }

    if (_currentlyPlayingItem?.id == item.id) {
      // Toggle play/pause for the same track
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play();
      }
      return;
    }

    // Update UI immediately so it always reflects what's loading
    if (mounted) {
      setState(() {
        _currentlyPlayingItem = item;
        _position = Duration.zero;
        _duration = Duration.zero;
        _isPlaying = false;
      });
    }

    try {
      // Stop current playback cleanly before loading a new source
      await _audioPlayer.stop();

      // Apply loop mode before setting new source
      await _audioPlayer.setLoopMode(_isLoop ? LoopMode.one : LoopMode.off);

      // Load the new audio source
      await _audioPlayer.setAudioSource(
        AudioSource.uri(
          Uri.file(item.localFilePath),
        ),
      );

      // Start playback
      await _audioPlayer.play();
    } on PlayerInterruptedException {
      // This is expected when a new track is requested before the previous
      // one finishes loading — safe to ignore.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing audio: $e')),
        );
      }
    }
  }

  void _playNext() {
    if (_currentPlaylist.isEmpty || _currentlyPlayingItem == null) return;

    final currentIndex =
        _currentPlaylist.indexWhere((i) => i.id == _currentlyPlayingItem!.id);
    if (currentIndex == -1) return;

    int nextIndex;
    if (_isShuffle) {
      // Pick a random index different from current
      do {
        nextIndex = Random().nextInt(_currentPlaylist.length);
      } while (_currentPlaylist.length > 1 && nextIndex == currentIndex);
    } else {
      nextIndex = currentIndex + 1;
      if (nextIndex >= _currentPlaylist.length) {
        if (_isLoop) {
          nextIndex = 0; // wrap around
        } else {
          return; // end of list, stop
        }
      }
    }

    _playAudio(_currentPlaylist[nextIndex]);
  }

  void _playPrevious() {
    // If more than 3 s in, restart current track
    if (_position.inSeconds > 3) {
      _audioPlayer.seek(Duration.zero);
      return;
    }

    if (_currentPlaylist.isEmpty || _currentlyPlayingItem == null) return;

    final currentIndex =
        _currentPlaylist.indexWhere((i) => i.id == _currentlyPlayingItem!.id);
    if (currentIndex == -1) return;

    int prevIndex;
    if (_isShuffle) {
      do {
        prevIndex = Random().nextInt(_currentPlaylist.length);
      } while (_currentPlaylist.length > 1 && prevIndex == currentIndex);
    } else {
      prevIndex = currentIndex - 1;
      if (prevIndex < 0) {
        prevIndex = _isLoop ? _currentPlaylist.length - 1 : 0;
      }
    }

    _playAudio(_currentPlaylist[prevIndex]);
  }

  // ──────────────────────────── Helpers ────────────────────────────

  String _formatDuration(Duration d) {
    String pad(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '${pad(h)}:${pad(m)}:${pad(s)}' : '${pad(m)}:${pad(s)}';
  }

  /// Thumbnail-style avatar: coloured background + music/video icon + first letter
  Widget _buildThumbnail(DownloadItem item, {double width = 80, double height = 50}) {
    final isVideo = item.type == 'video';
    final letter = item.title.isNotEmpty ? item.title[0].toUpperCase() : '?';
    final color = _colorFromString(item.title);

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Try network image; fall back to coloured avatar
            Image.network(
              item.thumbnailUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _colorAvatar(color, letter, isVideo, width, height),
            ),
            if (isVideo)
              const Center(
                child: Icon(Icons.play_circle_outline, color: Colors.white, size: 24),
              ),
          ],
        ),
      ),
    );
  }

  Widget _colorAvatar(Color color, String letter, bool isVideo, double w, double h) {
    return Container(
      width: w,
      height: h,
      color: color,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            letter,
            style: TextStyle(
              color: Colors.white.withAlpha(80),
              fontSize: h * 0.7,
              fontWeight: FontWeight.bold,
            ),
          ),
          Icon(
            isVideo ? Icons.videocam : Icons.music_note,
            color: Colors.white,
            size: h * 0.45,
          ),
        ],
      ),
    );
  }

  /// Deterministic colour from a string (for consistent avatars)
  Color _colorFromString(String s) {
    final hue = (s.codeUnits.fold(0, (a, b) => a + b) % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.5, 0.4).toColor();
  }

  // ──────────────────────────── CRUD ────────────────────────────

  void _deleteItem(DownloadItem item) async {
    final file = File(item.localFilePath);
    if (await file.exists()) await file.delete();
    await isarService.deleteDownloadItem(item.id);

    if (_currentlyPlayingItem?.id == item.id) {
      await _audioPlayer.stop();
      if (mounted) setState(() => _currentlyPlayingItem = null);
    }
  }

  Future<void> _exportToDownloads(DownloadItem item) async {
    try {
      final sourceFile = File(item.localFilePath);
      if (!await sourceFile.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Source file not found!')),
          );
        }
        return;
      }

      final ext = sourceFile.path.split('.').last;
      final cleanTitle = item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

      if (!Platform.isAndroid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Exporting is only supported on Android.')),
          );
        }
        return;
      }

      final targetPath = '/storage/emulated/0/Download/$cleanTitle.$ext';
      await sourceFile.copy(targetPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Exported to Downloads folder!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ──────────────────────────── Build ────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: Column(
        children: [
          // ── Media list ──
          Expanded(
            child: StreamBuilder<List<DownloadItem>>(
              stream: _downloadsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final items = snapshot.data ?? [];

                if (items.isEmpty) {
                  return const Center(child: Text('No downloaded media found.'));
                }

                // Update audio-only playlist
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _currentPlaylist = items.where((i) => i.type == 'audio').toList();
                  }
                });

                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isPlayingThis = _currentlyPlayingItem?.id == item.id;
                    final isVideo = item.type == 'video';

                    return ListTile(
                      leading: _buildThumbnail(item),
                      title: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(item.duration),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.download, color: Colors.green),
                            onPressed: () => _exportToDownloads(item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.qr_code, color: Colors.blue),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => QrShareScreen(item: item),
                              ),
                            ),
                          ),
                          isVideo
                              ? IconButton(
                                  icon: const Icon(Icons.play_circle_fill, color: Colors.red),
                                  onPressed: () async {
                                    final file = File(item.localFilePath);
                                    if (await file.exists()) {
                                      if (context.mounted) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => VideoPlayerScreen(videoFile: file),
                                          ),
                                        );
                                      }
                                    } else {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('File not found!')),
                                        );
                                      }
                                    }
                                  },
                                )
                              : IconButton(
                                  icon: Icon(
                                    isPlayingThis && _isPlaying
                                        ? Icons.pause_circle_filled
                                        : Icons.play_circle_filled,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _playAudio(item),
                                ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.grey),
                            onPressed: () => _deleteItem(item),
                          ),
                        ],
                      ),
                      onTap: () async {
                        if (isVideo) {
                          final file = File(item.localFilePath);
                          if (await file.exists()) {
                            if (context.mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VideoPlayerScreen(videoFile: file),
                                ),
                              );
                            }
                          }
                        } else {
                          _playAudio(item);
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),

          // ── Mini player ──
          if (_currentlyPlayingItem != null) _buildMiniPlayer(),
        ],
      ),
    );
  }

  Widget _buildMiniPlayer() {
    // Safe slider values — position must never exceed duration
    final maxSec = _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1.0;
    final posSec = _position.inSeconds.toDouble().clamp(0.0, maxSec);

    final letter = _currentlyPlayingItem!.title.isNotEmpty
        ? _currentlyPlayingItem!.title[0].toUpperCase()
        : '?';
    final avatarColor = _colorFromString(_currentlyPlayingItem!.title);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(38), // ~0.15 opacity
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
                // Always-visible album art (works offline)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          _currentlyPlayingItem!.thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _colorAvatar(
                            avatarColor, letter, false, 60, 60,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentlyPlayingItem!.title,
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
                          color: _isPlaying ? Colors.red : Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    await _audioPlayer.stop();
                    if (mounted) setState(() => _currentlyPlayingItem = null);
                  },
                ),
              ],
            ),

            const SizedBox(height: 8),

            // ── Controls row ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Shuffle
                IconButton(
                  icon: Icon(
                    Icons.shuffle,
                    color: _isShuffle ? Colors.red : Colors.grey,
                  ),
                  onPressed: () => setState(() => _isShuffle = !_isShuffle),
                ),
                // Previous
                IconButton(
                  icon: const Icon(Icons.skip_previous, size: 32),
                  onPressed: _playPrevious,
                ),
                // Play / Pause
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 36,
                    ),
                    onPressed: () {
                      if (_isPlaying) {
                        _audioPlayer.pause();
                      } else {
                        _audioPlayer.play();
                      }
                    },
                  ),
                ),
                // Next
                IconButton(
                  icon: const Icon(Icons.skip_next, size: 32),
                  onPressed: _playNext,
                ),
                // Loop
                IconButton(
                  icon: Icon(
                    _isLoop ? Icons.repeat_one : Icons.repeat,
                    color: _isLoop ? Colors.red : Colors.grey,
                  ),
                  onPressed: () async {
                    final newLoop = !_isLoop;
                    await _audioPlayer.setLoopMode(
                      newLoop ? LoopMode.one : LoopMode.off,
                    );
                    if (mounted) setState(() => _isLoop = newLoop);
                  },
                ),
              ],
            ),

            // ── Seek bar ──
            Row(
              children: [
                Text(_formatDuration(_position),
                    style: const TextStyle(fontSize: 11)),
                Expanded(
                  child: Slider(
                    value: posSec,
                    min: 0,
                    max: maxSec,
                    activeColor: Colors.red,
                    inactiveColor: Colors.red.withAlpha(77), // ~0.3 opacity
                    onChanged: (v) => _audioPlayer.seek(
                      Duration(seconds: v.toInt()),
                    ),
                  ),
                ),
                Text(_formatDuration(_duration),
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}
