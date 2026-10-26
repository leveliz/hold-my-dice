import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/features/room/application/room_clock.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/domain/entry_draft.dart';
import 'package:hold_my_dice/features/room/domain/room_models.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'room_test_app.dart';

const _owner = 'owner';
final _t0 = DateTime.utc(2026, 10, 26, 12);

void main() {
  late DateTime clock;
  late FakeRoomStore store;
  late String code;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    clock = _t0;
    store = FakeRoomStore(now: () => clock);
    code = await makeRoom(store);
    for (final (uid, name) in [('u2', 'แพร'), ('u3', 'มด')]) {
      await repoOn(
        store,
        uid,
      ).joinAsPlayer(code: code, name: name, color: 0xFFE11D48);
    }
    await repoOn(store, _owner).startGame(code);
  });

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  Future<void> open(WidgetTester tester, String uid, {String? at}) => openApp(
    tester,
    store,
    '/room/${at ?? code}',
    uid: uid,
    overrides: [roomClockProvider.overrideWithValue(() => clock)],
  );

  Future<void> pressEnd(WidgetTester tester) async {
    await tester.tap(key('end-game'));
    await tester.pumpAndSettle();
  }

  /// Plays a little: ต้น 1,700, แพร 1,200, มด 600.
  Future<void> play() async {
    await repoOn(store, _owner).submitEntry(code, EntryDraft.passGo());
    await repoOn(store, 'u2').submitEntry(code, EntryDraft.payBank(300));
    await repoOn(store, 'u3').submitEntry(code, EntryDraft.payBank(900));
  }

  group('ending the game', () {
    testWidgets('the owner is asked first, and backing out changes nothing', (
      tester,
    ) async {
      await open(tester, _owner);
      await pressEnd(tester);
      expect(key('end-game-dialog'), findsOneWidget);
      expect(find.textContaining('ย้อนกลับไม่ได้'), findsOneWidget);
      expect(find.textContaining('เจ้าของห้องหรือนายธนาคาร'), findsNothing);
      await tester.tap(key('end-game-cancel'));
      await tester.pumpAndSettle();
      expect(key('end-game-dialog'), findsNothing);
      expect(key('room-playing'), findsOneWidget);
      expect(key('room-summary'), findsNothing);
      await leave(tester);
    });

    testWidgets('the owner ends it and sees the summary', (tester) async {
      await play();
      await open(tester, _owner);
      await pressEnd(tester);
      await tester.tap(key('end-game-confirm'));
      await tester.pumpAndSettle();
      expect(key('room-summary'), findsOneWidget);
      expect(key('room-playing'), findsNothing);
      await leave(tester);
    });

    testWidgets(
      'a player has the button too, and is told it is not for them now',
      (tester) async {
        await open(tester, 'u2');
        await pressEnd(tester);
        expect(find.textContaining('เจ้าของห้องหรือนายธนาคาร'), findsWidgets);
        await tester.tap(key('end-game-confirm'));
        await tester.pumpAndSettle();
        expect(snackText(tester), contains('ตอนนี้ทำไม่ได้'));
        expect(key('room-playing'), findsOneWidget);
        await leave(tester);
      },
    );

    testWidgets(
      'a player ends it when the owner has been gone for 10 minutes',
      (tester) async {
        await open(tester, 'u2');
        clock = clock.add(const Duration(minutes: 11));
        await pressEnd(tester);
        await tester.tap(key('end-game-confirm'));
        await tester.pumpAndSettle();
        expect(key('room-summary'), findsOneWidget);
        await leave(tester);
      },
    );

    testWidgets('the button says what it does, also on a narrow screen', (
      tester,
    ) async {
      await open(tester, _owner);
      tester.view.physicalSize = const Size(320, 640);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: key('end-game'), matching: find.text('จบเกม')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await leave(tester);
    });

    testWidgets(
      'a message left over from the game does not cover the summary',
      (tester) async {
        await open(tester, 'u2');
        await pressEnd(tester);
        await tester.tap(key('end-game-confirm'));
        await tester.pumpAndSettle();
        expect(snackText(tester), contains('ตอนนี้ทำไม่ได้'));
        await tester.runAsync(() => repoOn(store, _owner).endGame(code));
        await tester.pumpAndSettle();
        expect(key('room-summary'), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        await leave(tester);
      },
    );

    testWidgets('a watcher has no button', (tester) async {
      await repoOn(
        store,
        's1',
      ).joinAsSpectator(code: code, name: 'ดู', color: 3);
      await open(tester, 's1');
      expect(key('end-game'), findsNothing);
      await leave(tester);
    });

    testWidgets('the banker has it', (tester) async {
      await repoOn(store, 'u3').submitEntry(code, EntryDraft.bankrupt(2000));
      await open(tester, 'u3');
      await pressEnd(tester);
      await tester.tap(key('end-game-confirm'));
      await tester.pumpAndSettle();
      expect(key('room-summary'), findsOneWidget);
      await leave(tester);
    });

    testWidgets(
      'another device that was playing turns into the summary by itself',
      (tester) async {
        await open(tester, 'u2');
        expect(key('room-playing'), findsOneWidget);
        await tester.runAsync(() => repoOn(store, _owner).endGame(code));
        await tester.pumpAndSettle();
        expect(key('room-summary'), findsOneWidget);
        await leave(tester);
      },
    );
  });

  group('when one player is left', () {
    Future<void> twoOut() async {
      await repoOn(store, 'u2').submitEntry(code, EntryDraft.bankrupt(2000));
      await repoOn(store, 'u3').submitEntry(code, EntryDraft.bankrupt(2000));
    }

    testWidgets('the owner is told, and can end the game from there', (
      tester,
    ) async {
      await twoOut();
      await open(tester, _owner);
      expect(key('band-last-one'), findsOneWidget);
      await tester.tap(key('last-one-end'));
      await tester.pumpAndSettle();
      expect(key('end-game-dialog'), findsOneWidget);
      await tester.tap(key('end-game-confirm'));
      await tester.pumpAndSettle();
      expect(key('room-summary'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('the banker is told, the others are not', (tester) async {
      await twoOut();
      await open(tester, 'u2');
      expect(key('band-last-one'), findsOneWidget, reason: 'u2 went out first');
      await tester.pumpWidget(const SizedBox());
      await open(tester, 'u3');
      expect(key('band-last-one'), findsNothing);
      await leave(tester);
    });

    testWidgets('it can be dismissed', (tester) async {
      await twoOut();
      await open(tester, _owner);
      await tester.tap(key('last-one-dismiss'));
      await tester.pumpAndSettle();
      expect(key('band-last-one'), findsNothing);
      await leave(tester);
    });

    testWidgets('it does not show while two are still in', (tester) async {
      await repoOn(store, 'u2').submitEntry(code, EntryDraft.bankrupt(2000));
      await open(tester, _owner);
      expect(key('band-last-one'), findsNothing);
      await leave(tester);
    });
  });

  group('the end of the room', () {
    Future<void> endedAndOpened(WidgetTester tester, String uid) async {
      await play();
      await repoOn(store, _owner).endGame(code);
      await open(tester, uid);
    }

    /// The room as the owner reads it (a stream that needs the real clock).
    Future<RoomMeta?> metaOf(WidgetTester tester, String c) async =>
        (await tester.runAsync<RoomMeta?>(
          () => repoOn(store, _owner).watchMeta(c).first,
        ));

    Future<void> tick(WidgetTester tester, Duration passed) async {
      clock = clock.add(passed);
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('everybody sees how long the room has left', (tester) async {
      await play();
      await repoOn(store, _owner).endGame(code);
      for (final uid in [_owner, 'u2']) {
        await open(tester, uid);
        expect(
          find.descendant(
            of: key('summary-close-notice'),
            matching: find.text('ห้องจะถูกปิดใน 5:00'),
          ),
          findsOneWidget,
          reason: uid,
        );
        await tick(tester, const Duration(minutes: 2));
        expect(find.text('ห้องจะถูกปิดใน 3:00'), findsOneWidget, reason: uid);
        await tick(tester, const Duration(seconds: 59));
        expect(find.text('ห้องจะถูกปิดใน 2:01'), findsOneWidget, reason: uid);
        clock = _t0;
        await leave(tester);
      }
    });

    testWidgets('a player phone takes the room down when the time is up', (
      tester,
    ) async {
      await endedAndOpened(tester, 'u2');
      await tick(tester, const Duration(minutes: 5, seconds: 1));
      await tester.pumpAndSettle();
      expect(await metaOf(tester, code), isNull);
      expect(find.text('ห้องนี้จบแล้วหรือไม่มีอยู่'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('the room is not taken down before the time is up', (
      tester,
    ) async {
      await endedAndOpened(tester, 'u2');
      await tick(tester, const Duration(minutes: 4, seconds: 58));
      await tester.pumpAndSettle();
      expect((await metaOf(tester, code))?.status, RoomStatus.ended);
      expect(key('room-summary'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('a watcher phone does not, it only says it is closing', (
      tester,
    ) async {
      await repoOn(
        store,
        's1',
      ).joinAsSpectator(code: code, name: 'ดู', color: 3);
      await repoOn(store, _owner).endGame(code);
      await open(tester, 's1');
      await tick(tester, const Duration(minutes: 6));
      await tester.pumpAndSettle();
      expect((await metaOf(tester, code))?.status, RoomStatus.ended);
      expect(find.text('กำลังปิดห้อง…'), findsOneWidget);
      await leave(tester);
    });

    testWidgets(
      'the owner is asked before closing, and backing out changes nothing',
      (tester) async {
        await endedAndOpened(tester, _owner);
        await tester.tap(key('summary-close'));
        await tester.pumpAndSettle();
        expect(key('close-room-dialog'), findsOneWidget);
        await tester.tap(key('close-room-cancel'));
        await tester.pumpAndSettle();
        expect(key('close-room-dialog'), findsNothing);
        expect((await metaOf(tester, code))?.status, RoomStatus.ended);
        await leave(tester);
      },
    );

    testWidgets('the owner closes the room and goes home', (tester) async {
      await endedAndOpened(tester, _owner);
      await tester.tap(key('summary-close'));
      await tester.pumpAndSettle();
      await tester.tap(key('close-room-confirm'));
      await tester.pumpAndSettle();
      expect(await metaOf(tester, code), isNull);
      expect(key('room-summary'), findsNothing);
      expect(find.text('ห้องนี้จบแล้วหรือไม่มีอยู่'), findsNothing);
      await leave(tester);
    });

    testWidgets(
      'a player who is on the summary is told when the owner closes it',
      (tester) async {
        await endedAndOpened(tester, 'u2');
        await tester.runAsync(() => repoOn(store, _owner).closeRoom(code));
        await tester.pumpAndSettle();
        expect(find.text('ห้องนี้จบแล้วหรือไม่มีอยู่'), findsOneWidget);
        await leave(tester);
      },
    );

    testWidgets('play again opens the next room for the owner', (tester) async {
      await endedAndOpened(tester, _owner);
      await tester.tap(key('summary-again'));
      await tester.pumpAndSettle();
      final next = (await metaOf(tester, code))?.nextCode;
      expect(next, isNotNull);
      expect((await metaOf(tester, next!))?.status, RoomStatus.lobby);
      expect(key('room-summary'), findsNothing);
      expect(key('ticket'), findsOneWidget);
      await leave(tester);
    });

    testWidgets(
      'the others see the new room instead of the countdown, and follow with one tap',
      (tester) async {
        await endedAndOpened(tester, 'u2');
        expect(key('summary-close-notice'), findsOneWidget);
        expect(key('summary-next-banner'), findsNothing);
        final next = (await tester.runAsync(
          () => repoOn(store, _owner).playAgain(code),
        ))!;
        await tester.pumpAndSettle();
        expect(key('summary-next-banner'), findsOneWidget);
        expect(key('summary-close-notice'), findsNothing);
        await tester.tap(key('summary-next-join'));
        await tester.pumpAndSettle();
        expect(key('ticket'), findsOneWidget);
        final me = await tester.runAsync(
          () => repoOn(store, 'u2').readMyMember(next.code),
        );
        expect(me?.seat, 'p2');
        expect(me?.name, 'แพร');
        await leave(tester);
      },
    );

    testWidgets('a watcher follows to the join form, not onto a seat', (
      tester,
    ) async {
      await repoOn(
        store,
        's1',
      ).joinAsSpectator(code: code, name: 'ดู', color: 3);
      await repoOn(store, _owner).endGame(code);
      await open(tester, 's1');
      final next = (await tester.runAsync(
        () => repoOn(store, _owner).playAgain(code),
      ))!;
      await tester.pumpAndSettle();
      await tester.tap(key('summary-next-join'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ชวนคุณเข้าห้อง'), findsOneWidget);
      expect(
        await tester.runAsync(
          () => repoOn(store, 's1').readMyMember(next.code),
        ),
        isNull,
      );
      await leave(tester);
    });

    testWidgets(
      'the owner who comes back to the old summary can go to the new room',
      (tester) async {
        await endedAndOpened(tester, _owner);
        await tester.runAsync(() => repoOn(store, _owner).playAgain(code));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: key('summary-next-join'),
            matching: find.text('ไปห้องใหม่'),
          ),
          findsOneWidget,
        );
        await tester.tap(key('summary-next-join'));
        await tester.pumpAndSettle();
        expect(key('ticket'), findsOneWidget);
        await leave(tester);
      },
    );

    testWidgets('a room with a password asks the owner for it again', (
      tester,
    ) async {
      final locked = await makeRoom(store, password: 'secret');
      await repoOn(
        store,
        'u2',
      ).joinAsPlayer(code: locked, name: 'แพร', color: 1, password: 'secret');
      await repoOn(store, _owner).startGame(locked);
      await repoOn(store, _owner).endGame(locked);
      await open(tester, _owner, at: locked);
      await tester.tap(key('summary-again'));
      await tester.pumpAndSettle();
      expect(key('again-dialog'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(key('again-confirm')).onPressed,
        isNull,
      );
      await tester.enterText(key('again-password'), 'newone');
      await tester.pump();
      await tester.tap(key('again-confirm'));
      await tester.pumpAndSettle();
      final next = (await metaOf(tester, locked))?.nextCode;
      expect((await metaOf(tester, next!))?.hasPassword, isTrue);
      expect(key('ticket'), findsOneWidget);
      await leave(tester);
    });

    testWidgets(
      'a player goes to the join form of a next room that has a password',
      (tester) async {
        final locked = await makeRoom(store, password: 'secret');
        await repoOn(
          store,
          'u2',
        ).joinAsPlayer(code: locked, name: 'แพร', color: 1, password: 'secret');
        await repoOn(store, _owner).startGame(locked);
        await repoOn(store, _owner).endGame(locked);
        final next = await repoOn(
          store,
          _owner,
        ).playAgain(locked, password: 'newone');
        await open(tester, 'u2', at: locked);
        await tester.tap(key('summary-next-join'));
        await tester.pumpAndSettle();
        expect(find.textContaining('ชวนคุณเข้าห้อง'), findsOneWidget);
        expect(
          await tester.runAsync(
            () => repoOn(store, 'u2').readMyMember(next.code),
          ),
          isNull,
        );
        await leave(tester);
      },
    );
  });

  group('the summary', () {
    Future<void> endedAndOpened(WidgetTester tester, String uid) async {
      await play();
      await repoOn(store, _owner).endGame(code);
      await open(tester, uid);
    }

    testWidgets('is the podium of the first three, with their money', (
      tester,
    ) async {
      await endedAndOpened(tester, _owner);
      expect(key('room-summary'), findsOneWidget);
      for (final (seat, name, money) in [
        ('p1', 'ต้น', '1,700'),
        ('p2', 'แพร', '1,200'),
        ('p3', 'มด', '600'),
      ]) {
        final card = key('podium-$seat');
        expect(card, findsOneWidget, reason: seat);
        expect(
          find.descendant(of: card, matching: find.text(name)),
          findsOneWidget,
          reason: seat,
        );
        expect(
          find.descendant(of: card, matching: find.text(money)),
          findsOneWidget,
          reason: seat,
        );
      }
      expect(
        find.descendant(of: key('podium-p1'), matching: find.text('ผู้ชนะ')),
        findsOneWidget,
      );
      await leave(tester);
    });

    testWidgets(
      'the winner is the one with the most money, not the first seat',
      (tester) async {
        await repoOn(store, _owner).submitEntry(code, EntryDraft.payBank(1000));
        await repoOn(store, 'u2').submitEntry(code, EntryDraft.passGo());
        await repoOn(store, _owner).endGame(code);
        await open(tester, _owner);
        expect(
          find.descendant(of: key('podium-p2'), matching: find.text('ผู้ชนะ')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: key('podium-p1'), matching: find.text('ผู้ชนะ')),
          findsNothing,
        );
        await leave(tester);
      },
    );

    testWidgets(
      'players who went out stand on the podium without money, marked',
      (tester) async {
        await repoOn(store, 'u2').submitEntry(code, EntryDraft.bankrupt(2000));
        await repoOn(store, 'u3').submitEntry(code, EntryDraft.bankrupt(2000));
        await repoOn(store, _owner).endGame(code);
        await open(tester, _owner);
        for (final seat in ['p2', 'p3']) {
          expect(
            find.descendant(
              of: key('podium-$seat'),
              matching: find.text('ล้มละลาย'),
            ),
            findsOneWidget,
            reason: seat,
          );
          expect(
            find.descendant(of: key('podium-$seat'), matching: find.text('0')),
            findsNothing,
            reason: seat,
          );
        }
        await leave(tester);
      },
    );

    testWidgets(
      'puts the first on the middle step, the second left, the third right',
      (tester) async {
        await endedAndOpened(tester, _owner);
        final x1 = tester.getCenter(key('podium-p1')).dx;
        final x2 = tester.getCenter(key('podium-p2')).dx;
        final x3 = tester.getCenter(key('podium-p3')).dx;
        expect(x2, lessThan(x1));
        expect(x1, lessThan(x3));
        expect(
          tester.getSize(key('podium-p1')).height,
          greaterThan(tester.getSize(key('podium-p2')).height),
        );
        await leave(tester);
      },
    );

    testWidgets(
      'lists the others below the podium, those who went out marked',
      (tester) async {
        final extra = await makeRoom(store);
        for (final u in ['u2', 'u3']) {
          await repoOn(store, u).joinAsPlayer(code: extra, name: u, color: 1);
        }
        await repoOn(
          store,
          'u4',
        ).joinAsPlayer(code: extra, name: 'u4', color: 1);
        await repoOn(store, _owner).startGame(extra);
        await repoOn(store, 'u4').submitEntry(extra, EntryDraft.bankrupt(2000));
        await repoOn(store, _owner).endGame(extra);
        await openApp(tester, store, '/room/$extra', uid: _owner);
        expect(key('podium-p4'), findsNothing);
        expect(key('standing-p4'), findsOneWidget);
        expect(
          find.descendant(
            of: key('standing-p4'),
            matching: find.text('ล้มละลาย'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: key('standing-p4'), matching: find.text('4')),
          findsOneWidget,
        );
        await leave(tester);
      },
    );

    testWidgets(
      'the winner has a trophy and the others do not, and no stray chip',
      (tester) async {
        await endedAndOpened(tester, _owner);
        expect(
          find.descendant(
            of: key('podium-p1'),
            matching: find.byIcon(LucideIcons.trophy),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: key('podium-p2'),
            matching: find.byIcon(LucideIcons.trophy),
          ),
          findsNothing,
        );
        expect(find.text('ดูสรุปอันดับ'), findsNothing);
        await leave(tester);
      },
    );

    testWidgets('a watcher sees it', (tester) async {
      await repoOn(
        store,
        's1',
      ).joinAsSpectator(code: code, name: 'ดู', color: 3);
      await endedAndOpened(tester, 's1');
      expect(key('room-summary'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('shows every balance even when the room hides them', (
      tester,
    ) async {
      final hidden = await makeRoom(
        store,
        settings: const RoomSettings(
          startingCash: 1500,
          goAmount: 200,
          maxPlayers: 4,
          hideOthers: true,
        ),
      );
      await repoOn(
        store,
        'u2',
      ).joinAsPlayer(code: hidden, name: 'แพร', color: 1);
      await repoOn(store, _owner).startGame(hidden);
      await repoOn(store, _owner).endGame(hidden);
      await openApp(tester, store, '/room/$hidden', uid: 'u2');
      expect(key('balance-hidden-p1'), findsNothing);
      expect(
        find.descendant(of: key('podium-p1'), matching: find.text('1,500')),
        findsOneWidget,
      );
      await leave(tester);
    });

    testWidgets('has the history for everybody, and "leave" for a player', (
      tester,
    ) async {
      await endedAndOpened(tester, 'u2');
      expect(key('summary-home'), findsOneWidget);
      expect(
        find.descendant(
          of: key('summary-home'),
          matching: find.text('ออกจากห้อง'),
        ),
        findsOneWidget,
      );
      expect(key('summary-again'), findsNothing);
      expect(key('summary-close'), findsNothing);
      await tester.tap(key('summary-history'));
      await tester.pumpAndSettle();
      expect(find.text('ประวัติทั้งหมด'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10)); // the bar behind the sheet
      await tester.pumpAndSettle();
      await tester.tap(key('summary-home'));
      await tester.pumpAndSettle();
      expect(key('room-summary'), findsNothing);
      await leave(tester);
    });

    testWidgets('has "play again" and "close the room" for the owner only', (
      tester,
    ) async {
      await endedAndOpened(tester, _owner);
      expect(key('summary-again'), findsOneWidget);
      expect(key('summary-close'), findsOneWidget);
      expect(key('summary-history'), findsOneWidget);
      expect(key('summary-home'), findsNothing);
      await leave(tester);
    });

    testWidgets('has only "leave" for the banker and a watcher', (
      tester,
    ) async {
      await repoOn(
        store,
        's1',
      ).joinAsSpectator(code: code, name: 'ดู', color: 3);
      await repoOn(store, 'u3').submitEntry(code, EntryDraft.bankrupt(2000));
      await repoOn(store, _owner).endGame(code);
      for (final uid in ['u3', 's1']) {
        await open(tester, uid);
        expect(key('summary-home'), findsOneWidget, reason: uid);
        expect(key('summary-again'), findsNothing, reason: uid);
        expect(key('summary-close'), findsNothing, reason: uid);
        await leave(tester);
      }
    });

    testWidgets('fits a narrow screen with long names and eight players', (
      tester,
    ) async {
      final eight = await makeRoom(
        store,
        settings: const RoomSettings(
          startingCash: 1500,
          goAmount: 200,
          maxPlayers: 8,
        ),
      );
      for (var i = 2; i <= 8; i++) {
        await repoOn(
          store,
          'w$i',
        ).joinAsPlayer(code: eight, name: 'สวัสดีชาวโลก😀😀😀😀', color: 1);
      }
      await repoOn(store, _owner).startGame(eight);
      await repoOn(store, _owner).endGame(eight);
      tester.view.physicalSize = const Size(320, 640);
      await openApp(tester, store, '/room/$eight', uid: _owner);
      tester.view.physicalSize = const Size(320, 640);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(key('room-summary'), findsOneWidget);
      await leave(tester);
    });
  });

  group('a game that ended, seen from outside', () {
    testWidgets('somebody who is not in it is told so, not offered a form', (
      tester,
    ) async {
      await repoOn(store, _owner).endGame(code);
      await open(tester, 'stranger');
      expect(find.text('เกมนี้จบแล้ว'), findsOneWidget);
      expect(key('join-name'), findsNothing);
      await leave(tester);
    });
  });

  group('the beats of presence', () {
    testWidgets('go on while the game is played and stop when it ends', (
      tester,
    ) async {
      await open(tester, 'u2');
      final first = store.lastSeen(code, 'u2');
      clock = clock.add(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 61));
      expect(store.lastSeen(code, 'u2'), clock, reason: 'it beat again');
      await tester.runAsync(() => repoOn(store, _owner).endGame(code));
      await tester.pumpAndSettle();
      final lastBeat = store.lastSeen(code, 'u2');
      clock = clock.add(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 61));
      expect(store.lastSeen(code, 'u2'), lastBeat, reason: 'no more beats');
      expect(first, isNotNull);
      await leave(tester);
    });
  });
}
