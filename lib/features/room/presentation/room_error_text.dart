import 'package:hold_my_dice/features/room/data/room_repository.dart';

/// What to tell a person when a room operation failed.
String roomErrorText(Object error) {
  if (error is! RoomException) return 'มีบางอย่างผิดพลาด ลองใหม่อีกครั้ง';
  return switch (error.error) {
    RoomError.roomNotFound => 'ห้องนี้จบแล้วหรือไม่มีอยู่',
    RoomError.wrongPassword => 'รหัสผ่านห้องไม่ถูกต้อง',
    RoomError.roomFull => 'ห้องเต็มแล้ว',
    RoomError.alreadyStarted => 'เกมเริ่มไปแล้ว',
    RoomError.seatTaken => 'ที่นั่งนี้มีคนนั่งแล้ว',
    RoomError.seatStillActive =>
      'ที่นั่งนี้ยังมีคนใช้อยู่ เข้าแทนได้เมื่อเจ้าของเดิมหายไปเกิน 2 นาที',
    RoomError.ownerStillActive =>
      'เจ้าของห้องยังอยู่ รับแทนได้เมื่อเจ้าของหายไปเกิน 2 นาที',
    RoomError.notStarted => 'เกมยังไม่เริ่ม',
    RoomError.notAPlayer =>
      'ที่นั่งนี้กดเงินไม่ได้ (เป็นผู้ชม หรือที่นั่งถูกคนอื่นเข้าแทนแล้ว)',
    RoomError.insufficientFunds =>
      'เงินไม่พอ รับเงินจากธนาคารด้วยเหตุผล "จำนอง" ก่อน',
    RoomError.invalidParties => 'โอนให้คนนี้ไม่ได้ (ออกจากเกมแล้ว)',
    RoomError.tooLate => 'ไม่ทันแล้ว มีรายการใหม่หรือหมดเวลา',
    RoomError.requestOpen => 'มีคำขอถึงคนนี้รออยู่แล้ว',
    RoomError.requestGone => 'คำขอนี้ปิดแล้ว',
    RoomError.alreadyPaid => 'จ่ายไปแล้ว',
    RoomError.bankEmpty => 'ธนาคารมีเงินไม่พอ',
    RoomError.reasonRequired => 'ใส่เหตุผลก่อนรับเงินจากธนาคาร',
    RoomError.invalidAmount => 'จำนวนเงินต้องเป็นเลขเต็ม 1 ถึง 999,999,999',
    RoomError.conflict => 'มีคนกดพร้อมกันหลายคน ลองอีกครั้ง',
    RoomError.unsure => 'ไม่แน่ใจว่าบันทึกแล้วหรือยัง ดูประวัติก่อนกดอีกครั้ง',
    RoomError.quotaExhausted => 'บริการเต็มวันนี้ ลองใหม่พรุ่งนี้',
    RoomError.notOwner => 'เฉพาะเจ้าของห้องที่ทำได้',
    RoomError.notEnoughPlayers => 'ต้องมีผู้เล่นอย่างน้อย 2 คน',
    RoomError.spectatorsNotAllowed => 'ห้องนี้ไม่รับผู้ชม',
    RoomError.notAMember => 'คุณยังไม่ได้เข้าห้องนี้',
    RoomError.unsupportedVersion => 'ต้องอัปเดตแอพก่อนเข้าห้องนี้',
    RoomError.offline => 'ออฟไลน์อยู่ ลองใหม่เมื่อมีสัญญาณ',
    RoomError.unknown => 'มีบางอย่างผิดพลาด ลองใหม่อีกครั้ง',
  };
}
