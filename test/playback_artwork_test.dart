import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/utils/playback_artwork.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('restored-artwork-');
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'restored queue replaces a removed scan cover with current Library art',
    () async {
      final removed = File(
        '${directory.path}/old-scan/cover.jpg',
      ).uri.toString();
      final current = File('${directory.path}/current cover #1.jpg');
      await current.writeAsBytes([1]);
      final resolved = await resolveRestoredArtworkUri(
        removed,
        loadLibraryCoverPath: () async => current.path,
      );
      expect(resolved, current.uri.toString());
      expect(File(Uri.parse(resolved!).toFilePath()).existsSync(), isTrue);
    },
  );

  test(
    'valid local and remote covers do not trigger Library lookups',
    () async {
      final current = File('${directory.path}/cover.jpg');
      await current.writeAsBytes([1]);
      for (final artwork in [
        current.path,
        current.uri.toString(),
        'https://example.com/cover.jpg',
      ]) {
        var lookups = 0;
        final resolved = await resolveRestoredArtworkUri(
          artwork,
          loadLibraryCoverPath: () async {
            lookups++;
            return null;
          },
        );
        expect(resolved, artwork);
        expect(lookups, 0);
      }
    },
  );

  test(
    'a missing Library image or lookup failure leaves the session usable',
    () async {
      final missing = File('${directory.path}/missing.jpg').uri.toString();
      expect(
        await resolveRestoredArtworkUri(
          missing,
          loadLibraryCoverPath: () async =>
              '${directory.path}/also-missing.jpg',
        ),
        missing,
      );
      expect(
        await resolveRestoredArtworkUri(
          missing,
          loadLibraryCoverPath: () async =>
              throw StateError('Library unavailable'),
        ),
        missing,
      );
    },
  );
}
