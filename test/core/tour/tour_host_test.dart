import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/core/theme.dart';
import 'package:hold_my_dice/core/tour/tour_host.dart';
import 'package:hold_my_dice/core/tour/tour_step.dart';
import 'package:hold_my_dice/core/tour/tour_store.dart';

/// A page that offers tours the way a helper's play screen does.
class DemoPage extends StatefulWidget {
  const DemoPage({
    super.key,
    required this.storage,
    this.ids = const ['demo'],
    this.alsoSeenOnSkip = const [],
    this.whenSideways = false,
    this.dialogFirst = false,
    this.missing = false,
    this.onBuildSteps,
  });

  final TourStorage storage;
  final List<String> ids;
  final List<String> alsoSeenOnSkip;
  final bool whenSideways;
  final bool dialogFirst;
  final bool missing;
  final void Function(String id)? onBuildSteps;

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> with TourHost<DemoPage> {
  final _target = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.dialogFirst) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('ถามก่อน'),
            actions: [
              TextButton(
                key: const ValueKey('dialog-ok'),
                onPressed: () => Navigator.pop(c),
                child: const Text('ตกลง'),
              ),
            ],
          ),
        );
      });
    }
    for (final id in widget.ids) {
      offerTour(
        storage: widget.storage,
        id: id,
        alsoSeenOnSkip: widget.alsoSeenOnSkip,
        ready: widget.whenSideways
            ? () {
                final size = MediaQuery.sizeOf(context);
                return size.width > size.height;
              }
            : null,
        steps: () {
          widget.onBuildSteps?.call(id);
          return [
            TourStep(
              title: 'ขั้นของ $id',
              body: 'ข้อความ',
              target: widget.missing ? GlobalKey() : _target,
            ),
          ];
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    MediaQuery.sizeOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('หน้าเล่น')),
      body: Stack(
        children: [
          Positioned(
            left: 20,
            top: 100,
            width: 120,
            height: 50,
            child: SizedBox(key: _target),
          ),
        ],
      ),
    );
  }
}

Finder byKey(String k) => find.byKey(ValueKey(k));

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  // The tour starts a frame after the page settles, and measures its card a
  // frame after that.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A home page with one button that opens the demo page.
