import 'package:flutter/material.dart';
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
                primary: widget.neutralActions ? Colors.white : null,
                onPrimary: widget.neutralActions ? surface : null,
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
  });

  final String name;
  final Widget artwork;
  final List<Widget> actions;
  final bool showTitle;
  final String? listeners;

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
            background: Stack(
              fit: StackFit.expand,
              children: [
                artwork,
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
              ],
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
          child: Column(
            children: [
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
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
}
