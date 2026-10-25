import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/domain/ledger.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';

const _seats = ['p1', 'p2', 'p3'];
const _cash = 1500;

LedgerState _start({int? bankLimit}) =>
    Ledger.initial(_seats, _cash, bankLimit: bankLimit);

RoomEntry _entry(
  EntryKind kind, {
  String seat = 'p1',
  String? from,
  String? to,
  int? amount,
  BankruptInfo? bankrupt,
  String? group,
  bool voided = false,
}) => RoomEntry(
  seq: 0,
  kind: kind,
  seat: seat,
  from: from,
  to: to,
  amount: amount,
  bankrupt: bankrupt,
  group: group,
  voided: voided,
);

RoomEntry _fromBank(EntryKind kind, String to, int amount) =>
    _entry(kind, from: 'bank', to: to, amount: amount);

RoomEntry _payBank(String from, int amount) => _entry(
  EntryKind.payBank,
  seat: from,
  from: from,
  to: 'bank',
  amount: amount,
);

RoomEntry _transfer(String from, String to, int amount) =>
    _entry(EntryKind.transfer, seat: from, from: from, to: to, amount: amount);

RoomEntry _bankrupt(String seat, int cash, int owed, {String? creditor}) =>
    _entry(
      EntryKind.bankrupt,
      seat: seat,
      bankrupt: BankruptInfo(
        seat: seat,
        creditorSeat: creditor,
        cash: cash,
        owed: owed,
      ),
    );

LedgerState _applied(LedgerResult r) {
  expect(r, isA<Applied>(), reason: r is Rejected ? '${r.reason}' : null);
  return (r as Applied).state;
}

LedgerRejection _rejected(LedgerResult r) {
  expect(r, isA<Rejected>());
  return (r as Rejected).reason;
}

