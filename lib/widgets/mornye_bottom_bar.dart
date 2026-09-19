import 'package:flutter/cupertino.dart' show CupertinoIcons;
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
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
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
    required this.onExpand,
    required this.onSearch,
    required this.blurEnabled,
  });

  final bool collapsed;
  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onExpand;
  final VoidCallback onSearch;
  final bool blurEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPlayer = ref.watch(
      currentMediaItemProvider.select((item) => item.value != null),
    );
    // Animated glass tabs already reserve 8px above their visible capsule.
    final tabGap =
        blurEnabled &&
            !MediaQuery.disableAnimationsOf(context) &&
            !MediaQuery.highContrastOf(context)
        ? 0.0
        : 8.0;
    // These contents do not depend on animation progress. Retain their widget
    // instances so folding only updates size/opacity wrappers each frame.
    Widget sideContent({
      required Widget icon,
      required String tooltip,
      required VoidCallback onPressed,
    }) => RepaintBoundary(
      child: MornyeGlass.navigation(
        blurEnabled: blurEnabled,
        strongTint: true,
        tintOpacity: MornyeTheme.chromeOpacity(context),
        radius: 26,
        child: SizedBox.square(
          dimension: 52,
          child: Material(
            color: Colors.transparent,
            child: IconButton(
              tooltip: tooltip,
              color: Theme.of(context).colorScheme.primary,
              icon: icon,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
    final expandButton = sideContent(
      icon: destinations[selectedIndex].icon,
      tooltip: context.l10n.mornyeShowTabs,
      onPressed: onExpand,
    );
    final searchButton = sideContent(
      icon: const Icon(CupertinoIcons.search),
      tooltip: context.l10n.mornyeSearch,
      onPressed: onSearch,
    );
    final player = MiniPlayer(compact: collapsed, bottomPadding: 0);
    final tabs = TickerMode(
      enabled: !collapsed,
      child: RepaintBoundary(
        child: MornyeTabBar(
          destinations: destinations,
          selectedIndex: selectedIndex,
          onSelected: onSelected,
          blurEnabled: blurEnabled,
        ),
      ),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(end: collapsed ? 1 : 0),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
      builder: (context, amount, _) {
        Widget sideButton({
          required Widget child,
          required Alignment alignment,
        }) => ClipRect(
          child: Align(
            alignment: alignment,
            widthFactor: amount,
            child: SizedBox(
              width: 60,
              height: 48 + 4 * amount,
              child: Align(
                alignment: alignment,
                child: IgnorePointer(
                  ignoring: !collapsed,
                  child: ExcludeSemantics(
                    excluding: !collapsed,
                    child: Opacity(opacity: amount, child: child),
                  ),
                ),
              ),
            ),
          ),
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasPlayer || amount > 0)
              Padding(
                padding: EdgeInsets.only(
                  bottom: tabGap + (8 - tabGap) * amount,
                ),
                child: Row(
                  children: [
                    sideButton(
                      child: expandButton,
                      alignment: Alignment.centerLeft,
                    ),
                    Expanded(child: player),
                    sideButton(
                      child: searchButton,
                      alignment: Alignment.centerRight,
                    ),
                  ],
                ),
              ),
            ClipRect(
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: 1 - amount,
                child: IgnorePointer(
                  ignoring: collapsed,
                  child: ExcludeSemantics(
                    excluding: collapsed,
                    child: Opacity(opacity: 1 - amount, child: tabs),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
