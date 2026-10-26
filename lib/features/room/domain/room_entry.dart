/// What an entry in a room's ledger does. One entry is one transaction, so the
/// rules that check an entry can be a fixed formula per kind.
enum EntryKind { receive, mortgage, passGo, payBank, transfer, bankrupt }

/// The reason a pass over GO is stored with.
const goReason = 'ผ่านจุดเริ่ม';

/// A seat going out of the game because it cannot pay [owed].
class BankruptInfo {
  const BankruptInfo({
    required this.seat,
    this.creditorSeat,
    required this.cash,
    required this.owed,
  });

  final String seat;

  /// Who is owed the money; null when the debt is to the bank.
  final String? creditorSeat;

  /// What the seat holds at that moment.
  final int cash;
  final int owed;
}

/// One line of a room's history, as the ledger sees it.
class RoomEntry {
  const RoomEntry({
    required this.seq,
    required this.kind,
    required this.seat,
    this.by,
    this.at,
    this.cid,
    this.from,
    this.to,
    this.amount,
    this.mortgage,
    this.bankrupt,
    this.group,
    this.reason,
    this.voided = false,
  });

  /// Reads an entry as it is stored; [data] has the keys [toMap] writes. A
  /// value that is missing or of the wrong kind is a [FormatException] naming
  /// the field, so one bad document cannot crash a whole screen. `at` may be
  /// null: a write still on its way has no server time yet.
  factory RoomEntry.fromMap(Map<String, Object?> data) {
    T? optional<T>(String key) {
      final value = data[key];
      if (value == null) return null;
      if (value is! T) {
        throw FormatException('entry field "$key" is a ${value.runtimeType}');
      }
      return value as T;
    }

    T required<T>(String key) =>
        optional<T>(key) ?? (throw FormatException('entry has no "$key"'));

    final seq = required<int>('seq');
    if (seq < 0) throw const FormatException('entry field "seq" is negative');
    final kindName = required<String>('kind');
    final kind = EntryKind.values.where((k) => k.name == kindName).firstOrNull;
    if (kind == null) {
      throw FormatException('entry field "kind" is unknown: $kindName');
    }
    return RoomEntry(
      seq: seq,
      kind: kind,
      seat: required<String>('seat'),
      by: optional<String>('by'),
      at: optional<DateTime>('at'),
      cid: optional<String>('cid'),
      from: optional<String>('from'),
      to: optional<String>('to'),
      amount: optional<int>('amount'),
      mortgage: optional<int>('mortgage'),
      bankrupt: _bankruptFrom(optional<Map<Object?, Object?>>('bankrupt')),
      reason: optional<String>('reason'),
      voided: optional<bool>('voided') ?? false,
    );
  }

  final int seq;
  final EntryKind kind;

  /// The seat of the person who pressed the button.
  final String seat;

  /// The uid of that person.
  final String? by;

  /// When the server took the entry; null while it is still on its way.
  final DateTime? at;

  /// A random code made for one press, so a press that is sent twice or whose
  /// answer was lost can be told from a new one.
  final String? cid;

  /// Who pays and who receives (a seat id or `bank`); empty for [bankrupt].
  final String? from;
  final String? to;
  final int? amount;

  /// What was raised by mortgage in the same press as a payment of [amount]
  /// (payBank or transfer only); null when nothing was mortgaged.
  final int? mortgage;
  final BankruptInfo? bankrupt;

  /// Entries made by one press (mortgage and then pay) share a group.
  final String? group;
  final String? reason;

  /// Undone: still shown in the history but it moves no money.
  final bool voided;

  /// The same entry, undone or not.
  RoomEntry copyWith({bool? voided}) => RoomEntry(
    seq: seq,
    kind: kind,
    seat: seat,
    by: by,
    at: at,
    cid: cid,
    from: from,
    to: to,
    amount: amount,
    mortgage: mortgage,
    bankrupt: bankrupt,
    group: group,
    reason: reason,
    voided: voided ?? this.voided,
  );

  Map<String, Object?>? get bankruptMap {
    final b = bankrupt;
    if (b == null) return null;
    return {
      'seat': b.seat,
      'creditorSeat': b.creditorSeat,
      'cash': b.cash,
      'owed': b.owed,
    };
  }

  /// The entry as stored, with [at] being what the database turns into the
  /// server time (a placeholder from the data layer). The layout is the same
  /// for every kind; `mortgage` and `bankrupt` are written only when present,
  /// so an entry without them is stored exactly as before. Groups are not
  /// stored.
  Map<String, Object?> toMap(Object at) {
    if (group != null) throw StateError('groups are not stored');
    if ((kind == EntryKind.bankrupt) != (bankrupt != null)) {
      throw StateError('the facts of a bankruptcy go with a bankrupt entry');
    }
    final by = this.by, cid = this.cid;
    if (by == null || cid == null) {
      throw StateError('an entry to store needs by and cid');
    }
    return {
      'v': 1,
      'seq': seq,
      'by': by,
      'seat': seat,
      'at': at,
      'kind': kind.name,
      'from': from,
      'to': to,
      'amount': amount,
      'mortgage': ?mortgage,
      'bankrupt': ?bankruptMap,
      'reason': reason,
      'cid': cid,
      'voided': voided,
    };
  }
}

BankruptInfo? _bankruptFrom(Map<Object?, Object?>? map) {
  if (map == null) return null;
  T? field<T>(String key, {bool nullable = false}) {
    final value = map[key];
    if (value == null && nullable) return null;
    if (value is! T) {
      throw FormatException('entry field "bankrupt.$key" is wrong: $value');
    }
    return value;
  }

  return BankruptInfo(
    seat: field<String>('seat')!,
    creditorSeat: field<String>('creditorSeat', nullable: true),
    cash: field<int>('cash')!,
    owed: field<int>('owed')!,
  );
}
