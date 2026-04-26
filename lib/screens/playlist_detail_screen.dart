import 'dart:io';
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/download_item.dart';
import '../models/playlist.dart';
import '../widgets/now_playing_header.dart';
import 'video_player_screen.dart';
import 'package:video_player/video_player.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final int playlistId;

  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  Playlist? _playlist;
  bool _isLoading = true;
  List<DownloadItem> _items = [];
  VideoPlayerController? _videoController;
  DownloadItem? _playingVideoItem;

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadPlaylist();
  }

  Future<void> _loadPlaylist() async {
    final playlist = await isarService.getPlaylist(widget.playlistId);
    if (mounted) {
      setState(() {
        _playlist = playlist;
        if (playlist != null) {
          _items = playlist.items.toList();
          if (playlist.itemOrder.isNotEmpty) {
            _items.sort((a, b) {
              int indexA = playlist.itemOrder.indexOf(a.id);
              int indexB = playlist.itemOrder.indexOf(b.id);
              if (indexA == -1) indexA = 99999;
              if (indexB == -1) indexB = 99999;
              return indexA.compareTo(indexB);
            });
          }
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _removeItem(DownloadItem item) async {
    if (_playlist != null) {
      await isarService.removeFromPlaylist(_playlist!.id, item);
      _loadPlaylist(); // reload list
    }
  }

  Widget _buildThumbnail(DownloadItem item) {
    final isVideo = item.type == 'video';
    final letter = item.title.isNotEmpty ? item.title[0].toUpperCase() : '?';
    final localThumbPath = '${item.localFilePath}.jpg';

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 80,
        height: 45,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(localThumbPath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Image.network(
                item.thumbnailUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey,
                  child: Center(child: Text(letter)),
                ),
              ),
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

  void _playQueue(int initialIndex) async {
    if (_items.isEmpty) return;

    final item = _items[initialIndex];
    final file = File(item.localFilePath);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File not found!')),
        );
      }
      return;
    }

    try {
      // Create an audio-only queue from the playlist
      final audioItems = _items.where((i) => i.type == 'audio').toList();
      int startIdx = audioItems.indexWhere((i) => i.id == item.id);
      if (startIdx == -1) startIdx = 0; // fallback if trying to play video as audio

      if (audioItems.isNotEmpty) {
        await audioHandler.playQueue(audioItems, initialIndex: startIdx);
        // Clear video state if audio plays
        if (_videoController != null) {
          _videoController!.pause();
          setState(() {
            _playingVideoItem = null;
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No audio files to play in this playlist.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing audio: $e')),
        );
      }
    }
  }

  void _playVideoInline(DownloadItem item) async {
    final file = File(item.localFilePath);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video file not found!')));
      }
      return;
    }

    // Stop background audio
    await audioHandler.pause();

    final oldController = _videoController;
    
    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    await controller.play();
    controller.setLooping(true);

    if (!mounted) {
      controller.dispose();
      return;
    }

    setState(() {
      _videoController = controller;
      _playingVideoItem = item;
    });

    oldController?.dispose();
  }

  void _playAtIndex(int index) {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    if (item.type == 'video') {
      _playVideoInline(item);
    } else {
      _playQueue(index);
    }
  }

  void _skipNext() {
    if (_items.isEmpty) return;
    int currentIndex = -1;
    if (_playingVideoItem != null) {
      currentIndex = _items.indexWhere((item) => item.id == _playingVideoItem!.id);
    } else {
      final mediaItem = audioHandler.mediaItem.value;
      if (mediaItem != null) {
        currentIndex = _items.indexWhere((item) => item.id.toString() == mediaItem.id);
      }
    }
    if (currentIndex == -1) currentIndex = -1; // Default to start
    int nextIndex = (currentIndex + 1) % _items.length;
    _playAtIndex(nextIndex);
  }

  void _skipPrevious() {
    if (_items.isEmpty) return;
    int currentIndex = -1;
    if (_playingVideoItem != null) {
      currentIndex = _items.indexWhere((item) => item.id == _playingVideoItem!.id);
    } else {
      final mediaItem = audioHandler.mediaItem.value;
      if (mediaItem != null) {
        currentIndex = _items.indexWhere((item) => item.id.toString() == mediaItem.id);
      }
    }
    if (currentIndex == -1) currentIndex = 1; // Default to end
    int prevIndex = (currentIndex - 1 + _items.length) % _items.length;
    _playAtIndex(prevIndex);
  }

  Future<void> _showAddSongsDialog() async {
    final allDownloads = await isarService.getAllDownloads();
    final existingIds = _items.map((e) => e.id).toSet();
    final availableSongs = allDownloads.where((item) => !existingIds.contains(item.id)).toList();

    if (!mounted) return;

    if (availableSongs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No new downloaded songs available to add.')),
      );
      return;
    }

    final selectedItems = <DownloadItem>{};

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Add Songs', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          TextButton(
                            onPressed: () async {
                              if (selectedItems.isNotEmpty) {
                                await isarService.addMultipleToPlaylist(widget.playlistId, selectedItems.toList());
                                _loadPlaylist();
                                if (context.mounted) Navigator.pop(context);
                              }
                            },
                            child: Text('Add (${selectedItems.length})', style: const TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: availableSongs.length,
                        itemBuilder: (context, index) {
                          final item = availableSongs[index];
                          final isSelected = selectedItems.contains(item);
                          return CheckboxListTile(
                            value: isSelected,
                            activeColor: Colors.redAccent,
                            checkColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                            subtitle: Text('${item.type.toUpperCase()} • ${item.duration}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            secondary: _buildThumbnail(item),
                            onChanged: (bool? value) {
                              setModalState(() {
                                if (value == true) {
                                  selectedItems.add(item);
                                } else {
                                  selectedItems.remove(item);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_playlist == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Playlist')),
        body: const Center(child: Text('Playlist not found')),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: _items.isEmpty
            ? SingleChildScrollView(
                child: Column(
                  children: [
                    NowPlayingHeader(
                      playlistName: _playlist!.name,
                      playlistItems: _items,
                      videoController: _videoController,
                      videoItem: _playingVideoItem,
                      onSkipNext: _skipNext,
                      onSkipPrev: _skipPrevious,
                      onFullscreen: () {
                        if (_playingVideoItem != null) {
                          final file = File(_playingVideoItem!.localFilePath);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VideoPlayerScreen(
                                videoFile: file,
                                controller: _videoController,
                                isFullscreen: true,
                              ),
                            ),
                          ).then((_) {
                            // Resume inline play when returning from full screen
                            _videoController?.play();
                          });
                          _videoController?.pause();
                        }
                      },
                    ),
                    const SizedBox(height: 100),
                    const Center(child: Text('Playlist is empty.')),
                  ],
                ),
              )
            : ReorderableListView.builder(
                header: NowPlayingHeader(
                  key: const ValueKey('header'),
                  playlistName: _playlist!.name,
                  playlistItems: _items,
                  videoController: _videoController,
                  videoItem: _playingVideoItem,
                  onSkipNext: _skipNext,
                  onSkipPrev: _skipPrevious,
                  onFullscreen: () {
                    if (_playingVideoItem != null) {
                      final file = File(_playingVideoItem!.localFilePath);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VideoPlayerScreen(
                            videoFile: file,
                            controller: _videoController,
                            isFullscreen: true,
                          ),
                        ),
                      ).then((_) {
                        _videoController?.play();
                      });
                      _videoController?.pause();
                    }
                  },
                ),
                itemCount: _items.length,
                onReorder: (oldIndex, newIndex) async {
                  setState(() {
                    if (newIndex > oldIndex) {
                      newIndex -= 1;
                    }
                    final item = _items.removeAt(oldIndex);
                    _items.insert(newIndex, item);
                  });
                  final orderedIds = _items.map((e) => e.id).toList();
                  await isarService.updatePlaylistOrder(_playlist!.id, orderedIds);
                },
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return ListTile(
                    key: ValueKey(item.id),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: _buildThumbnail(item),
                    title: Text(
                      item.title, 
                      maxLines: 2, 
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        '${item.type.toUpperCase()} • ${item.duration}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(8),
                          icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFE53935)),
                          onPressed: () => _removeItem(item),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Icon(Icons.drag_handle, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                    onTap: () async {
                      if (item.type == 'video') {
                        _playVideoInline(item);
                      } else {
                        _playQueue(index);
                      }
                    },
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSongsDialog,
        backgroundColor: Colors.redAccent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
