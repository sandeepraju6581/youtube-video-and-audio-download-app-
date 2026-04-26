import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/download_item.dart';

/// Custom AudioHandler that bridges just_audio → audio_service.
/// audio_service uses this to drive the OS media notification.
class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  // Expose the player so the UI can observe streams directly
  AudioPlayer get player => _player;

  // Queue Management
  List<DownloadItem> _customQueue = [];
  int _currentIndex = -1;
  bool _isShuffle = false;
  bool _isLoop = false;

  List<DownloadItem> get customQueue => _customQueue;
  int get currentIndex => _currentIndex;
  bool get isShuffle => _isShuffle;
  bool get isLoop => _isLoop;

  // Stream controllers to broadcast queue state changes
  final _queueStateController = StreamController<void>.broadcast();
  Stream<void> get queueStateStream => _queueStateController.stream;

  MyAudioHandler() {
    // Forward player state → audio_service playbackState
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Update duration in MediaItem when just_audio loads it
    // Android requires duration to display the progress bar in the notification
    _player.durationStream.listen((duration) {
      final currentItem = mediaItem.value;
      if (currentItem != null && duration != null) {
        mediaItem.add(currentItem.copyWith(duration: duration));
      }
    });

    // Listen to completed state to play next
    playbackState.listen((state) {
      if (state.processingState == AudioProcessingState.completed) {
        skipToNext();
      }
    });
  }

  void _notifyQueueState() {
    _queueStateController.add(null);
  }

  // ── Notification button actions ──────────────────────────────────────

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    _currentIndex = -1;
    _customQueue.clear();
    mediaItem.add(null);
    _notifyQueueState();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_customQueue.isEmpty || _currentIndex < 0) return;

    int nextIndex;
    if (_isShuffle) {
      do {
        nextIndex = Random().nextInt(_customQueue.length);
      } while (_customQueue.length > 1 && nextIndex == _currentIndex);
    } else {
      nextIndex = _currentIndex + 1;
      if (nextIndex >= _customQueue.length) {
        if (_isLoop) {
          nextIndex = 0;
        } else {
          return;
        }
      }
    }

    _currentIndex = nextIndex;
    _notifyQueueState();
    await _playCurrentIndex();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }

    if (_customQueue.isEmpty || _currentIndex < 0) return;

    int prevIndex;
    if (_isShuffle) {
      do {
        prevIndex = Random().nextInt(_customQueue.length);
      } while (_customQueue.length > 1 && prevIndex == _currentIndex);
    } else {
      prevIndex = _currentIndex - 1;
      if (prevIndex < 0) {
        prevIndex = _isLoop ? _customQueue.length - 1 : 0;
      }
    }

    _currentIndex = prevIndex;
    _notifyQueueState();
    await _playCurrentIndex();
  }

  // ── Queue & State Management ──────────────────────────────────────────

  Future<void> playQueue(List<DownloadItem> newQueue, {int initialIndex = 0}) async {
    _customQueue = List.from(newQueue);
    _currentIndex = initialIndex;
    _notifyQueueState();
    await _playCurrentIndex();
  }

  Future<void> toggleShuffle() async {
    _isShuffle = !_isShuffle;
    _notifyQueueState();
  }

  Future<void> toggleLoop() async {
    _isLoop = !_isLoop;
    await _player.setLoopMode(_isLoop ? LoopMode.one : LoopMode.off);
    _notifyQueueState();
  }

  Future<void> _playCurrentIndex() async {
    if (_currentIndex < 0 || _currentIndex >= _customQueue.length) return;

    final item = _customQueue[_currentIndex];
    final file = File(item.localFilePath);
    if (!await file.exists()) {
      return; // Skip if file not found
    }

    final mItem = MediaItem(
      id: item.id.toString(),
      title: item.title,
      artist: 'Downloaded Audio',
      artUri: item.thumbnailUrl.isNotEmpty ? Uri.tryParse(item.thumbnailUrl) : null,
    );

    await _playFromMediaItem(Uri.file(item.localFilePath), mItem);
  }

  // ── Load a track ────────────────────────────────────────────────────

  /// Load and play a local file URI, broadcasting mediaItem to notification.
  Future<void> _playFromMediaItem(Uri uri, MediaItem item) async {
    // Broadcast track metadata → notification shows title / artwork
    mediaItem.add(item);

    try {
      await _player.setLoopMode(_isLoop ? LoopMode.one : LoopMode.off);
      await _player.setAudioSource(AudioSource.uri(uri));
      await _player.play();
    } on PlayerInterruptedException {
      // Expected when switching tracks quickly — safe to ignore
    }
  }

  // ── Transform just_audio event → audio_service PlaybackState ────────

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        _player.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle:      AudioProcessingState.idle,
        ProcessingState.loading:   AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready:     AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _currentIndex,
    );
  }

  Future<void> disposePlayer() async {
    await _player.dispose();
    _queueStateController.close();
  }
}
