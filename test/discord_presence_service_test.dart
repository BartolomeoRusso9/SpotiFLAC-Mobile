import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/services/discord_presence_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/discord');
  late DiscordPresenceService service;
  late BaseAudioHandler player;
  late List<MethodCall> calls;

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'configure'
              ? ((call.arguments as Map)['enabled'] == true
                    ? 'ready'
                    : 'disabled')
              : null;
        });
    player = BaseAudioHandler();
    service = DiscordPresenceService(channel: channel)..bind(player);
  });

  tearDown(() async {
    await service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void play({String title = 'Track 🎵'}) {
    player.mediaItem.add(
      MediaItem(
        id: 'local-track',
        title: title,
        artist: 'Lead & Guest',
        album: 'Album',
        duration: const Duration(minutes: 3),
        artUri: Uri.parse('file:///private/cover.jpg'),
      ),
    );
    player.playbackState.add(
      PlaybackState(playing: true, processingState: AudioProcessingState.ready),
    );
  }

  test('opt-in persists and defaults to off', () {
    expect(AppSettings.fromJson({}).discordRichPresence, isFalse);
    final settings = const AppSettings().copyWith(discordRichPresence: true);
    expect(AppSettings.fromJson(settings.toJson()).discordRichPresence, isTrue);
  });

  test('publishes playback only after opt-in and clears on pause', () async {
    play();
    await settle();
    expect(calls, isEmpty);
    await service.setEnabled(true);
    await settle();
    final update = calls.singleWhere((c) => c.method == 'update');
    final data = update.arguments as Map;
    expect(data['title'], 'Track 🎵');
    expect(data['artist'], 'Lead & Guest');
    expect(data['cover'], '');
    expect((data['end'] as int) - (data['start'] as int), 180000);
    player.playbackState.add(
      PlaybackState(
        playing: false,
        processingState: AudioProcessingState.ready,
      ),
    );
    await settle();
    expect(calls.last.method, 'clear');
    await service.setEnabled(false);
    final count = calls.length;
    play(title: 'Next');
    await settle();
    expect(calls.length, count);
  });

  test('late configure completion cannot republish after disabling', () async {
    final ready = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return (call.arguments as Map)['enabled'] == true
              ? ready.future
              : 'disabled';
        });
    play();
    final enabling = service.setEnabled(true);
    await settle();
    final disabling = service.setEnabled(false);
    ready.complete('ready');
    await Future.wait([enabling, disabling]);
    await settle();
    expect(calls.map((c) => c.method), ['configure', 'configure']);
    expect(service.status.value, 'disabled');
  });

  test('position ticks are deduplicated but seek republishes', () async {
    play();
    await service.setEnabled(true);
    await settle();
    final initial = calls.where((c) => c.method == 'update').length;
    for (var i = 0; i < 8; i++) {
      player.playbackState.add(
        PlaybackState(
          playing: true,
          processingState: AudioProcessingState.ready,
        ),
      );
    }
    await settle();
    expect(calls.where((c) => c.method == 'update').length, initial);
    player.playbackState.add(
      PlaybackState(
        playing: true,
        processingState: AudioProcessingState.ready,
        updatePosition: const Duration(seconds: 30),
      ),
    );
    await settle();
    expect(calls.where((c) => c.method == 'update').length, initial + 1);
  });

  test('missing Discord does not publish or break playback', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return 'discord_missing';
        });
    play();
    await service.setEnabled(true);
    await settle();
    expect(service.status.value, 'discord_missing');
    expect(calls.map((c) => c.method), ['configure']);
    expect(player.playbackState.value.playing, isTrue);
  });
}
