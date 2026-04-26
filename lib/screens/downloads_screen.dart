import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'video_player_screen.dart';
import 'qr_share_screen.dart';
import '../main.dart'; // isarService + audioHandler
import '../models/download_item.dart';
import '../models/playlist.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Multi-selection state for sharing multiple items
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};

  // Filter state for media type
  String _filterType = 'all'; // 'all', 'audio', 'video'

  late final Stream<List<DownloadItem>> _downloadsStream;

  @override
  void initState() {
    super.initState();
    _downloadsStream = isarService.listenToDownloads();
  }

  // ──────────────────────────── Playback ────────────────────────────

  Future<void> _playAudio(List<DownloadItem> queue, int initialIndex) async {
    final item = queue[initialIndex];
    final file = File(item.localFilePath);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File not found! It may have been deleted.')),
        );
      }
      return;
    }

    try {
      await audioHandler.playQueue(queue, initialIndex: initialIndex);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing audio: $e')),
        );
      }
    }
  }

  // ──────────────────────────── Helpers ────────────────────────────

  Widget _buildThumbnail(DownloadItem item, {double width = 80, double height = 50}) {
    final isVideo = item.type == 'video';
    final letter = item.title.isNotEmpty ? item.title[0].toUpperCase() : '?';
    final color = _colorFromString(item.title);
    final localThumbPath = '${item.localFilePath}.jpg';

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(localThumbPath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Image.network(
                item.thumbnailUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _colorAvatar(color, letter, isVideo, width, height),
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

  Color _colorFromString(String s) {
    final hue = (s.codeUnits.fold(0, (a, b) => a + b) % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.5, 0.4).toColor();
  }

  // ──────────────────────────── CRUD ────────────────────────────

  void _deleteItem(DownloadItem item) async {
    final file = File(item.localFilePath);
    if (await file.exists()) await file.delete();
    
    final thumbFile = File('${item.localFilePath}.jpg');
    if (await thumbFile.exists()) await thumbFile.delete();

    await isarService.deleteDownloadItem(item.id);
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

  // ──────────────────────────── Playlist ────────────────────────────

  void _showAddToPlaylistBottomSheet(BuildContext context, DownloadItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StreamBuilder<List<Playlist>>(
          stream: isarService.listenToPlaylists(),
          builder: (context, snapshot) {
            final playlists = snapshot.data ?? [];
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.add, color: Theme.of(context).colorScheme.primary),
                    ),
                    title: const Text('New Playlist', style: TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(context);
                      _createPlaylistDialog(item);
                    },
                  ),
                  const Divider(),
                  if (playlists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Center(child: Text('No playlists yet')),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: playlists.length,
                        itemBuilder: (context, index) {
                          final p = playlists[index];
                          return ListTile(
                            leading: const Icon(Icons.queue_music),
                            title: Text(p.name),
                            onTap: () async {
                              await isarService.addToPlaylist(p.id, item);
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Added to ${p.name}')),
                                );
                              }
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _createPlaylistDialog(DownloadItem item) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New Playlist'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Playlist name'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  final newId = await isarService.createPlaylist(text);
                  await isarService.addToPlaylist(newId, item);
                  if (context.mounted) {
                     ScaffoldMessenger.of(context).showSnackBar(
                       SnackBar(content: Text('Created & added to $text')),
                     );
                  }
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  // ──────────────────────────── Build ────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      floatingActionButton: _isSelectionMode && _selectedIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QrShareScreen(
                      items: _selectedIds.toList(),
                    ),
                  ),
                );
              },
              icon: Icon(Icons.qr_code_scanner, color: Theme.of(context).colorScheme.onPrimary),
              label: Text('Share ${_selectedIds.length} items', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
              backgroundColor: Theme.of(context).colorScheme.primary,
            )
          : null,
      body: Column(
        children: [
          // ── Action Row ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isSelectionMode ? 'Select items to share' : 'Downloaded Media',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_isSelectionMode) ...[
                      IconButton(
                        tooltip: 'Show Audio Only',
                        icon: Icon(Icons.music_note, color: _filterType == 'audio' ? Theme.of(context).colorScheme.primary : Colors.grey),
                        onPressed: () => setState(() => _filterType = _filterType == 'audio' ? 'all' : 'audio'),
                      ),
                      IconButton(
                        tooltip: 'Show Video Only',
                        icon: Icon(Icons.videocam, color: _filterType == 'video' ? Theme.of(context).colorScheme.primary : Colors.grey),
                        onPressed: () => setState(() => _filterType = _filterType == 'video' ? 'all' : 'video'),
                      ),
                    ],
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _isSelectionMode = !_isSelectionMode;
                          if (!_isSelectionMode) _selectedIds.clear();
                        });
                      },
                      icon: Icon(_isSelectionMode ? Icons.close : Icons.checklist, color: Theme.of(context).colorScheme.primary),
                      label: Text(_isSelectionMode ? 'Cancel' : 'Multi-Select', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // ── Media list ──
          Expanded(
            child: StreamBuilder<List<DownloadItem>>(
              stream: _downloadsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allItems = snapshot.data ?? [];
                
                final items = allItems.where((i) {
                  if (_filterType == 'audio') return i.type == 'audio';
                  if (_filterType == 'video') return i.type == 'video';
                  return true;
                }).toList();

                if (items.isEmpty) {
                  return const Center(child: Text('No downloaded media found.'));
                }

                // Sort items by sortOrder
                items.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

                return ReorderableListView.builder(
                  itemCount: items.length,
                  onReorder: (oldIndex, newIndex) async {
                    setState(() {
                      if (newIndex > oldIndex) {
                        newIndex -= 1;
                      }
                      final item = items.removeAt(oldIndex);
                      items.insert(newIndex, item);

                      // Update sortOrder for all items to save persistently
                      for (int i = 0; i < items.length; i++) {
                        items[i].sortOrder = i;
                      }
                    });
                    await isarService.saveDownloadItems(items);
                  },
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isVideo = item.type == 'video';

                    return ListTile(
                      key: ValueKey(item.id),
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isSelectionMode) ...[
                            Checkbox(
                              value: _selectedIds.contains(item.id),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedIds.add(item.id);
                                  } else {
                                    _selectedIds.remove(item.id);
                                  }
                                });
                              },
                              activeColor: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                          ],
                          _buildThumbnail(item),
                        ],
                      ),
                      title: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      subtitle: Text(item.duration),
                      trailing: _isSelectionMode
                          ? const SizedBox(width: 24, height: 24) // Placeholder for alignment
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                isVideo
                                    ? IconButton(
                                        icon: Icon(Icons.play_circle_fill, color: Theme.of(context).colorScheme.primary),
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
                                    : StreamBuilder<void>(
                                        stream: audioHandler.queueStateStream,
                                        builder: (context, _) {
                                          final isPlayingThis = audioHandler.currentIndex >= 0 && 
                                              audioHandler.currentIndex < audioHandler.customQueue.length && 
                                              audioHandler.customQueue[audioHandler.currentIndex].id == item.id;
                                          return StreamBuilder<PlaybackState>(
                                            stream: audioHandler.playbackState,
                                            builder: (context, snapshot) {
                                              final isPlaying = snapshot.data?.playing ?? false;
                                              return IconButton(
                                                icon: Icon(
                                                  isPlayingThis && isPlaying
                                                      ? Icons.pause_circle_filled
                                                      : Icons.play_circle_filled,
                                                  color: Theme.of(context).colorScheme.primary,
                                                ),
                                                onPressed: () {
                                                  if (isPlayingThis) {
                                                    if (isPlaying) {
                                                      audioHandler.pause();
                                                    } else {
                                                      audioHandler.play();
                                                    }
                                                  } else {
                                                    // Pass the full sorted queue
                                                    _playAudio(items, index);
                                                  }
                                                },
                                              );
                                            }
                                          );
                                        }
                                      ),
                                PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'playlist') {
                                      _showAddToPlaylistBottomSheet(context, item);
                                    } else if (value == 'export') {
                                      _exportToDownloads(item);
                                    } else if (value == 'share') {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => QrShareScreen(items: [item.id]),
                                        ),
                                      );
                                    } else if (value == 'delete') {
                                      _deleteItem(item);
                                    }
                                  },
                                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                    const PopupMenuItem<String>(
                                      value: 'playlist',
                                      child: ListTile(
                                        leading: Icon(Icons.playlist_add, color: Colors.purple),
                                        title: Text('Add to Playlist'),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                    const PopupMenuItem<String>(
                                      value: 'export',
                                      child: ListTile(
                                        leading: Icon(Icons.download, color: Colors.green),
                                        title: Text('Export to Storage'),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                    const PopupMenuItem<String>(
                                      value: 'share',
                                      child: ListTile(
                                        leading: Icon(Icons.qr_code, color: Colors.blue),
                                        title: Text('Share via QR'),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                    const PopupMenuItem<String>(
                                      value: 'delete',
                                      child: ListTile(
                                        leading: Icon(Icons.delete, color: Colors.red),
                                        title: Text('Delete'),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ],
                                ),
                                // Drag handle for reordering
                                const ReorderableDragStartListener(
                                  index: 0, // Provided by ReorderableListView internally, but we use trailing
                                  child: Icon(Icons.drag_handle, color: Colors.grey),
                                )
                              ],
                            ),
                      onTap: () async {
                        if (_isSelectionMode) {
                          setState(() {
                            if (_selectedIds.contains(item.id)) {
                              _selectedIds.remove(item.id);
                            } else {
                              _selectedIds.add(item.id);
                            }
                          });
                          return;
                        }

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
                          _playAudio(items, index);
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
