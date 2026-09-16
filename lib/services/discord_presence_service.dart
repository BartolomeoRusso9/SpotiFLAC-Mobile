import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Opt-in Rich Presence, inspired by @itsmegaaa's contribution in #575/#576.
/// Playback remains independent of Discord availability.
class DiscordPresenceService {
  DiscordPresenceService({
    MethodChannel channel = const MethodChannel('com.zarz.spotiflac/discord'),
  }) : _channel = channel {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'status' && _enabled && _transportReady) {
        status.value = call.arguments as String;
      }
    });
  }

  static final instance = DiscordPresenceService();
  final MethodChannel _channel;
  final ValueNotifier<String> status = ValueNotifier('disabled');
  StreamSubscription<MediaItem?>? _mediaSubscription;
  StreamSubscription<PlaybackState>? _stateSubscription;
  MediaItem? _item;
  PlaybackState? _playback;
  bool _enabled = false;
  bool _configured = false;
  bool _transportReady = false;
  int _generation = 0;
  String? _lastPayload;
  int? _lastStart;
  Future<void> _pending = Future.value();

  void bind(AudioHandler handler) {
    unawaited(_mediaSubscription?.cancel());
    unawaited(_stateSubscription?.cancel());
    _mediaSubscription = handler.mediaItem.listen((item) {
      _item = item;
      _publish();
    });
    _stateSubscription = handler.playbackState.listen((state) {
      _playback = state;
      _publish();
    });
  }

  Future<void> setEnabled(bool enabled) {
    if (_configured && _enabled == enabled) return _pending;
    _configured = true;
    _enabled = enabled;
    _transportReady = false;
    final generation = ++_generation;
    _lastPayload = null;
    _lastStart = null;
    _pending = _pending.then((_) async {
      try {
        final result = await _channel.invokeMethod<String>('configure', {
          'enabled': enabled,
        });
        if (generation != _generation) return;
        status.value = result ?? 'unavailable';
        _transportReady = enabled && result == 'ready';
        if (_transportReady) _publish();
      } on PlatformException {
        if (generation == _generation) status.value = 'unavailable';
      } on MissingPluginException {
        if (generation == _generation) status.value = 'sdk_unavailable';
      }
    });
    return _pending;
  }

  void _publish() {
    if (!_enabled || !_transportReady) return;
    final item = _item;
    final playback = _playback;
    final playing =
        item != null &&
        playback != null &&
        playback.playing &&
        playback.processingState == AudioProcessingState.ready;
    final position = playback?.position ?? Duration.zero;
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = now - position.inMilliseconds;
    final payload = playing
        ? <String, Object?>{
            'title': item.title,
            'artist': item.artist ?? '',
            'album': item.album ?? '',
            'cover': item.artUri?.scheme == 'https'
                ? item.artUri.toString()
                : '',
            'start': start,
            'end': item.duration == null
                ? 0
                : start + item.duration!.inMilliseconds,
          }
        : null;
    // Position streams tick frequently. Only republish on track/state changes
    // or a seek that shifts the playback timeline by at least two seconds.
    final key = playing
        ? '${item.id}|${item.title}|${item.artist}|${item.album}|${item.artUri}|${item.duration}'
        : 'clear';
    if (key == _lastPayload &&
        (!playing ||
            (_lastStart != null && (start - _lastStart!).abs() < 2000))) {
      return;
    }
    _lastPayload = key;
    _lastStart = start;
    final generation = _generation;
    _pending = _pending.then((_) async {
      if (!_enabled || generation != _generation) return;
      try {
        await _channel.invokeMethod<void>(
          payload == null ? 'clear' : 'update',
          payload,
        );
      } on PlatformException {
        _lastPayload = null;
      } on MissingPluginException {
        _lastPayload = null;
      }
    });
  }

  Future<void> dispose() async {
    await _mediaSubscription?.cancel();
    await _stateSubscription?.cancel();
    await setEnabled(false);
    _channel.setMethodCallHandler(null);
    status.dispose();
  }
}
