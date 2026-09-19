import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/motion_header_banner.dart';
import 'package:spotiflac_android/widgets/player_artwork.dart';

class MornyePlayerArtwork extends StatelessWidget {
  const MornyePlayerArtwork({
    super.key,
    required this.mediaItem,
    this.videoUrl,
    this.onAspectRatioChanged,
    this.onError,
  });

  final MediaItem mediaItem;
  final String? videoUrl;
  final ValueChanged<double>? onAspectRatioChanged;
  final VoidCallback? onError;

  @override
  Widget build(BuildContext context) {
    final fallback = Align(
      alignment: Alignment.topCenter,
      child: AspectRatio(
        aspectRatio: 1,
        child: PlayerArtwork(
          artUri: mediaItem.artUri?.toString(),
          colorScheme: Theme.of(context).colorScheme,
          cacheWidth:
              (MediaQuery.sizeOf(context).width *
                      MediaQuery.devicePixelRatioOf(context))
                  .round(),
        ),
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return fallback;
    return videoUrl == null
        ? fallback
        : MotionHeaderBanner(
            key: ValueKey(videoUrl),
            videoUrl: videoUrl!,
            fallback: fallback,
            onAspectRatioChanged: onAspectRatioChanged,
            onError: onError,
          );
  }
}
