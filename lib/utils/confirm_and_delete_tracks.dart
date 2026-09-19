import 'package:flutter/material.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/widgets/app_alert_dialog.dart';

/// Shows a delete-confirmation dialog, deletes the given [ids] one by one via
/// [deleteItem], then shows a "deleted N tracks" snackbar.
/// [onExitSelectionMode] runs right after the delete loop, matching the
/// screens' original ordering.
///
/// Returns the number of items [deleteItem] reported deleted, or null if the
/// user cancelled the dialog.
/// [persistDeletedItems] commits successfully deleted IDs once before the UI
/// reports completion, including partial success if a later deletion throws.
Future<int?> confirmAndDeleteTracks({
  required BuildContext context,
  required List<String> ids,
  required Future<bool> Function(String id) deleteItem,
  Future<void> Function(List<String> ids)? persistDeletedItems,
  required VoidCallback onExitSelectionMode,
}) async {
  final confirmed = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => AppAlertDialog(
      title: Text(context.l10n.downloadedAlbumDeleteSelected),
      content: Text(context.l10n.downloadedAlbumDeleteMessage(ids.length)),
      actions: [
        AppDialogAction(
          isDefault: true,
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(context.l10n.dialogCancel),
        ),
        AppDialogAction(
          filled: true,
          isDestructive: true,
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(context.l10n.dialogDelete),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return null;

  final deletedIds = <String>[];
  try {
    for (final id in ids) {
      if (await deleteItem(id)) deletedIds.add(id);
    }
  } finally {
    if (deletedIds.isNotEmpty && persistDeletedItems != null) {
      await persistDeletedItems(deletedIds);
    }
  }
  final deletedCount = deletedIds.length;

  onExitSelectionMode();

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.snackbarDeletedTracks(deletedCount))),
    );
  }

  return deletedCount;
}
