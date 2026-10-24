import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/bank/application/entry_labels.dart';
import 'package:hold_my_dice/features/bank/domain/game_state.dart';

GameState newGame() => GameState.start(
  players: const [
    Player(id: 'a', name: 'ต้น', color: 1),
    Player(id: 'b', name: 'ใบ', color: 2),
    Player(id: 'c', name: 'ฟ้า', color: 3),
  ],
  startingCash: 1500,
  goAmount: 200,
);

GameState paid(PayResult r) => (r as Paid).state;

EntryLabel last(GameState g) => describeEntry(g, g.history.last);

void main() {
  test('simple transactions', () {
    expect(last(newGame().passGo('a')).title, 'ผ่านจุดเริ่ม ต้น +200');
    expect(
      last(newGame().receiveFromBank('a', 3000)).title,
      'รับจากธนาคาร ต้น +3,000',
    );
    expect(last(newGame().mortgage('a', 60)).title, 'จำนอง ต้น +60');
    expect(
      last(paid(newGame().payBank('a', 500))).title,
      'จ่ายธนาคาร ต้น -500',
    );
    expect(last(newGame().passGo('a')).subtitle, isNull);
  });

  test('transfer names both players', () {
    expect(
      last(paid(newGame().transfer('a', 'b', 1200))).title,
      'โอน 1,200 ต้น → ใบ',
    );
  });

  test('mortgage and pay lists the mortgages as a note', () {
    final g = paid(
      newGame().payWithMortgage(
        payerId: 'a',
        payeeId: 'b',
        amount: 1800,
        mortgages: [200, 150],
      ),
    );
    final l = last(g);
    expect(l.title, 'โอน 1,800 ต้น → ใบ');
    expect(l.subtitle, 'จำนอง +200 +150');
  });

  test('bankruptcy to a player says who is paid and who covers', () {
    final g = paid(
      newGame().payBank('a', 1300),
    ).declareBankrupt('a', owed: 1000, creditorId: 'b');
    final l = last(g);
    expect(l.title, 'ต้น ล้มละลาย');
    expect(l.subtitle, 'ใบ ได้รับ 1,000 · ธนาคารจ่ายส่วนต่าง 800');
  });

  test('bankruptcy to the bank returns the remaining cash', () {
    final g = paid(
      newGame().payBank('a', 1300),
    ).declareBankrupt('a', owed: 1000);
    expect(last(g).subtitle, 'เงินที่เหลือ 200 คืนธนาคาร');
  });

  test('bankruptcy with no cash left has no note about leftovers', () {
    final g = paid(newGame().payBank('a', 1500)).declareBankrupt('a', owed: 5);
    expect(last(g).title, 'ต้น ล้มละลาย');
    expect(last(g).subtitle, isNull);
  });
}
