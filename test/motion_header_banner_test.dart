import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/widgets/motion_header_banner.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _VideoPlatform extends VideoPlayerPlatform {
  bool playing = false;
  int playCalls = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(
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
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();

  @override
  Future<void> dispose(int playerId) async {}
}

void main() {
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
