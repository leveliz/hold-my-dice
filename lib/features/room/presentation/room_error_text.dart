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
    RoomError.notOwner => 'เฉพาะเจ้าของห้องที่ทำได้',
    RoomError.notEnoughPlayers => 'ต้องมีผู้เล่นอย่างน้อย 2 คน',
    RoomError.spectatorsNotAllowed => 'ห้องนี้ไม่รับผู้ชม',
    RoomError.notAMember => 'คุณยังไม่ได้เข้าห้องนี้',
    RoomError.unsupportedVersion => 'ต้องอัปเดตแอพก่อนเข้าห้องนี้',
    RoomError.offline => 'ออฟไลน์อยู่ ลองใหม่เมื่อมีสัญญาณ',
    RoomError.unknown => 'มีบางอย่างผิดพลาด ลองใหม่อีกครั้ง',
  };
}
