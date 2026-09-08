import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/data/mock_data.dart';
import 'package:oneleven/data/post_repository.dart';
import 'package:oneleven/models/post.dart';

void main() {
  // Use a fresh repository per test so the shared singleton's mutable state
  // never leaks between cases.
  late PostRepository repo;

  setUp(() {
    repo = PostRepository();
  });

  Post firstPost() => repo.forYou().first;

  group('forYou', () {
    test('returns posts newest-first', () {
      final list = repo.forYou();
      expect(list, isNotEmpty);
      for (var i = 0; i < list.length - 1; i++) {
        expect(
          list[i].createdAt.isAfter(list[i + 1].createdAt) ||
              list[i].createdAt.isAtSameMomentAs(list[i + 1].createdAt),
          isTrue,
          reason: 'expected descending createdAt order',
        );
      }
    });

    test('returns an unmodifiable view', () {
      final list = repo.forYou();
      expect(() => list.add(list.first), throwsUnsupportedError);
    });
  });

  group('following', () {
    test('only includes followed authors', () {
      final followedIds =
          MockData.followingPosts().map((p) => p.author.id).toSet();
      final following = repo.following();
      expect(following, isNotEmpty);
      for (final p in following) {
        expect(followedIds.contains(p.author.id), isTrue);
      }
    });
  });

  group('toggleLike', () {
    test('flips liked and increments then decrements the count', () {
      final post = firstPost();
      final startLiked = post.liked;
      final startCount = post.likeCount;

      final afterFirst = repo.toggleLike(post.id);
      expect(afterFirst, isNotNull);
      expect(afterFirst!.liked, !startLiked);
      expect(afterFirst.likeCount, startCount + (!startLiked ? 1 : -1));

      final afterSecond = repo.toggleLike(post.id);
      expect(afterSecond!.liked, startLiked);
      expect(afterSecond.likeCount, startCount);
    });

    test('notifies listeners', () {
      final post = firstPost();
      var notified = 0;
      repo.addListener(() => notified++);
      repo.toggleLike(post.id);
      expect(notified, 1);
    });

    test('returns null for an unknown id', () {
      expect(repo.toggleLike('does-not-exist'), isNull);
    });
  });

  group('toggleRepost', () {
    test('flips reposted and adjusts the count', () {
      final post = firstPost();
      final startReposted = post.reposted;
      final startCount = post.repostCount;

      final updated = repo.toggleRepost(post.id);
      expect(updated, isNotNull);
      expect(updated!.reposted, !startReposted);
      expect(updated.repostCount, startCount + (!startReposted ? 1 : -1));

      final reverted = repo.toggleRepost(post.id);
      expect(reverted!.reposted, startReposted);
      expect(reverted.repostCount, startCount);
    });

    test('returns null for an unknown id', () {
      expect(repo.toggleRepost('nope'), isNull);
    });
  });

  group('toggleBookmark', () {
    test('flips bookmarked without touching counts', () {
      final post = firstPost();
      final startBookmarked = post.bookmarked;
      final startLikeCount = post.likeCount;

      final updated = repo.toggleBookmark(post.id);
      expect(updated, isNotNull);
      expect(updated!.bookmarked, !startBookmarked);
      expect(updated.likeCount, startLikeCount);

      final reverted = repo.toggleBookmark(post.id);
      expect(reverted!.bookmarked, startBookmarked);
    });

    test('returns null for an unknown id', () {
      expect(repo.toggleBookmark('nope'), isNull);
    });
  });

  group('addPost', () {
    test('prepends the new post to the timeline', () {
      final before = repo.forYou().length;
      final post = Post(
        id: 'new-post-1',
        author: MockData.currentUser,
        content: 'A brand new post',
        createdAt: DateTime.now(),
      );

      repo.addPost(post);

      final after = repo.forYou();
      expect(after.length, before + 1);
      // forYou sorts newest-first; the just-added post uses DateTime.now() so
      // it should sort to the front.
      expect(after.first.id, 'new-post-1');
    });

    test('notifies listeners', () {
      var notified = 0;
      repo.addListener(() => notified++);
      repo.addPost(
        Post(
          id: 'new-post-2',
          author: MockData.currentUser,
          content: 'Another',
          createdAt: DateTime.now(),
        ),
      );
      expect(notified, 1);
    });
  });
}
