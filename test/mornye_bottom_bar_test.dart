import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/screens/settings/settings_tab.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/utils/nav_bar_inset.dart';
import 'package:spotiflac_android/widgets/album_detail_header.dart';
import 'package:spotiflac_android/widgets/collection_scaffold.dart';
import 'package:spotiflac_android/widgets/mini_player.dart';
import 'package:spotiflac_android/widgets/mornye_artist_header.dart';
import 'package:spotiflac_android/widgets/mornye_bottom_bar.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';

void main() {
  late MornyeChromeController chrome;
  late ScrollController scroll;
  late int searches;
  final capture = GlobalKey();

  setUp(() {
    chrome = MornyeChromeController();
    scroll = ScrollController();
    searches = 0;
  });
  tearDown(() {
    chrome.dispose();
    scroll.dispose();
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    bool withPlayer = true,
    bool blur = false,
    Brightness brightness = Brightness.light,
    Color? backdrop,
    Color? chromeSurface,
    Widget? body,
  }) async {
    tester.view.physicalSize = const Size(393, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentMediaItemProvider.overrideWith(
            (ref) => Stream.value(
              withPlayer
                  ? const MediaItem(
                      id: 'track',
                      title: 'A song',
                      artist: 'Artist',
                    )
                  : null,
            ),
          ),
          playbackStateProvider.overrideWith((ref) => const Stream.empty()),
          lowEndDeviceProvider.overrideWithValue(!blur),
          backdropBlurEnabledProvider.overrideWithValue(blur),
        ],
        child: MaterialApp(
          theme: MornyeTheme.build(brightness, chromeSurface: chromeSurface),
          builder: (_, child) => RepaintBoundary(key: capture, child: child),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            backgroundColor: backdrop,
            extendBody: true,
            body: NotificationListener<ScrollNotification>(
              onNotification: chrome.handleScroll,
              child:
                  body ??
                  ListView.builder(
                    controller: scroll,
                    itemExtent: 60,
                    itemCount: 50,
                    itemBuilder: (_, index) => Text('Row $index'),
                  ),
            ),
            bottomNavigationBar: ValueListenableBuilder<bool>(
              valueListenable: chrome,
              builder: (_, collapsed, _) => MornyeBottomBar(
                collapsed: collapsed,
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                  NavigationDestination(
                    icon: Icon(Icons.music_note),
                    label: 'Library',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings),
                    label: 'Settings',
                  ),
                ],
                selectedIndex: 0,
                onSelected: (_) {},
                onExpand: chrome.expand,
                onSearch: () => searches++,
                blurEnabled: blur,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const albumBlue = Color(0xff464566);
  for (final brightness in Brightness.values) {
    for (final backdrop in [
      Colors.white,
      Colors.black,
      if (brightness == Brightness.dark) albumBlue,
    ]) {
      testWidgets(
        'floating glass stays legible in $brightness over $backdrop',
        (tester) async {
          await pumpShell(
            tester,
            blur: true,
            brightness: brightness,
            backdrop: backdrop,
            chromeSurface: backdrop == albumBlue ? albumBlue : null,
          );
          final artist = find.text('Artist');
          // The glass renderer also builds a copy for the refractive pill.
          final libraryIcon = find
              .descendant(
                of: find.byType(MornyeTabBar),
                matching: find.byIcon(Icons.music_note),
              )
              .first;
          final artistRect = tester.getRect(artist);
          final iconRect = tester.getRect(libraryIcon);
          final foregrounds = [
            tester.widget<Text>(artist).style!.color!,
            IconTheme.of(tester.element(libraryIcon)).color!,
          ];
          final samples = [
            Offset(artistRect.left + 8, artistRect.bottom + 2),
            Offset(iconRect.right + 8, iconRect.center.dy),
          ];
          final backgrounds = await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(capture),
            );
            final image = await boundary.toImage();
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final colors = <Color>[];
            for (final point in samples) {
              final offset =
                  (point.dy.floor() * image.width + point.dx.floor()) * 4;
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
          for (var index = 0; index < foregrounds.length; index++) {
            if (backdrop == albumBlue) {
              final glass = HSLColor.fromColor(backgrounds![index]);
              final page = HSLColor.fromColor(albumBlue);
              expect(glass.hue, closeTo(page.hue, 8));
              expect(glass.saturation, greaterThan(page.saturation * 0.7));
            }
            final luminances = [
              foregrounds[index].computeLuminance(),
              backgrounds![index].computeLuminance(),
            ]..sort();
            final contrast =
                (luminances.last + 0.05) / (luminances.first + 0.05);
            expect(
              contrast,
              greaterThanOrEqualTo(index == 0 ? 4.5 : 3),
              reason: index == 0 ? 'Mini-player artist' : 'Inactive tab icon',
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('downward scroll folds the tabs without replacing the player', (
    tester,
  ) async {
    await pumpShell(tester);
    final playerState = tester.state(find.byType(MiniPlayer));
    final expandedHeight = tester.getSize(find.byType(MornyeBottomBar)).height;
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(chrome.value, isTrue);
    expect(tester.state(find.byType(MiniPlayer)), same(playerState));
    expect(tester.widget<MiniPlayer>(find.byType(MiniPlayer)).compact, isTrue);
    expect(
      tester.getSize(find.byType(MornyeBottomBar)).height,
      lessThan(expandedHeight - 60),
    );
    expect(find.byTooltip('Next track'), findsNothing);
    await tester.tap(find.byTooltip('Show tabs'));
    await tester.pumpAndSettle();
    expect(chrome.value, isFalse);
    expect(tester.getSize(find.byType(MornyeBottomBar)).height, expandedHeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'collapse keeps the player and tab contents out of frame rebuilds',
    (tester) async {
      await pumpShell(tester);
      var tabBuilds = 0;
      var playerBuilds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (element.widget is MornyeTabBar) tabBuilds++;
        if (element.widget is MiniPlayer) playerBuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      chrome.value = true;
      await tester.pump();
      for (var frame = 0; frame < 25; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        tabBuilds,
        lessThanOrEqualTo(2),
        reason: 'Only the wrapper geometry animates each frame',
      );
      expect(
        playerBuilds,
        lessThanOrEqualTo(2),
        reason:
            'The player rebuilds for compact mode, not for every animation tick',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('folding chrome updates the spacer without rebuilding Settings', (
    tester,
  ) async {
    await pumpShell(tester, body: const SettingsTab(), blur: true);
    var settingsBuilds = 0;
    var spacerBuilds = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (element.widget is SettingsTab) settingsBuilds++;
      if (element.widget is NavBarSliverSpacer) spacerBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);

    for (final collapsed in [true, false]) {
      chrome.value = collapsed;
      await tester.pump();
      for (var frame = 0; frame < 25; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    expect(settingsBuilds, 0);
    expect(spacerBuilds, greaterThan(20));
    expect(tester.takeException(), isNull);
  });

  for (final artist in [true, false]) {
    testWidgets('folding chrome isolates header insets (artist: $artist)', (
      tester,
    ) async {
      var pageBuilds = 0;
      await pumpShell(
        tester,
        body: Builder(
          builder: (context) {
            pageBuilds++;
            final tracks = SliverFixedExtentList.builder(
              itemExtent: 60,
              itemCount: 50,
              itemBuilder: (_, index) => Text('Track $index'),
            );
            if (artist) {
              return CustomScrollView(
                controller: scroll,
                slivers: [
                  ...const MornyeArtistHeader(
                    name: 'Artist',
                    showTitle: false,
                    artwork: ColoredBox(color: Colors.blue),
                    actions: [],
                  ).buildSlivers(context),
                  tracks,
                  const NavBarSliverSpacer(),
                ],
              );
            }
            return CollectionScaffold(
              scrollController: scroll,
              isSelectionMode: false,
              onExitSelectionMode: () {},
              appBar: const AlbumDetailHeader(
                title: 'Album',
                expandedHeight: 400,
                immersive: true,
                showTitleInAppBar: false,
                background: ColoredBox(color: Colors.blue),
              ),
              slivers: [tracks],
            );
          },
        ),
      );
      pageBuilds = 0;
      var collectionBuilds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (element.widget is CollectionScaffold) collectionBuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      for (final collapsed in [true, false]) {
        chrome.value = collapsed;
        await tester.pump();
        for (var frame = 0; frame < 25; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }
      expect(pageBuilds, 0);
      expect(collectionBuilds, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'scrolling up expands; programmatic and horizontal movement do not collapse',
    (tester) async {
      await pumpShell(tester);
      scroll.jumpTo(500);
      await tester.pumpAndSettle();
      expect(chrome.value, isFalse);
      await tester.drag(find.byType(ListView), const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(chrome.value, isFalse);
      await tester.drag(find.byType(ListView), const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(chrome.value, isTrue);
      await tester.drag(find.byType(ListView), const Offset(0, 90));
      await tester.pumpAndSettle();
      expect(chrome.value, isFalse);
    },
  );

  testWidgets(
    'glass bar stays mounted and pauses its tickers while collapsed',
    (tester) async {
      await pumpShell(tester, blur: true);
      final glass = tester.element(find.byType(LiquidGlassTabBar));
      final player = tester.state(find.byType(MiniPlayer));
      expect(TickerMode.valuesOf(glass).enabled, isTrue);
      chrome.value = true;
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(LiquidGlassTabBar)), same(glass));
      expect(TickerMode.valuesOf(glass).enabled, isFalse);
      chrome.expand();
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(LiquidGlassTabBar)), same(glass));
      expect(tester.state(find.byType(MiniPlayer)), same(player));
      expect(TickerMode.valuesOf(glass).enabled, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact navigation works without a playing track', (
    tester,
  ) async {
    await pumpShell(tester, withPlayer: false);
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(chrome.value, isTrue);
    await tester.tap(find.byTooltip('Search'));
    expect(searches, 1);
    await tester.tap(find.byTooltip('Show tabs'));
    await tester.pumpAndSettle();
    expect(chrome.value, isFalse);
    expect(tester.takeException(), isNull);
  });
}
