import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../main.dart';
import '../models/download_item.dart';
import '../models/video_model.dart'; // Adjust path if needed

class YouTubeDownloaderService {
  final YoutubeExplode _yt = YoutubeExplode();
  final Dio _dio = Dio();

  // Cache for search results
  final Map<String, List<VideoModel>> _searchCache = {};

  // Stream quality options
  static const List<String> videoQualities = [
    '1080p',
    '720p',
    '480p',
    '360p',
    '240p',
    '144p'
  ];

  static const List<String> audioQualities = ['High', 'Medium', 'Low'];

  // Search videos with caching
  Future<List<VideoModel>> searchVideos(String query,
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _searchCache.containsKey(query)) {
      return _searchCache[query]!;
    }

    try {
      // Searching YouTube directly returns populated View and Title data.
      // The search query returns the first page of results (usually ~15-20).
      // If we attempt .take(30), the library automatically fires additional network requests
      // sequentially to fetch the next page, drastically slowing down the UI loading.
      final searchResults = await _yt.search.search(query);
      
      final videos = searchResults.take(15).map((video) {
        return VideoModel.fromYoutubeVideo(video);
      }).toList();

      _searchCache[query] = videos;
      return videos;
    } catch (e) {
      throw Exception('Failed to search videos: $e');
    }
  }

  // Get video details by URL
  Future<VideoModel> getVideoDetails(String videoUrl) async {
    try {
      final video = await _yt.videos.get(videoUrl);
      return VideoModel.fromYoutubeVideo(video);
    } catch (e) {
      throw Exception('Failed to get video details: $e');
    }
  }

  bool isPlaylistUrl(String url) {
    return url.contains('list=');
  }

  Future<Map<String, dynamic>> getPlaylistDetails(String playlistUrl) async {
    try {
      final playlistDetails = await _yt.playlists.get(playlistUrl);
      final videosStream = _yt.playlists.getVideos(playlistUrl);
      final List<VideoModel> videos = [];
      
      await for (var video in videosStream.take(50)) { // limit to 50 for safety
        videos.add(VideoModel.fromYoutubeVideo(video));
      }

      return {
        'title': playlistDetails.title,
        'author': playlistDetails.author,
        'videos': videos
      };
    } catch (e) {
      throw Exception('Failed to get playlist details: $e');
    }
  }

  // Get available streams with quality information
  Future<List<Map<String, dynamic>>> getAvailableStreams(
      String videoUrl) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoUrl);
      final streams = <Map<String, dynamic>>[];

      // Video streams (using muxed to ensure audio+video are together)
      for (var stream in manifest.muxed) {
        streams.add({
          'type': 'video',
          'quality': stream.qualityLabel,
          'container': stream.container.name,
          'bitrate': stream.bitrate.bitsPerSecond,
          'size': stream.size.totalBytes,
          'url': stream.url.toString(),
        });
      }

      // Audio streams
      for (var stream in manifest.audio) {
        streams.add({
          'type': 'audio',
          'quality': '${(stream.bitrate.bitsPerSecond / 1000).round()} kbps',
          'container': stream.container.name,
          'bitrate': stream.bitrate.bitsPerSecond,
          'size': stream.size.totalBytes,
          'url': stream.url.toString(),
        });
      }

      return streams;
    } catch (e) {
      throw Exception('Failed to get streams: $e');
    }
  }

  // Download video (note: currently no merge — video only)
  Future<String> downloadVideo(
    String videoUrl,
    String quality,
    Function(double progress, String status) onProgress,
  ) async {
    try {
      onProgress(0.0, 'Getting video information...');
      
      // Fetch video and manifest concurrently for faster initialization
      final futureVideo = _yt.videos.get(videoUrl);
      final futureManifest = _yt.videos.streamsClient.getManifest(videoUrl);

      final video = await futureVideo;
      onProgress(0.1, 'Fetching available streams...');
      final manifest = await futureManifest;

      // Select muxed stream (contains both video + audio)
      StreamInfo? selectedVideoStream =
          manifest.muxed.where((s) => s.videoQualityLabel.contains(quality) || s.qualityLabel.contains(quality)).firstOrNull;

      if (selectedVideoStream == null && manifest.muxed.isNotEmpty) {
        selectedVideoStream = manifest.muxed.reduce((a, b) => 
            a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b);
      }

      if (selectedVideoStream == null) {
        throw Exception('No suitable video stream found');
      }

      onProgress(0.3, 'Preparing download...');

      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        throw Exception('Cannot access downloads directory');
      }

      final sanitizedTitle = _sanitizeFileName(video.title);
      final outputPath = '${downloadsDir.path}/$sanitizedTitle.mp4';

      onProgress(0.4, 'Downloading video...');
      await _downloadStream(selectedVideoStream, outputPath,
          (p) => onProgress(0.4 + p * 0.6, 'Downloading video...'));

      onProgress(1.0, 'Download complete!');

      final item = DownloadItem()
        ..youtubeId = video.id.value
        ..title = video.title
        ..url = videoUrl
        ..localFilePath = outputPath
        ..thumbnailUrl = getThumbnailUrl(video.id.value)
        ..duration = getDurationString(video.duration)
        ..downloadedAt = DateTime.now()
        ..status = 'Completed'
        ..type = 'video';
      await isarService.saveDownloadItem(item);

      return outputPath;
    } catch (e) {
      throw Exception('Failed to download video: $e');
    }
  }

  // Download audio only
  Future<String> downloadAudio(
    String videoUrl,
    String quality,
    Function(double progress, String status) onProgress,
  ) async {
    try {
      onProgress(0.0, 'Getting video information...');
      
      // Fetch video and manifest concurrently for faster initialization
      final futureVideo = _yt.videos.get(videoUrl);
      final futureManifest = _yt.videos.streamsClient.getManifest(videoUrl);

      final video = await futureVideo;
      onProgress(0.2, 'Fetching audio streams...');
      final manifest = await futureManifest;

      final audioStreams = manifest.audio;

      if (audioStreams.isEmpty) {
        throw Exception('No audio streams available');
      }

      onProgress(0.3, 'Selecting audio stream...');

      StreamInfo? selectedAudio;

      switch (quality) {
        case 'High':
          selectedAudio = audioStreams.isNotEmpty 
              ? audioStreams.reduce((a, b) => a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b) 
              : null;
          break;
        case 'Low':
          final sorted = audioStreams.toList()
            ..sort((a, b) =>
                a.bitrate.bitsPerSecond.compareTo(b.bitrate.bitsPerSecond));
          selectedAudio = sorted.first;
          break;
        case 'Medium':
        default:
          final sorted = audioStreams.toList()
            ..sort((a, b) =>
                a.bitrate.bitsPerSecond.compareTo(b.bitrate.bitsPerSecond));
          selectedAudio = sorted[sorted.length ~/ 2];
          break;
      }

      selectedAudio ??= audioStreams.isNotEmpty 
          ? audioStreams.reduce((a, b) => a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b) 
          : null;

      if (selectedAudio == null) {
        throw Exception('No suitable audio stream found');
      }

      onProgress(0.4, 'Preparing download...');

      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        throw Exception('Cannot access downloads directory');
      }

      final sanitizedTitle = _sanitizeFileName(video.title);
      final outputPath =
          '${downloadsDir.path}/$sanitizedTitle.${selectedAudio.container.name == 'mp4' ? 'm4a' : selectedAudio.container.name}';

      onProgress(0.5, 'Downloading audio...');
      await _downloadStream(selectedAudio, outputPath, (p) {
        onProgress(0.5 + p * 0.5, 'Downloading audio...');
      });

      onProgress(1.0, 'Download complete!');

      final item = DownloadItem()
        ..youtubeId = video.id.value
        ..title = video.title
        ..url = videoUrl
        ..localFilePath = outputPath
        ..thumbnailUrl = getThumbnailUrl(video.id.value)
        ..duration = getDurationString(video.duration)
        ..downloadedAt = DateTime.now()
        ..status = 'Completed'
        ..type = 'audio';
      await isarService.saveDownloadItem(item);

      return outputPath;
    } catch (e) {
      throw Exception('Failed to download audio: $e');
    }
  }

  Future<void> _downloadStream(
      StreamInfo streamInfo, String savePath, Function(double) onProgress) async {
    try {
      // Use Dio for downloading as it has highly optimized memory buffers 
      // compared to Dart's standard stream loop, speeding up the file writing.
      await _dio.download(
        streamInfo.url.toString(),
        savePath,
        options: Options(
          // Important for avoiding basic throttles
          headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},
        ),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received / total);
          } else {
            final totalSize = streamInfo.size.totalBytes;
            if (totalSize > 0) {
              onProgress(received / totalSize);
            }
          }
        },
      );
    } catch (e) {
      // Fallback to youtube_explode_dart stream if direct URL download fails
      final stream = _yt.videos.streamsClient.get(streamInfo);
      final file = File(savePath);
      final fileStream = file.openWrite();

      final totalSize = streamInfo.size.totalBytes;
      int received = 0;

      await for (final data in stream) {
        fileStream.add(data);
        received += data.length;
        if (totalSize > 0) {
          onProgress(received / totalSize);
        }
      }

      await fileStream.flush();
      await fileStream.close();
    }
  }

  String _sanitizeFileName(String fileName) {
    final invalidChars = RegExp(r'[<>:"/\\|?*]');
    return fileName
        .replaceAll(invalidChars, '_')
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'_{2,}'), '_')
        .trim();
  }

  String getThumbnailUrl(String videoId, {int quality = 0}) {
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

  bool isValidYouTubeUrl(String url) {
    final regex = RegExp(
      r'^(https?://)?(www\.)?(youtube\.com|youtu\.be)/.+$',
      caseSensitive: false,
    );
    return regex.hasMatch(url);
  }

  String? extractVideoId(String url) {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return null;

      if (uri.host == 'youtu.be') {
        return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      }

      if (uri.host.contains('youtube.com')) {
        if (uri.queryParameters.containsKey('v')) {
          return uri.queryParameters['v'];
        }
        // embed or shorts etc.
        if (uri.pathSegments.contains('embed') ||
            uri.pathSegments.contains('shorts')) {
          final idx =
              uri.pathSegments.indexWhere((s) => s == 'embed' || s == 'shorts');
          if (idx != -1 && idx + 1 < uri.pathSegments.length) {
            return uri.pathSegments[idx + 1];
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String getDurationString(Duration? duration) {
    if (duration == null) return 'Unknown';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return duration.inHours > 0
        ? '$hours:$minutes:$seconds'
        : '$minutes:$seconds';
  }

  void dispose() {
    _yt.close();
  }
}
