import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hold_my_dice/features/bank/domain/transaction.dart' as bank;
import 'package:hold_my_dice/features/room/application/connection_status.dart';
import 'package:hold_my_dice/features/room/application/room_code.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/entry_draft.dart';
import 'package:hold_my_dice/features/room/domain/ledger.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

const _codeTries = 5;

/// How long a write may take before the person is told they are offline.
/// Firestore keeps a write it cannot send and never fails it, so without a
/// limit a join without signal would wait for ever.
const _writeTimeout = Duration(seconds: 15);

/// How many times a press is built again after losing the race for its place
/// in the history to other presses.
const _pressTries = 12;

/// This press found the place it wanted already taken by another one.
class _LostTheRace implements Exception {
  const _LostTheRace();
}

/// Rooms in Cloud Firestore, laid out as firestore.rules expects:
/// `rooms/{code}` with `seats`, `members`, `presence` and `state` under it.
class FirestoreRoomRepository implements RoomRepository {
  FirestoreRoomRepository(this._db, this._auth, {Random? random})
    : _random = random ?? Random.secure();

  final FirebaseFirestore _db;
  final AuthService _auth;
  final Random _random;

  DocumentReference<Map<String, dynamic>> _room(String code) =>
      _db.collection('rooms').doc(code);
  DocumentReference<Map<String, dynamic>> _seat(String code, String id) =>
      _room(code).collection('seats').doc(id);
  DocumentReference<Map<String, dynamic>> _member(String code, String uid) =>
      _room(code).collection('members').doc(uid);
  DocumentReference<Map<String, dynamic>> _presence(String code, String uid) =>
      _room(code).collection('presence').doc(uid);
  DocumentReference<Map<String, dynamic>> _state(String code) =>
      _room(code).collection('state').doc('current');

  Future<void> _commit(WriteBatch batch) => batch.commit().timeout(
    _writeTimeout,
    onTimeout: () => throw const RoomException(RoomError.offline),
  );

  /// Runs [action], turning what Firestore throws into a [RoomException];
  /// a refusal by the rules becomes [onDenied].
  Future<T> _guard<T>(Future<T> Function() action, RoomError onDenied) async {
    try {
      return await action();
    } on FirebaseException catch (e) {
      throw _translate(e, onDenied);
    }
  }

  RoomException _translate(FirebaseException e, RoomError onDenied) =>
      switch (e.code) {
        'permission-denied' => RoomException(onDenied),
        'unavailable' ||
        'network-request-failed' => const RoomException(RoomError.offline),
        'resource-exhausted' => const RoomException(RoomError.quotaExhausted),
        _ => RoomException(RoomError.unknown, '${e.code}: ${e.message}'),
      };

  Stream<T> _guardStream<T>(Stream<T> source, RoomError onDenied) =>
      source.handleError((Object e) {
        if (e is FirebaseException) throw _translate(e, onDenied);
        // A document in a shape this app does not know is not the app's crash.
        if (e is FormatException) {
          throw RoomException(RoomError.unknown, e.message);
        }
        throw e;
      });

  // ---- reading documents ------------------------------------------------

  static RoomMeta _meta(String code, Map<String, dynamic> d) {
    final s = d['settings'] as Map<String, dynamic>;
    return RoomMeta(
      code: code,
      ownerUid: d['ownerUid'] as String,
      status: RoomStatus.values.byName(d['status'] as String),
      hasPassword: d['hasPassword'] as bool,
      settings: RoomSettings(
        startingCash: s['startingCash'] as int,
        goAmount: s['goAmount'] as int,
        maxPlayers: s['maxPlayers'] as int,
        hideOthers: s['hideOthers'] as bool,
        allowSpectators: s['allowSpectators'] as bool,
        bankLimit: s['bankLimit'] as int?,
      ),
    );
  }

  static Seat _seatOf(String id, Map<String, dynamic> d) => Seat(
    id: id,
    uid: d['uid'] as String,
    name: d['name'] as String,
    color: d['color'] as int,
  );

