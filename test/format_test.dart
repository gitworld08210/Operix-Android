import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/utils/format.dart';

void main() {
  group('fmtCount', () {
    test('values below 1000 render as-is', () {
      expect(fmtCount(0), '0');
      expect(fmtCount(1), '1');
      expect(fmtCount(42), '42');
      expect(fmtCount(999), '999');
    });

    test('thousands use the K suffix with a trimmed decimal', () {
      expect(fmtCount(1000), '1K');
      expect(fmtCount(1200), '1.2K');
      expect(fmtCount(1500), '1.5K');
      expect(fmtCount(9999), '10K'); // 9.999 -> toStringAsFixed(1) rounds to 10.0
      expect(fmtCount(12300), '12.3K');
      expect(fmtCount(999000), '999K');
    });

    test('millions use the M suffix', () {
      expect(fmtCount(1000000), '1M');
      expect(fmtCount(3400000), '3.4M');
      expect(fmtCount(12000000), '12M');
      expect(fmtCount(999000000), '999M');
    });

    test('billions use the B suffix', () {
      expect(fmtCount(1000000000), '1B');
      expect(fmtCount(2500000000), '2.5B');
    });

    test('trailing .0 is dropped', () {
      expect(fmtCount(2000), '2K');
      expect(fmtCount(5000000), '5M');
    });
  });

  group('timeAgo', () {
    final now = DateTime(2024, 6, 15, 12, 0, 0);

    test('very recent times are "now"', () {
      expect(timeAgo(now, now: now), 'now');
      expect(timeAgo(now.subtract(const Duration(seconds: 10)), now: now), 'now');
      expect(timeAgo(now.subtract(const Duration(seconds: 44)), now: now), 'now');
    });

    test('future times clamp to "now"', () {
      expect(timeAgo(now.add(const Duration(minutes: 5)), now: now), 'now');
    });

    test('minutes bucket', () {
      expect(timeAgo(now.subtract(const Duration(minutes: 1)), now: now), '1m');
      expect(timeAgo(now.subtract(const Duration(minutes: 5)), now: now), '5m');
      expect(timeAgo(now.subtract(const Duration(minutes: 59)), now: now), '59m');
    });

    test('the sub-minute boundary just past 45s reports 1m', () {
      // 50 seconds -> not "now", inMinutes == 0 -> displayed as 1m.
      expect(timeAgo(now.subtract(const Duration(seconds: 50)), now: now), '1m');
    });

    test('hours bucket', () {
      expect(timeAgo(now.subtract(const Duration(hours: 1)), now: now), '1h');
      expect(timeAgo(now.subtract(const Duration(hours: 2)), now: now), '2h');
      expect(timeAgo(now.subtract(const Duration(hours: 23)), now: now), '23h');
    });

    test('days bucket', () {
      expect(timeAgo(now.subtract(const Duration(days: 1)), now: now), '1d');
      expect(timeAgo(now.subtract(const Duration(days: 6)), now: now), '6d');
    });

    test('older than a week shows a short date', () {
      final old = DateTime(2024, 3, 9, 8, 0, 0);
      expect(timeAgo(old, now: now), 'Mar 9');
    });
  });
}
