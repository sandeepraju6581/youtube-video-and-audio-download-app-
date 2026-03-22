import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class VideoModel {
  final String id;
  final String title;
  final String author;
  final String duration;
  final String thumbnailUrl;
  final String url;
  final int viewCount;
  final DateTime? uploadDate;

  VideoModel({
    required this.id,
    required this.title,
    required this.author,
    required this.duration,
    required this.thumbnailUrl,
    required this.url,
    required this.viewCount,
    this.uploadDate,
  });

  factory VideoModel.fromYoutubeVideo(Video video) {
    return VideoModel(
      id: video.id.value,
      title: video.title,
      author: video.author ?? 'Unknown',
      duration: _formatDuration(video.duration),
      thumbnailUrl: _getThumbnailUrl(video.id.value),
      url: video.url,
      viewCount: video.engagement.viewCount,
      uploadDate: video.uploadDate,
    );
  }

  static String _formatDuration(Duration? duration) {
    if (duration == null) return 'Unknown';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    } else {
      return '$minutes:$seconds';
    }
  }

  static String _getThumbnailUrl(String videoId, {int quality = 0}) {
    switch (quality) {
      case 0:
        return 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg';
      case 1:
        return 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
      case 2:
        return 'https://img.youtube.com/vi/$videoId/mqdefault.jpg';
      default:
        return 'https://img.youtube.com/vi/$videoId/default.jpg';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'duration': duration,
      'thumbnailUrl': thumbnailUrl,
      'url': url,
      'viewCount': viewCount,
      'uploadDate': uploadDate?.toIso8601String(),
    };
  }

  factory VideoModel.fromJson(Map<String, dynamic> json) {
    return VideoModel(
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String,
      duration: json['duration'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String,
      url: json['url'] as String,
      viewCount: json['viewCount'] as int? ?? 0,
      uploadDate: json['uploadDate'] != null
          ? DateTime.tryParse(json['uploadDate'] as String)
          : null,
    );
  }
}

class DownloadOptions {
  final DownloadType type;
  final String? quality;
  final bool includeMetadata;

  DownloadOptions({
    required this.type,
    this.quality,
    this.includeMetadata = true,
  });
}

enum DownloadType {
  video,
  audio,
}

enum DownloadStatus {
  pending,
  downloading,
  completed,
  failed,
  cancelled,
}

class DownloadTask {
  final String id;
  final VideoModel video;
  final DownloadOptions options;
  DownloadStatus status;
  double progress;
  String? downloadedPath;
  String? errorMessage;
  final DateTime createdAt;

  DownloadTask({
    required this.id,
    required this.video,
    required this.options,
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    this.downloadedPath,
    this.errorMessage,
    required this.createdAt,
  });
}