  static Member _memberOf(String uid, Map<String, dynamic> d) => Member(
    uid: uid,
    name: d['name'] as String,
    color: d['color'] as int,
    role: MemberRole.values.byName(d['role'] as String),
    seat: d['seat'] as String?,
  );

  static RoomState _stateOf(Map<String, dynamic> d) => RoomState.fromMap(d);

  /// The room as it is now; throws [RoomError.roomNotFound] when there is none
  /// or it has ended.
  Future<RoomMeta> _readMeta(String code) async {
    final snap = await _guard(() => _room(code).get(), RoomError.roomNotFound);
    final data = snap.data();
    if (data == null) throw const RoomException(RoomError.roomNotFound);
    final meta = _meta(code, data);
    if (meta.status == RoomStatus.ended) {
      throw const RoomException(RoomError.roomNotFound);
    }
    return meta;
  }

  Future<String?> _passwordHashOf(String code) async {
    final snap = await _room(code).get();
    return snap.data()?['passwordHash'] as String?;
  }

  /// What a member document carries to prove the password, or nothing when the
  /// room has none. Throws [RoomError.wrongPassword] if it cannot match.
  Future<Map<String, dynamic>> _passwordProof(
    RoomMeta meta,
    String? password,
  ) async {
    if (!meta.hasPassword) return const {};
    final hash = password == null
        ? null
        : hashRoomPassword(password, meta.code);
    if (hash == null || hash != await _passwordHashOf(meta.code)) {
      throw const RoomException(RoomError.wrongPassword);
    }
    return {'pwHash': hash};
  }

  // ---- RoomRepository ---------------------------------------------------

  @override
  Future<RoomMeta> createRoom({
    required RoomSettings settings,
    String? password,
    required String name,
    required int color,
  }) async {
    final uid = await _auth.ensureSignedIn();
    final clean = cutName(name);
    final hasPassword = password != null && password.isNotEmpty;
    for (var attempt = 0; attempt < _codeTries; attempt++) {
      final code = generateRoomCode(_random);
      // The proof of the password goes in the owner's member document too: the
      // rules ask every new member for it, the creator included.
      final hash = hasPassword ? hashRoomPassword(password, code) : null;
      final batch = _db.batch()
        ..set(_room(code), {
          'v': 1,
          'ownerUid': uid,
          'status': 'lobby',
          'createdAt': FieldValue.serverTimestamp(),
          'settings': {
            'startingCash': settings.startingCash,
            'goAmount': settings.goAmount,
            'hideOthers': settings.hideOthers,
            'allowSpectators': settings.allowSpectators,
            'bankLimit': settings.bankLimit,
            'maxPlayers': settings.maxPlayers,
          },
          'hasPassword': hasPassword,
          'passwordHash': hash,
        })
        ..set(_seat(code, 'p1'), {
          'uid': uid,
          'name': clean,
          'color': color,
          'joinedAt': FieldValue.serverTimestamp(),
        })
        ..set(_member(code, uid), {
          'name': clean,
          'color': color,
          'role': 'player',
          'seat': 'p1',
          'pwHash': ?hash,
        })
        ..set(_presence(code, uid), {'lastSeen': FieldValue.serverTimestamp()});
      try {
        await _commit(batch);
      } on FirebaseException catch (e) {
        // A refusal here most likely means the code is taken: draw another.
        if (e.code == 'permission-denied' && attempt < _codeTries - 1) continue;
        throw _translate(e, RoomError.unknown);
      }
      return RoomMeta(
        code: code,
        ownerUid: uid,
        status: RoomStatus.lobby,
        settings: settings,
        hasPassword: hasPassword,
      );
    }
    throw const RoomException(RoomError.unknown);
  }

  @override
  Stream<RoomMeta?> watchMeta(String code) async* {
    await _auth.ensureSignedIn();
    yield* _guardStream(
      _room(code).snapshots().map((snap) {
        final data = snap.data();
        return data == null ? null : _meta(code, data);
      }),
      RoomError.roomNotFound,
    );
  }

