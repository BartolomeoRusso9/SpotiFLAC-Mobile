import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/theme/cover_palette.dart';

void main() {
  testWidgets('palette requests share a small aspect-preserving decode', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('palette-test-');
      final cache = PaintingBinding.instance.imageCache;
      cache.clear();
      cache.clearLiveImages();
      try {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 512, 256),
          Paint()..color = Colors.blue,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(512, 256);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        final file = File('${directory.path}/cover.png');
        await file.writeAsBytes(bytes!.buffer.asUint8List());

        final first = CoverPalette.resolve(file.path, Brightness.light);
        final second = CoverPalette.resolve(file.path, Brightness.light);
        expect(identical(first, second), isTrue);
        final scheme = await first;
        expect(scheme, isNotNull);
        // The original is 512 x 256. Its cached decode fits inside 112 x 112
        // while preserving the 2:1 aspect ratio, instead of retaining 512 KiB.
        expect(cache.currentSizeBytes, 112 * 56 * 4);
        expect(
          await CoverPalette.resolve(file.path, Brightness.light),
          same(scheme),
        );
      } finally {
        cache.clear();
        cache.clearLiveImages();
        await directory.delete(recursive: true);
      }
    });
  });
}
