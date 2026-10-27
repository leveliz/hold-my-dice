import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hold_my_dice/app_providers.dart';
import 'package:hold_my_dice/core/app_info.dart';
import 'package:hold_my_dice/core/paper_style.dart';
import 'package:hold_my_dice/core/palette.dart';
import 'package:hold_my_dice/core/platform_services.dart';
import 'package:hold_my_dice/core/widgets/stamp.dart';
import 'package:hold_my_dice/features/hub/about_tab.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bank/presentation/bank_flow_test.dart' as f;

class RecordingOpener implements LinkOpener {
  RecordingOpener({this.result = true});

  final bool result;
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return result;
  }
}

Finder byKey(String k) => find.byKey(ValueKey(k));

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.tap(byKey(k));
  await tester.pumpAndSettle();
}

ProviderContainer containerWith({
  LinkOpener? opener,
  Future<AppInfo>? info,
  bool noInfo = false,
}) {
  final c = ProviderContainer(
    overrides: [
      if (opener != null) linkOpenerProvider.overrideWithValue(opener),
      if (!noInfo)
        appInfoProvider.overrideWith(
          (ref) =>
              info ??
              Future.value(const AppInfo(version: '1.2.3', build: '45')),
        ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> openAbout(
  WidgetTester tester, {
  ProviderContainer? container,
  Brightness brightness = Brightness.light,
  Size size = const Size(400, 800),
}) async {
  await f.pumpAt(
    tester,
    '/',
    container: container ?? containerWith(),
    brightness: brightness,
    size: size,
  );
  await tapKey(tester, 'nav-about');
}

/// Records what is put on the clipboard.
List<String> watchClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the settings button in the corner', () {
    testWidgets('sits at the top right, where the dice stamp was', (
      tester,
    ) async {
      await f.pumpAt(tester, '/', container: containerWith());
      final button = tester.getRect(byKey('hub-settings'));
      expect(button.right, greaterThan(400 - 40));
      expect(button.top, lessThan(120));
    });

    testWidgets('is a stamp holding a settings icon, not a die', (
      tester,
    ) async {
      await f.pumpAt(tester, '/', container: containerWith());
      expect(
        find.descendant(
          of: byKey('hub-settings'),
          matching: find.byIcon(LucideIcons.settings),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: byKey('hub-header'),
          matching: find.byIcon(LucideIcons.dices),
        ),
        findsNothing,
      );
    });

    testWidgets('the dice stay on the start button', (tester) async {
      await f.pumpAt(tester, '/', container: containerWith());
      expect(
        find.descendant(
          of: byKey('nav-start'),
          matching: find.byIcon(LucideIcons.dices),
        ),
        findsOneWidget,
      );
    });

    testWidgets('opens the settings page and back arrow returns', (
      tester,
    ) async {
      await f.pumpAt(tester, '/', container: containerWith());
      await tapKey(tester, 'hub-settings');
      expect(byKey('theme-mode'), findsOneWidget);
      expect(find.text('ตั้งค่า'), findsOneWidget);
      expect(byKey('nav-home'), findsNothing, reason: 'no bar on this page');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(byKey('hub-settings'), findsOneWidget);
    });

    testWidgets('is on every tab of the hub', (tester) async {
      await f.pumpAt(tester, '/', container: containerWith());
      for (final tab in ['nav-saved', 'nav-about', 'nav-home']) {
        await tapKey(tester, tab);
        expect(byKey('hub-settings'), findsOneWidget, reason: tab);
      }
    });

    testWidgets('has a label for screen readers', (tester) async {
      await f.pumpAt(tester, '/', container: containerWith());
      expect(find.bySemanticsLabel('ตั้งค่า'), findsWidgets);
    });

    testWidgets('is the same in Aurora, and still opens the page', (
      tester,
    ) async {
      await f.pumpAt(
        tester,
        '/',
        container: containerWith(),
        brightness: Brightness.dark,
      );
      expect(
        find.descendant(
          of: byKey('hub-settings'),
          matching: find.byIcon(LucideIcons.settings),
        ),
        findsOneWidget,
      );
      await tapKey(tester, 'hub-settings');
      expect(byKey('theme-mode'), findsOneWidget);
    });

    testWidgets('the paper stamp is red and the Aurora one pale violet', (
      tester,
    ) async {
      await f.pumpAt(tester, '/', container: containerWith());
      expect(tester.widget<Stamp>(byKey('hub-stamp')).color, PaperStyle.stamp);
      await f.pumpAt(
        tester,
        '/',
        container: containerWith(),
        brightness: Brightness.dark,
      );
      expect(
        tester.widget<Stamp>(byKey('hub-stamp')).color,
        const Color(0xFFC4B5FD),
      );
    });
  });

  group('the bar has an about tab where settings was', () {
    testWidgets('there is no settings tab, and an about tab', (tester) async {
      await f.pumpAt(tester, '/', container: containerWith());
      expect(byKey('nav-about'), findsOneWidget);
      expect(byKey('nav-settings'), findsNothing);
    });

    testWidgets('it is the last tab on the right, with an info icon', (
      tester,
    ) async {
      await f.pumpAt(tester, '/', container: containerWith());
      final about = tester.getCenter(byKey('nav-about'));
      for (final k in ['nav-home', 'nav-saved', 'nav-rules']) {
        expect(about.dx, greaterThan(tester.getCenter(byKey(k)).dx), reason: k);
      }
      expect(
        find.descendant(
          of: byKey('nav-about'),
          matching: find.byIcon(LucideIcons.info),
        ),
        findsOneWidget,
      );
    });

    testWidgets('choosing it shows the about page and a dot under it', (
      tester,
    ) async {
      await openAbout(tester);
      expect(tester.widget<Text>(byKey('hub-title')).data, 'เกี่ยวกับ');
      expect(byKey('about-app'), findsOneWidget);
      expect(byKey('about-developer'), findsOneWidget);
    });

    testWidgets('has a label for screen readers', (tester) async {
      await f.pumpAt(tester, '/', container: containerWith());
      expect(find.bySemanticsLabel('เกี่ยวกับ'), findsWidgets);
    });
  });

  group('about the app', () {
    testWidgets('names the app and what it is for', (tester) async {
      await openAbout(tester);
      expect(
        find.descendant(
          of: byKey('about-app'),
          matching: find.text('Hold My Dice'),
        ),
        findsOneWidget,
      );
      expect(find.text('ตัวช่วยสำหรับเล่นบอร์ดเกม'), findsOneWidget);
    });

    testWidgets('says why the app was made, between the app and its maker', (
      tester,
    ) async {
      await openAbout(tester);
      expect(
        find.descendant(
          of: byKey('about-why'),
          matching: find.text('ทำไมถึงทำแอพนี้'),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(byKey('about-why-text')).data,
        allOf(
          contains('ปัญหาส่วนตัว'),
          contains('บอร์ดเกมกับเพื่อน'),
          contains('ฟีเจอร์ใหม่'),
          contains('แล้วแต่ใจผู้พัฒนา'),
        ),
      );
      final app = tester.getTopLeft(byKey('about-app')).dy;
      final why = tester.getTopLeft(byKey('about-why')).dy;
      final dev = tester.getTopLeft(byKey('about-developer')).dy;
      expect(app, lessThan(why));
      expect(why, lessThan(dev));
    });

    testWidgets('the reason fits a small screen and the dark theme', (
      tester,
    ) async {
      await f.pumpAt(
        tester,
        '/',
        container: containerWith(),
        brightness: Brightness.dark,
        size: const Size(320, 640),
      );
      await tapKey(tester, 'nav-about');
      await tester.ensureVisible(byKey('about-why'));
      expect(byKey('about-why-text'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the version of the installed app', (tester) async {
      await openAbout(tester);
      expect(
        tester.widget<Text>(byKey('about-version')).data,
        'เวอร์ชัน 1.2.3 (45)',
      );
    });

    testWidgets('shows a dash while the version is not known yet', (
      tester,
    ) async {
      final never = Completer<AppInfo>();
      await openAbout(tester, container: containerWith(info: never.future));
      expect(tester.widget<Text>(byKey('about-version')).data, 'เวอร์ชัน –');
    });

    testWidgets('shows a dash when the version cannot be read', (tester) async {
      await openAbout(
        tester,
        container: containerWith(
          info: Future<AppInfo>.error(StateError('no plugin'))..ignore(),
        ),
      );
      expect(tester.widget<Text>(byKey('about-version')).data, 'เวอร์ชัน –');
    });

    testWidgets('a phone with no plugin at all also shows a dash', (
      tester,
    ) async {
      await openAbout(tester, container: containerWith(noInfo: true));
      expect(tester.widget<Text>(byKey('about-version')).data, 'เวอร์ชัน –');
    });

    testWidgets('the app card has a stamp and a serif name on paper', (
      tester,
    ) async {
      await openAbout(tester);
      expect(
        find.descendant(of: byKey('about-app'), matching: find.byType(Stamp)),
        findsOneWidget,
      );
      final name = tester.widget<Text>(
        find.descendant(
          of: byKey('about-app'),
          matching: find.text('Hold My Dice'),
        ),
      );
      expect(
        DefaultTextStyle.of(
          tester.element(find.text('Hold My Dice').last),
        ).style.merge(name.style).fontFamily,
        'NotoSerifThai',
      );
    });

    testWidgets('in Aurora the cards are panels, with an indigo stamp', (
      tester,
    ) async {
      await openAbout(tester, brightness: Brightness.dark);
      final stamp = tester.widget<Stamp>(
        find.descendant(of: byKey('about-app'), matching: find.byType(Stamp)),
      );
      expect(stamp.color, Palette.auroraIndigo);
      final box = tester.widget<Container>(byKey('about-app'));
      expect((box.decoration! as BoxDecoration).boxShadow, isNull);
    });

    testWidgets('on paper the cards stack their sheets', (tester) async {
      await openAbout(tester);
      final box = tester.widget<Container>(byKey('about-app'));
      expect((box.decoration! as BoxDecoration).boxShadow!.length, 2);
    });

    testWidgets('both cards fit a small phone', (tester) async {
      await openAbout(tester, size: const Size(320, 568));
      expect(tester.takeException(), isNull);
      await openAbout(
        tester,
        size: const Size(320, 568),
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('about the developer', () {
    testWidgets('shows who made it and the link to their GitHub', (
      tester,
    ) async {
      await openAbout(tester);
      expect(
        tester.widget<Text>(byKey('about-developer-name')).data,
        'leveliz',
      );
      expect(find.text('github.com/leveliz'), findsOneWidget);
    });

    testWidgets('the link points at the developer profile', (tester) async {
      expect(developerGithub.toString(), 'https://github.com/leveliz');
      expect(developerName, 'leveliz');
    });

    testWidgets('tapping the link opens it in the browser', (tester) async {
      final opener = RecordingOpener();
      await openAbout(tester, container: containerWith(opener: opener));
      await tapKey(tester, 'about-github');
      expect(opener.opened, [Uri.parse('https://github.com/leveliz')]);
      expect(byKey('about-copied'), findsNothing);
    });

    testWidgets('when nothing can open it, the link is copied instead', (
      tester,
    ) async {
      final copied = watchClipboard(tester);
      final opener = RecordingOpener(result: false);
      await openAbout(tester, container: containerWith(opener: opener));
      await tapKey(tester, 'about-github');
      expect(opener.opened.length, 1);
      expect(copied, ['https://github.com/leveliz']);
      expect(find.text('เปิดลิงก์ไม่ได้ คัดลอกลิงก์ให้แล้ว'), findsOneWidget);
    });

    testWidgets('the copy button copies the link and says so', (tester) async {
      final copied = watchClipboard(tester);
      final opener = RecordingOpener();
      await openAbout(tester, container: containerWith(opener: opener));
      await tapKey(tester, 'about-copy-github');
      expect(copied, ['https://github.com/leveliz']);
      expect(find.text('คัดลอกลิงก์แล้ว'), findsOneWidget);
      expect(opener.opened, isEmpty, reason: 'copying does not open it');
    });

    testWidgets('with the real opener unavailable the app does not break', (
      tester,
    ) async {
      watchClipboard(tester);
      await openAbout(tester);
      await tapKey(tester, 'about-github');
      expect(tester.takeException(), isNull);
    });
  });

  group('the link opener', () {
    test('the default opens nothing and says so', () async {
      expect(
        await const NoLinkOpener().open(Uri.parse('https://example.com')),
        isFalse,
      );
    });

    test('the browser opener says no when the phone cannot do it', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      expect(
        await const BrowserLinkOpener().open(Uri.parse('https://example.com')),
        isFalse,
      );
    });

    test('the installed app uses the browser opener', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: productionOverrides(prefs));
      addTearDown(c.dispose);
      expect(c.read(linkOpenerProvider), isA<BrowserLinkOpener>());
    });

    test('tests start with the do-nothing opener', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(linkOpenerProvider), isA<NoLinkOpener>());
    });
  });

  group('reading the installed version', () {
    test('takes the version and the build number from the app', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      PackageInfo.setMockInitialValues(
        appName: 'Hold My Dice',
        packageName: 'com.wad.hold_my_dice',
        version: '2.4.1',
        buildNumber: '19',
        buildSignature: '',
      );
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final info = await c.read(appInfoProvider.future);
      expect(info.version, '2.4.1');
      expect(info.build, '19');
      expect(info.label, '2.4.1 (19)');
    });
  });

  group('the version label', () {
    test('shows version and build', () {
      expect(const AppInfo(version: '1.0.0', build: '7').label, '1.0.0 (7)');
    });

    test('leaves the build out when there is none', () {
      expect(const AppInfo(version: '1.0.0', build: '').label, '1.0.0');
    });
  });
}
