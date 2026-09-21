import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/mini_player.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';

/// Only deliberate vertical drags change the chrome. Horizontal artwork rows,
/// programmatic scrolling and edge bounce must not minimize the navigation.
class MornyeChromeController extends ValueNotifier<bool> {
  MornyeChromeController() : super(false);

  double _distance = 0;

  void expand() {
    _distance = 0;
    value = false;
  }

  bool handleScroll(ScrollNotification notification) {
    // Library's active list sits inside a PageView and NestedScrollView. Its
    // drag notifications have a greater depth than the outer header's scroll.
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification ||
        notification is ScrollEndNotification) {
      _distance = 0;
    }
    if (notification is! ScrollUpdateNotification ||
        notification.dragDetails == null) {
      return false;
    }
    final metrics = notification.metrics;
    if (metrics.pixels <= metrics.minScrollExtent + 12) {
      expand();
      return false;
    }
    if (metrics.outOfRange) return false;
    final delta = notification.scrollDelta ?? 0;
    if (delta == 0) return false;
    if (_distance.sign != delta.sign) _distance = 0;
    _distance += delta;
    if (_distance >= 28) {
      value = true;
      _distance = 0;
    } else if (_distance <= -18) {
      expand();
    }
    return false;
  }
}

/// A single mini-player survives the transition, preserving its artwork Hero,
/// playback controls and swipe-to-dismiss state as the tabs fold away.
class MornyeBottomBar extends ConsumerWidget {
  const MornyeBottomBar({
    super.key,
    required this.collapsed,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.onHome,
    required this.onSearch,
    required this.blurEnabled,
  });

