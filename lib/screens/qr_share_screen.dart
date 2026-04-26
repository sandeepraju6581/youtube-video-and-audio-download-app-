import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/local_share_service.dart';
import '../models/download_item.dart';
import '../main.dart'; // To access isarService

class QrShareScreen extends StatefulWidget {
  final List<int> items; // Now takes a list of IDs

  const QrShareScreen({super.key, required this.items});

  @override
  State<QrShareScreen> createState() => _QrShareScreenState();
}

class _QrShareScreenState extends State<QrShareScreen> {
  final LocalShareService _shareService = LocalShareService();
  String? _shareUrl;
  bool _isLoading = true;
  String? _error;
  final List<DownloadItem> _fetchedItems = [];

  @override
  void initState() {
    super.initState();
    _startSharing();
  }

  Future<void> _startSharing() async {
    if (widget.items.isEmpty) {
      if (mounted) {
        setState(() {
          _error = "No items selected.";
          _isLoading = false;
        });
      }
      return;
    }

    // Fetch the full items from the database
    for (var id in widget.items) {
      final item = await isarService.getDownloadItem(id);
      if (item != null) {
        _fetchedItems.add(item);
      }
    }

    if (_fetchedItems.isEmpty) {
      setState(() {
        _error = "Selected files could not be loaded.";
        _isLoading = false;
      });
      return;
    }

    // Filter out files that don't exist anymore
    final validItems = <DownloadItem>[];
    for (var item in _fetchedItems) {
      if (await File(item.localFilePath).exists()) {
        validItems.add(item);
      }
    }

    if (validItems.isEmpty) {
      setState(() {
        _error = "None of the selected files exist on your device.";
        _isLoading = false;
      });
      return;
    }

    // Upgrade: startSharingItems instead of File
    final url = await _shareService.startSharingItems(validItems);
    if (url != null) {
      // The QR code just points to the manifest endpoint instead of massive metadata
      final payload = jsonEncode({
        'u': url,
        'm': true, // Indicates it's a multi-file manifest
      });

      if (mounted) {
        setState(() {
          _shareUrl = payload;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _error = "Failed to start local server. Are you connected to WiFi?";
          _isLoading = false;
        });
      }
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
        title: Text('Share ${_fetchedItems.length} File${_fetchedItems.length > 1 ? 's' : ''}'),
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 16), textAlign: TextAlign.center),
                  )
                : SingleChildScrollView(
                    child: Column(
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
                                color: Colors.black.withAlpha(50),
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
                          child: Column(
                            children: _fetchedItems.take(3).map<Widget>((item) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4.0),
                                child: Text(
                                  "• ${item.title}",
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                              );
                            }).toList()
                              ..addAll([
                                if (_fetchedItems.length > 3)
                                  Text("... and ${_fetchedItems.length - 3} more",
                                      style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
                              ]),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          "Keep this screen open until the receiver finishes downloading.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
      ),
    );
  }
}