void main() {
  group('the start of a game', () {
    test('every seat starts with the starting cash', () {
      final s = _start();
      expect(s.balances, {'p1': _cash, 'p2': _cash, 'p3': _cash});
      expect(s.bankrupt, isEmpty);
      expect(s.bankerSeat, isNull);
      expect(s.startingCash, _cash);
    });

    test('the bank is tracked only when it has a limit', () {
      expect(_start().balances.containsKey('bank'), isFalse);
      expect(_start(bankLimit: 5000).balances['bank'], 5000);
    });
  });

  group('money from the bank', () {
    test('passGo adds the amount to the seat', () {
      final s = _applied(
        Ledger.apply(_start(), _fromBank(EntryKind.passGo, 'p2', 200)),
      );
      expect(s.balances['p2'], _cash + 200);
      expect(s.balances['p1'], _cash);
    });

    test('receive and mortgage add to the seat', () {
      var s = _applied(
        Ledger.apply(_start(), _fromBank(EntryKind.receive, 'p1', 300)),
      );
      s = _applied(Ledger.apply(s, _fromBank(EntryKind.mortgage, 'p1', 120)));
      expect(s.balances['p1'], _cash + 420);
    });

    test('money from the bank must come from the bank', () {
      final e = _entry(EntryKind.receive, from: 'p2', to: 'p1', amount: 10);
      expect(
        _rejected(Ledger.apply(_start(), e)),
        LedgerRejection.invalidParties,
      );
    });
  });

  group('paying the bank and other players', () {
    test(
      'payBank at or below the balance applies, above it is insufficient',
      () {
        final ok = _applied(Ledger.apply(_start(), _payBank('p1', _cash)));
        expect(ok.balances['p1'], 0);
        expect(
          _rejected(Ledger.apply(_start(), _payBank('p1', _cash + 1))),
          LedgerRejection.insufficient,
        );
      },
    );

    test('payBank must go to the bank', () {
      final e = _entry(EntryKind.payBank, from: 'p1', to: 'p2', amount: 10);
      expect(
        _rejected(Ledger.apply(_start(), e)),
        LedgerRejection.invalidParties,
      );
    });

    test('transfer moves exactly the amount', () {
      final s = _applied(Ledger.apply(_start(), _transfer('p1', 'p3', 400)));
      expect(s.balances, {'p1': _cash - 400, 'p2': _cash, 'p3': _cash + 400});
    });

    test(
      'transfer with not enough money is insufficient and changes nothing',
      () {
        final before = _start();
        final r = Ledger.apply(before, _transfer('p1', 'p2', _cash + 1));
        expect(_rejected(r), LedgerRejection.insufficient);
        expect(before.balances['p1'], _cash);
      },
    );

    test('a transfer to yourself is invalid', () {
      expect(
        _rejected(Ledger.apply(_start(), _transfer('p1', 'p1', 10))),
        LedgerRejection.invalidParties,
      );
    });
  });

  group('amounts', () {
    test('zero and negative amounts are invalid', () {
      for (final amount in [0, -1, -500]) {
        expect(
          _rejected(
            Ledger.apply(_start(), _fromBank(EntryKind.receive, 'p1', amount)),
          ),
          LedgerRejection.invalidAmount,
          reason: '$amount',
        );
      }
    });

    test(
      'an amount above 999,999,999 is invalid and the limit itself is fine',
      () {
        expect(
          _rejected(
            Ledger.apply(
              _start(),
              _fromBank(EntryKind.receive, 'p1', 1000000000),
            ),
          ),
          LedgerRejection.invalidAmount,
        );
        final s = _applied(
          Ledger.apply(_start(), _fromBank(EntryKind.receive, 'p1', 999999999)),
        );
        expect(s.balances['p1'], _cash + 999999999);
      },
    );

    test('a missing amount is invalid', () {
      final e = _entry(EntryKind.receive, from: 'bank', to: 'p1');
      expect(
        _rejected(Ledger.apply(_start(), e)),
        LedgerRejection.invalidAmount,
      );
    });
  });

  group('who can be involved', () {
    test('an unknown seat is not active', () {
      expect(
        _rejected(
          Ledger.apply(_start(), _fromBank(EntryKind.receive, 'p9', 10)),
        ),
        LedgerRejection.notActive,
      );
    });

    test('a bankrupt seat can neither pay nor be paid', () {
      final s = _applied(
        Ledger.apply(_start(), _bankrupt('p1', _cash, _cash + 1)),
      );
      expect(
        _rejected(Ledger.apply(s, _payBank('p1', 1))),
        LedgerRejection.notActive,
      );
      expect(
        _rejected(Ledger.apply(s, _transfer('p2', 'p1', 1))),
        LedgerRejection.notActive,
      );
      expect(
        _rejected(Ledger.apply(s, _fromBank(EntryKind.passGo, 'p1', 200))),
        LedgerRejection.notActive,
      );
    });

    test('a voided entry changes nothing', () {
      final e = _entry(
        EntryKind.receive,
        from: 'bank',
        to: 'p1',
        amount: 500,
        voided: true,
      );
      final s = _applied(Ledger.apply(_start(), e));
      expect(s.balances['p1'], _cash);
    });
  });

  group('bankruptcy', () {
    test('with a creditor: debtor to 0, creditor gets everything owed', () {
      final s = _applied(
        Ledger.apply(
          _start(bankLimit: 10000),
          _bankrupt('p1', _cash, 2000, creditor: 'p2'),
        ),
      );
      expect(s.balances['p1'], 0);
      expect(s.balances['p2'], _cash + 2000);
      expect(s.balances['bank'], 10000 - (2000 - _cash));
      expect(s.bankrupt, ['p1']);
    });

    test('without a creditor the cash goes to the bank', () {
      final s = _applied(
        Ledger.apply(_start(bankLimit: 10000), _bankrupt('p1', _cash, 2000)),
      );
      expect(s.balances['p1'], 0);
      expect(s.balances['p2'], _cash);
      expect(s.balances['bank'], 10000 + _cash);
    });

    test('with cash 0 and no creditor nothing moves but the seat is out', () {
      var s = _applied(Ledger.apply(_start(), _payBank('p1', _cash)));
      s = _applied(Ledger.apply(s, _bankrupt('p1', 0, 100)));
      expect(s.balances, {'p1': 0, 'p2': _cash, 'p3': _cash});
      expect(s.bankrupt, ['p1']);
    });

    test('cash that covers the debt is not bankruptcy', () {
      for (final owed in [_cash, _cash - 1, 1]) {
        expect(
          _rejected(Ledger.apply(_start(), _bankrupt('p1', _cash, owed))),
          LedgerRejection.invalidBankrupt,
          reason: '$owed',
        );
      }
    });

    test('the cash in the entry must match the real balance', () {
      expect(
        _rejected(Ledger.apply(_start(), _bankrupt('p1', _cash - 1, 2000))),
        LedgerRejection.invalidBankrupt,
      );
    });

    test(
      'a debt above ten times the starting cash is refused, ten times is allowed',
      () {
        expect(
          _rejected(
            Ledger.apply(
              _start(),
              _bankrupt('p1', _cash, 10 * _cash + 1, creditor: 'p2'),
            ),
          ),
          LedgerRejection.invalidBankrupt,
        );
        _applied(
          Ledger.apply(
            _start(),
            _bankrupt('p1', _cash, 10 * _cash, creditor: 'p2'),
          ),
        );
      },
    );

    test('the creditor must be another active seat', () {
      expect(
        _rejected(
          Ledger.apply(_start(), _bankrupt('p1', _cash, 2000, creditor: 'p1')),
        ),
        LedgerRejection.invalidBankrupt,
      );
      expect(
        _rejected(
          Ledger.apply(_start(), _bankrupt('p1', _cash, 2000, creditor: 'p9')),
        ),
        LedgerRejection.notActive,
      );
    });

    test('a bankrupt entry needs its details', () {
      final e = _entry(EntryKind.bankrupt);
      expect(
        _rejected(Ledger.apply(_start(), e)),
        LedgerRejection.invalidBankrupt,
      );
    });

    test('the first bankrupt seat becomes the banker, the second does not', () {
      var s = _applied(Ledger.apply(_start(), _bankrupt('p1', _cash, 2000)));
      expect(s.bankerSeat, 'p1');
      s = _applied(Ledger.apply(s, _bankrupt('p2', _cash, 2000)));
      expect(s.bankrupt, ['p1', 'p2']);
      expect(s.bankerSeat, 'p1');
    });

    test('a seat cannot go bankrupt twice', () {
      final s = _applied(Ledger.apply(_start(), _bankrupt('p1', _cash, 2000)));
      expect(
        _rejected(Ledger.apply(s, _bankrupt('p1', 0, 100))),
        LedgerRejection.notActive,
      );
    });
  });

  group('a bank with a limit', () {
    test('receiving takes from the bank and paying gives back', () {
      var s = _applied(
        Ledger.apply(
          _start(bankLimit: 1000),
          _fromBank(EntryKind.receive, 'p1', 400),
        ),
      );
      expect(s.balances['bank'], 600);
      s = _applied(Ledger.apply(s, _payBank('p1', 100)));
      expect(s.balances['bank'], 700);
    });

    test(
      'receiving more than the bank holds is refused, exactly all of it is fine',
      () {
        expect(
          _rejected(
            Ledger.apply(
              _start(bankLimit: 1000),
              _fromBank(EntryKind.receive, 'p1', 1001),
            ),
          ),
          LedgerRejection.bankLimit,
        );
        final s = _applied(
          Ledger.apply(
            _start(bankLimit: 1000),
            _fromBank(EntryKind.receive, 'p1', 1000),
          ),
        );
        expect(s.balances['bank'], 0);
      },
    );

    test('bankruptcy may take the bank below zero', () {
      final s = _applied(
        Ledger.apply(
          _start(bankLimit: 100),
          _bankrupt('p1', _cash, 2000, creditor: 'p2'),
        ),
      );
      expect(s.balances['bank'], 100 - (2000 - _cash));
      expect(s.balances['bank']!, lessThan(0));
    });

    test('transfers do not touch the bank', () {
      final s = _applied(
        Ledger.apply(_start(bankLimit: 1000), _transfer('p1', 'p2', 50)),
      );
      expect(s.balances['bank'], 1000);
    });
  });

  group('a group of entries from one press', () {
    test('mortgage then pay is applied together', () {
      final s = _applied(
        Ledger.applyGroup(_start(), [
          _fromBank(EntryKind.mortgage, 'p1', 500),
          _payBank('p1', _cash + 500),
        ]),
      );
      expect(s.balances['p1'], 0);
    });

    test('if the pay still falls short the whole group is refused', () {
      final before = _start();
      final r = Ledger.applyGroup(before, [
        _fromBank(EntryKind.mortgage, 'p1', 100),
        _payBank('p1', _cash + 101),
      ]);
      expect(_rejected(r), LedgerRejection.insufficient);
      expect(before.balances['p1'], _cash);
    });

    test('an empty group changes nothing', () {
      final s = _applied(Ledger.applyGroup(_start(), const []));
      expect(s.balances['p1'], _cash);
    });
  });

  test('apply never changes the state it was given', () {
    final before = _start();
    Ledger.apply(before, _transfer('p1', 'p2', 100));
    Ledger.apply(before, _bankrupt('p1', _cash, 2000));
    expect(before.balances, {'p1': _cash, 'p2': _cash, 'p3': _cash});
    expect(before.bankrupt, isEmpty);
    expect(before.bankerSeat, isNull);
    expect(() => before.balances['p1'] = 1, throwsUnsupportedError);
  });
}