  final bool collapsed;
  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onHome;
  final VoidCallback onSearch;
  final bool blurEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPlayer = ref.watch(
      currentMediaItemProvider.select((item) => item.value != null),
    );
    // Animated glass tabs already reserve 8px above their visible capsule.
    final glassTabs =
        blurEnabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.highContrastOf(context);
    final tabGap = glassTabs ? 0.0 : 8.0;
    // These contents do not depend on animation progress. Retain their widget
    // instances so folding only updates size/opacity wrappers each frame.
    Widget sideSurface({double radius = 26}) => RepaintBoundary(
      child: MornyeGlass.navigation(
        blurEnabled: blurEnabled,
        strongTint: true,
        tintOpacity: MornyeTheme.chromeOpacity(context),
        radius: radius,
        child: const SizedBox.expand(),
      ),
    );
    final leadingSurface = sideSurface();
    final searchSurface = sideSurface(radius: 32);
    final mainDestinations = destinations.sublist(0, destinations.length - 1);
    final searchSelected = selectedIndex == destinations.length - 1;
    final leadingIndex = searchSelected ? 0 : selectedIndex;
    final scheme = Theme.of(context).colorScheme;
    final inactiveIconColor = Color.lerp(
      scheme.onSurfaceVariant,
      scheme.onSurface,
      scheme.brightness == Brightness.dark ? 0.5 : 0.4,
    );
    final player = MiniPlayer(compact: collapsed, bottomPadding: 0);
    Widget tabs({required bool hideLeadingIcon}) => TickerMode(
      enabled: !collapsed,
      child: RepaintBoundary(
        child: MornyeTabBar(
          destinations: mainDestinations,
          selectedIndex: searchSelected ? -1 : selectedIndex,
          onSelected: onSelected,
          blurEnabled: blurEnabled,
          hiddenIconIndex: hideLeadingIcon ? leadingIndex : null,
        ),
      ),
    );
    // At rest the glass bar must paint its own active icon: its selected layer
    // follows a dragged pill before the destination is committed. Hand them
    // to the moving overlays only while folding, at the same coordinates.
    final fullTabs = tabs(hideLeadingIcon: false);
    final foldingTabs = tabs(hideLeadingIcon: true);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Match the tab's actual label height, including accessibility scaling.
        // Both icons stay mounted above the fading capsule for the whole trip.
        final labelStyle = Theme.of(context).textTheme.labelSmall!.copyWith(
          fontSize: glassTabs ? 11 : null,
          fontWeight: FontWeight.w600,
        );
        final labelPainter = TextPainter(
          text: TextSpan(text: destinations.first.label, style: labelStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final labelHeight = labelPainter.height;
        labelPainter.dispose();
        final fullIconBottom = glassTabs
            ? 40 + (labelHeight + 2) / 2
            : math.max(64.0, 49 + labelHeight) - 23.5;
        final tabInset = glassTabs ? 6.0 : 5.0;
        final fullIconStart =
            tabInset +
            (constraints.maxWidth - 76 - tabInset * 2) /
                mainDestinations.length *
                (leadingIndex + 0.5);
        final fullSearchBottom = glassTabs
            ? 8.0
            : (math.max(64.0, 49 + labelHeight) - 64) / 2;
        return TweenAnimationBuilder<double>(
          tween: Tween(end: collapsed ? 1 : 0),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 380),
          curve: Curves.easeInOutCubic,
          builder: (context, amount, _) {
            Widget movingIcon({
              required bool leading,
              required Widget surface,
            }) {
              final index = leading ? leadingIndex : destinations.length - 1;
              final offset = (fullIconStart - 26) * (1 - amount);
              final size = leading ? 52.0 : 64 - 12 * amount;
              return PositionedDirectional(
                start: leading ? offset : null,
                end: leading ? null : 0,
                bottom: leading
                    ? fullIconBottom * (1 - amount) + 34 * amount - 26
                    : fullSearchBottom * (1 - amount) + 8 * amount,
                width: size,
                height: size,
                child: IgnorePointer(
                  ignoring: leading && amount < 0.5,
                  child: ExcludeSemantics(
                    excluding: leading && amount < 0.5,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: Opacity(
                            opacity: leading ? amount : 1,
                            child: surface,
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: IconButton(
                            key: ValueKey(
                              leading
                                  ? 'mornye-compact-leading'
                                  : 'mornye-compact-search',
                            ),
                            tooltip: leading
                                ? destinations[leadingIndex].label
                                : context.l10n.mornyeSearch,
                            iconSize: 25,
                            constraints: BoxConstraints.tightFor(
                              width: size,
                              height: size,
                            ),
                            color: Color.lerp(
                              index == selectedIndex
                                  ? scheme.primary
                                  : inactiveIconColor,
                              scheme.primary,
                              amount,
                            ),
                            icon: Opacity(
                              opacity: leading && amount == 0 ? 0 : 1,
                              child: destinations[index].icon,
                            ),
                            onPressed: leading
                                ? leadingIndex == 0
                                      ? onHome
                                      : () => onSelected(leadingIndex)
                                : onSearch,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasPlayer || amount > 0)
                      Align(
                        alignment: Alignment.bottomCenter,
                        // With no track, introducing the row at full height would
                        // make the bar jump taller on the first animation frame.
                        heightFactor: hasPlayer ? 1 : amount,
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: hasPlayer
                                ? tabGap + (8 - tabGap) * amount
                                : 8,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 60 * amount,
                                height: hasPlayer ? 48 + 4 * amount : 52,
                              ),
                              Expanded(child: player),
                              SizedBox(
                                width: 60 * amount,
                                height: hasPlayer ? 48 + 4 * amount : 52,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ClipRect(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        heightFactor: 1 - amount,
                        child: IgnorePointer(
                          ignoring: amount > 0.5,
                          child: ExcludeSemantics(
                            excluding: amount > 0.5,
                            child: Opacity(
                              opacity: 1 - amount,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: 76,
                                ),
                                child: amount == 0 ? fullTabs : foldingTabs,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                movingIcon(leading: true, surface: leadingSurface),
                movingIcon(leading: false, surface: searchSurface),
              ],
            );
          },
        );
      },
    );
  }
}
