import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/download_item.dart';
import '../models/playlist.dart';

class IsarService {
  late Future<Isar> db;

  IsarService() {
    db = _initDb();
  }

  Future<Isar> _initDb() async {
    if (Isar.instanceNames.isEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      return await Isar.open(
        [DownloadItemSchema, PlaylistSchema],
        directory: dir.path,
        inspector: true,
      );
    }
    return Future.value(Isar.getInstance());
  }

  Future<void> saveDownloadItem(DownloadItem item) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.downloadItems.put(item);
    });
  }

  Stream<List<DownloadItem>> listenToDownloads() async* {
    final isar = await db;
    yield* isar.downloadItems.where().sortByDownloadedAtDesc().watch(fireImmediately: true);
  }

  Future<List<DownloadItem>> getAllDownloads() async {
    final isar = await db;
    return await isar.downloadItems.where().sortByDownloadedAtDesc().findAll();
  }

  Future<void> deleteDownloadItem(int id) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.downloadItems.delete(id);
    });
  }

  Future<DownloadItem?> getDownloadItemByYoutubeId(String youtubeId) async {
    final isar = await db;
    return await isar.downloadItems.getByYoutubeId(youtubeId);
  }

  Future<DownloadItem?> getDownloadItem(int id) async {
    final isar = await db;
    return await isar.downloadItems.get(id);
  }

  // ------------------ PLAYLISTS ------------------

  Future<int> createPlaylist(String name) async {
    final isar = await db;
    final playlist = Playlist()
      ..name = name
      ..createdAt = DateTime.now();
      
    return await isar.writeTxn(() async {
      return await isar.playlists.put(playlist);
    });
  }

  Future<void> deletePlaylist(int id) async {
    final isar = await db;
    await isar.writeTxn(() async {
      final playlist = await isar.playlists.get(id);
      if (playlist != null) {
        // Just delete the playlist, items stay in download_items
        await isar.playlists.delete(id);
      }
    });
  }

  Stream<List<Playlist>> listenToPlaylists() async* {
    final isar = await db;
    yield* isar.playlists.where().sortByCreatedAtDesc().watch(fireImmediately: true);
  }

  Future<void> addToPlaylist(int playlistId, DownloadItem item) async {
    final isar = await db;
    final playlist = await isar.playlists.get(playlistId);
    if (playlist != null) {
      await isar.writeTxn(() async {
        playlist.items.add(item);
        await playlist.items.save();
      });
    }
  }

  Future<void> addMultipleToPlaylist(int playlistId, List<DownloadItem> newItems) async {
    final isar = await db;
    final playlist = await isar.playlists.get(playlistId);
    if (playlist != null) {
      await isar.writeTxn(() async {
        playlist.items.addAll(newItems);
        await playlist.items.save();
      });
    }
  }

  Future<void> removeFromPlaylist(int playlistId, DownloadItem item) async {
    final isar = await db;
    final playlist = await isar.playlists.get(playlistId);
    if (playlist != null) {
      await isar.writeTxn(() async {
        playlist.items.remove(item);
        await playlist.items.save();
      });
    }
  }

  Future<Playlist?> getPlaylist(int id) async {
    final isar = await db;
    final playlist = await isar.playlists.get(id);
    if (playlist != null) {
      await playlist.items.load();
    }
    return playlist;
  }

  Future<void> updatePlaylistOrder(int playlistId, List<int> orderedIds) async {
    final isar = await db;
    await isar.writeTxn(() async {
      final playlist = await isar.playlists.get(playlistId);
      if (playlist != null) {
        playlist.itemOrder = orderedIds;
        await isar.playlists.put(playlist);
      }
    });
  }

  Future<void> saveDownloadItems(List<DownloadItem> items) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.downloadItems.putAll(items);
    });
  }
}
