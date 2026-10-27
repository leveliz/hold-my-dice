import 'package:hold_my_dice/features/room/application/press_control.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';

/// Why a press that was made under a sheet was dropped because the state
/// changed meanwhile; null while a press has just gone in (nothing to say).
String? pressBlockText(PressBlock block) => switch (block) {
  PressBlock.out => 'คุณออกจากเกมแล้ว กดเงินไม่ได้',
  PressBlock.unsure => 'ไม่แน่ใจว่าบันทึกแล้วหรือยัง ดูประวัติก่อน',
  PressBlock.offline => 'ออฟไลน์อยู่ ลองใหม่เมื่อมีสัญญาณ',
  PressBlock.mismatch => 'ยอดไม่ตรงกับประวัติ รอให้ระบบตรวจซ้ำก่อน',
  PressBlock.spectator => 'ผู้ชมกดเงินไม่ได้',
  PressBlock.none || PressBlock.sending || PressBlock.cooling => null,
};

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
    RoomError.insufficientFunds => 'เงินไม่พอ',
    RoomError.invalidParties => 'โอนให้คนนี้ไม่ได้ (ออกจากเกมแล้ว)',
    RoomError.tooLate => 'ไม่ทันแล้ว มีรายการใหม่หรือหมดเวลา',
    RoomError.requestOpen => 'มีคำขอถึงคนนี้รออยู่แล้ว',
    RoomError.requestGone => 'คำขอนี้ปิดแล้ว',
    RoomError.alreadyPaid => 'จ่ายไปแล้ว',
    RoomError.bankEmpty => 'ธนาคารมีเงินไม่พอ',
    RoomError.reasonRequired => 'ใส่เหตุผลก่อนรับเงินจากธนาคาร',
    RoomError.invalidAmount => 'จำนวนเงินต้องเป็นเลขเต็ม 1 ถึง 999,999,999',
    RoomError.invalidMortgage =>
      'จำนองไม่ถูกต้อง: ต้องจำเป็น พอจ่ายส่วนที่ขาด และเหลือไม่เกินครึ่งหนึ่งของเงินเริ่มต้น',
    RoomError.invalidBankrupt =>
      'ล้มละลายไม่ได้ ถ้าเงินที่มีพอจ่าย หรือหนี้เกิน 10 เท่าของเงินเริ่มต้น',
    RoomError.creditorOut => 'เจ้าหนี้ออกจากเกมไปแล้ว',
    RoomError.bankerPresses =>
      'ตอนนี้นายธนาคารเป็นคนกดรับเงิน จ่ายธนาคาร และ GO',
    RoomError.notBanker =>
      'เฉพาะนายธนาคารที่กดแทนคนอื่นได้ และกดแทนได้เฉพาะเรื่องเงินจากธนาคาร',
    RoomError.bankerStillActive => 'นายธนาคารยังออนไลน์อยู่',
    RoomError.bankerMustBeOut =>
      'นายธนาคารต้องเป็นคนที่ออกจากเกมแล้ว ผู้เล่นที่ยังเล่นอยู่เป็นไม่ได้',
    RoomError.notAllowed =>
      'ตอนนี้ทำไม่ได้: ให้เจ้าของห้องหรือนายธนาคารเป็นคนทำ',
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
