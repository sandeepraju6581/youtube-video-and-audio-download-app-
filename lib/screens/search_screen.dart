import 'package:flutter/material.dart';
import '../services/youtube_downloader_service.dart';
import '../models/video_model.dart';
import '../widgets/video_card.dart';
import '../widgets/download_progress.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final YouTubeDownloaderService _downloader = YouTubeDownloaderService();

  List<VideoModel> _videos = [];
  bool _isSearching = false;
  bool _isLoadingMore = false;
  int _currentPage = 0;
  String? _error;

  // Download tracking
  String? _downloadingVideoId;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';

  int _downloadType = 0; // 0: Video, 1: Audio
  String _selectedQuality = '720p';
  String _selectedAudioQuality = 'High';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search YouTube'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _showDownloadOptions(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          if (_error != null) _buildErrorWidget(),
          Expanded(
            child: _isSearching && _videos.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _videos.isEmpty
                    ? _buildEmptyState()
                    : _buildVideoList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search videos...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
              onSubmitted: (_) => _searchVideos(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _isSearching ? null : _searchVideos,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            child: Text(_isSearching ? 'Searching...' : 'Search'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Search for videos to download',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.red[50],
      child: Row(
        children: [
          const Icon(Icons.error, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
          TextButton(
            onPressed: _searchVideos,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoList() {
    return ListView.builder(
      itemCount: _videos.length,
      itemBuilder: (context, index) {
        final video = _videos[index];
        final isDownloading = _downloadingVideoId == video.id;

        return VideoCard(
          video: video,
          isDownloading: isDownloading,
          downloadProgress: isDownloading ? _downloadProgress : null,
          onDownload: () => _downloadVideo(video),
          onTap: () => _showVideoDetails(video),
        );
      },
    );
  }

  Future<void> _searchVideos() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _error = null;
      _videos = [];
    });

    try {
      final results = await _downloader.searchVideos(query);
      setState(() {
        _videos = results;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to search: $e';
      });
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  void _showDownloadOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateBottomSheet) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Download Settings',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  const Text('Download Type'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildBottomSheetOption(
                          context,
                          icon: Icons.video_library,
                          label: 'Video',
                          isSelected: _downloadType == 0,
                          onTap: () =>
                              setStateBottomSheet(() => _downloadType = 0),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildBottomSheetOption(
                          context,
                          icon: Icons.audiotrack,
                          label: 'Audio',
                          isSelected: _downloadType == 1,
                          onTap: () =>
                              setStateBottomSheet(() => _downloadType = 1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_downloadType == 0) ...[
                    const Text('Video Quality'),
                    const SizedBox(height: 8),
                    DropdownButton<String>(
                      value: _selectedQuality,
                      isExpanded: true,
                      items: ['1080p', '720p', '480p', '360p'].map((quality) {
                        return DropdownMenuItem(
                          value: quality,
                          child: Text(quality),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setStateBottomSheet(() => _selectedQuality = value!);
                      },
                    ),
                  ] else ...[
                    const Text('Audio Quality'),
                    const SizedBox(height: 8),
                    DropdownButton<String>(
                      value: _selectedAudioQuality,
                      isExpanded: true,
                      items: ['High', 'Medium', 'Low'].map((quality) {
                        return DropdownMenuItem(
                          value: quality,
                          child: Text(quality),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setStateBottomSheet(
                            () => _selectedAudioQuality = value!);
                      },
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Apply Settings'),
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

  Widget _buildBottomSheetOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.red : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.grey[700]),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadVideo(VideoModel video) async {
    setState(() {
      _downloadingVideoId = video.id;
      _downloadProgress = 0.0;
      _downloadStatus = 'Starting...';
    });

    try {
      String? downloadedPath;

      if (_downloadType == 0) {
        downloadedPath = await _downloader.downloadVideo(
          video.url,
          _selectedQuality,
          (progress, status) {
            setState(() {
              _downloadProgress = progress;
              _downloadStatus = status;
            });
          },
        );
      } else {
        downloadedPath = await _downloader.downloadAudio(
          video.url,
          _selectedAudioQuality,
          (progress, status) {
            setState(() {
              _downloadProgress = progress;
              _downloadStatus = status;
            });
          },
        );
      }

      if (mounted) {
        setState(() {
          _downloadingVideoId = null;
        });
        _showSuccess('Download completed!');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadingVideoId = null;
        });
        _showError('Download failed: $e');
      }
    }
  }

  void _showVideoDetails(VideoModel video) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  video.thumbnailUrl,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                video.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                video.author,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.play_circle_outline, size: 16),
                  const SizedBox(width: 4),
                  Text(video.duration),
                  const SizedBox(width: 16),
                  const Icon(Icons.visibility, size: 16),
                  const SizedBox(width: 4),
                  Text(_formatViewCount(video.viewCount)),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _downloadVideo(video);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Download'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatViewCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M views';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K views';
    } else {
      return '$count views';
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _downloader.dispose();
    super.dispose();
  }
}
