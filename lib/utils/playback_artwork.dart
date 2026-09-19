import 'dart:io';

/// A saved queue may outlive the scan directory that supplied its artwork.
/// Consult the Library only when the saved local image is missing.
Future<String?> resolveRestoredArtworkUri(
  String? artwork, {
  required Future<String?> Function() loadLibraryCoverPath,
}) async {
  try {
    if (artwork != null && artwork.isNotEmpty) {
      final uri = Uri.parse(artwork);
      if (uri.hasScheme && uri.scheme != 'file') return artwork;
      final path = uri.scheme == 'file' ? uri.toFilePath() : artwork;
      if (await File(path).exists()) return artwork;
    }
    final cover = await loadLibraryCoverPath();
    if (cover == null || cover.isEmpty) return artwork;
    final path = cover.startsWith('file://')
        ? Uri.parse(cover).toFilePath()
        : cover;
    if (await File(path).exists()) return Uri.file(path).toString();
  } catch (_) {
    // Missing artwork or an unavailable Library must not discard playback.
  }
  return artwork;
}
