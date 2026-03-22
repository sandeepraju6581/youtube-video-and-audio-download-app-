import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/download_item.dart';

class IsarService {
  late Future<Isar> db;

  IsarService() {
    db = _initDb();
  }

  Future<Isar> _initDb() async {
    if (Isar.instanceNames.isEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      return await Isar.open(
        [DownloadItemSchema],
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
}
