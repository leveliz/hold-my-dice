import 'package:hold_my_dice/core/format.dart';
import 'package:hold_my_dice/features/bank/application/entry_labels.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';

/// Thai text of one line of a room's history: the title says who and how
/// much, the subtitle the reason (and that it was undone). [nameOf] gives the
/// name of a seat.
EntryLabel describeRoomEntry(
  RoomEntry entry,
  String Function(String seat) nameOf,
) {
  final who = nameOf(entry.seat);
  final amount = formatMoney(entry.amount ?? 0);
  final title = switch (entry.kind) {
    EntryKind.passGo => 'ผ่านจุดเริ่ม $who +$amount',
    EntryKind.receive => 'รับจากธนาคาร $who +$amount',
    EntryKind.payBank => 'จ่ายธนาคาร $who -$amount',
    // Kinds of a later version of the app: shown, not understood.
    _ => 'รายการที่แอพนี้ยังไม่รู้จัก',
  };
  final reason = entry.kind == EntryKind.passGo ? null : entry.reason;
  final notes = [?reason, if (entry.voided) 'ยกเลิกแล้ว'];
  return EntryLabel(title, notes.isEmpty ? null : notes.join(' · '));
}
