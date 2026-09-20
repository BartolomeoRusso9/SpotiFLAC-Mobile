import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/services/motion_artwork_store.dart';

typedef PlayerArtworkAlbum = ({String album, String artist});

final motionArtworkStoreProvider = Provider((ref) => MotionArtworkStore());

/// Playback only reads artwork already saved with a download. Opening a player
/// must never search other extensions or trigger an artwork download.
final playerMotionArtworkProvider = FutureProvider.autoDispose
    .family<MotionArtwork?, PlayerArtworkAlbum>((ref, album) async {
      if (album.album.trim().isEmpty || album.artist.trim().isEmpty) {
        return null;
      }
      return ref.watch(motionArtworkStoreProvider).find(album);
    });
