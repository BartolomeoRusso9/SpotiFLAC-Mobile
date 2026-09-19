import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/l10n/app_localizations.dart';
import 'package:spotiflac_android/services/shell_navigation_service.dart';
import 'package:spotiflac_android/widgets/view_queue_snackbar_action.dart';

void main() {
  testWidgets('first search request reaches a lazily mounted Home tab', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _SearchShell()));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('one search request returns from an album and focuses Home', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _SearchShell()));
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    final navigator = ShellNavigationService.homeTabNavigatorKey.currentState!;
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Album')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.text('Album'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets(
    'search selects Home before requesting focus and stops when shell is absent',
    (tester) async {
      final owner = Object();
      var selectedHome = false;
      var focusRequests = 0;
      void onSearch() {
        expect(selectedHome, isTrue);
        focusRequests++;
      }

      ShellNavigationService.homeSearchRequests.addListener(onSearch);
      addTearDown(() {
        ShellNavigationService.homeSearchRequests.removeListener(onSearch);
        ShellNavigationService.unregisterTabSelectionHandler(owner);
      });
      ShellNavigationService.registerTabSelectionHandler(
        owner: owner,
        handler: (tab) => selectedHome = tab == ShellTab.home,
      );
      ShellNavigationService.requestHomeSearch();
      expect(focusRequests, 0);
      await tester.pump();
      expect(focusRequests, 1);
      ShellNavigationService.unregisterTabSelectionHandler(owner);
      ShellNavigationService.requestHomeSearch();
      expect(focusRequests, 1);
    },
  );

  group('ShellNavigationService tab requests', () {
    test('forwards a named tab request to the registered shell', () {
      final owner = Object();
      ShellTab? requestedTab;
      addTearDown(
        () => ShellNavigationService.unregisterTabSelectionHandler(owner),
      );

      ShellNavigationService.registerTabSelectionHandler(
        owner: owner,
        handler: (tab) => requestedTab = tab,
      );

      expect(ShellNavigationService.requestTab(ShellTab.library), isTrue);
      expect(requestedTab, ShellTab.library);
    });

    test('does not remove a newer shell handler', () {
      final oldOwner = Object();
      final currentOwner = Object();
      ShellTab? requestedTab;
      addTearDown(
        () =>
            ShellNavigationService.unregisterTabSelectionHandler(currentOwner),
      );

      ShellNavigationService.registerTabSelectionHandler(
        owner: oldOwner,
        handler: (_) {},
      );
      ShellNavigationService.registerTabSelectionHandler(
        owner: currentOwner,
        handler: (tab) => requestedTab = tab,
      );

      ShellNavigationService.unregisterTabSelectionHandler(oldOwner);

      expect(ShellNavigationService.requestTab(ShellTab.settings), isTrue);
      expect(requestedTab, ShellTab.settings);
    });

    test('reports when no shell can handle the request', () {
      final owner = Object();
      ShellNavigationService.registerTabSelectionHandler(
        owner: owner,
        handler: (_) {},
      );
      ShellNavigationService.unregisterTabSelectionHandler(owner);

      expect(ShellNavigationService.requestTab(ShellTab.library), isFalse);
    });

    testWidgets('View Queue snackbar action requests the Library tab', (
      tester,
    ) async {
      final owner = Object();
      ShellTab? requestedTab;
      addTearDown(
        () => ShellNavigationService.unregisterTabSelectionHandler(owner),
      );
      ShellNavigationService.registerTabSelectionHandler(
        owner: owner,
        handler: (tab) => requestedTab = tab,
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => buildViewQueueSnackBarAction(context),
            ),
          ),
        ),
      );

      await tester.tap(find.text('View Queue'));

      expect(requestedTab, ShellTab.library);
    });
  });
}

class _SearchShell extends StatefulWidget {
  const _SearchShell();

  @override
  State<_SearchShell> createState() => _SearchShellState();
}

class _SearchShellState extends State<_SearchShell> {
  final _pages = PageController(initialPage: 1);
  late final _observer = ShellChromeObserver(
    ShellNavigationService.homeTabNavigatorKey,
  );

  @override
  void initState() {
    super.initState();
    ShellNavigationService.syncState(currentTabIndex: 1, showRepoTab: false);
    ShellNavigationService.registerTabSelectionHandler(
      owner: this,
      handler: (_) {
        ShellNavigationService.syncState(
          currentTabIndex: 0,
          showRepoTab: false,
        );
        _pages.jumpToPage(0);
      },
    );
  }

  @override
  void dispose() {
    ShellNavigationService.unregisterTabSelectionHandler(this);
    _observer.detach();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextButton(
          onPressed: ShellNavigationService.requestHomeSearch,
          child: const Text('Search'),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pages,
            itemCount: 2,
            itemBuilder: (_, index) => index == 1
                ? const Text('Library')
                : Navigator(
                    key: ShellNavigationService.homeTabNavigatorKey,
                    observers: [_observer],
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => const _SearchHome(),
                    ),
                  ),
          ),
        ),
      ],
    ),
  );
}

class _SearchHome extends StatefulWidget {
  const _SearchHome();

  @override
  State<_SearchHome> createState() => _SearchHomeState();
}

class _SearchHomeState extends State<_SearchHome> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    ShellNavigationService.homeSearchRequests.addListener(_onSearch);
  }

  void _onSearch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    ShellNavigationService.homeSearchRequests.removeListener(_onSearch);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: TextField(focusNode: _focus));
}
