import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/widgets/playback_seek_slider.dart';

void main() {
  testWidgets('scrubbing previews locally and commits only the final target', (
    tester,
  ) async {
    final seeks = <Duration>[];
    final completion = Completer<void>();
    Widget app(Duration position) => MaterialApp(
      home: Scaffold(
        body: PlaybackSeekSlider(
          position: position,
          duration: const Duration(seconds: 100),
          onSeek: (target) {
            seeks.add(target);
            return completion.future;
          },
        ),
      ),
    );

    await tester.pumpWidget(app(const Duration(seconds: 10)));
    final bounds = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(
      Offset(bounds.left + bounds.width * 0.3, bounds.center.dy),
    );
    await gesture.moveBy(Offset(bounds.width * 0.3, 0));
    await tester.pump();
    final preview = tester.widget<Slider>(find.byType(Slider)).value;
    expect(preview, greaterThan(50000));
    expect(seeks, isEmpty);

    await tester.pumpWidget(app(const Duration(seconds: 11)));
    expect(tester.widget<Slider>(find.byType(Slider)).value, preview);
    await gesture.up();
    await tester.pump();
    expect(seeks, [Duration(milliseconds: preview.round())]);
    expect(tester.widget<Slider>(find.byType(Slider)).value, preview);

    await tester.pumpWidget(app(seeks.single));
    completion.complete();
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<Slider>(find.byType(Slider)).value,
      seeks.single.inMilliseconds.toDouble(),
    );
  });

  testWidgets('an earlier seek completion does not erase a new drag', (
    tester,
  ) async {
    final completions = <Completer<void>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackSeekSlider(
            position: Duration.zero,
            duration: const Duration(seconds: 100),
            onSeek: (_) {
              final completion = Completer<void>();
              completions.add(completion);
              return completion.future;
            },
          ),
        ),
      ),
    );
    final bounds = tester.getRect(find.byType(Slider));
    await tester.tapAt(Offset(bounds.center.dx, bounds.center.dy));
    await tester.pump();
    expect(completions, hasLength(1));

    final gesture = await tester.startGesture(
      Offset(bounds.left + bounds.width * 0.8, bounds.center.dy),
    );
    await tester.pump();
    final preview = tester.widget<Slider>(find.byType(Slider)).value;
    completions.first.complete();
    await tester.pump();
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, preview);
    await gesture.up();
    expect(completions, hasLength(2));
    completions.last.complete();
    await tester.pump();
    await tester.pump();
  });

  testWidgets('unknown duration disables seek and clamps stale position', (
    tester,
  ) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackSeekSlider(
            position: const Duration(minutes: 2),
            duration: Duration.zero,
            onSeek: (target) async => seeks.add(target),
          ),
        ),
      ),
    );
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 0);
    expect(slider.onChanged, isNull);
    await tester.tap(find.byType(Slider));
    expect(seeks, isEmpty);
  });
}
