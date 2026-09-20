import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/album_detail_header.dart';
import 'package:spotiflac_android/widgets/collection_scaffold.dart';
import 'package:spotiflac_android/widgets/mornye_artist_header.dart';

void main() {
  testWidgets('unavailable artist logo keeps the name and actions readable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: MornyeTheme.build(Brightness.dark),
          home: Scaffold(
            body: CustomScrollView(
              slivers: const [
                MornyeArtistHeader(
                  name: 'Example Artist',
                  logoUrl: 'https://example.invalid/unavailable-logo.png',
                  artwork: ColoredBox(color: Colors.orange),
                  actions: [Text('Artist action')],
                  showTitle: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find
          .descendant(
            of: find.byType(SliverToBoxAdapter),
            matching: find.text('Example Artist'),
          )
          .hitTestable(),
      findsOneWidget,
    );
    expect(find.text('Artist action').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('artist artwork blurs, disappears, and returns with scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    const artworkKey = ValueKey('artist-artwork');
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: MornyeTheme.build(Brightness.dark),
          home: Scaffold(
            body: CustomScrollView(
              controller: controller,
              slivers: const [
                MornyeArtistHeader(
                  name: 'Artist',
                  artwork: ColoredBox(key: artworkKey, color: Colors.orange),
                  actions: [Text('Artist action')],
                  showTitle: false,
                ),
                SliverToBoxAdapter(child: SizedBox(height: 2000)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    double fade() => tester
        .widget<ColoredBox>(find.byKey(const ValueKey('artist-artwork-fade')))
        .color
        .a;
    ImageFiltered filter() => tester.widget<ImageFiltered>(
      find.ancestor(
        of: find.byKey(artworkKey),
        matching: find.byType(ImageFiltered),
      ),
    );
    final artwork = tester.element(find.byKey(artworkKey));
    expect(fade(), 0);
    expect(filter().enabled, isFalse);

    controller.jumpTo(120);
    await tester.pumpAndSettle();
    expect(filter().enabled, isTrue);
    expect(fade(), inExclusiveRange(0, 1));
    expect(find.text('Artist action').hitTestable(), findsOneWidget);

    controller.jumpTo(210);
    await tester.pumpAndSettle();
    expect(fade(), 1);
    expect(filter().enabled, isFalse);
    expect(TickerMode.valuesOf(artwork).enabled, isFalse);
    expect(find.text('Artist action').hitTestable(), findsOneWidget);

    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(fade(), 0);
    expect(filter().enabled, isFalse);
    expect(TickerMode.valuesOf(artwork).enabled, isTrue);
    expect(tester.element(find.byKey(artworkKey)), same(artwork));
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'album actions and pinned navigation work in $brightness at $scale',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          tester.view.padding = FakeViewPadding(top: 59, bottom: 34);
          addTearDown(tester.view.reset);
          final controller = ScrollController();
          addTearDown(controller.dispose);
          var plays = 0;
          var shuffles = 0;
          var backs = 0;
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: MornyeTheme.build(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: CollectionScaffold(
                  scrollController: controller,
                  isSelectionMode: false,
                  onExitSelectionMode: () {},
                  bottomInset: 0,
                  appBar: AlbumDetailHeader(
                    immersive: true,
                    title:
                        'A long album title that must wrap without hiding any of its controls',
                    expandedHeight: 400,
                    showTitleInAppBar: false,
                    background: const ColoredBox(
                      key: ValueKey('album-artwork'),
                      color: Colors.orange,
                    ),
                    coverBuilder: (_, _) =>
                        const ColoredBox(color: Colors.orange),
                    subtitle: const Text('Artist name'),
                    leading: HeaderCircleButton(
                      icon: Icons.arrow_back,
                      tooltip: 'Back',
                      onPressed: () => backs++,
                    ),
                    actions: AlbumPlayActions(
                      playLabel: 'Play',
                      shuffleTooltip: 'Shuffle',
                      onPlay: () => plays++,
                      onShuffle: () => shuffles++,
                    ),
                  ),
                  slivers: [
                    SliverList.builder(
                      itemCount: 40,
                      itemBuilder: (_, index) =>
                          SizedBox(height: 64, child: Text('Track $index')),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byKey(const ValueKey('album-artwork'))),
            const Size(390, 390),
          );
          await tester.ensureVisible(find.text('Play'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Play'));
          await tester.tap(find.text('Shuffle'));
          expect(plays, 1);
          expect(shuffles, 1);
          controller.jumpTo(1300);
          await tester.pumpAndSettle();
          expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
          await tester.tap(find.byTooltip('Back'));
          expect(backs, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'artist identity grows with text and retains navigation after scroll',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var favorites = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: MornyeTheme.build(Brightness.dark),
            home: Builder(
              builder: (context) => Scaffold(
                body: CustomScrollView(
                  controller: controller,
                  slivers: [
                    ...MornyeArtistHeader(
                      name: 'An artist with a name spanning several lines',
                      showTitle: true,
                      artwork: const ColoredBox(color: Colors.orange),
                      actions: [
                        HeaderCircleButton(
                          icon: Icons.favorite_border,
                          tooltip: 'Favorite',
                          onPressed: () => favorites++,
                        ),
                      ],
                    ).buildSlivers(context),
                    const SliverToBoxAdapter(child: SizedBox(height: 2000)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Favorite'));
      expect(favorites, 1);
      controller.jumpTo(1000);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
