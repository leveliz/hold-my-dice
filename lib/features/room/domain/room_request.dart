/// The reason a transfer carries when it pays a request to pay.
const requestReason = 'ตามคำขอเรียกเก็บ';

/// How long a request to pay can be answered.
const requestLifetime = Duration(minutes: 2);

/// Where a request to pay stands.
enum RequestStatus { open, paid, cancelled }

/// One person asking another for money. There is room for one request per
/// pair (asker, payer): its id is [idFor] of the two seats, so nobody can pile
/// up requests, and asking again after it is closed (or after it ran out)
/// writes over it.
class RoomRequest {
  const RoomRequest({
    required this.id,
    required this.fromSeat,
    required this.toSeat,
    required this.amount,
    required this.status,
    this.createdAt,
    this.paidSeq,
  });

  /// Reads a request as it is stored. A missing or wrong field is a
  /// [FormatException] naming it, so one bad document cannot crash a screen.
  /// [createdAt] is null while the asker's own write has not been confirmed
  /// by the server yet.
  factory RoomRequest.fromMap(String id, Map<String, Object?> data) {
    T? optional<T>(String key) {
      final value = data[key];
      if (value == null) return null;
      if (value is! T) {
        throw FormatException('request field "$key" is a ${value.runtimeType}');
      }
      return value as T;
    }

    T required<T>(String key) =>
        optional<T>(key) ?? (throw FormatException('request has no "$key"'));

    final statusName = required<String>('status');
    final status = RequestStatus.values
        .where((s) => s.name == statusName)
        .firstOrNull;
    if (status == null) {
      throw FormatException('request field "status" is unknown: $statusName');
    }
    final amount = required<int>('amount');
    if (amount < 1) throw const FormatException('request amount is below 1');
    return RoomRequest(
      id: id,
      fromSeat: required<String>('fromSeat'),
      toSeat: required<String>('toSeat'),
      amount: amount,
      status: status,
      createdAt: optional<DateTime>('createdAt'),
      paidSeq: optional<int>('paidSeq'),
    );
  }

  /// The id of the request that [toSeat] makes to [fromSeat].
  static String idFor({required String toSeat, required String fromSeat}) =>
      '${toSeat}_$fromSeat';

  final String id;

  /// Who is asked to pay.
  final String fromSeat;

  /// Who asks, and gets the money.
  final String toSeat;
  final int amount;
  final RequestStatus status;

  /// When the server took the request; null while it is still on its way.
  final DateTime? createdAt;

  /// The number of the entry that paid it.
  final int? paidSeq;

  bool get isOpen => status == RequestStatus.open;

  /// The request as stored for a new ask; [createdAt] is what the database
  /// turns into the server time.
  Map<String, Object?> toMap(Object createdAt) => {
    'fromSeat': fromSeat,
    'toSeat': toSeat,
    'amount': amount,
    'status': status.name,
    'createdAt': createdAt,
    'paidSeq': paidSeq,
  };
}
