import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hold_my_dice/features/room/application/room_clock.dart';
import 'package:hold_my_dice/features/room/application/room_game.dart';
import 'package:hold_my_dice/features/room/application/room_providers.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';
import 'package:hold_my_dice/features/room/domain/room_request.dart';

/// Whether an open request ran out long ago, so that it is not offered again
/// when the screen is opened afresh (requests that run out are never closed in
/// the database). The server's own time is the judge when anything newer than
/// the request gives it ([newestServerTime]: an entry, or another request);
/// otherwise this phone's clock, with a minute of slack for a clock that is a
/// little off.
bool requestIsStale({
  required DateTime createdAt,
  required DateTime? newestServerTime,
  required DateTime now,
}) {
  final reference = newestServerTime;
  if (reference != null) {
    return reference.difference(createdAt) > requestLifetime;
  }
  return now.difference(createdAt) >
      requestLifetime + const Duration(minutes: 1);
}

/// A request that is still to be answered, with the moment this device stops
/// offering it. The time is counted here, from the moment the request was
/// first seen confirmed, because this device's clock cannot be compared with
/// the server's; the room itself refuses a payment that comes too late.
class PendingRequest {
  const PendingRequest(this.request, this.deadline);

  final RoomRequest request;
  final DateTime deadline;
}

/// What a person is told about a request they made that ended without being
/// paid. [id] tells one notice from the next.
class RequestNotice {
  const RequestNotice(this.id, this.text);

  final int id;
  final String text;
}

class RequestsState {
  const RequestsState({
    this.incoming = const [],
    this.outgoing = const [],
    this.notice,
  });

  /// Asked of this person, the one asked first first.
  final List<PendingRequest> incoming;

  /// Asked by this person.
  final List<PendingRequest> outgoing;
  final RequestNotice? notice;
}

/// Watches the requests of a room for one person: the ones to answer, the
/// ones waiting for an answer, and what became of those that were not paid.
class RequestsController extends Notifier<RequestsState> {
  RequestsController(this.code);

  final String code;
  final _deadlines = <String, DateTime>{};
  final _timers = <String, Timer>{};
  final _expired = <String>{};
  Map<String, RoomRequest>? _lastOutgoing;
  List<RoomRequest> _all = const [];
  String? _seat;
  var _notices = 0;

  static String _key(RoomRequest r) =>
      '${r.id}@${r.createdAt?.microsecondsSinceEpoch}';

  @override
  RequestsState build() {
    ref.onDispose(() {
      for (final t in _timers.values) {
        t.cancel();
      }
    });
    ref.listen(roomRequestsProvider(code), (_, next) {
      _all = next.value ?? _all;
      _look();
    });
    ref.listen(roomGameProvider(code), (_, next) {
      final seat = next.value?.mySeat;
      if (seat != _seat) {
        _seat = seat;
        _look();
      }
    });
    _all = ref.read(roomRequestsProvider(code)).value ?? const [];
    _seat = ref.read(roomGameProvider(code)).value?.mySeat;
    return _compute();
  }

  /// Stops offering a request that turned out not to be answerable (the room
  /// said it ran out or is closed).
  void dismiss(String id) {
    for (final r in _all.where((r) => r.id == id)) {
      _expired.add(_key(r));
    }
    _look();
  }

  /// The newest time the server gave to anything but [except].
  DateTime? _newestServerTime(
    List<RoomEntry>? entries, {
    required RoomRequest except,
  }) {
    DateTime? newest;
    void see(DateTime? t) {
      if (t != null && (newest == null || t.isAfter(newest!))) newest = t;
    }

    for (final e in entries ?? const <RoomEntry>[]) {
      see(e.at);
    }
    for (final r in _all) {
      if (r.id != except.id) see(r.createdAt);
    }
    return newest;
  }

  void _look() => state = _compute(keepNotice: state.notice);

  RequestsState _compute({RequestNotice? keepNotice}) {
    final seat = _seat;
    if (seat == null) return const RequestsState();
    final now = ref.read(roomClockProvider)();
    final entries = ref.read(roomGameProvider(code)).value?.entries;
    for (final r in _all) {
      if (!r.isOpen || r.createdAt == null) continue;
      final key = _key(r);
      if (_deadlines.containsKey(key) || _expired.contains(key)) continue;
      if (requestIsStale(
        createdAt: r.createdAt!,
        newestServerTime: _newestServerTime(entries, except: r),
        now: now,
      )) {
        _expired.add(key);
        continue;
      }
      _deadlines[key] = now.add(requestLifetime);
      _timers[key] = Timer(requestLifetime, () {
        _expired.add(key);
        _look();
      });
    }

    bool live(RoomRequest r) =>
        r.isOpen && r.createdAt != null && !_expired.contains(_key(r));
    List<PendingRequest> pending(bool Function(RoomRequest) mine) {
      final out = [
        for (final r in _all)
          if (live(r) && mine(r)) PendingRequest(r, _deadlines[_key(r)]!),
      ]..sort((a, b) => a.deadline.compareTo(b.deadline));
      return out;
    }

    final incoming = pending((r) => r.fromSeat == seat);
    final outgoing = pending((r) => r.toSeat == seat);

    // What became of the requests this person made.
    RequestNotice? notice;
    final before = _lastOutgoing;
    final nowOut = {for (final p in outgoing) p.request.id: p.request};
    if (before != null) {
      final lines = <String>[];
      for (final old in before.values) {
        if (nowOut[old.id] != null && _key(nowOut[old.id]!) == _key(old)) {
          continue;
        }
        final current = _all.where((r) => r.id == old.id).firstOrNull;
        if (current == null || _key(current) != _key(old)) continue;
        if (current.status == RequestStatus.cancelled) {
          lines.add('คำขอถูกยกเลิก');
        } else if (current.isOpen) {
          lines.add('คำขอหมดอายุ');
        }
      }
      if (lines.isNotEmpty) {
        notice = RequestNotice(++_notices, lines.toSet().join('\n'));
      }
    }
    _lastOutgoing = nowOut;
    return RequestsState(
      incoming: incoming,
      outgoing: outgoing,
      notice: notice ?? keepNotice,
    );
  }
}

final requestsControllerProvider = NotifierProvider.autoDispose
    .family<RequestsController, RequestsState, String>(RequestsController.new);
