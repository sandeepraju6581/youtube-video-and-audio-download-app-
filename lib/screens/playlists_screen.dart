import 'dart:io';
import 'package:flutter/material.dart';
import '../models/playlist.dart';
import '../main.dart'; // isarService
import 'playlist_detail_screen.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  void _createPlaylist() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New Playlist'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Playlist name',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  isarService.createPlaylist(text);
                }
                Navigator.pop(context);
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  void _deletePlaylist(Playlist playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Playlist?'),
        content: Text('Are you sure you want to delete "${playlist.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              isarService.deletePlaylist(playlist.id);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistThumbnail(Playlist playlist, BuildContext context) {
    if (playlist.items.isEmpty) {
      return Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.queue_music,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    final firstItem = playlist.itemOrder.isNotEmpty 
        ? playlist.items.firstWhere((i) => i.id == playlist.itemOrder.first, orElse: () => playlist.items.first)
        : playlist.items.first;
        
    final localThumbPath = '${firstItem.localFilePath}.jpg';
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 50,
        height: 50,
        child: Image.file(
          File(localThumbPath),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Image.network(
            firstItem.thumbnailUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              child: Icon(Icons.queue_music, color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _createPlaylist,
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Playlist>>(
        stream: isarService.listenToPlaylists(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final playlists = snapshot.data ?? [];

          if (playlists.isEmpty) {
            return const Center(
              child: Text('No playlists yet. Create one!'),
            );
          }

          return ListView.builder(
            itemCount: playlists.length,
            padding: const EdgeInsets.only(bottom: 80),
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return ListTile(
                leading: _buildPlaylistThumbnail(playlist, context),
                title: Text(
                  playlist.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('${playlist.items.length} items'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.grey),
                  onPressed: () => _deletePlaylist(playlist),
                ),
                onTap: () {
                   Navigator.push(
                     context,
                     MaterialPageRoute(
                       builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
                     ),
                   );
                },
              );
            },
          );
        },
      ),
    );
  }
}
