import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:dio/dio.dart';
import '../services/youtube_downloader_service.dart';
import '../models/video_model.dart';
import '../widgets/video_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final YouTubeDownloaderService _downloader = YouTubeDownloaderService();
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;

  List<VideoModel> _videos = [];
  bool _isSearching = false;
  String? _error;

  // Download tracking
  String? _downloadingVideoId;
  double _downloadProgress = 0.0;

  int _downloadType = 0; // 0: Video, 1: Audio
  String _selectedQuality = '720p';
  String _selectedAudioQuality = 'High';

  CancelToken? _cancelToken;
  List<VideoModel> _trendingVideos = [];
  bool _isLoadingTrending = true;

  @override
  void initState() {
    super.initState();
    _loadTrendingVideos();
  }

  Future<void> _loadTrendingVideos() async {
    try {
      final results = await _downloader.searchVideos('new telugusong');
      if (mounted) {
        setState(() {
          _trendingVideos = results.take(10).toList();
          _isLoadingTrending = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingTrending = false;
        });
      }
    }
  }

  void _toggleListening() async {
    // Lazily initialize SpeechToText when the user first clicks the mic.
    if (!_speechEnabled) {
      bool initialized = await _speechToText.initialize(
        onStatus: (status) {
          if (mounted) setState(() {});
          if (status == 'done') {
            if (mounted && _searchController.text.isNotEmpty && !_isSearching) {
              _searchVideos();
            }
          }
        },
        onError: (errorNotification) {
          debugPrint('Speech error: ${errorNotification.errorMsg}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('Speech error: ${errorNotification.errorMsg}')),
            );
          }
        },
      );

      if (mounted) {
        setState(() {
          _speechEnabled = initialized;
        });
      }

      if (!initialized) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Speech recognition is not available or permission was denied.')),
          );
        }
        return;
      }
    }

    if (_speechToText.isListening) {
      await _speechToText.stop();
      if (mounted) setState(() {});
    } else {
      await _speechToText.listen(
        onResult: (result) {
          if (mounted) {
            setState(() {
              _searchController.text = result.recognizedWords;
            });
          }
        },
      );
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search YouTube'),
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
                : _videos.isNotEmpty
                    ? _buildVideoList(_videos)
                    : _searchController.text.isNotEmpty
                        ? _buildEmptyState()
                        : _buildTrendingList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
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
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      ),
                    IconButton(
                      icon: Icon(
                        _speechToText.isListening ? Icons.mic : Icons.mic_none,
                        color: _speechToText.isListening ? Colors.red : null,
                      ),
                      onPressed: _toggleListening,
                    ),
                  ],
                ),
              ),
              onSubmitted: (_) => _searchVideos(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _isSearching ? null : _searchVideos,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(14),
            ),
            child: _isSearching 
                ? const SizedBox(
                    width: 24, 
                    height: 24, 
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  )
                : const Icon(Icons.search),
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
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.red[900]?.withValues(alpha: 0.3)
          : Colors.red[50],
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

  Widget _buildTrendingList() {
    if (_isLoadingTrending) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_trendingVideos.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.local_fire_department,
                  color: Colors.orange, size: 28),
              const SizedBox(width: 8),
              Text(
                ' Telugu song',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildVideoList(_trendingVideos)),
      ],
    );
  }

  Widget _buildVideoList(List<VideoModel> videoList) {
    return ListView.builder(
      itemCount: videoList.length,
      itemBuilder: (context, index) {
        final video = videoList[index];
        final isDownloading = _downloadingVideoId == video.id;

        return VideoCard(
          video: video,
          isDownloading: isDownloading,
          downloadProgress: isDownloading ? _downloadProgress : null,
          onDownload: () => _downloadVideo(video),
          onCancel: isDownloading
              ? () {
                  _cancelToken?.cancel();
                }
              : null,
          onTap: () => _showVideoDetails(video),
        );
      },
    );
  }

  Future<void> _searchVideos() async {
    if (_isSearching) return; // Prevent overlapping requests

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
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
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
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : (Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[800]
                  : Colors.grey[200]),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimary
                    : (Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[300]
                        : Colors.grey[700])),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimary
                    : (Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[300]
                        : Colors.grey[700]),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadVideo(VideoModel video) async {
    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    setState(() {
      _downloadingVideoId = video.id;
      _downloadProgress = 0.0;
    });

    try {
      if (_downloadType == 0) {
        await _downloader.downloadVideo(
          video.url,
          _selectedQuality,
          (progress, status) {
            if (mounted) {
              setState(() {
                _downloadProgress = progress;
              });
            }
          },
          cancelToken: _cancelToken,
        );
      } else {
        await _downloader.downloadAudio(
          video.url,
          _selectedAudioQuality,
          (progress, status) {
            if (mounted) {
              setState(() {
                _downloadProgress = progress;
              });
            }
          },
          cancelToken: _cancelToken,
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
        if (e is DioException && e.type == DioExceptionType.cancel ||
            e.toString().contains('cancelled')) {
          _showError('Download cancelled');
        } else {
          _showError('Download failed: $e');
        }
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
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
