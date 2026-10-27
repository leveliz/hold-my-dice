import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/data/firestore_room_repository.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

Matcher _unsupported() => throwsA(
  isA<RoomException>().having(
    (e) => e.error,
    'error',
    RoomError.unsupportedVersion,
  ),
);

/// A room document as the app writes it.
Map<String, dynamic> _room({Object? v = 1, Map<String, dynamic>? over}) => {
  'v': ?v,
  'ownerUid': 'owner',
  'status': 'ended',
  'createdAt': Timestamp.fromMillisecondsSinceEpoch(1000),
  'endedAt': Timestamp.fromMillisecondsSinceEpoch(5000),
  'nextCode': 'ABC234',
  'hasPassword': false,
  'settings': {
    'startingCash': 1500,
    'goAmount': 200,
    'hideOthers': false,
    'allowSpectators': true,
    'bankLimit': null,
    'maxPlayers': 4,
  },
  ...?over,
};

void main() {
  group('the version of a room', () {
    test('this app reads version 1', () {
      expect(supportedRoomVersion, 1);
      checkRoomVersion(1);
    });

    test('a newer layout is refused', () {
      expect(() => checkRoomVersion(2), _unsupported());
      expect(() => checkRoomVersion(99), _unsupported());
    });

    test('a room with no version, or one that is not a number, is refused', () {
      expect(() => checkRoomVersion(null), _unsupported());
      expect(() => checkRoomVersion('1'), _unsupported());
    });
  });

  group('reading a room document', () {
    test('gives the room, with its end and the next game', () {
      final meta = FirestoreRoomRepository.metaOf('ABC234', _room());
      expect(meta.code, 'ABC234');
      expect(meta.status, RoomStatus.ended);
      expect(meta.endedAt, DateTime.fromMillisecondsSinceEpoch(5000));
      expect(meta.nextCode, 'ABC234');
      expect(meta.settings.maxPlayers, 4);
    });

    test('no next game and no end are null', () {
      final meta = FirestoreRoomRepository.metaOf(
        'ABC234',
        _room(over: {'status': 'lobby', 'endedAt': null, 'nextCode': null}),
      );
      expect(meta.nextCode, isNull);
      expect(meta.endedAt, isNull);
    });

    test('a room of a newer layout is refused before anything else in it', () {
      expect(
        () => FirestoreRoomRepository.metaOf('ABC234', _room(v: 2)),
        _unsupported(),
      );
      // Even when it has fields this app does not know and misses its own.
      expect(
        () => FirestoreRoomRepository.metaOf('ABC234', {'v': 2, 'x': 1}),
        _unsupported(),
      );
    });

    test('a room with no version is refused too', () {
      expect(
        () => FirestoreRoomRepository.metaOf('ABC234', _room(v: null)),
        _unsupported(),
      );
    });
  });
}
