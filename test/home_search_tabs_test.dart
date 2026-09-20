import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/l10n/app_localizations.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/download_history_provider.dart';
import 'package:spotiflac_android/providers/explore_provider.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/recent_access_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/track_provider.dart';
import 'package:spotiflac_android/screens/home_tab.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';

void main() {
  testWidgets(
    'Home keeps its feed while Search retains its query and results',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final search = _Search();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_Settings.new),
            extensionProvider.overrideWith(_Extensions.new),
            exploreProvider.overrideWith(_Explore.new),
            downloadHistoryProvider.overrideWith(_History.new),
            recentAccessProvider.overrideWith(_Recent.new),
            trackProvider.overrideWith(() => search),
          ],
          child: MaterialApp(
            theme: MornyeTheme.build(Brightness.dark),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const _Tabs(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Featured albums'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Recently visited artist'), findsNothing);

      await tester.tap(find.text('Open Search'));
      await tester.pumpAndSettle();
      expect(find.text('Search'), findsWidgets);
      expect(find.text('Featured albums'), findsNothing);
      expect(find.text('Recently visited artist'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Example');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Example',
      );
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(search._requests, 1);
      expect(find.text('Found artist'), findsOneWidget);

      await tester.tap(find.text('Open Home'));
      await tester.pumpAndSettle();
      expect(find.text('Featured albums'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Found artist'), findsNothing);

      await tester.tap(find.text('Open Search'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Example',
      );
      expect(find.text('Found artist'), findsOneWidget);
      expect(search._requests, 1);
      await tester.tap(find.byTooltip('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('Found artist'), findsNothing);
      expect(find.text('Recently visited artist'), findsOneWidget);
      expect(find.text('Featured albums'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Tabs extends StatefulWidget {
  const _Tabs();

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _index,
      children: [
        TickerMode(
          enabled: _index == 0,
          child: const HomeTab(mode: HomeTabMode.browse),
        ),
        TickerMode(
          enabled: _index == 1,
          child: const HomeTab(mode: HomeTabMode.search),
        ),
      ],
    ),
    bottomNavigationBar: Row(
      children: [
        for (final (index, label) in [(0, 'Open Home'), (1, 'Open Search')])
          TextButton(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() => _index = index);
            },
            child: Text(label),
          ),
      ],
    ),
  );
}

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() =>
      const AppSettings(searchProvider: 'example', hasSearchedBefore: true);
}

class _Extensions extends ExtensionNotifier {
  @override
  ExtensionState build() => const ExtensionState(
    isInitialized: true,
    extensions: [
      Extension(
        id: 'example',
        name: 'example',
        displayName: 'Example',
        version: '1.0.0',
        description: '',
        enabled: true,
        status: 'loaded',
        hasMetadataProvider: true,
        searchBehavior: SearchBehavior(enabled: true),
      ),
    ],
  );
}

class _Explore extends ExploreNotifier {
  @override
  ExploreState build() => const ExploreState(
    sections: [
      ExploreSection(
        uri: 'example:featured',
        title: 'Featured albums',
        items: [],
      ),
    ],
  );
}

class _History extends DownloadHistoryNotifier {
  @override
  DownloadHistoryState build() => DownloadHistoryState();
}

class _Recent extends RecentAccessNotifier {
  @override
  RecentAccessState build() => RecentAccessState(
    isLoaded: true,
    items: [
      RecentAccessItem(
        id: 'recent',
        name: 'Recently visited artist',
        type: RecentAccessType.artist,
        accessedAt: DateTime(2026),
        providerId: 'example',
      ),
    ],
  );
}

class _Search extends TrackNotifier {
  int _requests = 0;

  @override
  Future<void> customSearch(
    String extensionId,
    String query, {
    Map<String, dynamic>? options,
    String? selectedFilter,
    bool allowVerificationRetry = true,
  }) async {
    _requests++;
    state = const TrackState(
      hasSearchText: true,
      searchExtensionId: 'example',
      tracks: [
        Track(
          id: 'artist',
          name: 'Found artist',
          artistName: '',
          albumName: '',
          duration: 0,
          itemType: 'artist',
          source: 'example',
        ),
      ],
    );
  }
}
