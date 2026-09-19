import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:spotiflac_android/l10n/l10n.dart';

/// Landscape keeps the cover in place while the right pane switches between
/// lyrics, the queue, and controls revealed by a tap.
class MornyeLandscapePlayer extends StatefulWidget {
  const MornyeLandscapePlayer({
    super.key,
    required this.artwork,
    required this.header,
    required this.lyrics,
    required this.queue,
    required this.controls,
    required this.volume,
  });

  final Widget artwork;
  final Widget header;
  final Widget lyrics;
  final Widget queue;
  final Widget controls;
  final Widget volume;

  @override
  State<MornyeLandscapePlayer> createState() => _MornyeLandscapePlayerState();
}

class _MornyeLandscapePlayerState extends State<MornyeLandscapePlayer> {
  Timer? _hideTimer;
  bool _controlsVisible = false;
  bool _queueVisible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.accessibleNavigationOf(context)) {
      _controlsVisible = true;
      _hideTimer?.cancel();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_controlsVisible || MediaQuery.accessibleNavigationOf(context)) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent == false) {
        _scheduleHide();
        return;
      }
      setState(() => _controlsVisible = false);
    });
  }

  void _reveal() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _showPanel({required bool queue}) {
    _hideTimer?.cancel();
    setState(() {
      _queueVisible = queue;
      _controlsVisible = false;
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _hideTimer?.cancel(),
    onPointerUp: (_) => _scheduleHide(),
    onPointerCancel: (_) => _scheduleHide(),
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _reveal,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(child: widget.artwork),
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: widget.header,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        layoutBuilder: (current, previous) => Stack(
                          fit: StackFit.expand,
                          children: [
                            for (final child in previous)
                              IgnorePointer(
                                child: ExcludeSemantics(child: child),
                              ),
                            ?current,
                          ],
                        ),
                        child: _controlsVisible
                            ? SingleChildScrollView(
                                key: const ValueKey('landscape-controls'),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight,
                                  ),
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      widget.controls,
                                      widget.volume,
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            IconButton(
                                              tooltip: context
                                                  .l10n
                                                  .nowPlayingTabLyrics,
                                              icon: const Icon(
                                                CupertinoIcons.quote_bubble,
                                              ),
                                              onPressed: () =>
                                                  _showPanel(queue: false),
                                            ),
                                            IconButton(
                                              tooltip:
                                                  context.l10n.nowPlayingUpNext,
                                              icon: const Icon(
                                                CupertinoIcons.list_bullet,
                                              ),
                                              onPressed: () =>
                                                  _showPanel(queue: true),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : KeyedSubtree(
                                key: ValueKey(_queueVisible),
                                child: _queueVisible
                                    ? widget.queue
                                    : widget.lyrics,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
