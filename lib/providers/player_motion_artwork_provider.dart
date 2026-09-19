import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/providers/extension_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/services/motion_artwork_store.dart';
import 'package:spotiflac_android/utils/string_utils.dart';
import 'package:spotiflac_android/utils/ttl_cache.dart';

typedef PlayerArtworkAlbum = ({String album, String artist});

final motionArtworkStoreProvider = Provider((ref) => MotionArtworkStore());

final _motionCache = TtlCache<Future<String?>>(
  const Duration(minutes: 10),
  maxEntries: 32,
);

/// Resolve the same album motion artwork used by collection headers. Cache by
/// album so advancing through its tracks does not repeat metadata requests.
final playerMotionArtworkProvider = FutureProvider.autoDispose
    .family<MotionArtwork?, PlayerArtworkAlbum>((ref, album) async {
      if (album.album.trim().isEmpty || album.artist.trim().isEmpty) {
        return null;
      }
      final local = await ref.read(motionArtworkStoreProvider).find(album);
      if (local != null) return local;
      if (!ref.mounted) return null;
      final extensions = ref.watch(extensionProvider);
      final preferred = ref.watch(
        settingsProvider.select((s) => s.searchProvider),
      );
      final enabled = extensions.extensions
          .where((extension) => extension.enabled && extension.hasCustomSearch)
          .map((extension) => extension.id)
          .toSet();
      final providers = <String>{
        if (preferred != null && enabled.contains(preferred)) preferred,
        ...extensions.metadataProviderPriority.where(enabled.contains),
        ...enabled,
      }.toList();
      if (providers.isEmpty) return null;
      final key = jsonEncode([album.album, album.artist, providers]);
      final cached = _motionCache.get(key);
      if (cached != null) {
        final source = await cached;
        return source == null ? null : MotionArtwork(source);
      }
      final request = findPlayerMotionArtwork(
        album: album,
        providerIds: providers,
        search: (provider, query) => PlatformBridge.customSearchWithExtension(
          provider,
          query,
          options: {'filter': 'album', 'limit': 8},
        ).timeout(const Duration(seconds: 6)),
        loadAlbum: (provider, id) => PlatformBridge.getProviderMetadata(
          provider,
          'album',
          id,
        ).timeout(const Duration(seconds: 6)),
      );
      _motionCache.set(key, request);
      final source = await request;
      return source == null ? null : MotionArtwork(source);
    });

Future<String?> findPlayerMotionArtwork({
  required PlayerArtworkAlbum album,
  required List<String> providerIds,
  required Future<List<Map<String, dynamic>>> Function(
    String provider,
    String query,
  )
  search,
  required Future<Map<String, dynamic>> Function(String provider, String id)
  loadAlbum,
}) async {
  String normalized(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  for (final provider in providerIds) {
    try {
      final results = await search(provider, '${album.album} ${album.artist}');
      for (final result in results) {
        final name = (result['name'] ?? result['album_name'] ?? '').toString();
        final artist =
            (result['artists'] ??
                    result['artist'] ??
                    result['artist_name'] ??
                    '')
                .toString();
        // Never attach a similarly named album's video to the playing track.
        if (normalized(name) != normalized(album.album) ||
            normalized(artist) != normalized(album.artist)) {
          continue;
        }
        final direct = normalizeRemoteHttpUrl(
          result['header_video']?.toString(),
        );
        if (direct != null) return direct;
        final id = (result['id'] ?? result['album_id'] ?? '').toString();
        if (id.isEmpty) continue;
        final metadata = await loadAlbum(provider, id);
        final info = metadata['album_info'];
        final video = normalizeRemoteHttpUrl(
          ((info is Map ? info['header_video'] : null) ??
                  metadata['header_video'])
              ?.toString(),
        );
        if (video != null) return video;
      }
    } catch (_) {
      // Offline, unsupported providers and expired links keep the static cover.
    }
  }
  return null;
}
