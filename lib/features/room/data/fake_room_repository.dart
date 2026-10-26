import 'dart:async';
import 'dart:math';

import 'package:hold_my_dice/features/bank/domain/transaction.dart';
import 'package:hold_my_dice/features/room/application/room_code.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/entry_draft.dart';
import 'package:hold_my_dice/features/room/domain/ledger.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';

const _seatIsStaleAfter = Duration(minutes: 2);

/// Always the same person; what tests use instead of Firebase Auth.
class FakeAuthService implements AuthService {
  FakeAuthService(this.uid);

  final String uid;

  @override
  Future<String> ensureSignedIn() async => uid;
}

/// A value that tells everyone who listens when it changes, and hands the
/// current value to each new listener first.
class _Feed<T> {
  _Feed(this._value);

  T _value;
  final _listeners = <MultiStreamController<T>>[];

  T get value => _value;

  Stream<T> watch() => Stream<T>.multi((controller) {
    controller.add(_value);
    _listeners.add(controller);
    controller.onCancel = () => _listeners.remove(controller);
  });

  void set(T value) {
    _value = value;
    for (final listener in [..._listeners]) {
      listener.add(value);
    }
  }
}

class _Room {
  _Room(this.code, this.ownerUid, this.settings, this.passwordHash)
    : meta = _Feed<RoomMeta?>(null),
      members = _Feed<List<Member>>(const []),
      state = _Feed<RoomState?>(null),
      entryFeed = _Feed<List<RoomEntry>>(const []);

  final String code;
  String ownerUid;
  final RoomSettings settings;
  final String? passwordHash;
  var status = RoomStatus.lobby;
  final seats = <String, Seat>{};
  final memberByUid = <String, Member>{};
  final presence = <String, DateTime>{};
  final _Feed<RoomMeta?> meta;
  final _Feed<List<Member>> members;
  final _Feed<RoomState?> state;
  final entries = <RoomEntry>[];
  final _Feed<List<RoomEntry>> entryFeed;

  RoomMeta get metaNow => RoomMeta(
    code: code,
    ownerUid: ownerUid,
    status: status,
    settings: settings,
    hasPassword: passwordHash != null,
  );

  void publishMeta() => meta.set(metaNow);

  void publishMembers() => members.set(List.unmodifiable(memberByUid.values));
}

/// Rooms kept in memory, shared by every [FakeRoomRepository] made on it, so
/// a test can be several people at once. Follows the same rules as the
/// Firestore rules do.
class FakeRoomStore {
  FakeRoomStore({DateTime Function()? now, Random? random})
    : now = now ?? DateTime.now,
      random = random ?? Random.secure();

  final DateTime Function() now;
  final Random random;
  final _rooms = <String, _Room>{};
  final _online = _Feed<bool>(true);

  /// Lets a test cut or restore the connection of every person in the rooms.
  void setOnline(bool online) => _online.set(online);

  /// When [uid] last sent a heartbeat in the room, or null.
  DateTime? lastSeen(String code, String uid) => _rooms[code]?.presence[uid];
}

/// A [RoomRepository] on a [FakeRoomStore], acting as the person [auth] gives.
class FakeRoomRepository implements RoomRepository {
  FakeRoomRepository(this._store, this._auth);

  final FakeRoomStore _store;
  final AuthService _auth;

  _Room _room(String code) {
    final room = _store._rooms[code];
    if (room == null || room.status == RoomStatus.ended) {
      throw const RoomException(RoomError.roomNotFound);
    }
    return room;
  }

  void _checkPassword(_Room room, String? password) {
    final hash = room.passwordHash;
    if (hash == null) return;
    if (password == null || hashRoomPassword(password, room.code) != hash) {
      throw const RoomException(RoomError.wrongPassword);
    }
  }

  void _sit(_Room room, Seat seat, Member member) {
    room.seats[seat.id] = seat;
    room.memberByUid[member.uid] = member;
    room.presence[member.uid] = _store.now();
    room.publishMembers();
  }

