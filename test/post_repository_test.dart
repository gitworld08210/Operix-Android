import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/data/load_status.dart';
import 'package:oneleven/data/post_repository.dart';

/// These tests exercise the parts of [PostRepository] that do NOT require a
/// booted Supabase client. The repository is now fully Supabase-backed with no
/// mock fallback, so a fresh instance starts empty in the [LoadStatus.idle]
/// state; loading, engagement writes, replies, etc. require a live client and
/// are covered by manual/integration verification rather than these unit tests.
void main() {
  late PostRepository repo;

  setUp(() {
    repo = PostRepository();
  });

  group('initial state', () {
    test('starts idle with empty timelines', () {
      expect(repo.status, LoadStatus.idle);
      expect(repo.forYou(), isEmpty);
      expect(repo.following(), isEmpty);
      expect(repo.followingIds, isEmpty);
      expect(repo.error, isNull);
      expect(repo.lastError, isNull);
    });

    test('forYou returns an unmodifiable view', () {
      final list = repo.forYou();
      expect(() => list.clear(), throwsUnsupportedError);
    });
  });

  group('toggles on an unknown id', () {
    test('toggleLike returns null without touching the network', () async {
      expect(await repo.toggleLike('does-not-exist'), isNull);
    });

    test('toggleRepost returns null', () async {
      expect(await repo.toggleRepost('nope'), isNull);
    });

    test('toggleBookmark returns null', () async {
      expect(await repo.toggleBookmark('nope'), isNull);
    });
  });

  group('clear', () {
    test('resets to the idle empty state and notifies', () {
      var notified = 0;
      repo.addListener(() => notified++);
      repo.clear();
      expect(repo.status, LoadStatus.idle);
      expect(repo.forYou(), isEmpty);
      expect(notified, 1);
    });
  });
}
