import 'package:flutter/material.dart';
import 'package:spotiflac_android/theme/cover_palette.dart';

/// Opaque cover-derived surface, with full-bleed artwork on the player page
/// and a muted two-tone gradient behind lyrics and the queue.
class MornyePlayerBackground extends StatelessWidget {
  const MornyePlayerBackground({
    super.key,
    required this.artUri,
    this.artwork,
    this.squareArtwork = true,
    this.artworkAspectRatio,
  });

  final Uri? artUri;
  final Widget? artwork;
  final bool squareArtwork;
  final double? artworkAspectRatio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = artUri?.scheme == 'file'
        ? artUri!.toFilePath()
        : artUri?.toString();

    return Theme(
      // Missing or unreadable covers use neutral gray, not the app's accent.
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          brightness: Brightness.dark,
          primary: const Color(0xff808080),
        ),
      ),
      child: CoverPaletteBuilder(
        imageSource: source,
        builder: (context, scheme) {
          final dominant = HSLColor.fromColor(scheme.primary);
          final muted = dominant.withSaturation(
            dominant.saturation.clamp(0.0, 0.28),
          );
          final motion = MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 380);
          return AnimatedContainer(
            duration: motion,
            curve: Curves.easeInOutCubic,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  muted.withLightness(artwork == null ? 0.28 : 0.10).toColor(),
                  muted.withLightness(artwork == null ? 0.15 : 0.10).toColor(),
                ],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: artworkAspectRatio != null && artworkAspectRatio! > 0
                      ? (MediaQuery.sizeOf(context).width / artworkAspectRatio!)
                            .clamp(
                              0.0,
                              MediaQuery.sizeOf(context).height * 0.75,
                            )
                      : squareArtwork
                      ? MediaQuery.sizeOf(context).width
                      : MediaQuery.sizeOf(context).height * 0.66,
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.58, 1],
                      colors: [Colors.white, Colors.white, Colors.transparent],
                    ).createShader(bounds),
                    child: HeroMode(
                      // The compact header owns the route hero while the
                      // full cover is fading out behind the lyrics.
                      enabled: artwork != null,
                      child: AnimatedSwitcher(
                        duration: motion,
                        switchInCurve: Curves.easeInOutCubic,
                        switchOutCurve: Curves.easeInOutCubic,
                        layoutBuilder: (current, previous) => Stack(
                          fit: StackFit.expand,
                          children: [
                            for (final child in previous)
                              HeroMode(enabled: false, child: child),
                            ?current,
                          ],
                        ),
                        child: artwork == null
                            ? null
                            : KeyedSubtree(
                                key: const ValueKey('full-player-artwork'),
                                child: artwork!,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