  @override
  Future<RoomMeta> createRoom({
    required RoomSettings settings,
    String? password,
    required String name,
    required int color,
  }) async {
    final uid = await _auth.ensureSignedIn();
    String code;
    do {
      code = generateRoomCode(_store.random);
    } while (_store._rooms.containsKey(code));
    final hasPassword = password != null && password.isNotEmpty;
    final room = _Room(
      code,
      uid,
      settings,
      hasPassword ? hashRoomPassword(password, code) : null,
    );
    _store._rooms[code] = room;
    final clean = cutName(name);
    _sit(
      room,
      Seat(id: 'p1', uid: uid, name: clean, color: color),
      Member(
        uid: uid,
        name: clean,
        color: color,
        role: MemberRole.player,
        seat: 'p1',
      ),
    );
    room.publishMeta();
    return room.metaNow;
  }

  @override
  Stream<RoomMeta?> watchMeta(String code) async* {
    await _auth.ensureSignedIn();
    final room = _store._rooms[code];
    if (room == null) {
      yield null;
      return;
    }
    yield* room.meta.watch();
  }

  @override
  Future<List<Seat?>> readSeats(String code) async {
    await _auth.ensureSignedIn();
    final room = _room(code);
    return [for (var i = 1; i <= 8; i++) room.seats['p$i']];
  }

  @override
  Future<Seat> joinAsPlayer({
    required String code,
    required String name,
    required int color,
    String? password,
  }) async {
    final uid = await _auth.ensureSignedIn();
    final room = _room(code);
    final existing = room.memberByUid[uid];
    if (existing != null && existing.seat != null) {
      return room.seats[existing.seat]!;
    }
    _checkPassword(room, password);
    if (room.status != RoomStatus.lobby) {
      throw const RoomException(RoomError.alreadyStarted);
    }
    final free = [
      for (var i = 1; i <= room.settings.maxPlayers; i++)
        if (!room.seats.containsKey('p$i')) 'p$i',
    ];
    if (free.isEmpty) throw const RoomException(RoomError.roomFull);
    final clean = cutName(name);
    final seat = Seat(id: free.first, uid: uid, name: clean, color: color);
    _sit(
      room,
      seat,
      Member(
        uid: uid,
        name: clean,
        color: color,
        role: MemberRole.player,
        seat: seat.id,
      ),
    );
    return seat;
  }

  @override
  Future<void> joinAsSpectator({
    required String code,
    required String name,
    required int color,
    String? password,
  }) async {
    final uid = await _auth.ensureSignedIn();
    final room = _room(code);
    if (room.memberByUid.containsKey(uid)) return;
    _checkPassword(room, password);
    if (!room.settings.allowSpectators) {
      throw const RoomException(RoomError.spectatorsNotAllowed);
    }
    room.memberByUid[uid] = Member(
      uid: uid,
      name: cutName(name),
      color: color,
      role: MemberRole.spectator,
    );
    room.presence[uid] = _store.now();
    room.publishMembers();
  }

  @override
  Future<Seat> claimSeat({
    required String code,
    required String seatId,
    String? password,
  }) async {
    final uid = await _auth.ensureSignedIn();
    final room = _room(code);
    final seat = room.seats[seatId];
    if (seat == null) {
      throw const RoomException(RoomError.unknown, 'no such seat');
    }
    if (seat.uid == uid) return seat;
    _checkPassword(room, password);
    final seen = room.presence[seat.uid];
    if (seen == null || _store.now().difference(seen) < _seatIsStaleAfter) {
      throw const RoomException(RoomError.seatStillActive);
    }
    final taken = Seat(
      id: seatId,
      uid: uid,
      name: seat.name,
      color: seat.color,
    );
    // The old identity is gone from the room; the person sits on as before.
    room.memberByUid.remove(seat.uid);
    room.presence.remove(seat.uid);
    _sit(
      room,
      taken,
      Member(
        uid: uid,
        name: seat.name,
        color: seat.color,
        role: MemberRole.player,
        seat: seatId,
      ),
    );
    // Sitting in the owner's seat is also taking the room, until it starts.
    if (seat.uid == room.ownerUid && room.status == RoomStatus.lobby) {
      room.ownerUid = uid;
      room.publishMeta();
    }
    return taken;
  }

  /// The room, if the signed-in person is in it; otherwise throws.
  Future<_Room> _asMember(String code) async {
    final uid = await _auth.ensureSignedIn();
    final room = _room(code);
    if (!room.memberByUid.containsKey(uid)) {
      throw const RoomException(RoomError.notAMember);
    }
    return room;
  }

