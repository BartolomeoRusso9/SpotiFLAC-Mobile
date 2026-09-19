import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';

/// Bounds of the tapped control or row, in the root overlay's coordinates.
Rect? mornyeMenuAnchor(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  if (box.size.height > MediaQuery.sizeOf(context).height * 0.65) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

Future<T?> showMornyeContextMenu<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Rect? anchor,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final target = anchor ?? mornyeMenuAnchor(context);
  return navigator.push<T>(
    RawDialogRoute<T>(
      barrierColor: Colors.black.withValues(alpha: 0.12),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      // Opacity layers isolate a BackdropFilter from the underlying artwork.
      transitionBuilder: (_, _, _, child) => child,
      pageBuilder: (context, animation, _) {
        final media = MediaQuery.of(context);
        return Semantics(
          scopesRoute: true,
          namesRoute: true,
          label: MaterialLocalizations.of(context).popupMenuLabel,
          explicitChildNodes: true,
          child: CustomSingleChildLayout(
            delegate: _MenuLayout(
              anchor: target,
              padding: media.padding.copyWith(
                bottom: math.max(media.padding.bottom, media.viewInsets.bottom),
              ),
            ),
            child: ScaleTransition(
              scale: animation.drive(Tween<double>(begin: 0.96, end: 1)),
              child: themes.wrap(Builder(builder: builder)),
            ),
          ),
        );
      },
    ),
  );
}

class _MenuLayout extends SingleChildLayoutDelegate {
  const _MenuLayout({required this.anchor, required this.padding});

  final Rect? anchor;
  final EdgeInsets padding;
  static const double _margin = 16;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = math.min(
      320.0,
      math.max(0.0, constraints.maxWidth - padding.horizontal - _margin * 2),
    );
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.max(
        0,
        constraints.maxHeight - padding.vertical - _margin * 2,
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = padding.left + _margin;
    final top = padding.top + _margin;
    final right = math.max(
      left,
      size.width - padding.right - _margin - childSize.width,
    );
    final bottom = math.max(
      top,
      size.height - padding.bottom - _margin - childSize.height,
    );
    final x = anchor == null
        ? (size.width - childSize.width) / 2
        : anchor!.right - childSize.width;
    var y = anchor == null ? size.height * 0.18 : anchor!.bottom + 8;
    if (anchor != null && y > bottom) {
      y = anchor!.top - childSize.height - 8;
      if (y < top) y = bottom;
    }
    return Offset(x.clamp(left, right), y.clamp(top, bottom));
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor || padding != oldDelegate.padding;
}

class MornyeMenuAction {
  const MornyeMenuAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.subtitle,
    this.selected = false,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onPressed;
  final bool selected;
  final bool destructive;
}

/// One frosted popover, with compact shortcuts and separated action groups.
class MornyeContextMenu extends StatelessWidget {
  const MornyeContextMenu({
    super.key,
    this.quickActions = const [],
    required this.groups,
    this.inheritSurface = false,
  });

  final List<MornyeMenuAction> quickActions;
  final List<List<MornyeMenuAction>> groups;
  final bool inheritSurface;

  @override
  Widget build(BuildContext context) {
    final theme = inheritSurface
        ? Theme.of(context)
        : MornyeTheme.build(Theme.of(context).brightness);
    final visibleGroups = groups.where((group) => group.isNotEmpty).toList();
    final shortcuts = quickActions.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final action in quickActions)
                  Expanded(child: _action(theme, action, compact: true)),
              ],
            ),
          );
    final actions = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < visibleGroups.length; i++) ...[
            if (i > 0 || quickActions.isNotEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: i == 0 ? 0 : 8),
                child: const Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 20,
                  endIndent: 20,
                ),
              ),
            for (final action in visibleGroups[i]) _action(theme, action),
          ],
        ],
      ),
    );
    return Theme(
      data: theme,
      child: MornyeGlassPanel.overlay(
        radius: 28,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Let the entire menu scroll when pinning the shortcuts would
            // leave too little room for a row in landscape or large text.
            if (constraints.maxHeight < 360 ||
                MediaQuery.textScalerOf(context).scale(17) > 28) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [?shortcuts, actions],
                ),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ?shortcuts,
                Flexible(child: SingleChildScrollView(child: actions)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _action(
    ThemeData theme,
    MornyeMenuAction action, {
    bool compact = false,
  }) {
    final color = action.onPressed == null
        ? theme.colorScheme.onSurfaceVariant
        : action.destructive || action.selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;
    final icon = Icon(action.icon, size: compact ? 23 : 21, color: color);
    final label = Text(
      action.label,
      textAlign: compact ? TextAlign.center : TextAlign.start,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: color,
        fontSize: compact ? 13 : 17,
        fontWeight: compact ? FontWeight.w600 : FontWeight.w400,
      ),
    );
    return Semantics(
      selected: action.selected,
      child: CupertinoButton(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 4, vertical: 10)
            : const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        onPressed: action.onPressed,
        child: compact
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [icon, const SizedBox(height: 7), label],
              )
            : Row(
                children: [
                  icon,
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        label,
                        if (action.subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            action.subtitle!,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
