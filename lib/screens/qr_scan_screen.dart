import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import '../main.dart';
import '../models/download_item.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _status = "Scanning for QR Code...";
  int _currentItemIndex = 0;
  int _totalItems = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_isDownloading) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? rawValue = barcodes.first.rawValue;
      if (rawValue != null) {
        _scannerController.stop(); // Stop scanning to prevent overlapping triggers
        await _processPayload(rawValue);
      }
    }
  }

  Future<void> _processPayload(String rawValue) async {
    try {
      if (rawValue.startsWith('{')) {
        // It's a structured JSON payload
        final data = jsonDecode(rawValue);
        final url = data['u'] as String?;
        final isMulti = data['m'] == true;

        if (url != null && url.startsWith('http')) {
          if (isMulti) {
            await _downloadMultipleFiles(url);
          } else {
            // Legacy support for single-file payloads
            final title = data['t'] as String? ?? 'Shared File';
            final thumb = data['i'] as String? ?? '';
            final duration = data['d'] as String? ?? 'Unknown';
            final type = data['tp'] as String? ?? 'video';
            
            setState(() {
              _totalItems = 1;
              _currentItemIndex = 1;
            });
            await _downloadSingleFile(url, title, thumb, duration, type);
            _showSuccess();
          }
        }
      } else if (rawValue.startsWith('http')) {
        // Legacy generic URL
        setState(() {
          _totalItems = 1;
          _currentItemIndex = 1;
        });
        await _downloadSingleFile(rawValue, 'Received File ${DateTime.now().millisecondsSinceEpoch}', '', 'Unknown', 'video');
        _showSuccess();
      }
    } catch (e) {
      if (mounted && !_isDownloading) {
        _scannerController.start(); // Restart if crashed
      }
    }
  }

  Future<void> _downloadMultipleFiles(String baseUrl) async {
    setState(() {
      _isDownloading = true;
      _status = "Connecting to sender...";
      _downloadProgress = 0.0;
    });

    try {
      final dio = Dio();
      
      // 1. Fetch manifest
      final manifestResponse = await dio.get('$baseUrl/manifest');
      final List<dynamic> manifest = manifestResponse.data;

      if (manifest.isEmpty) {
        throw Exception("Manifest is empty. No files to download.");
      }

      setState(() {
        _totalItems = manifest.length;
      });

      // 2. Loop and download
      for (int i = 0; i < manifest.length; i++) {
        setState(() {
          _currentItemIndex = i + 1;
          _downloadProgress = 0.0;
          _status = "Downloading $_currentItemIndex of $_totalItems...";
        });

        final itemData = manifest[i];
        final title = itemData['t'] as String? ?? 'Shared File $i';
        final thumb = itemData['i'] as String? ?? '';
        final duration = itemData['d'] as String? ?? '0:00';
        final type = itemData['tp'] as String? ?? 'audio';
        final downloadUrl = '$baseUrl/download/$i';

        await _downloadSingleFile(downloadUrl, title, thumb, duration, type);
      }

      _showSuccess();
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = "Failed to download playlist: $e";
          _isDownloading = false;
        });
        _scannerController.start(); // Restart scanner so they can try again
      }
    }
  }

  Future<void> _downloadSingleFile(String downloadUrl, String title, String thumb, String duration, String type) async {
    final dio = Dio();
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = type == 'audio' ? 'mp3' : 'mp4';
    final savePath = '${dir.path}/shared_file_$timestamp.$ext';
    
    await dio.download(
      downloadUrl,
      savePath,
      onReceiveProgress: (received, total) {
        if (total != -1 && mounted) {
          setState(() {
            _downloadProgress = received / total;
            if (_totalItems > 1) {
              _status = "Downloading $_currentItemIndex of $_totalItems... (${(_downloadProgress * 100).toInt()}%)";
            } else {
              _status = "Receiving file from sender...";
            }
          });
        }
      },
    );

    // Save to local database so it appears in DownloadsScreen
    final item = DownloadItem()
      ..youtubeId = 'shared_$timestamp'
      ..title = title
      ..url = downloadUrl // We keep the local URL for reference
      ..localFilePath = savePath
      ..thumbnailUrl = thumb
      ..duration = duration
      ..status = 'completed'
      ..type = type
      ..downloadedAt = DateTime.now();
      
    await isarService.saveDownloadItem(item);
  }

  void _showSuccess() {
    if (!mounted) return;

    setState(() {
      _status = "Download Complete!";
      _downloadProgress = 1.0;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Success"),
        content: Text("Successfully received $_totalItems media file${_totalItems > 1 ? 's' : ''}!"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Close screen
            },
            child: const Text("OK"),
          )
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive Shared Media'),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: _isDownloading
                ? Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.cloud_download, color: Colors.red, size: 80),
                          const SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: LinearProgressIndicator(
                              value: _downloadProgress,
                              backgroundColor: Colors.grey.withAlpha(50),
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            "${(_downloadProgress * 100).toStringAsFixed(1)}%",
                            style: TextStyle(
                              color: Theme.of(context).textTheme.bodyLarge?.color,
                              fontSize: 24, 
                              fontWeight: FontWeight.bold
                            ),
                          )
                        ],
                      ),
                    ),
                  )
                : MobileScanner(
                    controller: _scannerController,
                    onDetect: _handleBarcode,
                  ),
          ),
          Container(
            height: 120,
            width: double.infinity,
            color: Theme.of(context).cardColor,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16, 
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                if (_isDownloading && _downloadProgress < 1.0) ...[
                  const SizedBox(height: 8),
                  const Text("Please keep the app open and stay on the same WiFi.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ],
            ),
          )
        ],
      ),
    );
  }
}
