import 'package:flutter/widgets.dart';

/// What the ghost hand shows on a step.
enum TourGesture { none, tap, swipeDown, drag }

/// One stop of a tour: what is lit up and what it says.
class TourStep {
  const TourStep({
    required this.title,
    required this.body,
    required this.target,
    this.gesture = TourGesture.none,
    this.destination,
  });

  final String title;
  final String body;

  /// The widget that is lit up.
  final GlobalKey target;

  final TourGesture gesture;

  /// Where a [TourGesture.drag] ends, lit up as well.
  final GlobalKey? destination;
}
