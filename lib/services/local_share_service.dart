import 'dart:io';
import 'dart:developer';
import 'dart:convert';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import '../models/download_item.dart';

class LocalShareService {
  HttpServer? _server;

  /// Starts a local HTTP server that serves a dynamic list of files.
  /// Returns the base URL (e.g. http://192.168.1.5:8080) that the receiver should hit.
  Future<String?> startSharingItems(List<DownloadItem> items) async {
    try {
      if (_server != null) {
        await stopSharing();
      }

      final info = NetworkInfo();
      String? ip = await info.getWifiIP();
      
      if (ip == null) {
        throw Exception("Could not determine Local WiFi IP. Please ensure you are connected to a WiFi network.");
      }

      Future<Response> handler(Request request) async {
        if (request.method != 'GET') {
          return Response.notFound('Not found');
        }

        final path = request.url.path;

        // 1. Manifest Endpoint
        // Returns a JSON list of all the files available for download
        if (path == 'manifest') {
          final manifest = items.map((item) => {
            't': item.title,
            'i': item.thumbnailUrl,
            'd': item.duration,
            'tp': item.type,
          }).toList();
          
          return Response.ok(
            jsonEncode(manifest),
            headers: {HttpHeaders.contentTypeHeader: 'application/json'},
          );
        }

        // 2. File Download Endpoint
        // /download/0, /download/1, etc.
        if (path.startsWith('download/')) {
          final indexStr = path.replaceFirst('download/', '');
          final index = int.tryParse(indexStr);

          if (index != null && index >= 0 && index < items.length) {
            final file = File(items[index].localFilePath);
            if (await file.exists()) {
              final size = await file.length();
              final ext = items[index].type == 'video' ? 'mp4' : 'mp3';
              final contentType = ext == 'mp4' ? 'video/mp4' : 'audio/mpeg';

              final headers = {
                HttpHeaders.contentTypeHeader: contentType,
                HttpHeaders.contentLengthHeader: size.toString(),
                'Content-Disposition': 'attachment; filename="shared_$index.$ext"',
              };

              return Response.ok(
                file.openRead(),
                headers: headers,
              );
            }
          }
        }

        return Response.notFound('Not found');
      }

      // Bind to the local IP on port 8080
      _server = await io.serve(handler, ip, 8080);
      return 'http://$ip:8080';
    } catch (e) {
      log('Error starting local server: $e');
      return null;
    }
  }

  Future<void> stopSharing() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
    }
  }
}
