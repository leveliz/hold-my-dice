import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/domain/ledger.dart';
import 'package:hold_my_dice/features/room/domain/room_entry.dart';

/// The cases the Firestore rules are held against (firebase_tests runs each of
/// them on the emulator and expects the rules to accept exactly when [Ledger]
/// does). They are made here, from the Ledger itself, so the two cannot drift
/// apart unnoticed: when the Ledger changes, this test fails until the file is
/// made again with
///   UPDATE_PARITY=1 flutter test test/features/room/domain/rules_parity_cases_test.dart
const _file = 'firebase_tests/parity_cases.json';
const _seats = ['p1', 'p2', 'p3', 'p4'];
const _goAmount = 200;

List<Map<String, Object?>> _cases() {
  final random = Random(7);
  int pick(List<int> values) => values[random.nextInt(values.length)];
  final cases = <Map<String, Object?>>[];
  for (var i = 0; i < 600; i++) {
    final balances = {
      for (final s in _seats)
        s: pick([0, 1, 100, 1500, 3000, random.nextInt(4000)]),
    };
    if (random.nextBool()) {
      balances['bank'] = pick([0, 50, 5000, random.nextInt(6000)]);
    }
    final bankrupt = random.nextInt(7) == 0
        ? [_seats[random.nextInt(_seats.length)]]
        : <String>[];
    final undo = random.nextInt(4) == 0;
    // receive, passGo, payBank, transfer
    final kind = EntryKind.values[[0, 2, 3, 4][random.nextInt(4)]];
    final seat = _seats[random.nextInt(_seats.length)];
    final held = balances[seat]!;
    final amount = kind == EntryKind.passGo && !undo
        ? _goAmount
        : pick([
            0,
            1,
            50,
            100,
            held,
            held + 1,
            999999999,
            1000000000,
            1 + random.nextInt(3000),
          ]);
    // Who gets a transfer: mostly another player; a taking back only ever
    // names another player of the game.
    final others = _seats.where((s) => s != seat).toList();
    final to = kind != EntryKind.transfer
        ? null
        : undo || random.nextInt(8) != 0
        ? others[random.nextInt(others.length)]
        : pick([0, 1, 2]) == 0
        ? seat
        : 'bank';
    final entry = RoomEntry(
      seq: 0,
      kind: kind,
      seat: seat,
      from: kind == EntryKind.payBank || kind == EntryKind.transfer
          ? seat
          : 'bank',
      to: kind == EntryKind.payBank ? 'bank' : (to ?? seat),
      amount: amount,
    );
    final state = LedgerState(
      balances: balances,
      bankrupt: bankrupt,
      bankerSeat: null,
      startingCash: 1500,
    );
    final result = undo
        ? Ledger.undo(state, entry)
        : Ledger.apply(state, entry);
    cases.add({
      'op': undo ? 'undo' : 'press',
      'balances': balances,
      'bankrupt': bankrupt,
      'kind': kind.name,
      'seat': seat,
      'to': ?to,
      'amount': amount,
      'accepted': result is Applied,
      'after': result is Applied ? result.state.balances : null,
    });
  }
  return cases;
}

void main() {
  test('the cases for the rules are what the Ledger says now', () {
    final cases = _cases();
    final text = '[\n${cases.map(jsonEncode).join(',\n')}\n]\n';
    final file = File(_file);
    if (Platform.environment['UPDATE_PARITY'] == '1') {
      file.writeAsStringSync(text);
    }
    expect(
      file.readAsStringSync().replaceAll('\r\n', '\n'),
      text,
      reason: 'the Ledger and $_file differ: run with UPDATE_PARITY=1',
    );
  });

  test('the cases cover both answers, every kind and taking back', () {
    final cases = _cases();
    expect(cases.where((c) => c['accepted'] == true).length, greaterThan(100));
    expect(cases.where((c) => c['accepted'] == false).length, greaterThan(100));
    for (final op in ['press', 'undo']) {
      for (final kind in ['receive', 'passGo', 'payBank', 'transfer']) {
        for (final accepted in [true, false]) {
          expect(
            cases.where(
              (c) =>
                  c['op'] == op &&
                  c['kind'] == kind &&
                  c['accepted'] == accepted,
            ),
            isNotEmpty,
            reason: '$op $kind accepted=$accepted',
          );
        }
      }
    }
    expect(
      cases.where((c) => (c['balances']! as Map).containsKey('bank')),
      isNotEmpty,
    );
    expect(cases.where((c) => (c['bankrupt']! as List).isNotEmpty), isNotEmpty);
    // A transfer to oneself or to the bank is among the refused ones.
    expect(
      cases.where(
        (c) =>
            c['kind'] == 'transfer' &&
            c['op'] == 'press' &&
            (c['to'] == c['seat'] || c['to'] == 'bank'),
      ),
      isNotEmpty,
    );
  });
}
