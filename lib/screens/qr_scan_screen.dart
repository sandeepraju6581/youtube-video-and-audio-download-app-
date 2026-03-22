import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import '../main.dart';
import '../models/download_item.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({Key? key}) : super(key: key);

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _status = "Scanning for QR Code...";

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
        
        try {
          if (rawValue.startsWith('{')) {
            // It's a structured JSON payload
            final data = jsonDecode(rawValue);
            final url = data['u'] as String?;
            final title = data['t'] as String? ?? 'Shared File';
            final thumb = data['i'] as String? ?? '';
            final duration = data['d'] as String? ?? 'Unknown';
            if (url != null && url.startsWith('http')) {
              final type = data['tp'] as String? ?? 'video'; // 'audio' or 'video'
              await _downloadFile(url, title, thumb, duration, type);
            }
          } else if (rawValue.startsWith('http')) {
            // Legacy generic URL — infer type from extension
            await _downloadFile(rawValue, 'Received File ${DateTime.now().millisecondsSinceEpoch}', '', 'Unknown', 'video');
          }
        } catch (e) {
          _scannerController.start(); // Restart if crashed
        }
      }
    }
  }

  Future<void> _downloadFile(String url, String title, String thumb, String duration, String type) async {
    setState(() {
      _isDownloading = true;
      _status = "Connecting to sender...";
      _downloadProgress = 0.0;
    });

    try {
      final dio = Dio();
      
      // Determine save path
      final dir = await getApplicationDocumentsDirectory();
      // For shared files without a strict YouTube ID, we will save it generically based on timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = type == 'audio' ? 'mp3' : 'mp4';
      final savePath = '${dir.path}/shared_file_$timestamp.$ext';
      
      await dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _downloadProgress = received / total;
              _status = "Receiving file from sender...";
            });
          }
        },
      );

      // Save to local database so it appears in DownloadsScreen
      final item = DownloadItem()
        ..youtubeId = 'shared_$timestamp'
        ..title = title
        ..url = url // Original local network source URL
        ..localFilePath = savePath
        ..thumbnailUrl = thumb // Embedded thumbnail from sender
        ..duration = duration
        ..status = 'completed'
        ..type = type // Use the type sent by the sender
        ..downloadedAt = DateTime.now();
        
      await isarService.saveDownloadItem(item);

      setState(() {
        _status = "Download Complete!";
        _downloadProgress = 1.0;
      });

      // Show success
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text("Success"),
            content: Text("File successfully received and saved to your Downloads!\n\nPath: $savePath"),
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

    } catch (e) {
      setState(() {
        _status = "Failed to download: $e";
        _isDownloading = false;
      });
      _scannerController.start(); // Restart scanner
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive Shared File'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: _isDownloading
                ? Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.cloud_download, color: Colors.white, size: 80),
                          const SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: LinearProgressIndicator(
                              value: _downloadProgress,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            "${(_downloadProgress * 100).toStringAsFixed(1)}%",
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
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
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (_isDownloading && _downloadProgress < 1.0) ...[
                  const SizedBox(height: 8),
                  const Text("Please keep the app open and stay on the same WiFi.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                ]
              ],
            ),
          )
        ],
      ),
    );
  }
}
