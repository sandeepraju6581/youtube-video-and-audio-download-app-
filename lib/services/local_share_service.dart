import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

class LocalShareService {
  HttpServer? _server;

  /// Starts a local HTTP server that serves exactly one file to any device on the network.
  /// Returns the full URL (e.g. http://192.168.1.5:8080) that the receiver should hit.
  Future<String?> startSharingFile(File file) async {
    try {
      if (_server != null) {
        await stopSharing();
      }

      final info = NetworkInfo();
      String? ip = await info.getWifiIP();
      
      if (ip == null) {
        throw Exception("Could not determine Local WiFi IP. Please ensure you are connected to a WiFi network.");
      }

      var handler = (Request request) async {
        // We only respond to basic GET requests for the file
        if (request.method != 'GET') {
          return Response.notFound('Not found');
        }

        final size = await file.length();
        final ext = file.path.split('.').last.toLowerCase();
        final contentType = ext == 'mp4' ? 'video/mp4' : 'audio/mpeg';

        // Set headers for file download
        final headers = {
          HttpHeaders.contentTypeHeader: contentType,
          HttpHeaders.contentLengthHeader: size.toString(),
          'Content-Disposition': 'attachment; filename="${file.path.split(Platform.pathSeparator).last}"',
        };

        return Response.ok(
          file.openRead(),
          headers: headers,
        );
      };

      // Bind to the local IP on port 8080
      _server = await io.serve(handler, ip, 8080);
      return 'http://$ip:8080';
    } catch (e) {
      print('Error starting local server: $e');
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
