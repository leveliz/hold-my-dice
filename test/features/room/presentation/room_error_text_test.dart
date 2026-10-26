import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/application/press_control.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/presentation/room_error_text.dart';

void main() {
  test('not enough money does not give advice a player cannot follow', () {
    final text = roomErrorText(
      const RoomException(RoomError.insufficientFunds),
    );
    expect(text, contains('เงินไม่พอ'));
    expect(text, isNot(contains('จำนอง')));
  });

  test('the creditor who is out is the one owed, not the debtor', () {
    expect(
      roomErrorText(const RoomException(RoomError.creditorOut)),
      'เจ้าหนี้ออกจากเกมไปแล้ว',
    );
  });

  group('pressBlockText', () {
    test(
      'says why a press was dropped when the state changed under a sheet',
      () {
        expect(pressBlockText(PressBlock.out), contains('ออกจากเกม'));
        expect(pressBlockText(PressBlock.unsure), contains('ไม่แน่ใจ'));
        expect(pressBlockText(PressBlock.offline), contains('ออฟไลน์'));
        expect(pressBlockText(PressBlock.mismatch), contains('ยอดไม่ตรง'));
        expect(pressBlockText(PressBlock.spectator), contains('ผู้ชม'));
      },
    );

    test('is silent while a press has just gone in', () {
      expect(pressBlockText(PressBlock.none), isNull);
      expect(pressBlockText(PressBlock.sending), isNull);
      expect(pressBlockText(PressBlock.cooling), isNull);
    });
  });
}
