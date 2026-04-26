import 'package:flutter/material.dart';
import '../models/video_model.dart';

class DownloadProgressDialog extends StatelessWidget {
  final double progress;
  final String status;
  final String? fileName;
  final VoidCallback? onCancel;

  const DownloadProgressDialog({
    super.key,
    required this.progress,
    required this.status,
    this.fileName,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Downloading'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fileName != null) ...[
            Text(
              fileName!,
              style: const TextStyle(fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
          ],
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey[300],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
          ),
          const SizedBox(height: 12),
          Text(
            '${(progress * 100).toStringAsFixed(1)}%',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            status,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        if (onCancel != null)
          TextButton(
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
      ],
    );
  }
}

class DownloadTaskItem extends StatelessWidget {
  final VideoModel video;
  final double progress;
  final DownloadStatus status;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onOpen;

  const DownloadTaskItem({
    super.key,
    required this.video,
    required this.progress,
    required this.status,
    this.onCancel,
    this.onRetry,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(
            video.thumbnailUrl,
            width: 50,
            height: 50,
            fit: BoxFit.cover,
          ),
        ),
        title: Text(
          video.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              video.author,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            _buildStatusWidget(),
          ],
        ),
        trailing: _buildActionButtons(),
      ),
    );
  }

  Widget _buildStatusWidget() {
    switch (status) {
      case DownloadStatus.downloading:
        return Column(
          children: [
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[300],
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
            ),
            const SizedBox(height: 4),
            Text(
              '${(progress * 100).toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        );
      case DownloadStatus.completed:
        return const Text(
          'Completed',
          style: TextStyle(color: Colors.green, fontSize: 12),
        );
      case DownloadStatus.failed:
        return const Text(
          'Failed',
          style: TextStyle(color: Colors.red, fontSize: 12),
        );
      case DownloadStatus.cancelled:
        return const Text(
          'Cancelled',
          style: TextStyle(color: Colors.orange, fontSize: 12),
        );
      default:
        return const Text(
          'Pending',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        );
    }
  }

  Widget? _buildActionButtons() {
    switch (status) {
      case DownloadStatus.downloading:
        return IconButton(
          icon: const Icon(Icons.cancel, color: Colors.red),
          onPressed: onCancel,
        );
      case DownloadStatus.failed:
        return IconButton(
          icon: const Icon(Icons.refresh, color: Colors.green),
          onPressed: onRetry,
        );
      case DownloadStatus.completed:
        return IconButton(
          icon: const Icon(Icons.folder_open, color: Colors.blue),
          onPressed: onOpen,
        );
      default:
        return null;
    }
  }
}
