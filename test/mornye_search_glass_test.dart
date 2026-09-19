import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'search glass cards scroll and filters remain usable in $brightness',
      (tester) async {
        var selected = false;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: MornyeTheme.build(brightness),
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) => Column(
                    children: [
                      MornyeGlassPanel.overlay(
                        radius: 24,
                        child: MornyeFilterChip(
                          label: 'Albums',
                          selected: selected,
                          glass: false,
                          tonal: selected,
                          onTap: () => setState(() => selected = !selected),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: 12,
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: MornyeGlassPanel.overlay(
                              radius: 24,
                              child: SizedBox(
                                height: 88,
                                child: Text('Result $index'),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Albums'));
        await tester.pumpAndSettle();
        expect(selected, isTrue);
        await tester.scrollUntilVisible(find.text('Result 11'), 200);
        await tester.pumpAndSettle();
        expect(find.text('Result 11').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
