import 'package:flutter_test/flutter_test.dart';
import 'package:hold_my_dice/features/room/application/relative_time.dart';

void main() {
  final now = DateTime.utc(2026, 10, 26, 12);

  String ago(Duration d) => relativeTime(now.subtract(d), now);

  test('under a minute is just now', () {
    expect(ago(Duration.zero), 'เมื่อกี้');
    expect(ago(const Duration(seconds: 59)), 'เมื่อกี้');
  });

  test('a clock that is a little behind is just now, not negative', () {
    expect(relativeTime(now.add(const Duration(seconds: 30)), now), 'เมื่อกี้');
  });

  test('minutes, hours and days change at their edges', () {
    expect(ago(const Duration(minutes: 1)), '1 นาที');
    expect(ago(const Duration(minutes: 59, seconds: 59)), '59 นาที');
    expect(ago(const Duration(hours: 1)), '1 ชม.');
    expect(ago(const Duration(hours: 23, minutes: 59)), '23 ชม.');
    expect(ago(const Duration(days: 1)), '1 วัน');
    expect(ago(const Duration(days: 12)), '12 วัน');
  });
}
