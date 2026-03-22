import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/local_share_service.dart';
import '../models/download_item.dart';

class QrShareScreen extends StatefulWidget {
  final DownloadItem item;

  const QrShareScreen({Key? key, required this.item}) : super(key: key);

  @override
  State<QrShareScreen> createState() => _QrShareScreenState();
}

class _QrShareScreenState extends State<QrShareScreen> {
  final LocalShareService _shareService = LocalShareService();
  String? _shareUrl;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startSharing();
  }

  Future<void> _startSharing() async {
    final file = File(widget.item.localFilePath);
    if (!await file.exists()) {
      setState(() {
        _error = "File does not exist on your device.";
        _isLoading = false;
      });
      return;
    }

    final url = await _shareService.startSharingFile(file);
    if (url != null) {
      final payload = jsonEncode({
        'u': url,
        't': widget.item.title,
        'i': widget.item.thumbnailUrl,
        'd': widget.item.duration,
        'tp': widget.item.type, // 'audio' or 'video'
      });

      if (mounted) {
        setState(() {
          _shareUrl = payload;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() {
        _error = "Failed to start local server. Are you connected to WiFi?";
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _shareService.stopSharing();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share File Offset'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 16), textAlign: TextAlign.center),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Scan this QR Code\nfrom another device on the same WiFi!",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 30),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ]
                        ),
                        child: QrImageView(
                          data: _shareUrl!,
                          version: QrVersions.auto,
                          size: 250.0,
                        ),
                      ),
                      const SizedBox(height: 30),
                      Text("Currently Sharing:", style: TextStyle(color: Colors.grey[600])),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          widget.item.title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Keep this screen open until the receiver finishes downloading.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
      ),
    );
  }
}
