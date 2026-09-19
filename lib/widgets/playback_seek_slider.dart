import 'package:flutter/material.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/mornye_player_slider.dart';

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
    if (context.isMornye) {
      final currentMs = (_previewMs ?? widget.position.inMilliseconds)
          .clamp(0, maxMs)
          .toDouble();
      String percentage(double milliseconds) =>
          '${(milliseconds / maxMs * 100).clamp(0, 100).round()}%';
      return LayoutBuilder(
        builder: (context, constraints) => Semantics(
          slider: true,
          enabled: enabled,
          excludeSemantics: true,
          value: percentage(currentMs),
          increasedValue: enabled
              ? percentage((currentMs + 5000).clamp(0, maxMs).toDouble())
              : null,
          decreasedValue: enabled
              ? percentage((currentMs - 5000).clamp(0, maxMs).toDouble())
              : null,
          onIncrease: enabled
              ? () => _commit((currentMs + 5000).clamp(0, maxMs).toDouble())
              : null,
          onDecrease: enabled
              ? () => _commit((currentMs - 5000).clamp(0, maxMs).toDouble())
              : null,
          child: IgnorePointer(
            ignoring: !enabled,
            child: MornyePlayerSlider(
              value: enabled ? currentMs : 0,
              max: maxMs,
              onChangeStart: (_) => _gestureGeneration++,
              onChanged: (value) => setState(() => _previewMs = value),
              onChangeEnd: _commit,
            ),
          ),
        ),
      );
    }
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
