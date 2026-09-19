import 'package:flutter/material.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';

/// One inline surface, matching the metadata groups and dialog controls.
class AppContentCard extends StatelessWidget {
  const AppContentCard({
    super.key,
    required this.child,
    this.color,
    this.shape,
    this.elevation,
    this.clipBehavior = Clip.none,
    this.preserveColor = false,
  });

  final Widget child;
  final Color? color;
  final ShapeBorder? shape;
  final double? elevation;
  final Clip clipBehavior;
  final bool preserveColor;

  @override
  Widget build(BuildContext context) {
    if (!context.isMornye) {
      return Card(
        color: color,
        shape: shape,
        elevation: elevation,
        clipBehavior: clipBehavior,
        child: child,
      );
    }
    return Material(
      color: preserveColor ? color : MornyeTheme.controlFill(context),
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: DividerTheme(
        data: DividerTheme.of(
          context,
        ).copyWith(color: MornyeTheme.metadataDividerColor(context)),
        child: child,
      ),
    );
  }
}
