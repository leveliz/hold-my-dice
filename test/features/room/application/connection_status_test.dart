import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/application/connection_status.dart';

void main() {
  /// Runs [body] with a source of "this snapshot came from the cache" and the
  /// list of what [onlineFrom] says.
  void scenario(
    void Function(
      FakeAsync async,
      StreamController<bool> fromCache,
      List<bool> says,
    )
    body, {
    Duration grace = const Duration(seconds: 8),
  }) {
    FakeAsync().run((async) {
      final source = StreamController<bool>();
      final says = <bool>[];
      final sub = onlineFrom(source.stream, grace: grace).listen(says.add);
      body(async, source, says);
      unawaited(sub.cancel());
      unawaited(source.close());
      async.flushMicrotasks();
    });
  }

  test('starts as online, before anything is known', () {
    scenario((async, source, says) {
      async.flushMicrotasks();
      expect(says, [true]);
    });
  });

  test('snapshots from the server keep it online', () {
    scenario((async, source, says) {
      source.add(false);
      async.elapse(const Duration(minutes: 1));
      source.add(false);
      async.flushMicrotasks();
      expect(says, [true]);
    });
  });

  test('cache snapshots for less than the grace time are not offline', () {
    scenario((async, source, says) {
      source.add(true);
      async.elapse(const Duration(seconds: 7));
      expect(says, [true]);
    });
  });

  test('cache snapshots for the whole grace time mean offline', () {
    scenario((async, source, says) {
      source.add(true);
      async.elapse(const Duration(seconds: 8));
      expect(says, [true, false]);
    });
  });

  test('more cache snapshots do not move the end of the grace time', () {
    scenario((async, source, says) {
      source.add(true);
      async.elapse(const Duration(seconds: 5));
      source.add(true);
      async.elapse(const Duration(seconds: 3));
      expect(says, [true, false]);
      expect(async.pendingTimers, isEmpty, reason: 'one countdown, not two');
    });
  });

  test('a server snapshot in time cancels the countdown', () {
    scenario((async, source, says) {
      source.add(true);
      async.elapse(const Duration(seconds: 6));
      source.add(false);
      async.elapse(const Duration(minutes: 1));
      expect(says, [true]);
    });
  });

  test('the first server snapshot after being offline is online again', () {
    scenario((async, source, says) {
      source.add(true);
      async.elapse(const Duration(seconds: 9));
      source.add(false);
      async.flushMicrotasks();
      expect(says, [true, false, true]);
    });
  });

  test('it only speaks when the answer changes', () {
    scenario((async, source, says) {
      source.add(true);
      async.elapse(const Duration(seconds: 9));
      source.add(true);
      async.elapse(const Duration(seconds: 30));
      source.add(false);
      source.add(false);
      async.flushMicrotasks();
      expect(says, [true, false, true]);
    });
  });

  test('the grace time can be chosen', () {
    scenario(grace: const Duration(seconds: 2), (async, source, says) {
      source.add(true);
      async.elapse(const Duration(seconds: 2));
      expect(says, [true, false]);
    });
  });

  test('stopping listening leaves no timer behind', () {
    FakeAsync().run((async) {
      final source = StreamController<bool>();
      final sub = onlineFrom(source.stream).listen((_) {});
      source.add(true);
      async.elapse(const Duration(seconds: 1));
      unawaited(sub.cancel());
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);
      unawaited(source.close());
    });
  });

  test('an error of the source is passed on, not swallowed', () {
    FakeAsync().run((async) {
      final source = StreamController<bool>();
      final errors = <Object>[];
      final sub = onlineFrom(source.stream).listen((_) {}, onError: errors.add);
      source.addError(StateError('boom'));
      async.flushMicrotasks();
      expect(errors.single, isA<StateError>());
      unawaited(sub.cancel());
      unawaited(source.close());
    });
  });
}
