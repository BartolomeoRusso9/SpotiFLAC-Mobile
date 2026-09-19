import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/l10n/app_localizations.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/download_service_picker.dart';

class _Extensions extends ExtensionNotifier {
  _Extensions(this._qualityCount);

  final int _qualityCount;

  @override
  ExtensionState build() => ExtensionState(
    extensions: [
      Extension(
        id: 'example',
        name: 'example',
        displayName: 'Example',
        version: '1.0.0',
        description: '',
        enabled: true,
        status: 'loaded',
        hasDownloadProvider: true,
        qualityOptions: List.generate(
          _qualityCount,
          (index) => QualityOption(id: '$index', label: 'Quality $index'),
        ),
      ),
    ],
  );

  @override
  void refreshEnabledExtensionHealth({bool force = false}) {}
}

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

void main() {
  for (final (qualityCount, mornye) in [
    (3, false),
    (16, false),
    (3, true),
    (16, true),
  ]) {
    testWidgets(
      'picker fits $qualityCount options and dismisses (Mornye=$mornye)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        (String, String)? selection;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              extensionProvider.overrideWith(() => _Extensions(qualityCount)),
              settingsProvider.overrideWith(_Settings.new),
            ],
            child: MaterialApp(
              theme: mornye
                  ? MornyeTheme.build(Brightness.dark)
                  : ThemeData(platform: TargetPlatform.iOS),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => DownloadServicePicker.show(
                      context,
                      trackName: 'Example track',
                      onSelect: (quality, service) =>
                          selection = (quality, service),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        if (qualityCount == 3) {
          final sheetBottom = tester.getBottomLeft(find.byType(BottomSheet)).dy;
          final lastOptionBottom = tester
              .getBottomLeft(find.text('Quality 2'))
              .dy;
          expect(sheetBottom - lastOptionBottom, lessThan(100));
        }
        if (qualityCount == 16) {
          final scroll = find.descendant(
            of: find.byType(DownloadServicePicker),
            matching: find.byType(SingleChildScrollView),
          );
          await tester.drag(scroll, const Offset(0, -300));
          await tester.pumpAndSettle();
          expect(find.byType(DownloadServicePicker), findsOneWidget);
          await tester.drag(scroll, const Offset(0, 1500));
          await tester.pumpAndSettle();
        }
        final sheetTop = tester.getTopLeft(find.byType(BottomSheet));
        final sheetWidth = tester.getSize(find.byType(BottomSheet)).width;
        await tester.dragFrom(
          sheetTop + Offset(sheetWidth / 2, 16),
          const Offset(0, 600),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DownloadServicePicker), findsNothing);
        expect(selection, isNull);
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final lastQuality = find.text('Quality ${qualityCount - 1}');
        await tester.ensureVisible(lastQuality);
        await tester.pumpAndSettle();
        await tester.tap(lastQuality);
        await tester.pumpAndSettle();
        expect(selection, ('${qualityCount - 1}', 'example'));
        expect(find.byType(DownloadServicePicker), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
