import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether this launch of the app has already asked about unfinished games. A
/// game left on purpose is not asked about again when the person is back at
/// the start page: it waits in the "เกมค้าง" tab. Leaving a game counts as
/// having been asked, so the question does not follow the person out of it.
class ResumeOffered extends Notifier<bool> {
  @override
  bool build() => false;

  void mark() => state = true;
}

final resumeOfferedProvider = NotifierProvider<ResumeOffered, bool>(
  ResumeOffered.new,
);
