import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/providers/player_motion_artwork_provider.dart';
import 'package:spotiflac_android/screens/now_playing_screen.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/mornye_volume_control.dart';
import 'package:spotiflac_android/widgets/mornye_player_queue.dart';
import 'package:spotiflac_android/widgets/mornye_playback_button.dart';
import 'package:spotiflac_android/widgets/mornye_playback_time.dart';
import 'package:spotiflac_android/widgets/mornye_player_actions_sheet.dart';
import 'package:spotiflac_android/widgets/mornye_player_favorite_button.dart';
import 'package:spotiflac_android/widgets/mornye_player_details_sheet.dart';
import 'package:spotiflac_android/widgets/mornye_metadata_row.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';
import 'package:spotiflac_android/widgets/mornye_player_background.dart';
import 'package:spotiflac_android/widgets/mornye_player_artwork.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const backendChannel = MethodChannel('com.zarz.spotiflac/backend');
  late StreamController<MediaItem?> mediaItems;
  late List<double> volumeWrites;
  late Map<String, dynamic> metadataOverrides;
  late List<String> metadataReads;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mediaItems = StreamController<MediaItem?>.broadcast();
    volumeWrites = [];
    metadataOverrides = {};
    metadataReads = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backendChannel, (call) async {
          if (call.method != 'readFileMetadata') {
            fail('Unexpected platform call: ${call.method}');
          }
          final arguments = (call.arguments as Map).cast<String, dynamic>();
          final path = arguments['file_path']?.toString() ?? '';
          metadataReads.add(path);
          final lyrics = path.endsWith('/timed.flac')
              ? '''<tt xmlns="http://www.w3.org/ns/ttml"><body><div><p begin="00:00.000" end="00:02.000"><span begin="00:00.000">Short</span></p></div></body></tt>'''
              : path.endsWith('/many.flac')
              ? '[00:00.00]First line\n[00:02.00]Second line\n[00:04.00]Third line\n[00:06.00]Fourth line'
              : path.endsWith('/second.flac')
              ? '[00:01.00]Second lyric'
              : '[00:01.00]First lyric';
          return jsonEncode({
            'title': path.endsWith('/second.flac') ? 'Second' : 'First',
            'lyrics': lyrics,
            ...metadataOverrides,
          });
        });
  });

  tearDown(() async {
    await mediaItems.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(backendChannel, null);
  });

  MediaItem item(String id) => MediaItem(
    id: id,
    title: id == 'first' ? 'First' : 'Second',
    artist: 'Artist',
    album: 'Album',
    duration: const Duration(minutes: 3),
    extras: {'source': 'content://library/$id.flac'},
  );

  Future<void> pumpNowPlaying(
    WidgetTester tester, {
    ThemeData? theme,
    Size size = const Size(1080, 1920),
    PlaybackState? playback,
    Stream<PlaybackState>? playbackEvents,
    Widget Function(Widget)? wrapPlayer,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentMediaItemProvider.overrideWith((ref) => mediaItems.stream),
          playerMotionArtworkProvider.overrideWith((ref, album) async => null),
          playerCollectionTrackProvider.overrideWith(
            (ref, item) async => Track(
              id: item.id,
              name: item.title,
              artistName: item.artist ?? '',
              albumName: item.album ?? '',
              duration: item.duration?.inSeconds ?? 0,
              source: 'local',
            ),
          ),
          libraryCollectionsProvider.overrideWith(_TestCollections.new),
          playbackStateProvider.overrideWith(
            (ref) =>
                playbackEvents ??
                (playback == null
                    ? const Stream.empty()
                    : Stream.value(playback)),
          ),
          playQueueProvider.overrideWith((ref) => const Stream.empty()),
          systemVolumeProvider.overrideWith((ref) => Stream.value(0.5)),
          systemVolumeWriterProvider.overrideWith(
            (ref) =>
                (value) async => volumeWrites.add(value),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: theme,
          home:
              wrapPlayer?.call(const NowPlayingScreen()) ??
              const NowPlayingScreen(),
        ),
      ),
    );
  }

  testWidgets('Mornye player background does not reveal the page below', (
    tester,
  ) async {
    final background = ValueNotifier<Color>(Colors.white);
    addTearDown(background.dispose);
    final capture = GlobalKey();
    await pumpNowPlaying(
      tester,
      theme: MornyeTheme.build(Brightness.light),
      size: const Size(393, 780),
      wrapPlayer: (player) => RepaintBoundary(
        key: capture,
        child: ValueListenableBuilder<Color>(
          valueListenable: background,
          child: player,
          builder: (context, color, child) => Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: color),
              child!,
            ],
          ),
        ),
      ),
    );
    mediaItems.add(item('first'));
    await tester.pumpAndSettle();

    Future<List<int>?> edgePixel() => tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final offset = (image.width + 1) * 4;
      final pixel = List<int>.generate(4, (i) => bytes.getUint8(offset + i));
      image.dispose();
      return pixel;
    });

    final onWhite = await edgePixel();
    background.value = Colors.red;
    await tester.pumpAndSettle();
    expect(await edgePixel(), onWhite);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Mornye player menu floats above its button and retains dark colors',
    (tester) async {
      await pumpNowPlaying(
        tester,
        theme: MornyeTheme.build(Brightness.light),
        size: const Size(393, 780),
      );
      mediaItems.add(item('first'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.ellipsis).hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final panel = find.byType(MornyePlayerActionsSheet);
      final enteringWidth = tester.getSize(panel).width;
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).width, enteringWidth);
      expect(tester.getRect(panel).bottom, lessThan(780 - 16));
      expect(tester.getRect(panel).width, 320);
      expect(find.byType(BottomSheet), findsNothing);
      expect(Theme.of(tester.element(panel)).brightness, Brightness.dark);
      expect(
        tester.widget<Text>(find.text('Go to Album')).style?.color,
        Colors.white,
      );
      expect(find.byIcon(CupertinoIcons.square_stack), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.moon_zzz), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.gear_alt), findsNothing);
      await tester.tap(find.text('Sleep timer'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('15 minutes'))).brightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Mornye title opens artist and album destinations with subtitles',
    (tester) async {
      await pumpNowPlaying(
        tester,
        theme: MornyeTheme.build(Brightness.dark),
        size: const Size(393, 780),
      );
      mediaItems.add(item('first'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('First').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Go to Artist'), findsOneWidget);
      expect(find.text('Go to Album'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MornyePlayerNavigationMenu),
          matching: find.text('Artist'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(MornyePlayerNavigationMenu),
          matching: find.text('Album'),
        ),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(5, 770));
      await tester.pumpAndSettle();
      expect(find.byType(MornyePlayerNavigationMenu), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Android Details reads full tags from a restored content URI', (
    tester,
  ) async {
    metadataOverrides = {
      'album_artist': 'Album Artist',
      'genre': 'Pop/Rock',
      'composer': 'Composer Name',
      'date': '2025-04-16',
      'track_number': 4,
    };
    await pumpNowPlaying(
      tester,
      theme: MornyeTheme.build(
        Brightness.dark,
      ).copyWith(platform: TargetPlatform.android),
      size: const Size(393, 852),
    );
    mediaItems.add(item('first'));
    await tester.pumpAndSettle();
    expect(metadataReads, isEmpty);

    await tester.tap(find.byIcon(CupertinoIcons.ellipsis).hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    expect(metadataReads, ['content://library/first.flac']);
    final details = tester.widget<MornyePlayerDetailsSheet>(
      find.byType(MornyePlayerDetailsSheet),
    );
    expect(
      details.rows,
      containsAll([
        ('Title', 'First'),
        ('Album', 'Album'),
        ('Album Artist', 'Album Artist'),
        ('Genre', 'Pop/Rock'),
        ('Composer', 'Composer Name'),
        ('Date', '2025-04-16'),
        ('Track #', '4'),
      ]),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Mornye Details keeps long values readable and Done visible while scrolling',
    (tester) async {
      final rights = List.filled(10, 'A long copyright value').join(' ');
      metadataOverrides = {
        'title': 'First',
        'artist': 'Artist',
        'album': 'Album',
        'genre': 'Rock',
        'composer': 'Composer',
        'isrc': 'USAAA2600001',
        'copyright': rights,
        'format': 'flac',
        'sample_rate': 96000,
        'bit_depth': 24,
      };
      await pumpNowPlaying(
        tester,
        theme: MornyeTheme.build(Brightness.light),
        size: const Size(393, 780),
      );
      mediaItems.add(
        item('first').copyWith(extras: {'source': '/library/first.flac'}),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.ellipsis).hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      final sheet = find.byType(MornyePlayerDetailsSheet);
      expect(sheet, findsOneWidget);
      expect(Theme.of(tester.element(sheet)).brightness, Brightness.dark);
      expect(
        find.descendant(of: sheet, matching: find.byType(Card)),
        findsNothing,
      );
      expect(
        find.descendant(of: sheet, matching: find.byType(MornyeGlass)),
        findsOneWidget,
      );
      final titleRow = find.widgetWithText(MornyeMetadataRow, 'Title');
      expect(
        tester
            .getTopLeft(
              find.descendant(of: titleRow, matching: find.text('First')),
            )
            .dy,
        greaterThan(tester.getBottomLeft(find.text('Title')).dy),
      );
      await tester.scrollUntilVisible(
        find.text(rights),
        200,
        scrollable: find.descendant(
          of: sheet,
          matching: find.byType(Scrollable),
        ),
      );
      expect(tester.getSize(find.text(rights)).height, greaterThan(40));
      expect(find.text('Done').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Mornye star shares Library favorites across tracks and compact headers',
    (tester) async {
      await pumpNowPlaying(
        tester,
        theme: MornyeTheme.build(Brightness.light),
        size: const Size(393, 780),
      );
      mediaItems.add(item('first'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NowPlayingScreen)),
      );
      final star = find.byIcon(CupertinoIcons.star).hitTestable();
      expect(star, findsOneWidget);
      await tester.tap(star);
      await tester.pumpAndSettle();
      expect(
        find.byIcon(CupertinoIcons.star_fill).hitTestable(),
        findsOneWidget,
      );
      expect(
        container.read(libraryCollectionsProvider).loved.single.track.id,
        'first',
      );
      await tester.tap(find.byIcon(CupertinoIcons.list_bullet));
      await tester.pumpAndSettle();
      expect(
        find.byIcon(CupertinoIcons.star_fill).hitTestable(),
        findsOneWidget,
      );
      mediaItems.add(item('second'));
      await tester.pumpAndSettle();
      expect(find.byIcon(CupertinoIcons.star).hitTestable(), findsOneWidget);
      mediaItems.add(item('first'));
      await tester.pumpAndSettle();
      expect(
        find.byIcon(CupertinoIcons.star_fill).hitTestable(),
        findsOneWidget,
      );

      // A change from Library must also update the player, without reopening it.
      final track = container
          .read(libraryCollectionsProvider)
          .loved
          .single
          .track;
      await container
          .read(libraryCollectionsProvider.notifier)
          .toggleLoved(track);
      await tester.pumpAndSettle();
      expect(find.byIcon(CupertinoIcons.star).hitTestable(), findsOneWidget);
      expect(
        find.byType(MornyePlayerFavoriteButton).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Mornye lyrics stay blurred until playback starts', (
    tester,
  ) async {
    final playback = StreamController<PlaybackState>();
    addTearDown(playback.close);
    await pumpNowPlaying(
      tester,
      theme: MornyeTheme.build(Brightness.dark),
      size: const Size(393, 780),
      playbackEvents: playback.stream,
    );
    mediaItems.add(item('many'));
    playback.add(
      PlaybackState(
        processingState: AudioProcessingState.loading,
        playing: true,
        updatePosition: const Duration(seconds: 2),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    void expectLine(String text, {required bool active}) {
      final line = find.text(text);
      final filter = tester.widget<ImageFiltered>(
        find.ancestor(of: line, matching: find.byType(ImageFiltered)).first,
      );
      final opacity = tester.widget<AnimatedOpacity>(
        find.ancestor(of: line, matching: find.byType(AnimatedOpacity)).first,
      );
      expect(opacity.opacity, active ? 1 : 0.48);
      expect(filter.enabled, !active, reason: '$text: ${filter.imageFilter}');
    }

    expectLine('First line', active: false);
    expectLine('Second line', active: false);
    expectLine('Third line', active: false);

    playback.add(PlaybackState(processingState: AudioProcessingState.ready));
    await tester.pumpAndSettle();
    expectLine('First line', active: false);

    playback.add(
      PlaybackState(
        processingState: AudioProcessingState.ready,
        playing: true,
        updatePosition: const Duration(seconds: 2),
      ),
    );
    await tester.pump();
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 160));
    }
    expectLine('First line', active: false);
    expectLine('Second line', active: true);
    expectLine('Third line', active: false);

    playback.add(
      PlaybackState(
        processingState: AudioProcessingState.ready,
        updatePosition: const Duration(seconds: 2),
      ),
    );
    await tester.pumpAndSettle();
    expectLine('Second line', active: true);

    playback.add(
      PlaybackState(
        processingState: AudioProcessingState.buffering,
        playing: true,
        updatePosition: const Duration(seconds: 2),
      ),
    );
    await tester.pump();
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 160));
    }
    expectLine('First line', active: false);
    expectLine('Second line', active: false);
    expectLine('Third line', active: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Mornye lyrics keep the active line sharp with bold leading-aligned text',
    (tester) async {
      await pumpNowPlaying(
        tester,
        theme: MornyeTheme.build(Brightness.light),
        size: const Size(393, 780),
        playback: PlaybackState(updatePosition: const Duration(seconds: 2)),
      );
      mediaItems.add(item('many'));
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      final active = find.text('Second line');
      final inactive = find.text('Third line');
      final activeText = tester.widget<Text>(active);
      expect(activeText.textAlign, TextAlign.start);
      expect(activeText.style?.fontWeight, FontWeight.bold);
      expect(activeText.style?.fontSize, 28);
      expect(tester.getTopLeft(active).dx, tester.getTopLeft(inactive).dx);
      expect(
        tester.getTopLeft(active).dx,
        tester.getTopLeft(find.byType(ListView)).dx + 24,
      );
      final activeFilters = tester.widgetList<ImageFiltered>(
        find.ancestor(of: active, matching: find.byType(ImageFiltered)),
      );
      expect(activeFilters.any((filter) => !filter.enabled), isTrue);
      final inactiveFilters = tester.widgetList<ImageFiltered>(
        find.ancestor(of: inactive, matching: find.byType(ImageFiltered)),
      );
      expect(
        inactiveFilters.any(
          (filter) =>
              filter.enabled &&
              filter.imageFilter == ImageFilter.blur(sigmaX: 0.6, sigmaY: 0.6),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Mornye queue replaces artwork while volume and playback stay in place',
    (tester) async {
      await pumpNowPlaying(
        tester,
        theme: MornyeTheme.build(Brightness.light),
        size: const Size(393, 780),
      );
      mediaItems.add(item('first'));
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(find.text('First lyric').hitTestable(), findsOneWidget);
      final volume = tester.getRect(find.byType(MornyeVolumeControl));
      await tester.tap(find.byIcon(CupertinoIcons.list_bullet));
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(find.byType(MornyePlayerQueue), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.getRect(find.byType(MornyeVolumeControl)), volume);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(CupertinoIcons.list_bullet));
      await tester.pump();
      expect(find.text('First lyric'), findsNothing);
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('First lyric'), findsNothing);
      expect(find.byType(MornyePlayerQueue), findsOneWidget);
      expect(find.byType(MornyePlayerQueue).hitTestable(), findsNothing);
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(find.byType(MornyePlayerQueue), findsNothing);
      expect(tester.getRect(find.byType(MornyeVolumeControl)), volume);
    },
  );

  testWidgets('Mornye player renders Apple-style transport controls', (
    tester,
  ) async {
    await pumpNowPlaying(tester, theme: MornyeTheme.build(Brightness.light));
    mediaItems.add(item('first'));
    await tester.pumpAndSettle();

    expect(find.byIcon(CupertinoIcons.play_fill), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.backward_fill), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.forward_fill), findsOneWidget);
    expect(find.byType(MornyeVolumeControl), findsOneWidget);
    expect(tester.takeException(), isNull);

    final nextButton = find.widgetWithIcon(
      MornyePlaybackButton,
      CupertinoIcons.forward_fill,
    );
    final nextState = tester.state(nextButton);
    mediaItems.add(item('second'));
    await tester.pumpAndSettle();
    expect(tester.state(nextButton), same(nextState));
  });

  testWidgets('Mornye elapsed and remaining times roll on the same second', (
    tester,
  ) async {
    final playbackEvents = StreamController<PlaybackState>();
    addTearDown(playbackEvents.close);
    await pumpNowPlaying(
      tester,
      theme: MornyeTheme.build(Brightness.dark),
      size: const Size(393, 780),
      playbackEvents: playbackEvents.stream,
    );
    mediaItems.add(
      item(
        'first',
      ).copyWith(duration: const Duration(seconds: 180, milliseconds: 600)),
    );

    Future<void> positionAt(int milliseconds) async {
      playbackEvents.add(
        PlaybackState(
          processingState: AudioProcessingState.ready,
          playing: false,
          updatePosition: Duration(milliseconds: milliseconds),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    final elapsed = find.byKey(const ValueKey('elapsed:first'));
    final remaining = find.byKey(const ValueKey('remaining:first'));
    void expectTimes(int elapsedSeconds, int remainingSeconds) {
      expect(
        tester.widget<MornyePlaybackTime>(elapsed).seconds,
        elapsedSeconds,
      );
      expect(
        tester.widget<MornyePlaybackTime>(remaining).seconds,
        remainingSeconds,
      );
    }

    await positionAt(34200);
    await tester.pumpAndSettle();
    expectTimes(34, 146);
    await positionAt(34800);
    expectTimes(34, 146);

    await positionAt(35000);
    await tester.pump(const Duration(milliseconds: 80));
    expectTimes(35, 145);
    double incomingOffset(Finder label) => tester
        .widget<SlideTransition>(
          find
              .ancestor(
                of: find.descendant(of: label, matching: find.text('5')),
                matching: find.byType(SlideTransition),
              )
              .first,
        )
        .position
        .value
        .dy;
    expect(incomingOffset(elapsed), greaterThan(0));
    expect(incomingOffset(remaining), -incomingOffset(elapsed));

    // Another position report within this second must not restart either roll.
    await positionAt(35200);
    await tester.pump(const Duration(milliseconds: 200));
    expect(incomingOffset(elapsed), 0);
    expect(incomingOffset(remaining), 0);
    await positionAt(35900);
    expectTimes(35, 145);
    await positionAt(36000);
    expectTimes(36, 144);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mornye volume stays above the bottom actions on a phone', (
    tester,
  ) async {
    await pumpNowPlaying(
      tester,
      theme: MornyeTheme.build(Brightness.dark),
      size: const Size(393, 700),
    );
    mediaItems.add(item('first'));
    await tester.pumpAndSettle();

    final volume = find.byType(MornyeVolumeControl);
    final lyricsButton = find.byIcon(CupertinoIcons.quote_bubble);
    final slider = find.descendant(of: volume, matching: find.byType(Slider));
    expect(
      tester.getRect(volume).bottom,
      lessThan(tester.getRect(lyricsButton).top),
    );
    expect(tester.getSize(slider).height, greaterThanOrEqualTo(44));
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(volumeWrites, isNotEmpty);
    expect(volumeWrites.last, greaterThan(0.5));
    await gesture.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(volumeWrites, isNotEmpty);
    expect(volumeWrites.last, greaterThan(0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Mornye landscape shows lyrics automatically without bottom actions',
    (tester) async {
      await pumpNowPlaying(
        tester,
        theme: MornyeTheme.build(Brightness.dark),
        size: const Size(393, 852),
      );
      mediaItems.add(item('first'));
      await tester.pumpAndSettle();

      tester.view.physicalSize = const Size(852, 393);
      tester.view.padding = FakeViewPadding(left: 59, right: 59, bottom: 21);
      addTearDown(tester.view.resetPadding);
      await tester.pumpAndSettle();

      final artwork = find.byType(Hero);
      final volume = find.byType(MornyeVolumeControl);
      final artRect = tester.getRect(artwork);
      expect(artRect.width, closeTo(artRect.height, 0.1));
      expect(artRect.width, greaterThan(140));
      expect(artRect.top, greaterThanOrEqualTo(36));
      final header = find.text('First').hitTestable();
      final lyric = find.text('First lyric').hitTestable();
      expect(header, findsOneWidget);
      expect(lyric, findsOneWidget);
      expect(tester.getRect(header).left, greaterThan(artRect.right));
      expect(tester.getRect(lyric).left, greaterThan(artRect.right));
      expect(
        tester.getRect(lyric).top,
        greaterThan(tester.getRect(header).bottom),
      );
      expect(volume, findsNothing);
      expect(find.byIcon(CupertinoIcons.quote_bubble), findsNothing);
      expect(find.byIcon(CupertinoIcons.list_bullet), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(artwork);
      await tester.pumpAndSettle();
      expect(volume.hitTestable(), findsOneWidget);
      expect(
        find.byIcon(CupertinoIcons.play_fill).hitTestable(),
        findsOneWidget,
      );
      final volumeSlider = find.descendant(
        of: volume,
        matching: find.byType(Slider),
      );
      final drag = await tester.startGesture(tester.getCenter(volumeSlider));
      await drag.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(seconds: 5));
      expect(volume.hitTestable(), findsOneWidget);
      expect(volumeWrites, isNotEmpty);
      await drag.up();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(volume, findsNothing);
      expect(find.text('First lyric').hitTestable(), findsOneWidget);

      mediaItems.add(item('second'));
      await tester.pumpAndSettle();
      expect(find.text('Second lyric').hitTestable(), findsOneWidget);
      expect(find.text('First lyric'), findsNothing);
      tester.view.physicalSize = const Size(393, 852);
      tester.view.resetPadding();
      await tester.pumpAndSettle();
      expect(
        find.byIcon(CupertinoIcons.quote_bubble).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byIcon(CupertinoIcons.list_bullet).hitTestable(),
        findsOneWidget,
      );
      expect(
        tester.getRect(artwork).bottom,
        lessThan(tester.getRect(volume).top),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Mornye cover stays attached throughout opening and closing', (
    tester,
  ) async {
    tester.view.padding = FakeViewPadding(top: 59, bottom: 34);
    tester.view.viewPadding = FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await pumpNowPlaying(
      tester,
      theme: MornyeTheme.build(Brightness.dark),
      size: const Size(393, 852),
      wrapPlayer: (_) => Consumer(
        builder: (context, ref, _) {
          ref.watch(currentMediaItemProvider);
          return Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(NowPlayingRoute()),
                child: const Hero(
                  tag: kNowPlayingArtworkHeroTag,
                  child: SizedBox.square(dimension: 38, child: Text('Open')),
                ),
              ),
            ),
          );
        },
      ),
    );
    mediaItems.add(item('first'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pump();

    void expectAttached() {
      final panel = tester.getRect(find.byType(MornyePlayerBackground));
      final artwork = tester.getRect(find.byType(MornyePlayerArtwork));
      expect(artwork.left, closeTo(panel.left, 0.01));
      expect(artwork.top, closeTo(panel.top, 0.01));
      expect(artwork.width, closeTo(393, 0.01));
      expect(artwork.height, closeTo(393, 0.01));
    }

    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
      expectAttached();
    }
    await tester.pumpAndSettle();
    expectAttached();
    Navigator.of(tester.element(find.byType(NowPlayingScreen))).pop();
    await tester.pump();
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
      expectAttached();
      expect(
        tester.getTopLeft(find.byType(MornyePlayerBackground)).dy,
        greaterThan(0),
      );
    }
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mornye lyrics replace artwork while controls stay in place', (
    tester,
  ) async {
    await pumpNowPlaying(
      tester,
      theme: MornyeTheme.build(Brightness.dark),
      size: const Size(393, 700),
    );
    mediaItems.add(item('first'));
    await tester.pumpAndSettle();

    final artwork = find.byType(Hero);
    final fullArtwork = tester.getRect(artwork);
    expect(fullArtwork.height, fullArtwork.width);
    final volume = find.byType(MornyeVolumeControl);
    final volumeRect = tester.getRect(volume);
    final play = find.byIcon(CupertinoIcons.play_fill);
    final playRect = tester.getRect(play);
    final lyricsButton = find.byIcon(CupertinoIcons.quote_bubble);
    await tester.tap(lyricsButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final fullCover = find.byKey(const ValueKey('full-player-artwork'));
    double fullCoverOpacity() => tester
        .widget<FadeTransition>(
          find
              .ancestor(of: fullCover, matching: find.byType(FadeTransition))
              .first,
        )
        .opacity
        .value;
    expect(fullCover, findsOneWidget);
    expect(fullCoverOpacity(), inExclusiveRange(0.0, 1.0));
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsNothing);
    expect(find.text('First lyric').hitTestable(), findsOneWidget);
    expect(tester.getSize(artwork).width, lessThan(fullArtwork.width));
    expect(fullArtwork.top, 0);
    expect(fullArtwork.width, 393);
    expect(tester.getRect(volume), volumeRect);
    expect(tester.getRect(play), playRect);

    mediaItems.add(item('second'));
    await tester.pumpAndSettle();
    expect(find.text('Second lyric').hitTestable(), findsOneWidget);
    expect(find.text('First lyric'), findsNothing);

    await tester.tap(lyricsButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(fullCoverOpacity(), inExclusiveRange(0.0, 1.0));
    expect(
      find.descendant(
        of: find.byType(MornyePlayerBackground),
        matching: find.byType(Hero),
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(artwork), fullArtwork);
    expect(find.text('Second lyric').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'automatic SAF track change refreshes lyrics while Lyrics page is active',
    (tester) async {
      await pumpNowPlaying(tester);

      mediaItems.add(item('first'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-700, 0));
      await tester.pumpAndSettle();
      expect(find.text('First lyric'), findsOneWidget);

      mediaItems.add(item('second'));
      await tester.pumpAndSettle();

      expect(find.text('Second lyric'), findsOneWidget);
      expect(find.text('First lyric'), findsNothing);
    },
  );

  testWidgets('timed lyric fills text fragments in reading order', (
    tester,
  ) async {
    const lyricText = 'AAAA BBBB CCCC DDDD EEEE FFFF GGGG HHHH';
    metadataOverrides['lyrics'] =
        '<tt xmlns="http://www.w3.org/ns/ttml"><body><div>'
        '<p begin="00:00.000" end="00:08.000">'
        '<span begin="00:00.000">$lyricText</span>'
        '</p></div></body></tt>';
    await pumpNowPlaying(
      tester,
      theme: MornyeTheme.build(Brightness.dark),
      size: const Size(320, 844),
      playback: PlaybackState(
        processingState: AudioProcessingState.ready,
        playing: false,
        updatePosition: const Duration(seconds: 2),
      ),
    );
    mediaItems.add(item('first'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
    await tester.pumpAndSettle();

    final paintFinder = find.descendant(
      of: find.bySemanticsLabel(lyricText),
      matching: find.byType(CustomPaint),
    );
    final painter = tester.widget<CustomPaint>(paintFinder).painter!;
    final size = tester.getSize(paintFinder);
    final highlightedPixels = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        size.width.ceil(),
        size.height.ceil(),
      );
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      var upper = 0;
      var lower = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          if (bytes.getUint8((y * image.width + x) * 4 + 3) < 230) continue;
          if (y < image.height ~/ 2) {
            upper++;
          } else {
            lower++;
          }
        }
      }
      image.dispose();
      picture.dispose();
      return (upper, lower);
    });
    expect(highlightedPixels!.$1, greaterThan(0));
    expect(highlightedPixels.$2, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short timed lyric remains horizontally centered', (
    tester,
  ) async {
    await pumpNowPlaying(tester);

    mediaItems.add(item('timed'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();

    final lyric = find.bySemanticsLabel('Short');
    expect(lyric, findsOneWidget);
    expect(tester.getCenter(lyric).dx, closeTo(540, 1));
  });

  testWidgets('Now Playing menu exposes Go to Album when album is known', (
    tester,
  ) async {
    await pumpNowPlaying(tester);
    mediaItems.add(item('first'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Go to Album'), findsOneWidget);
    expect(find.byIcon(Icons.album_outlined), findsOneWidget);
  });

  testWidgets('Now Playing menu exposes sleep timer duration choices', (
    tester,
  ) async {
    await pumpNowPlaying(tester);
    mediaItems.add(item('first'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sleep timer'));
    await tester.pumpAndSettle();

    expect(find.text('15 minutes'), findsOneWidget);
    expect(find.text('30 minutes'), findsOneWidget);
    expect(find.text('45 minutes'), findsOneWidget);
    expect(find.text('60 minutes'), findsOneWidget);
    expect(find.text('Turn off sleep timer'), findsNothing);
  });
}

class _TestCollections extends LibraryCollectionsNotifier {
  @override
  LibraryCollectionsState build() => LibraryCollectionsState(isLoaded: true);

  @override
  Future<bool> toggleLoved(Track track) async {
    final key = trackCollectionKey(track);
    final added = !state.isLoved(track);
    state = state.copyWith(
      loved: added
          ? [
              ...state.loved,
              CollectionTrackEntry(
                key: key,
                track: track,
                addedAt: DateTime.now(),
              ),
            ]
          : state.loved.where((entry) => entry.key != key).toList(),
    );
    return added;
  }
}
