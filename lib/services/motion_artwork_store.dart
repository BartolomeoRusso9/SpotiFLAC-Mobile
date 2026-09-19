import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/services/ffmpeg_service.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:spotiflac_android/utils/string_utils.dart';

typedef MotionArtworkAlbum = ({String album, String artist});

class MotionArtwork {
  const MotionArtwork(this.source, {this.aspectRatio});

  final String source;
  final double? aspectRatio;
}

/// Durable, album-scoped artwork. Relative filenames survive iOS reinstalls
/// that relocate the app container; temporary cache cleanup does not remove it.
class MotionArtworkStore {
  MotionArtworkStore({
    Future<Directory> Function()? directory,
    Future<double?> Function(String source, String output)? download,
  }) : _directory = directory ?? defaultDirectory,
       _download = download ?? _downloadVideo;

  final Future<Directory> Function() _directory;
  final Future<double?> Function(String source, String output) _download;
  final _pending = <String, Future<MotionArtwork?>>{};
  bool _clearing = false;
  static final _log = AppLogger('MotionArtwork');

  static Future<Directory> defaultDirectory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/motion_artwork',
  );

  String _key(MotionArtworkAlbum album) {
    String normalize(String value) =>
        value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([normalize(album.album), normalize(album.artist)]),
          ),
        )
        .toString();
  }

  Future<MotionArtwork?> find(MotionArtworkAlbum album) async {
    try {
      final root = await _directory();
      final key = _key(album);
      final file = File('${root.path}/$key.mp4');
      if (!await file.exists() || await file.length() == 0) return null;
      double? ratio;
      final info = File('${root.path}/$key.json');
      if (await info.exists()) {
        final data = jsonDecode(await info.readAsString());
        if (data is Map && data['aspectRatio'] is num) {
          final value = (data['aspectRatio'] as num).toDouble();
          if (value.isFinite && value > 0) ratio = value;
        }
      }
      return MotionArtwork(file.uri.toString(), aspectRatio: ratio);
    } catch (_) {
      return null;
    }
  }

  Future<MotionArtwork?> save(
    MotionArtworkAlbum album, {
    required Future<String?> Function() resolveSource,
  }) {
    if (_clearing ||
        album.album.trim().isEmpty ||
        album.artist.trim().isEmpty) {
      return Future.value();
    }
    final key = _key(album);
    return _pending.putIfAbsent(key, () async {
      try {
        return await _save(album, key, resolveSource);
      } finally {
        _pending.remove(key);
      }
    });
  }

  Future<void> clear() async {
    _clearing = true;
    try {
      await Future.wait(_pending.values.toList());
      final root = await _directory();
      if (await root.exists()) await root.delete(recursive: true);
    } finally {
      _clearing = false;
    }
  }

  Future<MotionArtwork?> _save(
    MotionArtworkAlbum album,
    String key,
    Future<String?> Function() resolveSource,
  ) async {
    File? temporary;
    File? infoTemporary;
    try {
      final existing = await find(album);
      if (existing != null) return existing;
      final source = normalizeRemoteHttpUrl(await resolveSource());
      if (source == null) return null;
      final root = await _directory();
      await root.create(recursive: true);
      temporary = File('${root.path}/$key.partial.mp4');
      final ratio = await _download(source, temporary.path);
      if (ratio == null ||
          !ratio.isFinite ||
          ratio <= 0 ||
          !await temporary.exists() ||
          await temporary.length() == 0) {
        return null;
      }
      infoTemporary = File('${root.path}/$key.partial.json');
      await infoTemporary.writeAsString(
        jsonEncode({'aspectRatio': ratio}),
        flush: true,
      );
      final file = await temporary.rename('${root.path}/$key.mp4');
      await infoTemporary.rename('${root.path}/$key.json');
      return MotionArtwork(file.uri.toString(), aspectRatio: ratio);
    } catch (error) {
      _log.w('Could not save optional motion artwork: ${error.runtimeType}');
      return null;
    } finally {
      for (final file in [temporary, infoTemporary]) {
        try {
          if (file != null && await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  static Future<double?> _downloadVideo(String source, String output) async {
    final completed = Completer<bool>();
    // Remux public video/HLS into a self-contained, silent MP4. Bound both
    // transfer time and output size; never let optional artwork block audio.
    final session = await FFmpegKit.executeWithArgumentsAsync(
      [
        '-y',
        '-protocol_whitelist',
        'http,https,tcp,tls,crypto',
        '-rw_timeout',
        '10000000',
        '-i',
        source,
        '-map',
        '0:v:0',
        '-an',
        '-sn',
        '-dn',
        '-c:v',
        'copy',
        '-t',
        '30',
        '-fs',
        '25165824',
        '-movflags',
        '+faststart',
        output,
      ],
      (session) async {
        final success = ReturnCode.isSuccess(await session.getReturnCode());
        if (!completed.isCompleted) completed.complete(success);
      },
    );
    final success = await completed.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () async {
        await FFmpegKit.cancel(session.getSessionId());
        // Wait for this session to release its file before removing partials.
        await completed.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => false,
        );
        return false;
      },
    );
    if (!success) return null;
    final dimensions = await FFmpegService.probeImageDimensions(output);
    return dimensions == null ? null : dimensions.width / dimensions.height;
  }
}