  @override
  Future<void> claimOwnership(String code) async {
    final room = await _asMember(code);
    final uid = await _auth.ensureSignedIn();
    if (room.ownerUid == uid) return;
    if (room.status != RoomStatus.lobby) {
      throw const RoomException(RoomError.alreadyStarted);
    }
    final seen = room.presence[room.ownerUid];
    if (seen == null || _store.now().difference(seen) < _seatIsStaleAfter) {
      throw const RoomException(RoomError.ownerStillActive);
    }
    room.ownerUid = uid;
    room.publishMeta();
  }

  @override
  Future<Member?> readMyMember(String code) async {
    final uid = await _auth.ensureSignedIn();
    return _room(code).memberByUid[uid];
  }

  @override
  Stream<List<Member>> watchMembers(String code) async* {
    final room = await _asMember(code);
    yield* room.members.watch();
  }

  @override
  Future<void> startGame(String code) async {
    final uid = await _auth.ensureSignedIn();
    final room = _room(code);
    if (room.ownerUid != uid) throw const RoomException(RoomError.notOwner);
    if (room.status != RoomStatus.lobby) {
      throw const RoomException(RoomError.alreadyStarted);
    }
    final seats = room.seats.keys.toList()..sort((a, b) => a.compareTo(b));
    if (seats.length < 2) {
      throw const RoomException(RoomError.notEnoughPlayers);
    }
    room.status = RoomStatus.playing;
    room.state.set(
      RoomState(
        seq: 0,
        seats: seats,
        balances: {
          for (final s in seats) s: room.settings.startingCash,
          if (room.settings.bankLimit != null) 'bank': room.settings.bankLimit!,
        },
        bankrupt: const [],
        bankerSeat: null,
        status: RoomStatus.playing,
      ),
    );
    room.publishMeta();
  }

  @override
  Stream<RoomState?> watchState(String code) async* {
    final room = await _asMember(code);
    yield* room.state.watch();
  }

  @override
  Stream<bool> watchOnline(String code) => _store._online.watch();

  @override
  Stream<List<RoomEntry>> watchEntries(String code) async* {
    final room = await _asMember(code);
    yield* room.entryFeed.watch();
  }

  @override
  Future<void> submitEntry(String code, EntryDraft draft) async {
    final uid = await _auth.ensureSignedIn();
    final room = _room(code);
    final me = room.memberByUid[uid];
    if (me == null) throw const RoomException(RoomError.notAMember);
    final state = room.state.value;
    if (room.status != RoomStatus.playing || state == null) {
      throw const RoomException(RoomError.notStarted);
    }
    final seat = me.seat;
    if (me.role != MemberRole.player || seat == null) {
      throw const RoomException(RoomError.notAPlayer);
    }
    // The same press sent again is the same press.
    if (room.entries.any((e) => e.cid == draft.cid && e.seat == seat)) return;

    final reason = storedReason(draft);
    final entry = RoomEntry(
      seq: state.seq,
      kind: draft.kind,
      seat: seat,
      by: uid,
      at: _store.now(),
      cid: draft.cid,
      from: draft.kind == EntryKind.payBank ? seat : Transaction.bank,
      to: draft.kind == EntryKind.payBank ? Transaction.bank : seat,
      amount: draft.kind == EntryKind.passGo
          ? room.settings.goAmount
          : draft.amount,
      reason: reason,
    );
    final result = Ledger.apply(state.toLedger(room.settings), entry);
    if (result is Rejected) {
      throw RoomException(roomErrorOf(result.reason));
    }
    room.entries.add(entry);
    room.entryFeed.set(List.unmodifiable(room.entries));
    room.state.set(
      RoomState(
        seq: state.seq + 1,
        seats: state.seats,
        balances: (result as Applied).state.balances,
        bankrupt: state.bankrupt,
        bankerSeat: state.bankerSeat,
        status: state.status,
      ),
    );
  }

  @override
  Future<void> heartbeat(String code) async {
    final uid = await _auth.ensureSignedIn();
    final room = await _asMember(code);
    room.presence[uid] = _store.now();
  }
}
