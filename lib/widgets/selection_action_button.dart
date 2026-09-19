import 'package:flutter/material.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/app_action_button.dart';

/// Icon+label pill used in selection-mode bottom bars. Disabled state dims
/// both the fill and the content to 50% alpha.
class SelectionActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final ColorScheme colorScheme;

  const SelectionActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    if (context.isMornye) {
      return AppActionButton(
        outlined: true,
        tonal: true,
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
        fontSize: 15,
      );
    }
    final isDisabled = onPressed == null;
    return Semantics(
      button: true,
      enabled: !isDisabled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: isDisabled
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: context.tokens.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: isDisabled
                        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                        : colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDisabled
                            ? colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.5,
                              )
                            : colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
