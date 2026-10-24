import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/core/players/player.dart';
import 'package:hold_my_dice/core/widgets/player_setup.dart';

PlayerSetupController make({List<PlayerSetting>? initial, int min = 2}) {
  final c = PlayerSetupController(initial: initial, minPlayers: min);
  addTearDown(c.dispose);
  return c;
}

List<String> names(PlayerSetupController c) =>
    c.drafts.map((d) => d.name.text).toList();

void main() {
  test('starts with the minimum number of default players', () {
    expect(names(make()), ['ผู้เล่น 1', 'ผู้เล่น 2']);
    expect(names(make(min: 3)), ['ผู้เล่น 1', 'ผู้เล่น 2', 'ผู้เล่น 3']);
  });

  test(
    'every player starts with a different colour, however many are added',
    () {
      final c = make();
      for (var i = 0; i < 14; i++) {
        c.add();
      }
      final colors = c.drafts.map((d) => d.color.toARGB32()).toSet();
      expect(c.drafts.length, 16);
      expect(colors.length, 16);
    },
  );

  test('ids stay unique even after players are removed', () {
    final c = make();
    c.add();
    c.remove(c.drafts[1]);
    c.add();
    final ids = c.drafts.map((d) => d.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('a removed player frees its default name', () {
    final c = make();
    c.add();
    c.remove(c.drafts[1]);
    c.add();
    expect(names(c), ['ผู้เล่น 1', 'ผู้เล่น 3', 'ผู้เล่น 2']);
  });

  test('cannot go below the minimum', () {
    final c = make();
    expect(c.canRemove, isFalse);
    c.add();
    expect(c.canRemove, isTrue);
    expect(c.hasEnough, isTrue);
  });

  test('restores names and colours from the last game, still editable', () {
    final c = make(
      initial: const [
        PlayerSetting(name: 'ต้น', color: 0xFF3D5AFE),
        PlayerSetting(name: 'ใบ', color: 0xFF2E9E57),
        PlayerSetting(name: 'ฟ้า', color: 0xFFE8920C),
      ],
    );
    expect(names(c), ['ต้น', 'ใบ', 'ฟ้า']);
    expect(c.drafts[2].color, const Color(0xFFE8920C));
    c.drafts[0].name.text = 'แบงค์';
    c.setColor(c.drafts[0], const Color(0xFFD6409F));
    expect(c.toPlayers().first.name, 'แบงค์');
    expect(c.toPlayers().first.color, 0xFFD6409F);
  });

  test('fewer remembered players than the minimum are ignored', () {
    final c = make(
      initial: const [PlayerSetting(name: 'เดี่ยว', color: 0xFF3D5AFE)],
    );
    expect(names(c), ['ผู้เล่น 1', 'ผู้เล่น 2']);
  });

  test('a blank name becomes the default for its position', () {
    final c = make();
    c.drafts[1].name.text = '   ';
    expect(c.toPlayers()[1].name, 'ผู้เล่น 2');
    c.drafts[0].name.text = '  ต้น  ';
    expect(c.toPlayers()[0].name, 'ต้น');
  });

  test('settings mirror the players', () {
    final c = make();
    c.drafts[0].name.text = 'ต้น';
    final settings = c.toSettings();
    expect(settings.map((s) => s.name), ['ต้น', 'ผู้เล่น 2']);
    expect(settings.map((s) => s.color), c.toPlayers().map((p) => p.color));
  });

  test('a colour picker never offers the colours other players use', () {
    final c = make();
    final taken = c.colorsTakenByOthers(c.drafts[0]);
    expect(taken, {c.drafts[1].color.toARGB32()});
  });

  test('listeners hear about adds, removes and colour changes', () {
    final c = make();
    var calls = 0;
    c.addListener(() => calls++);
    c.add();
    c.setColor(c.drafts[0], const Color(0xFF000000));
    c.remove(c.drafts.last);
    expect(calls, 3);
  });
}
