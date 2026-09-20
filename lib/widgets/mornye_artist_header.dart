import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/theme/cover_palette.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/services/shell_navigation_service.dart';
import 'package:spotiflac_android/widgets/album_detail_header.dart';

/// Share the same artwork-derived dark surface while loading and after the
/// artist metadata arrives, including when the app itself uses light mode.
class MornyeArtistSurface extends StatefulWidget {
  const MornyeArtistSurface({
    super.key,
    required this.imageSource,
    required this.child,
    this.neutralActions = false,
  });

  final String? imageSource;
  final Widget child;

  /// Album and playlist actions use white controls over the artwork tint.
  final bool neutralActions;

  @override
  State<MornyeArtistSurface> createState() => _MornyeArtistSurfaceState();
}

class _MornyeArtistSurfaceState extends State<MornyeArtistSurface> {
  @override
  void dispose() {
    ShellNavigationService.clearChromeBrightness(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final darkTheme = MornyeTheme.build(Brightness.dark);
    return Theme(
      data: darkTheme.copyWith(
        colorScheme: darkTheme.colorScheme.copyWith(primary: Colors.grey),
      ),
      child: CoverPaletteBuilder(
        imageSource: widget.imageSource,
        builder: (context, palette) {
          // Retain the artwork's hue with a muted, slightly lifted surface.
          // Large backgrounds need less saturation than the cover's accent.
          final dominant = HSLColor.fromColor(palette.primary);
          final surface = dominant
              .withSaturation((dominant.saturation * 0.45).clamp(0.0, 0.22))
              .withLightness(0.34)
              .toColor();
          final route = ModalRoute.of(context);
          if (route != null) {
            ShellNavigationService.setChromeBrightness(
              owner: this,
              route: route,
              brightness: Brightness.dark,
              surface: surface,
            );
          }
          return Theme(
            data: darkTheme.copyWith(
              scaffoldBackgroundColor: surface,
              colorScheme: darkTheme.colorScheme.copyWith(
                primary: widget.neutralActions ? Colors.white : palette.primary,
                onPrimary: widget.neutralActions ? surface : palette.onPrimary,
                onSurfaceVariant: widget.neutralActions ? Colors.white70 : null,
                surface: surface,
                surfaceContainer: Color.alphaBlend(
                  Colors.white.withValues(alpha: 0.08),
                  surface,
                ),
                surfaceContainerHigh: Color.alphaBlend(
                  Colors.white.withValues(alpha: 0.12),
                  surface,
                ),
              ),
            ),
            child: widget.child,
          );
        },
      ),
    );
  }
}

/// Portrait and centered identity from Mornye's MobileArtistView. Actions stay
/// supplied by the screen so remote artists retain download/favorite behavior.
class MornyeArtistHeader extends StatelessWidget {
  const MornyeArtistHeader({
    super.key,
    required this.name,
    required this.artwork,
    required this.actions,
    required this.showTitle,
    this.listeners,
    this.logoUrl,
  });

  final String name;
  final Widget artwork;
  final List<Widget> actions;
  final bool showTitle;
  final String? listeners;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) =>
      SliverMainAxisGroup(slivers: buildSlivers(context));

  List<Widget> buildSlivers(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return [
      // Padding changes while the shell folds. Keep that dependency on the
      // toolbar so callers do not rebuild the artist's entire discography.
      Builder(
        builder: (context) => SliverAppBar(
          pinned: true,
          expandedHeight: 342 - MediaQuery.paddingOf(context).top,
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          leadingWidth: 64,
          leading: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: HeaderCircleButton(
              icon: Icons.arrow_back,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.pop(context),
            ),
          ),
          title: AnimatedOpacity(
            opacity: showTitle ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.pin,
            background: _ArtistCollapsingArtwork(
              surface: surface,
              child: artwork,
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
          child: Column(
            children: [
              _buildIdentity(),
              if (listeners != null) ...[
                const SizedBox(height: 7),
                Text(
                  listeners!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 24,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildIdentity() {
    final fallback = Text(
      name,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
    final logo = logoUrl?.trim();
    if (logo == null || logo.isEmpty) return fallback;
    return Semantics(
      label: name,
      image: true,
      excludeSemantics: true,
      child: CachedNetworkImage(
        imageUrl: logo,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        imageBuilder: (_, provider) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320, maxHeight: 124),
          child: Image(image: provider, fit: BoxFit.contain),
        ),
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}

/// Follow the sliver's actual collapse extent so scrolling back restores the
/// same artwork immediately, without a timer or rebuilding the discography.
class _ArtistCollapsingArtwork extends ConsumerWidget {
  const _ArtistCollapsingArtwork({required this.surface, required this.child});

  final Color surface;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final range = settings == null
        ? 0.0
        : settings.maxExtent - settings.minExtent;
    final collapse = range <= 0
        ? 0.0
        : ((settings!.maxExtent - settings.currentExtent) / range).clamp(
            0.0,
            1.0,
          );
    final fade = const Interval(
      0.30,
      0.88,
      curve: Curves.easeInOut,
    ).transform(collapse);
    final blur = 18 * Curves.easeOut.transform(collapse);
    final blurEnabled =
        !MediaQuery.disableAnimationsOf(context) &&
        (!ref.watch(lowEndDeviceProvider) ||
            ref.watch(backdropBlurEnabledProvider));

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          TickerMode(
            enabled: fade < 1,
            child: ImageFiltered(
              enabled: blurEnabled && blur > 0 && fade < 1,
              imageFilter: ImageFilter.blur(
                sigmaX: blur,
                sigmaY: blur,
                tileMode: TileMode.clamp,
              ),
              child: RepaintBoundary(child: child),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.52, 1],
                colors: [
                  Colors.black.withValues(alpha: 0.15),
                  surface.withValues(alpha: 0),
                  surface,
                ],
              ),
            ),
          ),
          ColoredBox(
            key: const ValueKey('artist-artwork-fade'),
            color: surface.withValues(alpha: fade),
          ),
        ],
      ),
    );
  }
}
