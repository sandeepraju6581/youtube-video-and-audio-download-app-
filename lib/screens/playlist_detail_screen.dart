import 'dart:io';
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/download_item.dart';
import '../models/playlist.dart';
import 'video_player_screen.dart';

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
        height: 50,
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

  void _playAll() {
    final audioItems = _items.where((i) => i.type == 'audio').toList();
    if (audioItems.isNotEmpty) {
      audioHandler.playQueue(audioItems, initialIndex: 0);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No audio files to play.')),
      );
    }
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
      appBar: AppBar(
        title: Text(_playlist!.name),
        actions: [
          StreamBuilder<void>(
            stream: audioHandler.queueStateStream,
            builder: (context, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.shuffle,
                      color: audioHandler.isShuffle ? Theme.of(context).colorScheme.primary : Colors.white,
                    ),
                    tooltip: 'Toggle Shuffle',
                    onPressed: () => audioHandler.toggleShuffle(),
                  ),
                  IconButton(
                    icon: Icon(
                      audioHandler.isLoop ? Icons.repeat_one : Icons.repeat,
                      color: audioHandler.isLoop ? Theme.of(context).colorScheme.primary : Colors.white,
                    ),
                    tooltip: 'Toggle Loop',
                    onPressed: () => audioHandler.toggleLoop(),
                  ),
                ],
              );
            }
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Play All',
            onPressed: _playAll,
          ),
        ],
      ),
      body: _items.isEmpty
          ? const Center(child: Text('Playlist is empty.'))
          : ReorderableListView.builder(
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
              itemBuilder: (context, index) {
                final item = _items[index];
                return ListTile(
                  key: ValueKey(item.id),
                  leading: _buildThumbnail(item),
                  title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${item.type.toUpperCase()} • ${item.duration}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                        onPressed: () => _removeItem(item),
                      ),
                      const ReorderableDragStartListener(
                        index: 0,
                        child: Icon(Icons.drag_handle, color: Colors.grey),
                      ),
                    ],
                  ),
                  onTap: () async {
                    if (item.type == 'video') {
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
                      _playQueue(index);
                    }
                  },
                );
              },
            ),
    );
  }
}
