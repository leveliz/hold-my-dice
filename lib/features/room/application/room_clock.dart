import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What "now" is for the times the screen shows and counts from; tests
/// replace it.
final roomClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
