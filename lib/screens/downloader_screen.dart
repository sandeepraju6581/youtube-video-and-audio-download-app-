import 'package:flutter/material.dart';
import '../services/youtube_downloader_service.dart';
import '../models/video_model.dart';

class DownloaderScreen extends StatefulWidget {
  const DownloaderScreen({super.key});

  @override
  State<DownloaderScreen> createState() => _DownloaderScreenState();
}

class _DownloaderScreenState extends State<DownloaderScreen> {
  final TextEditingController _urlController = TextEditingController();
  final YouTubeDownloaderService _downloader = YouTubeDownloaderService();

  bool _isLoading = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';
  
  // Single mode state
  VideoModel? _currentVideo;
  
  // Playlist mode state
  bool _isPlaylistMode = false;
  Map<String, dynamic>? _currentPlaylist;
  Set<String> _selectedPlaylistVideos = {};

  int _downloadType = 0; // 0: Video, 1: Audio
  String _selectedQuality = '720p';
  String _selectedAudioQuality = 'High';

  final List<String> _videoQualities = ['1080p', '720p', '480p', '360p'];
  final List<String> _audioQualities = ['High', 'Medium', 'Low'];

  Future<void> _analyzeUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || !_downloader.isValidYouTubeUrl(url)) {
      _showError('Please enter a valid YouTube URL');
      return;
    }
    
    // Hide keyboard
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _currentVideo = null;
      _currentPlaylist = null;
    });

    try {
      if (_downloader.isPlaylistUrl(url)) {
        final playlist = await _downloader.getPlaylistDetails(url);
        setState(() {
          _isPlaylistMode = true;
          _currentPlaylist = playlist;
          _selectedPlaylistVideos = (playlist['videos'] as List<VideoModel>).map((v) => v.id).toSet();
          _isLoading = false;
        });
      } else {
        final video = await _downloader.getVideoDetails(url);
        setState(() {
          _isPlaylistMode = false;
          _currentVideo = video;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showError('Failed to analyze URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Download Engine'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // URL Input
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: 'Enter Video or Playlist URL',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.link),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search, color: Colors.red),
                  onPressed: _isLoading || _isDownloading ? null : _analyzeUrl,
                ),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // Download Type Selection
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Format Targeting',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTypeOption(
                          icon: Icons.video_library,
                          label: 'Video',
                          isSelected: _downloadType == 0,
                          onTap: () => setState(() => _downloadType = 0),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTypeOption(
                          icon: Icons.audiotrack,
                          label: 'Audio',
                          isSelected: _downloadType == 1,
                          onTap: () => setState(() => _downloadType = 1),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Quality Selection
            if (_downloadType == 0)
              _buildQualitySelector(
                title: 'Video Quality Requirement',
                value: _selectedQuality,
                values: _videoQualities,
                onChanged: (value) => setState(() => _selectedQuality = value),
              )
            else
              _buildQualitySelector(
                title: 'Audio Quality Component',
                value: _selectedAudioQuality,
                values: _audioQualities,
                onChanged: (value) =>
                    setState(() => _selectedAudioQuality = value),
              ),

            const SizedBox(height: 24),

            // Download Button
            ElevatedButton(
              onPressed: _isLoading || _isDownloading ? null : _startDownloadNetwork,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                _isLoading
                    ? 'Fetching Metadata...'
                    : _isDownloading
                        ? 'Processing Queue...'
                        : 'Initiate Download',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),

            if (_isDownloading) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(_downloadStatus, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _downloadProgress,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                    ),
                    const SizedBox(height: 8),
                    Text("${(_downloadProgress * 100).toStringAsFixed(1)}%", style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],

            if (_currentVideo != null) ...[
              const SizedBox(height: 24),
              _buildVideoInfo(),
            ],
            
            if (_currentPlaylist != null) ...[
              const SizedBox(height: 24),
              _buildPlaylistUI(),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildTypeOption({
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
          border: Border.all(
            color: isSelected ? Colors.red : Colors.grey[400]!,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey[700],
              size: 24,
            ),
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

  Widget _buildQualitySelector({
    required String title,
    required String value,
    required List<String> values,
    required Function(String) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: values.map((quality) {
              final isSelected = quality == value;
              return FilterChip(
                label: Text(quality),
                selected: isSelected,
                onSelected: (_) => onChanged(quality),
                backgroundColor: Colors.grey[200],
                selectedColor: Colors.red,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Target Payload',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  _currentVideo!.thumbnailUrl,
                  width: 80,
                  height: 60,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentVideo!.title,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentVideo!.author,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Duration: ${_currentVideo!.duration}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildPlaylistUI() {
    final title = _currentPlaylist!['title'];
    final author = _currentPlaylist!['author'];
    final videos = _currentPlaylist!['videos'] as List<VideoModel>;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        color: Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Playlist Analysis',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 16),
              ),
              Text(
                "${_selectedPlaylistVideos.length} / ${videos.length} selected",
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
              )
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          Text("By $author", style: const TextStyle(color: Colors.grey)),
          const Divider(),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: videos.length,
            itemBuilder: (context, index) {
              final video = videos[index];
              final isSelected = _selectedPlaylistVideos.contains(video.id);
              return CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: isSelected,
                activeColor: Colors.blue,
                title: Text(video.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                subtitle: Text(video.duration, style: const TextStyle(fontSize: 12)),
                onChanged: (bool? checked) {
                  setState(() {
                    if (checked == true) {
                      _selectedPlaylistVideos.add(video.id);
                    } else {
                      _selectedPlaylistVideos.remove(video.id);
                    }
                  });
                },
              );
            },
          )
        ],
      ),
    );
  }

  Future<void> _startDownloadNetwork() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || !_downloader.isValidYouTubeUrl(url)) {
      _showError('Please enter a valid YouTube URL');
      return;
    }

    if (_isPlaylistMode && _currentPlaylist != null) {
      final videos = (_currentPlaylist!['videos'] as List<VideoModel>)
          .where((v) => _selectedPlaylistVideos.contains(v.id))
          .toList();
          
      if (videos.isEmpty) {
        _showError('No videos selected in the playlist!');
        return;
      }
      
      await _executeBatchQueue(videos);
    } else if (_currentVideo != null && _currentVideo!.id == _downloader.extractVideoId(url)) {
      await _executeSingleDownload(url, _currentVideo!);
    } else {
      // Analyze the newly pasted URL first before downloading immediately
      await _analyzeUrl();
      if (_isPlaylistMode && _currentPlaylist != null) {
        _startDownloadNetwork(); // recurse into block above
      } else if (_currentVideo != null) {
        await _executeSingleDownload(url, _currentVideo!);
      }
    }
  }
  
  Future<void> _executeBatchQueue(List<VideoModel> videos) async {
    setState(() {
      _isDownloading = true;
    });

    int successes = 0;
    for (int i = 0; i < videos.length; i++) {
        final video = videos[i];
        try {
          setState(() {
            _downloadStatus = 'Batch Queue: [${i + 1} / ${videos.length}]\nDownloading ${video.title}';
            _downloadProgress = 0.0;
          });
          
          final targetUrl = 'https://youtube.com/watch?v=${video.id}';
          
          if (_downloadType == 0) {
            await _downloader.downloadVideo(targetUrl, _selectedQuality, (progress, status) {
              if (mounted) setState(() => _downloadProgress = progress);
            });
          } else {
            await _downloader.downloadAudio(targetUrl, _selectedAudioQuality, (progress, status) {
              if (mounted) setState(() => _downloadProgress = progress);
            });
          }
          successes++;
        } catch (e) {
          // Log failure and continue to next item in queue!
          if (mounted) _showError("Failed to fetch ${video.title}: $e");
          await Future.delayed(const Duration(seconds: 2));
        }
    }

    setState(() {
      _isDownloading = false;
    });
    
    _showSuccess('Batch queue completed! Evaluated ${videos.length} tasks ($successes succeeded).');
  }

  Future<void> _executeSingleDownload(String url, VideoModel meta) async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = 'Starting download...';
    });

    try {
      if (_downloadType == 0) {
        await _downloader.downloadVideo(
          url,
          _selectedQuality,
          (progress, status) {
            if (mounted) setState(() {
              _downloadProgress = progress;
              _downloadStatus = status;
            });
          },
        );
      } else {
        await _downloader.downloadAudio(
          url,
          _selectedAudioQuality,
          (progress, status) {
             if (mounted) setState(() {
              _downloadProgress = progress;
              _downloadStatus = status;
            });
          },
        );
      }

      setState(() => _isDownloading = false);
      _showSuccess('Download completed successfully!');
    } catch (e) {
      if (mounted) setState(() => _isDownloading = false);
      _showError('Download failed: $e');
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
    _urlController.dispose();
    _downloader.dispose();
    super.dispose();
  }
}
