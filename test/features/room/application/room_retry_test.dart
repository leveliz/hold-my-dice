import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';

RoomException _room(RoomError e) => RoomException(e);

void main() {
  group('when a failed read is tried again by itself', () {
    test('not for a room that is not there, a newer layout or a refusal', () {
      for (final e in [
        RoomError.roomNotFound,
        RoomError.unsupportedVersion,
        RoomError.notAMember,
        RoomError.notAllowed,
        RoomError.wrongPassword,
        RoomError.quotaExhausted,
        RoomError.unknown,
      ]) {
        expect(roomRetry(0, _room(e)), isNull, reason: '$e');
      }
    });

    test('for a lost connection, waiting longer each time, then giving up', () {
      final offline = _room(RoomError.offline);
      expect(roomRetry(0, offline), const Duration(milliseconds: 200));
      expect(roomRetry(1, offline), const Duration(milliseconds: 400));
      expect(roomRetry(5, offline), const Duration(milliseconds: 6400));
      expect(roomRetry(10, offline), isNull);
    });

    test('other errors keep the rule of Riverpod', () {
      expect(roomRetry(0, Exception('x')), const Duration(milliseconds: 200));
      expect(roomRetry(0, StateError('a bug')), isNull);
    });
  });

  group('a provider that reads a room', () {
    test('asks once when the room is not there', () async {
      var asked = 0;
      final provider = FutureProvider.autoDispose<int>((ref) {
        asked++;
        throw _room(RoomError.roomNotFound);
      });
      final c = ProviderContainer(retry: roomRetry);
      addTearDown(c.dispose);
      final sub = c.listen(provider, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(asked, 1);
      expect(sub.read().hasError, isTrue);
    });

    test(
      'is asked again when the connection was lost, and then works',
      () async {
        var asked = 0;
        final provider = FutureProvider.autoDispose<int>((ref) {
          asked++;
          if (asked < 3) throw _room(RoomError.offline);
          return 7;
        });
        final c = ProviderContainer(retry: roomRetry);
        addTearDown(c.dispose);
        final sub = c.listen(provider, (_, _) {});
        addTearDown(sub.close);
        await Future<void>.delayed(const Duration(milliseconds: 900));
        expect(asked, 3);
        expect(sub.read().value, 7);
      },
    );
  });
}
