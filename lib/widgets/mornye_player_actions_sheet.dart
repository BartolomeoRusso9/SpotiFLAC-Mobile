import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/theme/cover_palette.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/mornye_context_menu.dart';

/// Navigation for the title/artist, separate from playback and file actions.
class MornyePlayerNavigationMenu extends StatelessWidget {
  const MornyePlayerNavigationMenu({super.key, required this.mediaItem});

  final MediaItem mediaItem;

  @override
  Widget build(BuildContext context) {
    final theme = MornyeTheme.build(Brightness.dark);
    final art = mediaItem.artUri;
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(primary: Colors.grey),
      ),
      child: CoverPaletteBuilder(
        imageSource: art?.scheme == 'file'
            ? art!.toFilePath()
            : art?.toString(),
        builder: (context, palette) {
          final dominant = HSLColor.fromColor(palette.primary);
          final surface = dominant
              .withSaturation(dominant.saturation.clamp(0.0, 0.28))
              .withLightness(0.28)
              .toColor();
          return Theme(
            data: theme.copyWith(
              colorScheme: theme.colorScheme.copyWith(
                surfaceContainerHigh: surface,
              ),
            ),
            child: MornyeContextMenu(
              inheritSurface: true,
              groups: [
                [
                  if ((mediaItem.artist ?? '').trim().isNotEmpty)
                    MornyeMenuAction(
                      icon: CupertinoIcons.mic,
                      label: context.l10n.mornyeGoToArtist,
                      subtitle: mediaItem.artist,
                      onPressed: () => Navigator.of(context).pop('artist'),
                    ),
                  if ((mediaItem.album ?? '').trim().isNotEmpty)
                    MornyeMenuAction(
                      icon: CupertinoIcons.square_stack,
                      label: context.l10n.homeGoToAlbum,
                      subtitle: mediaItem.album,
                      onPressed: () => Navigator.of(context).pop('album'),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A floating menu that inherits the player's dark appearance.
class MornyePlayerActionsSheet extends StatelessWidget {
  const MornyePlayerActionsSheet({
    super.key,
    required this.mediaItem,
    this.sleepTimerSubtitle,
  });

  final MediaItem mediaItem;
  final String? sleepTimerSubtitle;

  @override
  Widget build(BuildContext context) => MornyeContextMenu(
    groups: [
      [
        if ((mediaItem.album ?? '').trim().isNotEmpty)
          _action(
            context,
            'album',
            context.l10n.homeGoToAlbum,
            CupertinoIcons.square_stack,
          ),
        _action(
          context,
          'details',
          context.l10n.nowPlayingDetails,
          CupertinoIcons.info,
        ),
      ],
      [
        _action(
          context,
          'sleepTimer',
          context.l10n.nowPlayingSleepTimer,
          CupertinoIcons.moon_zzz,
          subtitle: sleepTimerSubtitle,
        ),
        _action(
          context,
          'external',
          context.l10n.nowPlayingOpenInExternalPlayer,
          CupertinoIcons.arrow_up_right_square,
        ),
      ],
    ],
  );

  MornyeMenuAction _action(
    BuildContext context,
    String value,
    String label,
    IconData icon, {
    String? subtitle,
  }) => MornyeMenuAction(
    icon: icon,
    label: label,
    subtitle: subtitle,
    onPressed: () => Navigator.of(context).pop(value),
  );
}
