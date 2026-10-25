import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/application/presence_beater.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';

/// A repository that counts heartbeats and can be made to fail them.
class _Counting extends FakeRoomRepository {
  _Counting() : super(FakeRoomStore(), FakeAuthService('me'));

  final beats = <String>[];
  var failing = false;

  @override
  Future<void> heartbeat(String code) async {
    beats.add(code);
    if (failing) throw const RoomException(RoomError.offline);
  }
}

void main() {
  test('start sends one beat at once', () {
    FakeAsync().run((async) {
      final repo = _Counting();
      PresenceBeater(repo, 'ABC234').start();
      async.flushMicrotasks();
      expect(repo.beats, ['ABC234']);
    });
  });

  test('then one every 60 seconds', () {
    FakeAsync().run((async) {
      final repo = _Counting();
      PresenceBeater(repo, 'ABC234').start();
      async.elapse(const Duration(seconds: 59));
      expect(repo.beats.length, 1);
      async.elapse(const Duration(seconds: 1));
      expect(repo.beats.length, 2);
      async.elapse(const Duration(minutes: 3));
      expect(repo.beats.length, 5);
    });
  });

  test('the interval can be chosen', () {
    FakeAsync().run((async) {
      final repo = _Counting();
      PresenceBeater(
        repo,
        'ABC234',
        every: const Duration(seconds: 10),
      ).start();
      async.elapse(const Duration(seconds: 30));
      expect(repo.beats.length, 4);
    });
  });

  test('stop ends the beats and leaves no timer behind', () {
    FakeAsync().run((async) {
      final repo = _Counting();
      final beater = PresenceBeater(repo, 'ABC234')..start();
      async.elapse(const Duration(seconds: 61));
      beater.stop();
      expect(async.pendingTimers, isEmpty);
      async.elapse(const Duration(minutes: 10));
      expect(repo.beats.length, 2);
    });
  });

  test('a failed beat does not stop the next ones and does not throw', () {
    FakeAsync().run((async) {
      final repo = _Counting()..failing = true;
      PresenceBeater(repo, 'ABC234').start();
      async.elapse(const Duration(seconds: 61));
      repo.failing = false;
      async.elapse(const Duration(seconds: 60));
      expect(repo.beats.length, 3);
    });
  });

  test('start twice does not double the beats', () {
    FakeAsync().run((async) {
      final repo = _Counting();
      PresenceBeater(repo, 'ABC234')
        ..start()
        ..start();
      async.elapse(const Duration(seconds: 61));
      expect(repo.beats.length, 2);
      expect(async.pendingTimers.length, 1);
    });
  });

  test('it can be started again after a stop', () {
    FakeAsync().run((async) {
      final repo = _Counting();
      final beater = PresenceBeater(repo, 'ABC234')
        ..start()
        ..stop()
        ..start();
      async.elapse(const Duration(seconds: 61));
      expect(repo.beats.length, 3);
      beater.stop();
    });
  });
}
