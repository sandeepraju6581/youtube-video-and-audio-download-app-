import 'package:isar/isar.dart';
import 'download_item.dart';

part 'playlist.g.dart';

@collection
class Playlist {
  Id id = Isar.autoIncrement;

  late String name;

  late DateTime createdAt;

  final items = IsarLinks<DownloadItem>();

  // Stores the ordered IDs of the items for drag-and-drop
  List<int> itemOrder = [];
}
