import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/app_alert_dialog.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';
import 'package:spotiflac_android/widgets/playlist_picker_sheet.dart';
import 'package:spotiflac_android/widgets/track_collection_quick_actions.dart';

const _track = Track(
  id: 'example-track',
  name: 'Example track',
  artistName: 'Example artist',
  albumName: 'Example album',
  duration: 180,
);

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

class _Collections extends LibraryCollectionsNotifier {
  List<PlaylistPickerSummary> _summaries = [];
  final additions = <String>[];
  final createdNames = <String>[];

  @override
  LibraryCollectionsState build() => LibraryCollectionsState(isLoaded: true);

  @override
  Future<String> createPlaylist(String name) async {
    createdNames.add(name);
    _summaries = [..._summaries, _playlist(name)];
    ref.invalidate(libraryPlaylistPickerSummariesProvider);
    return name;
  }

  @override
  Future<PlaylistAddBatchResult> addTracksToPlaylist(
    String playlistId,
    Iterable<Track> tracks,
  ) async {
    additions.add(playlistId);
    return PlaylistAddBatchResult(
      addedCount: tracks.length,
      alreadyInPlaylistCount: 0,
    );
  }
}

PlaylistPickerSummary _playlist(String name, {bool contains = false}) =>
    PlaylistPickerSummary(
      id: name,
      name: name,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      trackCount: 2,
      containsAllRequestedTracks: contains,
    );

Widget _app(
  Widget child,
  _Collections collections, {
  required Brightness brightness,
  bool mornye = true,
  double textScale = 1,
}) => ProviderScope(
  overrides: [
    settingsProvider.overrideWith(_Settings.new),
    libraryCollectionsProvider.overrideWith(() => collections),
    libraryPlaylistPickerSummariesProvider.overrideWith(
      (ref, request) async => collections._summaries,
    ),
  ],
  child: MaterialApp(
    theme: mornye ? MornyeTheme.build(brightness) : ThemeData(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(body: child),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
  });

  for (final brightness in Brightness.values) {
    testWidgets('track menu reaches playlist creation in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 680);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final collections = _Collections();
      await tester.pumpWidget(
        _app(
          const TrackCollectionQuickActions(track: _track),
          collections,
          brightness: brightness,
          textScale: 1.5,
        ),
      );
      await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
      await tester.pumpAndSettle();
      expect(find.byType(MornyeGlassPanel), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      expect(find.byIcon(CupertinoIcons.doc_on_doc), findsNWidgets(2));

      await tester.ensureVisible(find.text('Add to playlist'));
      await tester.tap(find.text('Add to playlist'));
      await tester.pumpAndSettle();
      expect(find.text('No playlists yet'), findsOneWidget);
      expect(find.byType(MornyeGlassPanel), findsOneWidget);
      expect(find.text('Done').hitTestable(), findsOneWidget);

      await tester.tap(find.text('Create playlist'));
      await tester.pumpAndSettle();
      expect(find.byType(AppAlertDialog), findsOneWidget);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(collections.createdNames, isEmpty);
      await tester.enterText(find.byType(TextFormField), 'Evening music');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(collections.createdNames, ['Evening music']);
      expect(collections.additions, ['Evening music']);
      expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(collections.additions, ['Evening music']);
      expect(find.byType(MornyeGlassPanel), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final mornye in [true, false]) {
    testWidgets('picker adds only new selections (Mornye: $mornye)', (
      tester,
    ) async {
      final collections = _Collections()
        .._summaries = [
          _playlist('Already included', contains: true),
          _playlist('Road trip'),
          _playlist('Unselected playlist'),
        ];
      await tester.pumpWidget(
        _app(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () =>
                  showAddTracksToPlaylistSheet(context, ref, [_track]),
              child: const Text('Open'),
            ),
          ),
          collections,
          brightness: Brightness.light,
          mornye: mornye,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Already included'));
      await tester.tap(find.text('Road trip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(collections.additions, ['Road trip']);
      expect(tester.takeException(), isNull);
    });
  }
}
