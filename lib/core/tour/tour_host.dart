import 'package:flutter/material.dart';
import 'package:hold_my_dice/core/tour/tour_overlay.dart';
import 'package:hold_my_dice/core/tour/tour_step.dart';
import 'package:hold_my_dice/core/tour/tour_store.dart';

class _Offer {
  _Offer(this.storage, this.id, this.steps, this.alsoSeenOnSkip, this.ready);

  final TourStorage storage;
  final String id;
  final List<TourStep> Function() steps;
  final List<String> alsoSeenOnSkip;
  final bool Function()? ready;
}

/// Lets a screen offer first-run tours. A tour starts once the screen is the
/// top route and has finished sliding in, nothing else is on it, and the
/// person has not seen that tour. Tours offered together run one after the
/// other. A tour that is cut short because the screen went away does not
/// count as seen.
mixin TourHost<T extends StatefulWidget> on State<T> {
  final _offers = <_Offer>[];
  TourSession? _session;
  Animation<double>? _watched;

  /// Offers the tour [id] made of [steps] (built when it starts, so the
  /// targets are on screen). Skipping it also marks [alsoSeenOnSkip]. If
  /// [ready] is given the tour waits until it says true; it is asked again
  /// whenever the screen's surroundings change (size, route).
  void offerTour({
    required TourStorage storage,
    required String id,
    required List<TourStep> Function() steps,
    List<String> alsoSeenOnSkip = const [],
    bool Function()? ready,
  }) {
    if (storage.isSeen(id)) return;
    _offers.add(_Offer(storage, id, steps, alsoSeenOnSkip, ready));
    _kick();
  }

  // Asking for the route makes this run again whenever the screen becomes the
  // top route (a dialog above it closed) and whenever the size changes.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute.of(context);
    if (_offers.isNotEmpty) _kick();
  }

  @override
  void dispose() {
    _watched?.removeStatusListener(_onAnimation);
    _offers.clear();
    _session?.close();
    super.dispose();
  }

  void _kick() {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _tryStart())
      // A quiet screen draws no frame of its own to run this in.
      ..scheduleFrame();
  }

  void _onAnimation(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _watched?.removeStatusListener(_onAnimation);
      _watched = null;
      _kick();
    }
  }

  Future<void> _tryStart() async {
    if (!mounted || _session != null || _offers.isEmpty) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    final sliding = route?.animation;
    if (sliding != null && !sliding.isCompleted) {
      if (_watched != sliding) {
        _watched?.removeStatusListener(_onAnimation);
        _watched = sliding..addStatusListener(_onAnimation);
      }
      return;
    }
    final offer = _offers.first;
    if (offer.storage.isSeen(offer.id)) {
      _offers.removeAt(0);
      return _tryStart();
    }
    if (!(offer.ready?.call() ?? true)) return;

    final session = showTour(context, offer.steps());
    _session = session;
    final outcome = await session.result;
    _session = null;
    switch (outcome) {
      case TourOutcome.finished:
        offer.storage.markSeen([offer.id]);
      case TourOutcome.skipped:
        offer.storage.markSeen([offer.id, ...offer.alsoSeenOnSkip]);
      case TourOutcome.closed:
        break;
    }
    _offers.remove(offer);
    if (mounted) _kick();
  }
}