Future<void> openDemo(
  WidgetTester tester,
  DemoPage page, {
  Size size = const Size(400, 800),
  bool wait = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => page)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  if (wait) await settle(tester);
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('the tour opens on a page that was not seen yet', (tester) async {
    await openDemo(tester, DemoPage(storage: MemoryTourStorage()));
    expect(byKey('tour-card'), findsOneWidget);
    expect(tester.widget<Text>(byKey('tour-title')).data, 'ขั้นของ demo');
  });

  testWidgets('it waits until the page has slid in', (tester) async {
    await openDemo(tester, DemoPage(storage: MemoryTourStorage()), wait: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(byKey('tour-card'), findsNothing);
    await settle(tester);
    expect(byKey('tour-card'), findsOneWidget);
  });

  testWidgets('finishing marks it seen and it never comes back', (
    tester,
  ) async {
    final storage = MemoryTourStorage();
    await openDemo(tester, DemoPage(storage: storage));
    expect(storage.isSeen('demo'), isFalse);
    await tester.tap(byKey('tour-next'));
    await settle(tester);
    expect(storage.isSeen('demo'), isTrue);
    expect(byKey('tour-card'), findsNothing);
  });

  testWidgets('a seen tour is not even prepared', (tester) async {
    final storage = MemoryTourStorage()..markSeen(['demo']);
    final built = <String>[];
    await openDemo(tester, DemoPage(storage: storage, onBuildSteps: built.add));
    expect(byKey('tour-card'), findsNothing);
    expect(built, isEmpty);
  });

  testWidgets('skipping marks its tips as seen too', (tester) async {
    final storage = MemoryTourStorage();
    await openDemo(
      tester,
      DemoPage(storage: storage, alsoSeenOnSkip: const ['tip']),
    );
    await tester.tap(byKey('tour-skip'));
    await settle(tester);
    expect(storage.isSeen('demo'), isTrue);
    expect(storage.isSeen('tip'), isTrue);
  });

  testWidgets('finishing leaves its tips for later', (tester) async {
    final storage = MemoryTourStorage();
    await openDemo(
      tester,
      DemoPage(storage: storage, alsoSeenOnSkip: const ['tip']),
    );
    await tester.tap(byKey('tour-next'));
    await settle(tester);
    expect(storage.isSeen('demo'), isTrue);
    expect(storage.isSeen('tip'), isFalse);
  });

  testWidgets('a dialog on the page holds the tour back until it closes', (
    tester,
  ) async {
    final storage = MemoryTourStorage();
    await openDemo(tester, DemoPage(storage: storage, dialogFirst: true));
    expect(byKey('dialog-ok'), findsOneWidget);
    expect(byKey('tour-card'), findsNothing);
    await tester.tap(byKey('dialog-ok'));
    await settle(tester);
    expect(byKey('tour-card'), findsOneWidget);
  });

  testWidgets('a tour that needs the screen sideways waits for it', (
    tester,
  ) async {
    await openDemo(
      tester,
      DemoPage(storage: MemoryTourStorage(), whenSideways: true),
    );
    expect(byKey('tour-card'), findsNothing);
    tester.view.physicalSize = const Size(800, 400);
    await settle(tester);
    expect(byKey('tour-card'), findsOneWidget);
  });

  testWidgets('tours offered together run one after the other', (tester) async {
    final storage = MemoryTourStorage();
    await openDemo(tester, DemoPage(storage: storage, ids: const ['a', 'b']));
    expect(tester.widget<Text>(byKey('tour-title')).data, 'ขั้นของ a');
    await tester.tap(byKey('tour-next'));
    await settle(tester);
    expect(tester.widget<Text>(byKey('tour-title')).data, 'ขั้นของ b');
    expect(storage.isSeen('a'), isTrue);
    expect(storage.isSeen('b'), isFalse);
    await tester.tap(byKey('tour-next'));
    await settle(tester);
    expect(storage.isSeen('b'), isTrue);
    expect(byKey('tour-card'), findsNothing);
  });

  testWidgets(
    'a tip waits behind its tour and is dropped if that was skipped',
    (tester) async {
      final storage = MemoryTourStorage();
      await openDemo(
        tester,
        DemoPage(
          storage: storage,
          ids: const ['main', 'tip'],
          alsoSeenOnSkip: const ['tip'],
        ),
      );
      expect(tester.widget<Text>(byKey('tour-title')).data, 'ขั้นของ main');
      await tester.tap(byKey('tour-skip'));
      await settle(tester);
      expect(byKey('tour-card'), findsNothing);
    },
  );

  testWidgets('leaving the page closes the tour without counting it', (
    tester,
  ) async {
    final storage = MemoryTourStorage();
    await openDemo(tester, DemoPage(storage: storage));
    expect(byKey('tour-card'), findsOneWidget);
    final route = ModalRoute.of(tester.element(find.byType(DemoPage)))!;
    route.navigator!.removeRoute(route);
    await settle(tester);
    expect(byKey('tour-card'), findsNothing);
    expect(storage.isSeen('demo'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tour whose spots are all gone is dropped, not retried', (
    tester,
  ) async {
    final storage = MemoryTourStorage();
    var built = 0;
    await openDemo(
      tester,
      DemoPage(storage: storage, missing: true, onBuildSteps: (_) => built++),
    );
    expect(byKey('tour-card'), findsNothing);
    expect(built, 1);
    tester.view.physicalSize = const Size(420, 800);
    await settle(tester);
    expect(built, 1);
    expect(storage.isSeen('demo'), isFalse);
  });
}
