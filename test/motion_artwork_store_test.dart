import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/player_motion_artwork_provider.dart';
import 'package:spotiflac_android/services/motion_artwork_store.dart';

void main() {
  const album = (album: 'An Album', artist: 'An Artist');
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('motion-test-'),
  );
  tearDown(() async => root.delete(recursive: true));

  test(
    'saved video survives restart and app directory relocation offline',
    () async {
      var downloads = 0;
      var location = Directory('${root.path}/old-container');
      final store = MotionArtworkStore(
        directory: () async => location,
        download: (_, output) async {
          downloads++;
          await File(output).writeAsBytes([1, 2, 3, 4]);
          return 0.75;
        },
      );
      final saved = await store.save(
        album,
        resolveSource: () async => 'https://example.com/cover.m3u8',
      );
      expect(saved?.aspectRatio, 0.75);
      expect(await File.fromUri(Uri.parse(saved!.source)).readAsBytes(), [
        1,
        2,
        3,
        4,
      ]);
      location = await location.rename('${root.path}/new-container');
      final restarted = MotionArtworkStore(
        directory: () async => location,
        download: (_, _) async => throw StateError('offline'),
      );
      final cached = await restarted.save((
        album: '  AN   ALBUM ',
        artist: 'AN ARTIST',
      ), resolveSource: () async => throw StateError('offline'));
      expect(cached?.source, contains('new-container'));
      expect(cached?.aspectRatio, 0.75);
      expect(downloads, 1);
      final container = ProviderContainer(
        overrides: [motionArtworkStoreProvider.overrideWithValue(restarted)],
      );
      addTearDown(container.dispose);
      final playback = await container.read(
        playerMotionArtworkProvider(album).future,
      );
      expect(playback?.source, cached?.source);
      expect(container.exists(extensionProvider), isFalse);
    },
  );

  test('concurrent tracks in one album download one complete video', () async {
    final gate = Completer<void>();
    var downloads = 0;
    var lookups = 0;
    final store = MotionArtworkStore(
      directory: () async => root,
      download: (_, output) async {
        downloads++;
        await gate.future;
        await File(output).writeAsBytes([1]);
        return 0.75;
      },
    );
    Future<String?> resolve() async {
      lookups++;
      return 'https://example.com/video.mp4';
    }

    final first = store.save(album, resolveSource: resolve);
    final second = store.save(album, resolveSource: resolve);
    gate.complete();
    final saved = await Future.wait([first, second]);
    expect(saved.first?.source, saved.last?.source);
    expect(downloads, 1);
    expect(lookups, 1);
    expect(
      root.listSync().whereType<File>().where((f) => f.path.endsWith('.mp4')),
      hasLength(1),
    );
  });

  test(
    'failed optional transfers leave no partial file and can retry',
    () async {
      var fail = true;
      final store = MotionArtworkStore(
        directory: () async => root,
        download: (_, output) async {
          await File(output).writeAsBytes([1]);
          if (fail) throw const SocketException('offline');
          return 1.0;
        },
      );
      Future<String?> resolve() async => 'https://example.com/video.mp4';
      expect(await store.save(album, resolveSource: resolve), isNull);
      expect(root.listSync(), isEmpty);
      expect(await store.find(album), isNull);
      fail = false;
      expect(await store.save(album, resolveSource: resolve), isNotNull);
    },
  );

  test(
    'only remote artwork is downloaded and unknown albums keep static art',
    () async {
      final store = MotionArtworkStore(
        directory: () async => root,
        download: (_, _) async => throw StateError('must not download'),
      );
      expect(
        await store.save(
          album,
          resolveSource: () async => 'file:///private/video.mp4',
        ),
        isNull,
      );
      expect(
        await store.save((
          album: '',
          artist: '',
        ), resolveSource: () async => throw StateError('no album')),
        isNull,
      );
      expect(root.listSync(), isEmpty);
    },
  );

  test(
    'clearing saved motion waits for writes and keeps the music file',
    () async {
      final music = File('${root.path}/song.flac');
      await music.writeAsBytes([9, 8, 7]);
      final gate = Completer<void>();
      final started = Completer<void>();
      final store = MotionArtworkStore(
        directory: () async => Directory('${root.path}/motion'),
        download: (_, output) async {
          started.complete();
          await gate.future;
          await File(output).writeAsBytes([1]);
          return 0.75;
        },
      );
      final save = store.save(
        album,
        resolveSource: () async => 'https://example.com/cover.mp4',
      );
      await started.future;
      final clear = store.clear();
      expect(
        await store.save(
          album,
          resolveSource: () async => throw StateError('clearing'),
        ),
        isNull,
      );
      gate.complete();
      await save;
      await clear;
      expect(await store.find(album), isNull);
      expect(await music.readAsBytes(), [9, 8, 7]);
    },
  );

  test(
    'download queue track serialization retains extension motion artwork',
    () {
      final track = Track.fromBackendMap({
        'id': 'track',
        'name': 'Track',
        'artists': 'Artist',
        'album_name': 'Album',
        'header_video': 'https://example.com/cover.m3u8',
      }, source: 'example-provider');
      final restored = Track.fromJson(track.copyWith(name: 'Updated').toJson());
      expect(restored.headerVideoUrl, 'https://example.com/cover.m3u8');
      expect(restored.source, 'example-provider');
    },
  );
}
