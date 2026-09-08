import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/data/mock_data.dart';
import 'package:oneleven/data/save_repository.dart';

void main() {
  // Use a fresh repository per test so the shared singleton's mutable state
  // never leaks between cases (mirrors the other repository tests).
  late SaveRepository repo;

  setUp(() {
    repo = SaveRepository();
  });

  group('seed', () {
    test('defaults to empty so the feed/bookmark assertions are unchanged', () {
      expect(repo.savedIds, isEmpty);
      expect(MockData.savedPostIds(), isEmpty);
    });

    test('exposes an unmodifiable view', () {
      expect(() => repo.savedIds.add('x'), throwsUnsupportedError);
    });
  });

  group('toggleSave', () {
    test('adds then removes, reflected via isSaved', () {
      expect(repo.isSaved('p1'), isFalse);
      repo.toggleSave('p1');
      expect(repo.isSaved('p1'), isTrue);
      expect(repo.savedIds, contains('p1'));
      repo.toggleSave('p1');
      expect(repo.isSaved('p1'), isFalse);
      expect(repo.savedIds, isEmpty);
    });

    test('fires exactly one notify per toggle', () {
      var notified = 0;
      repo.addListener(() => notified++);
      repo.toggleSave('p1');
      expect(notified, 1);
      repo.toggleSave('p1');
      expect(notified, 2);
    });

    test('is idempotent-safe across independent ids', () {
      repo.toggleSave('p1');
      repo.toggleSave('p2');
      expect(repo.savedIds, <String>{'p1', 'p2'});
      repo.toggleSave('p1');
      expect(repo.savedIds, <String>{'p2'});
    });

    test('guarded persistence does not throw on the mock/offline path', () {
      expect(() => repo.toggleSave('p1'), returnsNormally);
    });
  });

  group('offline load', () {
    test('is a no-op firing zero notifications (no reachable Supabase)', () async {
      var notified = 0;
      repo.addListener(() => notified++);
      await repo.load();
      expect(notified, 0);
      expect(repo.savedIds, isEmpty);
    });
  });
}
