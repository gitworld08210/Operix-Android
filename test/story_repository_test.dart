import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/data/mock_data.dart';
import 'package:oneleven/data/story_repository.dart';
import 'package:oneleven/models/story.dart';

void main() {
  late StoryRepository repo;

  setUp(() {
    // Fresh repository per test to avoid singleton state leakage (mirrors the
    // other repository tests). The constructor kicks off a guarded load() that
    // is a no-op offline (Supabase uninitialized), so the mock seed stands.
    repo = StoryRepository();
  });

  group('Story model', () {
    test('isActive is true before expiry and false after', () {
      final created = DateTime(2024, 1, 1, 12);
      final story = Story.ephemeral(
        id: 's',
        author: MockData.aria,
        mediaUrl: 'https://example.com/s.jpg',
        createdAt: created,
      );
      // 23h in: still active. 25h in: expired.
      expect(story.isActive(created.add(const Duration(hours: 23))), isTrue);
      expect(story.isActive(created.add(const Duration(hours: 25))), isFalse);
      // Exactly at expiry is NOT active (now.isBefore(expiresAt) is false).
      expect(story.isActive(story.expiresAt), isFalse);
    });

    test('Story.ephemeral sets expiresAt = createdAt + 24h by default', () {
      final created = DateTime(2024, 1, 1, 12);
      final story = Story.ephemeral(
        id: 's',
        author: MockData.aria,
        mediaUrl: 'https://example.com/s.jpg',
        createdAt: created,
      );
      expect(story.expiresAt, created.add(const Duration(hours: 24)));
    });

    test('copyWith + id-based equality', () {
      final created = DateTime(2024, 1, 1, 12);
      final story = Story.ephemeral(
        id: 's1',
        author: MockData.aria,
        mediaUrl: 'https://example.com/s.jpg',
        createdAt: created,
      );
      final seen = story.copyWith(seen: true);
      expect(seen.seen, isTrue);
      expect(seen.id, story.id);
      // Equality is id-based: same id => equal even with a different seen flag.
      expect(seen, equals(story));
      expect(seen.hashCode, story.hashCode);
    });
  });

  group('activeStoryGroups', () {
    test('excludes expired stories and includes active ones', () {
      final groups = repo.activeStoryGroups();
      final allIds = groups.expand((g) => g.stories).map((s) => s.id).toSet();
      // The seeded expired story never appears.
      expect(allIds.contains('s_marco_expired'), isFalse);
      // Active seeds appear.
      expect(allIds.contains('s_aria1'), isTrue);
      expect(allIds.contains('s_me1'), isTrue);
    });

    test('groups by author with the current user group first', () {
      final groups = repo.activeStoryGroups();
      expect(groups, isNotEmpty);
      expect(groups.first.author.id, MockData.currentUser.id);
      // One group per active author (no duplicates).
      final authorIds = groups.map((g) => g.author.id).toList();
      expect(authorIds.toSet().length, authorIds.length);
    });

    test('stories within a group are chronological (oldest-first)', () {
      final groups = repo.activeStoryGroups();
      final aria =
          groups.firstWhere((g) => g.author.id == MockData.aria.id);
      expect(aria.stories.length, 2);
      for (var i = 0; i < aria.stories.length - 1; i++) {
        expect(
          aria.stories[i].createdAt.isBefore(aria.stories[i + 1].createdAt),
          isTrue,
        );
      }
    });

    test('hasUnseen reflects the seen flags', () {
      final groups = repo.activeStoryGroups();
      final aria =
          groups.firstWhere((g) => g.author.id == MockData.aria.id);
      // Aria's seeds are both unseen.
      expect(aria.hasUnseen, isTrue);
      // Nova's single active seed is seen.
      final nova =
          groups.firstWhere((g) => g.author.id == MockData.nova.id);
      expect(nova.hasUnseen, isFalse);
    });
  });

  group('activeStoriesFor', () {
    test('returns only that author active stories, chronological', () {
      final aria = repo.activeStoriesFor(MockData.aria.id);
      expect(aria.map((s) => s.id).toList(), <String>['s_aria1', 's_aria2']);
      for (final s in aria) {
        expect(s.author.id, MockData.aria.id);
      }
    });

    test('excludes expired stories', () {
      final marco = repo.activeStoriesFor(MockData.marco.id);
      expect(marco.any((s) => s.id == 's_marco_expired'), isFalse);
      expect(marco.any((s) => s.id == 's_marco1'), isTrue);
    });

    test('empty for an author with no active stories', () {
      expect(repo.activeStoriesFor('does_not_exist'), isEmpty);
    });
  });

  group('markSeen', () {
    test('flips a story to seen with exactly one notify', () {
      var notified = 0;
      repo.addListener(() => notified++);

      // s_aria1 starts unseen.
      expect(
        repo.activeStoriesFor(MockData.aria.id).first.seen,
        isFalse,
      );
      repo.markSeen('s_aria1');
      expect(notified, 1);
      expect(
        repo.activeStoriesFor(MockData.aria.id).first.seen,
        isTrue,
      );
    });

    test('is idempotent (no notify when already seen)', () {
      repo.markSeen('s_aria1');
      var notified = 0;
      repo.addListener(() => notified++);
      repo.markSeen('s_aria1'); // already seen
      expect(notified, 0);
    });

    test('is a no-op for an unknown story id (no notify)', () {
      var notified = 0;
      repo.addListener(() => notified++);
      repo.markSeen('nope');
      expect(notified, 0);
    });

    test('does not notify for an already-seen seed story', () {
      // s_nova1 is seeded seen=true.
      var notified = 0;
      repo.addListener(() => notified++);
      repo.markSeen('s_nova1');
      expect(notified, 0);
    });
  });

  group('load (offline)', () {
    test('is a no-op firing zero notifications on the mock fallback', () async {
      var notified = 0;
      repo.addListener(() => notified++);
      // Supabase is uninitialized under tests, so load() must be guarded and
      // leave the mock seed intact without notifying (mirrors the
      // relationship/safety offline-load tests).
      await repo.load();
      expect(notified, 0);
      // Seed still intact.
      expect(repo.activeStoriesFor(MockData.aria.id), isNotEmpty);
    });
  });
}
