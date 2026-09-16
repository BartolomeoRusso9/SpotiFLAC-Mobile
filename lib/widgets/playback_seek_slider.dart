import 'package:flutter/material.dart';

/// Previews scrubbing locally and seeks once when the gesture ends.
class PlaybackSeekSlider extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Future<void> Function(Duration) onSeek;

  const PlaybackSeekSlider({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  @override
  State<PlaybackSeekSlider> createState() => _PlaybackSeekSliderState();
}

class _PlaybackSeekSliderState extends State<PlaybackSeekSlider> {
  double? _previewMs;
  int _gestureGeneration = 0;

  Future<void> _commit(double value) async {
    final generation = _gestureGeneration;
    try {
      await widget.onSeek(Duration(milliseconds: value.round()));
    } finally {
      if (mounted && generation == _gestureGeneration) {
        setState(() => _previewMs = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final durationMs = widget.duration.inMilliseconds;
    final enabled = durationMs > 0;
    final maxMs = enabled ? durationMs.toDouble() : 1.0;
    return Slider(
      value: enabled
          ? (_previewMs ?? widget.position.inMilliseconds.toDouble()).clamp(
              0,
              maxMs,
            )
          : 0,
      max: maxMs,
      onChangeStart: enabled ? (_) => _gestureGeneration++ : null,
      onChanged: enabled ? (value) => setState(() => _previewMs = value) : null,
      onChangeEnd: enabled ? _commit : null,
    );
  }
}
