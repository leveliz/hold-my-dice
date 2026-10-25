import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/core/tour/tour_layout.dart';

const _phone = Size(400, 800);
const _sideways = Size(800, 400);
const _card = Size(300, 120);

Offset? place(
  Size screen,
  List<Rect> spots, {
  Size card = _card,
  EdgeInsets safe = EdgeInsets.zero,
}) => placeTourCard(screen: screen, safe: safe, spots: spots, card: card);

Rect cardAt(Offset o, [Size card = _card]) => o & card;

void main() {
  group('a phone held upright', () {
    test('a spot near the top puts the card at the bottom', () {
      final spot = const Rect.fromLTWH(20, 100, 360, 80);
      final at = place(_phone, [spot])!;
      expect(at.dy + _card.height, _phone.height - tourMargin);
      expect(at.dx, (_phone.width - _card.width) / 2);
    });

    test('a spot in the lower half puts the card at the top', () {
      final spot = const Rect.fromLTWH(20, 600, 360, 80);
      final at = place(_phone, [spot])!;
      expect(at.dy, tourMargin);
    });

    test('with room at both ends the card goes away from the spot', () {
      final above = place(_phone, [const Rect.fromLTWH(150, 300, 100, 60)])!;
      expect(above.dy, _phone.height - tourMargin - _card.height);
      final below = place(_phone, [const Rect.fromLTWH(150, 450, 100, 60)])!;
      expect(below.dy, tourMargin);
    });

    test('the safe area keeps the card off the edges', () {
      final spot = const Rect.fromLTWH(20, 100, 360, 80);
      const safe = EdgeInsets.only(top: 40, bottom: 30);
      final at = place(_phone, [spot], safe: safe)!;
      expect(at.dy + _card.height, _phone.height - 30 - tourMargin);
      final high = place(_phone, [
        const Rect.fromLTWH(20, 600, 360, 80),
      ], safe: safe)!;
      expect(high.dy, 40 + tourMargin);
    });

    test('a spot at each end leaves the card in the band between them', () {
      final top = const Rect.fromLTWH(20, 60, 360, 90);
      final bottom = const Rect.fromLTWH(20, 700, 360, 70);
      final at = place(_phone, [top, bottom])!;
      final card = cardAt(at);
      expect(card.top, greaterThan(top.bottom));
      expect(card.bottom, lessThan(bottom.top));
    });

    test('there is no place when the spots leave no room', () {
      final spot = const Rect.fromLTWH(0, 0, 400, 800);
      expect(place(_phone, [spot]), isNull);
      final tight = const Rect.fromLTWH(0, 100, 400, 640);
      expect(place(_phone, [tight]), isNull);
    });

    test('no spots, no place', () {
      expect(place(_phone, const []), isNull);
    });

    test('the card never covers a spot wherever the spot is', () {
      for (var y = 0.0; y <= 700; y += 50) {
        final spot = Rect.fromLTWH(40, y, 320, 90);
        final at = place(_phone, [spot]);
        if (at == null) continue;
        expect(cardAt(at).overlaps(spot), isFalse, reason: 'y=$y');
      }
    });
  });

  group('a screen held sideways', () {
    const wide = Size(300, 110);

    test('a spot on the right puts the card in a bottom left corner', () {
      final spot = const Rect.fromLTWH(420, 20, 360, 300);
      final at = place(_sideways, [spot], card: wide)!;
      expect(at.dx, tourMargin);
      expect(at.dy + wide.height, _sideways.height - tourMargin);
    });

    test('a spot on the left puts the card in a bottom right corner', () {
      final spot = const Rect.fromLTWH(20, 20, 360, 300);
      final at = place(_sideways, [spot], card: wide)!;
      expect(at.dx + wide.width, _sideways.width - tourMargin);
      expect(at.dy + wide.height, _sideways.height - tourMargin);
    });

    test('with every corner free the card goes to the far side', () {
      final right = place(_sideways, [
        const Rect.fromLTWH(560, 150, 80, 80),
      ], card: wide)!;
      expect(right.dx, tourMargin);
      final left = place(_sideways, [
        const Rect.fromLTWH(160, 150, 80, 80),
      ], card: wide)!;
      expect(left.dx + wide.width, _sideways.width - tourMargin);
    });

    test('a spot in the bottom corners sends the card up', () {
      final left = const Rect.fromLTWH(20, 250, 200, 130);
      final right = const Rect.fromLTWH(580, 250, 200, 130);
      final at = place(_sideways, [left, right], card: wide)!;
      expect(at.dy, tourMargin);
    });

    test('there is no place when every corner is lit', () {
      final spot = const Rect.fromLTWH(0, 0, 800, 400);
      expect(place(_sideways, [spot], card: wide), isNull);
    });
  });

  group('finding a widget on the screen', () {
    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Stack(children: [child])),
        ),
      );
    }

    testWidgets('gives the rectangle of a widget that is on screen', (
      tester,
    ) async {
      final key = GlobalKey();
      await pump(
        tester,
        Positioned(
          left: 30,
          top: 50,
          width: 100,
          height: 60,
          child: SizedBox(key: key),
        ),
      );
      expect(
        tourTargetRect(key, const Size(400, 800)),
        const Rect.fromLTWH(30, 50, 100, 60),
      );
    });

    testWidgets('gives nothing for a widget that is not built', (tester) async {
      await pump(tester, const SizedBox());
      expect(tourTargetRect(GlobalKey(), const Size(400, 800)), isNull);
      expect(tourTargetRect(null, const Size(400, 800)), isNull);
    });

    testWidgets('gives nothing for a widget without size', (tester) async {
      final key = GlobalKey();
      await pump(
        tester,
        Positioned(left: 30, top: 50, child: SizedBox.shrink(key: key)),
      );
      expect(tourTargetRect(key, const Size(400, 800)), isNull);
    });

    testWidgets('gives nothing for a widget whose middle is off screen', (
      tester,
    ) async {
      final key = GlobalKey();
      await pump(
        tester,
        Positioned(
          left: 30,
          top: 900,
          width: 100,
          height: 60,
          child: SizedBox(key: key),
        ),
      );
      expect(tourTargetRect(key, const Size(400, 800)), isNull);
    });
  });
}
