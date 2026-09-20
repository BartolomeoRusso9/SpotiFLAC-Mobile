import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/providers/player_artwork_video_provider.dart';
import 'package:spotiflac_android/widgets/mornye_player_artwork.dart';
import 'package:spotiflac_android/widgets/motion_header_banner.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _VideoPlatform extends VideoPlayerPlatform {
  bool playing = false;
  int playCalls = 0;
  bool looping = false;
  double volume = 1;
  DataSource? source;
  int creations = 0;
  int disposals = 0;
  Map<int, StreamController<VideoEvent>>? events;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    source = options.dataSource;
    final id = ++creations;
    events?[id] = StreamController<VideoEvent>();
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      events?[playerId]?.stream ??
      Stream.value(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 30),
          size: const Size(320, 180),
        ),
      );

  @override
  Future<void> play(int playerId) async {
    playing = true;
    playCalls++;
  }

  @override
  Future<void> pause(int playerId) async => playing = false;

  @override
  Future<void> setLooping(int playerId, bool looping) async =>
      this.looping = looping;

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      this.volume = volume;

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();

  @override
  Future<void> dispose(int playerId) async {
    disposals++;
    await events?[playerId]?.close();
  }
}

void main() {
  testWidgets(
    'prepared player video opens without a new decoder or cover fade',
    (tester) async {
      final previous = VideoPlayerPlatform.instance;
      final platform = _VideoPlatform();
      VideoPlayerPlatform.instance = platform;
      addTearDown(() => VideoPlayerPlatform.instance = previous);
      final show = ValueNotifier(false);
      addTearDown(show.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                ref.watch(playerArtworkVideoProvider('file:///cover.mp4'));
                return ValueListenableBuilder(
                  valueListenable: show,
                  builder: (_, visible, _) => visible
                      ? const MornyePlayerArtwork(
                          mediaItem: MediaItem(id: 'song', title: 'Song'),
                          videoUrl: 'file:///cover.mp4',
                        )
                      : const SizedBox(),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(platform.creations, 1);
      expect(platform.playing, isFalse);
      show.value = true;
      await tester.pump();
      expect(platform.creations, 1);
      expect(platform.playing, isTrue);
      final banner = tester.widget<MotionHeaderBanner>(
        find.byType(MotionHeaderBanner),
      );
      expect(banner.controller!.value.isInitialized, isTrue);
      expect(banner.fadeDuration, Duration.zero);
      show.value = false;
      await tester.pump();
      expect(platform.playing, isFalse);
      expect(platform.disposals, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(platform.disposals, 1);
    },
  );

  testWidgets('changing tracks retains video until the new frame is ready', (
    tester,
  ) async {
    final previous = VideoPlayerPlatform.instance;
    final platform = _VideoPlatform()..events = {};
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = previous);
    final source = ValueNotifier('file:///first.mp4');
    addTearDown(source.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: source,
            builder: (_, url, _) => MornyePlayerArtwork(
              mediaItem: MediaItem(id: url, title: 'Song'),
              videoUrl: url,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    void ready(int id) => platform.events![id]!.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 10),
        size: const Size(300, 400),
      ),
    );
    ready(1);
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<MotionHeaderBanner>(find.byType(MotionHeaderBanner))
          .videoUrl,
      source.value,
    );
    source.value = 'file:///second.mp4';
    await tester.pump();
    expect(
      tester
          .widget<MotionHeaderBanner>(find.byType(MotionHeaderBanner))
          .videoUrl,
      'file:///first.mp4',
    );
    expect(platform.disposals, 0);
    ready(2);
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<MotionHeaderBanner>(find.byType(MotionHeaderBanner))
          .videoUrl,
      source.value,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'offline cover uses a silent looping file and reports its ratio',
    (tester) async {
      final previousPlatform = VideoPlayerPlatform.instance;
      final platform = _VideoPlatform();
      VideoPlayerPlatform.instance = platform;
      addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
      double? ratio;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 320,
            height: 180,
            child: MotionHeaderBanner(
              videoUrl: 'file:///app/motion_artwork/cover.mp4',
              fallback: const ColoredBox(color: Colors.black),
              onAspectRatioChanged: (value) => ratio = value,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(platform.source?.sourceType, DataSourceType.file);
      expect(platform.looping, isTrue);
      expect(platform.volume, 0);
      expect(platform.playing, isTrue);
      expect(ratio, closeTo(320 / 180, 0.001));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('collapsed headers pause video and visible headers resume', (
    tester,
  ) async {
    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);

    Widget app({bool active = true}) => MaterialApp(
      home: Scaffold(
        body: TickerMode(
          enabled: active,
          child: CustomScrollView(
            controller: scroll,
            slivers: const [
              SliverAppBar(
                pinned: true,
                expandedHeight: 300,
                flexibleSpace: FlexibleSpaceBar(
                  background: MotionHeaderBanner(
                    videoUrl: 'https://example.com/banner.m3u8',
                    fallback: ColoredBox(color: Colors.blue),
                  ),
                ),
              ),
              SliverToBoxAdapter(child: SizedBox(height: 2000)),
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pump();
    expect(platform.playing, isTrue);
    expect(platform.looping, isTrue);
    expect(platform.volume, 0);
    final initialPlayCalls = platform.playCalls;

    scroll.jumpTo(50);
    await tester.pump();
    expect(platform.playCalls, initialPlayCalls);
    scroll.jumpTo(400);
    await tester.pump();
    expect(platform.playing, isFalse);

    scroll.jumpTo(0);
    await tester.pump();
    expect(platform.playing, isTrue);
    await tester.pumpWidget(app(active: false));
    await tester.pump();
    expect(platform.playing, isFalse);
    await tester.pumpWidget(app());
    await tester.pump();
    expect(platform.playing, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(platform.playing, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.playing, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
