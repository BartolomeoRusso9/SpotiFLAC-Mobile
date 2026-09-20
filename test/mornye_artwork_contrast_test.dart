import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/widgets/mornye_artwork_contrast.dart';

void main() {
  testWidgets('foreground follows changing frames separately for each region', (
    tester,
  ) async {
    final header = GlobalKey();
    final controls = GlobalKey();
    Map<String, Color> colors = {};
    var changes = 0;
    Widget app(Color top, Color bottom) => MaterialApp(
      home: Stack(
        fit: StackFit.expand,
        children: [
          MornyeArtworkContrast(
            enabled: true,
            targets: {'header': header, 'controls': controls},
            onChanged: (value) {
              colors = value;
              changes++;
            },
            child: Column(
              children: [
                Expanded(
                  child: ColoredBox(color: top, child: const SizedBox.expand()),
                ),
                Expanded(
                  child: ColoredBox(
                    color: bottom,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 20,
            left: 20,
            width: 100,
            height: 30,
            child: SizedBox(key: header),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            width: 100,
            height: 30,
            child: SizedBox(key: controls),
          ),
        ],
      ),
    );
    Future<void> sample() async {
      await tester.pump(const Duration(milliseconds: 334));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }

    await tester.pumpWidget(app(Colors.white, Colors.black));
    await sample();
    expect(colors, {'header': Colors.black, 'controls': Colors.white});
    await tester.pumpWidget(app(Colors.black, Colors.white));
    await sample();
    expect(colors, {'header': Colors.white, 'controls': Colors.black});
    final previousChanges = changes;
    await sample();
    expect(changes, previousChanges);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpWidget(app(Colors.white, Colors.black));
    await sample();
    expect(changes, previousChanges);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await sample();
    expect(colors, {'header': Colors.black, 'controls': Colors.white});
    await tester.pumpWidget(const SizedBox());
  });
}
