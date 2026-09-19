import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/app_snack_bar.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('snackbar retains backdrop color during entry in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final capture = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: MornyeTheme.build(brightness),
            builder: (_, child) => RepaintBoundary(key: capture, child: child),
            home: Builder(
              builder: (context) => Scaffold(
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: ColoredBox(color: Colors.blue)),
                        Expanded(child: ColoredBox(color: Colors.red)),
                      ],
                    ),
                    Center(
                      child: TextButton(
                        onPressed: () => showAppSnackBar(
                          context,
                          content: const Text('Extension installed'),
                        ),
                        child: const Text('Show'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pump();
      for (final elapsed in [16, 80, 250]) {
        await tester.pump(Duration(milliseconds: elapsed));
        final rect = tester.getRect(find.byType(MornyeGlassPanel));
        final colors = await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(capture),
          );
          final image = await boundary.toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final colors = <Color>[];
          for (final fraction in [0.25, 0.75]) {
            final x = (rect.left + rect.width * fraction).floor();
            final y = (rect.bottom - 8).floor();
            final offset = (y * image.width + x) * 4;
            colors.add(
              Color.fromARGB(
                bytes.getUint8(offset + 3),
                bytes.getUint8(offset),
                bytes.getUint8(offset + 1),
                bytes.getUint8(offset + 2),
              ),
            );
          }
          image.dispose();
          return colors;
        });
        // Retain a visible backdrop hue even beneath the glass shadow.
        expect(colors![0].b - colors[0].r, greaterThan(0.20));
        expect(colors[1].r - colors[1].b, greaterThan(0.20));
        final foreground = MornyeTheme.build(brightness).colorScheme.onSurface;
        for (final background in colors) {
          final luminances = [
            foreground.computeLuminance(),
            background.computeLuminance(),
          ]..sort();
          expect(
            (luminances.last + 0.05) / (luminances.first + 0.05),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final mornye in [true, false]) {
    testWidgets(
      'messages still queue, time out and dismiss (Mornye: $mornye)',
      (tester) async {
        late BuildContext messageContext;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: mornye ? MornyeTheme.build(Brightness.dark) : ThemeData(),
              home: Builder(
                builder: (context) {
                  messageContext = context;
                  return const Scaffold(body: SizedBox.expand());
                },
              ),
            ),
          ),
        );
        final first = showAppSnackBar(
          messageContext,
          content: const Text('First'),
          duration: const Duration(seconds: 1),
        );
        final second = showAppSnackBar(
          messageContext,
          content: const Text('Second'),
        );
        await tester.pumpAndSettle();
        expect(find.text('First'), findsOneWidget);
        expect(find.text('Second'), findsNothing);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(await first.closed, SnackBarClosedReason.timeout);
        expect(find.text('Second'), findsOneWidget);
        await tester.drag(find.text('Second'), const Offset(0, 300));
        await tester.pumpAndSettle();
        expect(await second.closed, SnackBarClosedReason.swipe);
        expect(find.text('Second'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
