import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:nfc_manager/nfc_manager.dart';
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
  bool _nfcWritten = false;

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

  Future<void> _writeToNfc() async {
    if (_shareUrl == null) return;

    // Check availability
    bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('NFC is not available on this device.')),
        );
      }
      return;
    }

    // Show dialog to prompt user to tap tag
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Ready to Write'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.nfc, size: 64, color: Colors.blue),
            SizedBox(height: 16),
            Text('Hold your NFC tag near the back of your device.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              NfcManager.instance.stopSession();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    // Start Session
    NfcManager.instance.startSession(onDiscovered: (NfcTag tag) async {
      var ndef = Ndef.from(tag);
      if (ndef == null || !ndef.isWritable) {
        NfcManager.instance.stopSession(errorMessage: 'Tag is not writable.');
        return;
      }

      NdefMessage message = NdefMessage([
        NdefRecord.createText(_shareUrl!),
        NdefRecord(
          typeNameFormat: NdefTypeNameFormat.nfcExternal,
          type: Uint8List.fromList('android.com:pkg'.codeUnits),
          identifier: Uint8List.fromList([]),
          payload: Uint8List.fromList('com.example.videodownloader'.codeUnits),
        ),
      ]);

      try {
        await ndef.write(message);
        NfcManager.instance.stopSession();
        if (mounted) {
          Navigator.pop(context); // Close "Ready to Write" dialog
          setState(() {
            _nfcWritten = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Successfully wrote to NFC tag!')),
          );
        }
      } catch (e) {
        NfcManager.instance.stopSession(errorMessage: 'Write failed: $e');
      }
    });
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
                          "Scan this QR Code or tap your written NFC tag\nfrom another device on the same WiFi!",
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
                        const SizedBox(height: 24),
                        if (_nfcWritten)
                          Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.green.withAlpha(30),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, color: Colors.green),
                                SizedBox(width: 8),
                                Text(
                                  "NFC Tag is ready to share!",
                                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ElevatedButton.icon(
                          onPressed: _isLoading || _error != null ? null : _writeToNfc,
                          icon: const Icon(Icons.nfc),
                          label: Text(_nfcWritten ? 'Rewrite NFC Tag' : 'Write to NFC Tag'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
      ),
    );
  }
}
