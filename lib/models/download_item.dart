import 'package:isar/isar.dart';

part 'download_item.g.dart';

@collection
class DownloadItem {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String youtubeId;

  late String title;
  
  late String url;

  late String localFilePath;

  late String thumbnailUrl;

  late String duration;

  late DateTime downloadedAt;

  // "Completed", "Pending", "Failed"
  late String status;

  // "video" or "audio"
  late String type;
}
