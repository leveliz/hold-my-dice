import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/palette.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/tour/tour_layout.dart';
import 'package:hold_my_dice/core/tour/tour_step.dart';
import 'package:hold_my_dice/core/widgets/dashed_border.dart';

/// How a tour ended. [closed] means the screen under it went away, so the
/// tour was cut short and does not count as seen.
enum TourOutcome { finished, skipped, closed }

const _cardMaxWidth = 480.0;
const _cardMinWidth = 280.0;
const _spotRadius = 10.0;
const _spotPadding = 4.0;

/// A tour that is on the screen.
class TourSession {
  TourSession._(this._navigator, this._route);

  final NavigatorState _navigator;
  final Route<TourOutcome> _route;
  var _closedFromOutside = false;

  /// Completes when the tour ends.
  Future<TourOutcome> get result async {
    final outcome = await _route.popped;
    if (_closedFromOutside) return TourOutcome.closed;
    return outcome ?? TourOutcome.skipped;
  }

  /// Takes the tour off the screen without finishing it.
  void close() {
    if (!_route.isActive) return;
    _closedFromOutside = true;
    _navigator.removeRoute(_route);
  }
}

/// Shows [steps] over the current screen: everything goes dark except the
/// lit-up spot, and a card says what it is. The system back button skips.
TourSession showTour(BuildContext context, List<TourStep> steps) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = RawDialogRoute<TourOutcome>(
    barrierDismissible: false,
    barrierColor: null,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) => _TourPage(steps: steps),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
  navigator.push(route);
  return TourSession._(navigator, route);
}

class _TourPage extends StatefulWidget {
  const _TourPage({required this.steps});

  final List<TourStep> steps;

  @override
  State<_TourPage> createState() => _TourPageState();
}

