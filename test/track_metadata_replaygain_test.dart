import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/download_history_provider.dart';
import 'package:spotiflac_android/screens/track_metadata_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.zarz.spotiflac/backend');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  for (final hasTags in [true, false]) {
    testWidgets('metadata displays only saved ReplayGain (tags=$hasTags)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final metadata = hasTags
          ? {
              'replaygain_track_gain': ' -6.20 dB ',
              'replaygain_track_peak': '0.000000',
              'replaygain_album_gain': '0.00 dB',
              'replaygain_album_peak': '1.234567',
            }
          : {'replaygain_track_gain': ' ', 'replaygain_album_peak': null};
      messenger.setMockMethodCallHandler(channel, (call) async {
        return switch (call.method) {
          'safStat' => jsonEncode({'exists': true, 'size': 100}),
          'readAudioMetadata' => jsonEncode(metadata),
          'getLyricsLRCWithSource' => jsonEncode({'lyrics': '', 'source': ''}),
          'getSafFileModTimes' => '{}',
          _ => null,
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final item = DownloadHistoryItem(
        id: 'track-$hasTags',
        trackName: 'Track',
        artistName: 'Artist',
        albumName: 'Album',
        filePath: 'content://library/document/track-$hasTags.flac',
        service: 'provider-a',
        downloadedAt: DateTime(2026),
        quality: '16-bit/44.1kHz',
        bitDepth: 16,
        sampleRate: 44100,
        format: 'flac',
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: TrackMetadataScreen(item: item),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final text in [
        'ReplayGain Track Gain',
        'ReplayGain Track Peak',
        'ReplayGain Album Gain',
        'ReplayGain Album Peak',
        '-6.20 dB',
        '0.000000',
        '0.00 dB',
        '1.234567',
      ]) {
        expect(find.text(text), hasTags ? findsOneWidget : findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