  @override
  Future<List<Seat?>> readSeats(String code) async {
    await _auth.ensureSignedIn();
    await _readMeta(code);
    final snaps = await _guard(
      () =>
          Future.wait([for (var i = 1; i <= 8; i++) _seat(code, 'p$i').get()]),
      RoomError.unknown,
    );
    return [
      for (final (i, snap) in snaps.indexed)
        snap.data() == null ? null : _seatOf('p${i + 1}', snap.data()!),
    ];
  }

  @override
  Future<Seat> joinAsPlayer({
    required String code,
    required String name,
    required int color,
    String? password,
  }) async {
    final uid = await _auth.ensureSignedIn();
    final meta = await _readMeta(code);
    final mine = await _member(
      code,
      uid,
    ).get().then((s) => s.data(), onError: (Object _) => null);
    final mySeat = mine?['seat'] as String?;
    if (mySeat != null) {
      final snap = await _seat(code, mySeat).get();
      return _seatOf(mySeat, snap.data()!);
    }
    final proof = await _passwordProof(meta, password);
    if (meta.status != RoomStatus.lobby) {
      throw const RoomException(RoomError.alreadyStarted);
    }
    final seats = await readSeats(code);
    final free = [
      for (var i = 0; i < meta.settings.maxPlayers; i++)
        if (seats[i] == null) 'p${i + 1}',
    ];
    final clean = cutName(name);
    // Two people may pick the same free seat at once; the loser is refused by
    // the rules and tries the next free one.
    for (final id in free) {
      final batch = _db.batch()
        ..set(_seat(code, id), {
          'uid': uid,
          'name': clean,
          'color': color,
          'joinedAt': FieldValue.serverTimestamp(),
        })
        ..set(_member(code, uid), {
          'name': clean,
          'color': color,
          'role': 'player',
          'seat': id,
          ...proof,
        })
        ..set(_presence(code, uid), {'lastSeen': FieldValue.serverTimestamp()});
      try {
        await _commit(batch);
        return Seat(id: id, uid: uid, name: clean, color: color);
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') {
          throw _translate(e, RoomError.unknown);
        }
      }
    }
    throw const RoomException(RoomError.roomFull);
  }

  @override
  Future<void> joinAsSpectator({
    required String code,
    required String name,
    required int color,
    String? password,
  }) async {
    final uid = await _auth.ensureSignedIn();
    final meta = await _readMeta(code);
    final existing = await _member(
      code,
      uid,
    ).get().then((s) => s.exists, onError: (Object _) => false);
    if (existing) return;
    final proof = await _passwordProof(meta, password);
    if (!meta.settings.allowSpectators) {
      throw const RoomException(RoomError.spectatorsNotAllowed);
    }
    final batch = _db.batch()
      ..set(_member(code, uid), {
        'name': cutName(name),
        'color': color,
        'role': 'spectator',
        'seat': null,
        ...proof,
      })
      ..set(_presence(code, uid), {'lastSeen': FieldValue.serverTimestamp()});
    await _guard(() => _commit(batch), RoomError.unknown);
  }

  @override
  Future<Seat> claimSeat({
    required String code,
    required String seatId,
    String? password,
  }) async {
    final uid = await _auth.ensureSignedIn();
    final meta = await _readMeta(code);
    final snap = await _seat(code, seatId).get();
    final data = snap.data();
    if (data == null) {
      throw const RoomException(RoomError.unknown, 'no such seat');
    }
    final seat = _seatOf(seatId, data);
    if (seat.uid == uid) return seat;
    final proof = await _passwordProof(meta, password);
    // A person outside the room cannot read the old holder's presence, so the
    // rules decide whether that holder has been gone for 2 minutes; a refusal
    // means the seat is still in use.
    final batch = _db.batch()
      ..update(_seat(code, seatId), {'uid': uid})
      ..set(_member(code, uid), {
        'name': seat.name,
        'color': seat.color,
        'role': 'player',
        'seat': seatId,
        ...proof,
      })
      ..delete(_member(code, seat.uid))
      ..set(_presence(code, uid), {'lastSeen': FieldValue.serverTimestamp()});
    await _guard(() => _commit(batch), RoomError.seatStillActive);
    // The owner's seat comes with the room. It is a second write because the
    // rules let only a member take the room, and the member document exists
    // only once the batch above is committed. If it is refused the person
    // still has their seat and can ask again from the waiting room.
    if (seat.uid == meta.ownerUid && meta.status == RoomStatus.lobby) {
      try {
        await claimOwnership(code);
      } on RoomException {
        // See above.
      }
    }
    return Seat(id: seatId, uid: uid, name: seat.name, color: seat.color);
  }

  @override
  Future<void> claimOwnership(String code) async {
    final uid = await _auth.ensureSignedIn();
    final meta = await _readMeta(code);
    if (meta.ownerUid == uid) return;
    if (meta.status != RoomStatus.lobby) {
      throw const RoomException(RoomError.alreadyStarted);
    }
    if (await readMyMember(code) == null) {
      throw const RoomException(RoomError.notAMember);
    }
    await _guard(
      () => _room(code).update({'ownerUid': uid}),
      RoomError.ownerStillActive,
    );
  }

  @override
  Future<Member?> readMyMember(String code) async {
    final uid = await _auth.ensureSignedIn();
    await _readMeta(code);
    try {
      final snap = await _member(code, uid).get();
      final data = snap.data();
      return data == null ? null : _memberOf(uid, data);
    } on FirebaseException catch (e) {
      // Only members may read the member documents, so a person who has not
      // joined is refused.
      if (e.code == 'permission-denied') return null;
      throw _translate(e, RoomError.unknown);
    }
  }

  DocumentReference<Map<String, dynamic>> _entry(String code, int seq) =>
      _room(code).collection('entries').doc('$seq');

  /// An entry as stored; the time of one still on its way is not known yet.
  static RoomEntry _entryOf(Map<String, dynamic> d) {
    final at = d['at'];
    return RoomEntry.fromMap({...d, 'at': at is Timestamp ? at.toDate() : at});
  }

  /// Whether a press with this code is already in the history.
  Future<bool> _alreadyWritten(String code, String cid) async {
    final found = await _room(
      code,
    ).collection('entries').where('cid', isEqualTo: cid).limit(1).get();
    return found.docs.isNotEmpty;
  }

  @override
  Future<void> submitEntry(String code, EntryDraft draft) async {
    final uid = await _auth.ensureSignedIn();
    final meta = await _readMeta(code);
    if (meta.status != RoomStatus.playing) {
      throw const RoomException(RoomError.notStarted);
    }
    final me = await readMyMember(code);
    if (me == null) throw const RoomException(RoomError.notAMember);
    final seat = me.seat;
    if (me.role != MemberRole.player || seat == null) {
      throw const RoomException(RoomError.notAPlayer);
    }
    final reason = storedReason(draft);
    final amount = draft.kind == EntryKind.passGo
        ? meta.settings.goAmount
        : draft.amount;

    for (var attempt = 1; ; attempt++) {
      var triedSeq = -1;
      try {
        await _db
            .runTransaction<void>((tx) async {
              final snap = await tx.get(_state(code));
              final data = snap.data();
              if (data == null) throw const RoomException(RoomError.notStarted);
              final state = RoomState.fromMap(data);
              triedSeq = state.seq;
              final place = _entry(code, state.seq);
              if ((await tx.get(place)).exists) throw const _LostTheRace();
              final entry = RoomEntry(
                seq: state.seq,
                kind: draft.kind,
                seat: seat,
                by: uid,
                cid: draft.cid,
                from: draft.kind == EntryKind.payBank
                    ? seat
                    : bank.Transaction.bank,
                to: draft.kind == EntryKind.payBank
                    ? bank.Transaction.bank
                    : seat,
                amount: amount,
                reason: reason,
              );
              final result = Ledger.apply(state.toLedger(meta.settings), entry);
              if (result is Rejected) {
                throw RoomException(roomErrorOf(result.reason));
              }
              tx.set(place, entry.toMap(FieldValue.serverTimestamp()));
              tx.update(_state(code), {
                'seq': state.seq + 1,
                'balances': (result as Applied).state.balances,
              });
            })
            .timeout(
              _writeTimeout,
              onTimeout: () => throw const RoomException(RoomError.unsure),
            );
        return;
      } on _LostTheRace {
        if (attempt >= _pressTries) {
          throw const RoomException(RoomError.conflict);
        }
      } on FirebaseException catch (e) {
        final race = e.code == 'permission-denied' || e.code == 'aborted';
        if (!race) throw _translate(e, RoomError.notAPlayer);
        // The rules read the state, so a press that lost the race to another
        // is refused like a bad one. Tell them apart: if the press got in after
        // all, or the state has moved on since this attempt, build it again.
        if (await _alreadyWritten(code, draft.cid)) return;
        final now = await _guard(() => _state(code).get(), RoomError.unknown);
        final moved = (now.data()?['seq'] as int?) != triedSeq;
        if (!moved || attempt >= _pressTries) {
          throw RoomException(
            e.code == 'aborted' || moved
                ? RoomError.conflict
                : RoomError.notAPlayer,
          );
        }
      }
    }
  }

  @override
  Stream<List<RoomEntry>> watchEntries(String code) async* {
    await _auth.ensureSignedIn();
    yield* _guardStream(
      _room(code)
          .collection('entries')
          .orderBy('seq')
          .snapshots()
          .map((q) => [for (final d in q.docs) _entryOf(d.data())]),
      RoomError.notAMember,
    );
  }

  @override
  Stream<bool> watchOnline(String code) async* {
    await _auth.ensureSignedIn();
    yield* onlineFrom(
      _state(code)
          .snapshots(includeMetadataChanges: true)
          .map((s) => s.metadata.isFromCache),
    );
  }

  @override
  Stream<List<Member>> watchMembers(String code) async* {
    await _auth.ensureSignedIn();
    yield* _guardStream(
      _room(code)
          .collection('members')
          .snapshots()
          .map((q) => [for (final d in q.docs) _memberOf(d.id, d.data())]),
      RoomError.notAMember,
    );
  }

  @override
  Future<void> startGame(String code) async {
    final uid = await _auth.ensureSignedIn();
    final meta = await _readMeta(code);
    if (meta.ownerUid != uid) throw const RoomException(RoomError.notOwner);
    if (meta.status != RoomStatus.lobby) {
      throw const RoomException(RoomError.alreadyStarted);
    }
    final seats = [
      for (final s in await readSeats(code))
        if (s != null) s.id,
    ];
    if (seats.length < 2) {
      throw const RoomException(RoomError.notEnoughPlayers);
    }
    final bankLimit = meta.settings.bankLimit;
    final batch = _db.batch()
      ..update(_room(code), {'status': 'playing'})
      ..set(_state(code), {
        'v': 1,
        'seq': 0,
        'seats': seats,
        'balances': {
          for (final id in seats) id: meta.settings.startingCash,
          'bank': ?bankLimit,
        },
        'bankrupt': <String>[],
        'bankerSeat': null,
        'status': 'playing',
      });
    await _guard(() => _commit(batch), RoomError.notOwner);
  }

  @override
  Stream<RoomState?> watchState(String code) async* {
    await _auth.ensureSignedIn();
    yield* _guardStream(
      _state(code).snapshots().map((snap) {
        final data = snap.data();
        return data == null ? null : _stateOf(data);
      }),
      RoomError.notAMember,
    );
  }

  @override
  Future<void> heartbeat(String code) async {
    final uid = await _auth.ensureSignedIn();
    await _guard(
      () =>
          _presence(code, uid).set({'lastSeen': FieldValue.serverTimestamp()}),
      RoomError.notAMember,
    );
  }
}