class _TourPageState extends State<_TourPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hand = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  final _cardKey = GlobalKey();

  /// Index into the tour's steps of the one on show.
  var _at = 0;
  Size? _cardSize;

  /// A step that left the card no room is shown with its destination lit up
  /// and no hand.
  var _degraded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // With reduced motion the hand stands still, so there is nothing to run.
    if (MediaQuery.disableAnimationsOf(context)) {
      _hand.stop();
    } else if (!_hand.isAnimating) {
      _hand.repeat();
    }
  }

  @override
  void dispose() {
    _hand.dispose();
    super.dispose();
  }

  /// The steps whose spot can be found on this screen right now.
  List<int> _playable(Size screen) => [
    for (var i = 0; i < widget.steps.length; i++)
      if (tourTargetRect(widget.steps[i].target, screen) != null) i,
  ];

  void _end(TourOutcome outcome) {
    if (mounted) Navigator.of(context).pop(outcome);
  }

  void _go(int step) => setState(() {
    _at = step;
    _degraded = false;
    _cardSize = null;
  });

  void _next(List<int> playable) {
    final i = playable.indexOf(_at);
    i + 1 >= playable.length
        ? _end(TourOutcome.finished)
        : _go(playable[i + 1]);
  }

  void _back(List<int> playable) {
    final i = playable.indexOf(_at);
    if (i > 0) _go(playable[i - 1]);
  }

  KeyEventResult _onKey(List<int> playable, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _end(TourOutcome.skipped);
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.enter) {
      _next(playable);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _back(playable);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _measureCard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = _cardKey.currentContext?.size;
      if (size != null && size != _cardSize) setState(() => _cardSize = size);
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final playable = _playable(screen);
    if (playable.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _end(TourOutcome.closed),
      );
      return const SizedBox.shrink();
    }
    if (!playable.contains(_at)) {
      // This step lost its spot (the window changed): move on to the next one
      // that still has it, or the last one before it.
      final next = playable.firstWhere(
        (i) => i > _at,
        orElse: () => playable.last,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _go(next);
      });
      return const SizedBox.shrink();
    }

    final step = widget.steps[_at];
    final position = playable.indexOf(_at);
    final last = position == playable.length - 1;
    final target = tourTargetRect(step.target, screen)!;
    final destination = tourTargetRect(step.destination, screen);
    final wantsHand =
        step.gesture != TourGesture.none &&
        (step.gesture != TourGesture.drag || destination != null);
    final showHand = wantsHand && !_degraded;
    final spots = [if (!_degraded || destination == null) target, ?destination];

    final landscape = screen.width > screen.height;
    // Sideways the card takes under half the width (two fifths) so it can sit in a corner,
    // but never so little that its buttons do not fit.
    final cardWidth = math.min(
      math.min(_cardMaxWidth, screen.width - 2 * tourMargin),
      landscape ? math.max(_cardMinWidth, screen.width * 0.4) : _cardMaxWidth,
    );
    final size = _cardSize;
    var offset = size == null
        ? null
        : placeTourCard(
            screen: screen,
            safe: media.padding,
            spots: spots,
            card: size,
          );
    if (size != null && offset == null) {
      if (!_degraded && wantsHand) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _degraded = true);
        });
      } else {
        // No free place at all: the card sits at the bottom over the spot.
        offset = Offset(
          (screen.width - size.width) / 2,
          screen.height - media.padding.bottom - tourMargin - size.height,
        );
      }
    }
    _measureCard();

    final reduce = MediaQuery.disableAnimationsOf(context);
    final paper = PaperStyle.maybeOf(context) != null;
    final ring = paper ? PaperStyle.stamp : Palette.cobaltLight;

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) => _onKey(playable, event),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _end(TourOutcome.skipped);
        },
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: ExcludeSemantics(
                  child: CustomPaint(
                    key: const ValueKey('tour-dim'),
                    painter: _DimPainter(
                      spots: spots,
                      color: paper
                          ? PaperStyle.ink.withValues(alpha: 0.7)
                          : Colors.black.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < spots.length; i++)
                Positioned.fromRect(
                  key: ValueKey('tour-spot-$i'),
                  rect: spots[i].inflate(_spotPadding),
                  child: IgnorePointer(
                    // A spot that fills much of the screen (a whole half of
                    // Point Blank) is already plain from the dark around it,
                    // and its outline would run across the middle buttons.
                    child: _isLarge(spots[i], screen)
                        ? const SizedBox.expand()
                        : DashedBorder(
                            color: ring,
                            radius: _spotRadius,
                            child: const SizedBox.expand(),
                          ),
                  ),
                ),
              if (showHand)
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _hand,
                        builder: (context, _) => CustomPaint(
                          key: const ValueKey('tour-hand'),
                          painter: _HandPainter(
                            gesture: step.gesture,
                            from: target,
                            to: destination,
                            t: reduce ? null : _hand.value,
                            color: ring,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: offset?.dx ?? 0,
                top: offset?.dy ?? 0,
                child: Opacity(
                  opacity: offset == null ? 0 : 1,
                  child: SizedBox(
                    key: _cardKey,
                    width: cardWidth,
                    child: _TourCard(
                      step: step,
                      position: position,
                      count: playable.length,
                      last: last,
                      onSkip: () => _end(TourOutcome.skipped),
                      onBack: position == 0 ? null : () => _back(playable),
                      onNext: () => _next(playable),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isLarge(Rect spot, Size screen) =>
    spot.width * spot.height > screen.width * screen.height * 0.3;

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.step,
    required this.position,
    required this.count,
    required this.last,
    required this.onSkip,
    required this.onBack,
    required this.onNext,
  });

  final TourStep step;
  final int position;
  final int count;
  final bool last;
  final VoidCallback onSkip;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.7);
    // Skip and Back are the quiet choices: plain text in the body colour.
    final quiet = TextButton.styleFrom(foregroundColor: scheme.onSurface);
    return Semantics(
      container: true,
      label: '${step.title}. ${step.body}. ขั้น ${position + 1} จาก $count',
      child: Container(
        key: const ValueKey('tour-card'),
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
        decoration: panelDecoration(context),
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      step.title,
                      key: const ValueKey('tour-title'),
                      style: headingStyle(context, text.titleMedium),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${position + 1}/$count',
                    key: const ValueKey('tour-step'),
                    style: text.bodyMedium?.copyWith(color: muted),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                step.body,
                key: const ValueKey('tour-body'),
                style: text.bodyMedium,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton(
                    key: const ValueKey('tour-skip'),
                    onPressed: onSkip,
                    style: quiet,
                    child: const Text('ข้าม'),
                  ),
                  const Spacer(),
                  if (onBack != null)
                    TextButton(
                      key: const ValueKey('tour-back'),
                      onPressed: onBack,
                      style: quiet,
                      child: const Text('ย้อนกลับ'),
                    ),
                  const SizedBox(width: 4),
                  FilledButton(
                    key: const ValueKey('tour-next'),
                    onPressed: onNext,
                    child: Text(last ? 'เข้าใจแล้ว' : 'ถัดไป'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Darkens the screen except where the spots are.
class _DimPainter extends CustomPainter {
  const _DimPainter({required this.spots, required this.color});

  final List<Rect> spots;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Dark everywhere, then each spot rubbed out of that layer. (Cutting the
    // spots out of a path instead did not come out on every platform.)
    final area = Offset.zero & size;
    canvas.saveLayer(area, Paint());
    canvas.drawRect(area, Paint()..color = color);
    for (final spot in spots) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          spot.inflate(_spotPadding),
          const Radius.circular(_spotRadius),
        ),
        Paint()..blendMode = BlendMode.clear,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DimPainter old) =>
      old.color != color || !_sameRects(old.spots, spots);
}

bool _sameRects(List<Rect> a, List<Rect> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A hand showing the gesture: a tap, a quick swipe down, or a press and drag
/// from one spot to another. With [t] null (reduced motion) it stands still at
/// the start, with a dashed arrow for the gestures that move.
class _HandPainter extends CustomPainter {
  const _HandPainter({
    required this.gesture,
    required this.from,
    required this.to,
    required this.t,
    required this.color,
  });

  final TourGesture gesture;
  final Rect from;
  final Rect? to;
  final double? t;
  final Color color;

  /// Where the hand first touches. A small spot (a team name, a serve button)
  /// would be hidden under the hand, so it touches the lower right corner.
  Offset get start => switch (gesture) {
    TourGesture.swipeDown => Offset(
      from.center.dx,
      from.top + from.height * 0.3,
    ),
    _ when from.width < 140 && from.height < 80 => Offset(
      from.right - math.min(24, from.width * 0.3),
      from.bottom - math.min(14, from.height * 0.3),
    ),
    _ => from.center,
  };

  Offset? get _end => switch (gesture) {
    TourGesture.swipeDown => Offset(
      from.center.dx,
      from.top + from.height * 0.75,
    ),
    TourGesture.drag => to?.center,
    _ => null,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final start = this.start;
    final end = _end;
    var finger = start;
    var press = 1.0;
    if (t != null && end != null) {
      // Swipes are quick, drags are slow; both rest a moment at the end.
      final run = gesture == TourGesture.swipeDown ? 0.35 : 0.6;
      final p = (t! / run).clamp(0.0, 1.0);
      finger = Offset.lerp(start, end, Curves.easeInOut.transform(p))!;
    } else if (t != null) {
      press = 1 - 0.25 * math.sin(t! * math.pi * 2).abs();
    }
    if (end != null) {
      final trail = Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final length = (end - start).distance;
      final dir = (end - start) / length;
      for (var d = 0.0; d < length; d += 12) {
        canvas.drawLine(
          start + dir * d,
          start + dir * math.min(d + 5, length),
          trail,
        );
      }
    }
    canvas.drawCircle(
      finger,
      24 * press,
      Paint()..color = Colors.white.withValues(alpha: 0.3),
    );
    canvas.drawCircle(finger, 14, Paint()..color = Colors.white);
    canvas.drawCircle(
      finger,
      14,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_HandPainter old) =>
      old.t != t ||
      old.gesture != gesture ||
      old.from != from ||
      old.to != to ||
      old.color != color;
}
