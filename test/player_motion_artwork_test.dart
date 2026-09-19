import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/providers/player_motion_artwork_provider.dart';

void main() {
  const album = (album: 'An Album', artist: 'An Artist');

  test(
    'motion lookup checks album and artist before loading metadata',
    () async {
      final loaded = <String>[];
      final result = await findPlayerMotionArtwork(
        album: album,
        providerIds: ['provider-a'],
        search: (_, _) async => [
          {
            'id': 'wrong-artist',
            'name': 'An Album',
            'artists': 'Not An Artist',
          },
          {
            'id': 'wrong-album',
            'name': 'Another Album',
            'artists': 'An Artist',
          },
          {'id': 'match', 'name': 'AN ALBUM', 'artists': 'An Artist'},
        ],
        loadAlbum: (_, id) async {
          loaded.add(id);
          return {
            'album_info': {'header_video': 'https://example.com/cover.m3u8'},
          };
        },
      );
      expect(loaded, ['match']);
      expect(result, 'https://example.com/cover.m3u8');
    },
  );

  test('motion lookup falls back to another provider after an error', () async {
    final result = await findPlayerMotionArtwork(
      album: album,
      providerIds: ['provider-a', 'provider-b'],
      search: (provider, _) async {
        if (provider == 'provider-a') throw StateError('offline');
        return [
          {
            'name': 'An Album',
            'artists': 'An Artist',
            'header_video': 'https://example.com/motion.m3u8',
          },
        ];
      },
      loadAlbum: (_, _) async =>
          throw StateError('Direct artwork needs no lookup'),
    );
    expect(result, 'https://example.com/motion.m3u8');
  });

  test('unavailable or unsupported motion keeps the static cover', () async {
    final result = await findPlayerMotionArtwork(
      album: album,
      providerIds: ['provider-a'],
      search: (_, _) async => [
        {
          'name': 'An Album',
          'artists': 'An Artist',
          'header_video': 'file:///invalid.m3u8',
        },
      ],
      loadAlbum: (_, _) async => {},
    );
    expect(result, isNull);
  });
}
