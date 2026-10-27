import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/features/room/application/press_control.dart';
import 'package:hold_my_dice/features/room/data/fake_room_repository.dart';
import 'package:hold_my_dice/features/room/data/room_repository.dart';
import 'package:hold_my_dice/features/room/domain/room_request.dart';

import 'room_test_app.dart';

/// A repository that counts the payments of requests, and whose list of
/// requests goes quiet once one is paid: the card of a request stays on the
/// screen for a while when the news that it was paid comes late.
class _LateNews extends FakeRoomRepository {
  _LateNews(super.store, super.auth);

  var payments = 0;
  var _quiet = false;

  /// Refuses this many payments before letting one through.
  var refuse = 0;

  @override
  Future<void> payRequest(
    String code,
    String id, {
    required String cid,
    int? mortgage,
  }) async {
    payments++;
    if (refuse > 0) {
      refuse--;
      throw const RoomException(RoomError.conflict);
    }
    await super.payRequest(code, id, cid: cid, mortgage: mortgage);
    _quiet = true;
  }

  @override
  Stream<List<RoomRequest>> watchRequests(String code) =>
      super.watchRequests(code).takeWhile((_) => !_quiet);
}

void main() {
  late FakeRoomStore store;
  late String code;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    store = FakeRoomStore();
    code = await makeRoom(store);
    await repoOn(
      store,
      'u2',
    ).joinAsPlayer(code: code, name: 'แพร', color: 0xFFE11D48);
    await repoOn(store, 'owner').startGame(code);
  });

  Finder key(String k) => find.byKey(ValueKey(k));

  testWidgets('a second tap on a request that was just paid does nothing', (
    tester,
  ) async {
    final repo = _LateNews(store, FakeAuthService('owner'));
    await openApp(
      tester,
      store,
      '/room/$code',
      uid: 'owner',
      repo: repo,
      overrides: [pressCooldownProvider.overrideWithValue(Duration.zero)],
    );
    await tester.runAsync(
      () => repoOn(store, 'u2').requestMoney(code, fromSeat: 'p1', amount: 300),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(key('request-pay'));
    await tester.pumpAndSettle();
    expect(repo.payments, 1);
    expect(tester.widget<Text>(key('my-balance')).data, '1,200');
    // The news that it was paid has not come: the card is still there.
    expect(key('request-card'), findsOneWidget);
    await tester.tap(key('request-pay'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(repo.payments, 1, reason: 'not paid a second time');
    expect(snackText(tester), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('a payment that was refused can be tried again', (tester) async {
    final repo = _LateNews(store, FakeAuthService('owner'))..refuse = 1;
    await openApp(
      tester,
      store,
      '/room/$code',
      uid: 'owner',
      repo: repo,
      overrides: [pressCooldownProvider.overrideWithValue(Duration.zero)],
    );
    await tester.runAsync(
      () => repoOn(store, 'u2').requestMoney(code, fromSeat: 'p1', amount: 300),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(key('request-pay'));
    await tester.pumpAndSettle();
    expect(snackText(tester), isNotNull);
    expect(tester.widget<Text>(key('my-balance')).data, '1,500');
    // The message goes away by itself and stops covering the button.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(key('request-pay'));
    await tester.pumpAndSettle();
    expect(repo.payments, 2);
    expect(tester.widget<Text>(key('my-balance')).data, '1,200');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
