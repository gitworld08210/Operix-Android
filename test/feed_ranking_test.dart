import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/data/feed_page.dart';
import 'package:oneleven/data/feed_ranking.dart';
import 'package:oneleven/models/post.dart';
import 'package:oneleven/models/user_profile.dart';

void main() {
  const author = UserProfile(
    id: 'u1',
    username: 'ada',
    displayName: 'Ada',
  );

  Post post(
    String id,
    DateTime createdAt, {
    int likeCount = 0,
    int repostCount = 0,
    int replyCount = 0,
    int viewCount = 0,
  }) {
    return Post(
      id: id,
      author: author,
      content: id,
      createdAt: createdAt,
      likeCount: likeCount,
      repostCount: repostCount,
      replyCount: replyCount,
      viewCount: viewCount,
    );
  }

  group('ChronologicalRanking', () {
    const ranking = ChronologicalRanking();

    test('orders posts newest-first', () {
      final older = post('a', DateTime(2024, 1, 1));
      final newer = post('b', DateTime(2024, 6, 1));
      final newest = post('c', DateTime(2024, 12, 1));

      final ranked = ranking.rank([older, newest, newer]);

      expect(ranked.map((p) => p.id).toList(), ['c', 'b', 'a']);
    });

    test('is pure: does not mutate or alias the input list', () {
      final input = [
        post('a', DateTime(2024, 1, 1)),
        post('b', DateTime(2024, 2, 1)),
      ];
      final ranked = ranking.rank(input);

      expect(input.map((p) => p.id).toList(), ['a', 'b'],
          reason: 'input order must be untouched');
      expect(identical(ranked, input), isFalse);
    });
  });

  group('EngagementRanking', () {
    const ranking = EngagementRanking();

    test('orders by engagement score descending, not by recency', () {
      // Oldest post but by far the most engagement -> should rank first.
      final highEngagement =
          post('hot', DateTime(2024, 1, 1), likeCount: 100, repostCount: 50);
      final midEngagement =
          post('warm', DateTime(2024, 6, 1), likeCount: 10);
      final noEngagement = post('cold', DateTime(2024, 12, 1));

      final ranked = ranking.rank([noEngagement, midEngagement, highEngagement]);

      expect(ranked.map((p) => p.id).toList(), ['hot', 'warm', 'cold']);
    });

    test('breaks ties newest-first for stability', () {
      // Identical (zero) engagement -> falls back to chronological.
      final older = post('a', DateTime(2024, 1, 1));
      final newer = post('b', DateTime(2024, 2, 1));

      final ranked = ranking.rank([older, newer]);

      expect(ranked.map((p) => p.id).toList(), ['b', 'a']);
    });
  });

  group('FeedCursor', () {
    test('round-trips from a post', () {
      final p = post('x', DateTime(2024, 3, 4, 5, 6, 7));
      final cursor = FeedCursor.fromPost(p);

      expect(cursor.id, 'x');
      expect(cursor.createdAt, DateTime(2024, 3, 4, 5, 6, 7));
    });

    test('equality and hashCode are value-based', () {
      final a = FeedCursor(createdAt: DateTime(2024, 1, 1), id: 'p1');
      final b = FeedCursor(createdAt: DateTime(2024, 1, 1), id: 'p1');
      final c = FeedCursor(createdAt: DateTime(2024, 1, 1), id: 'p2');

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('compareTo orders newer-before-older with id as tie-breaker', () {
      final newer = FeedCursor(createdAt: DateTime(2024, 6, 1), id: 'a');
      final older = FeedCursor(createdAt: DateTime(2024, 1, 1), id: 'z');

      // Newer sorts before older -> negative.
      expect(newer.compareTo(older), lessThan(0));
      expect(older.compareTo(newer), greaterThan(0));

      // Same timestamp: higher id sorts first (descending id tie-break).
      final tieHigh = FeedCursor(createdAt: DateTime(2024, 6, 1), id: 'z');
      final tieLow = FeedCursor(createdAt: DateTime(2024, 6, 1), id: 'a');
      expect(tieHigh.compareTo(tieLow), lessThan(0));
      expect(tieHigh.compareTo(tieHigh), 0);
    });
  });

  group('FeedPage', () {
    test('empty terminal page has no posts and no more pages', () {
      expect(FeedPage.empty.posts, isEmpty);
      expect(FeedPage.empty.hasMore, isFalse);
      expect(FeedPage.empty.nextCursor, isNull);
    });

    test('a full-sized page signals hasMore and the shared bound is > 0', () {
      expect(kFeedPageSize, greaterThan(0));

      final posts = List<Post>.generate(
        kFeedPageSize,
        (i) => post('p$i', DateTime(2024, 1, 1).add(Duration(minutes: i))),
      );
      final page = FeedPage(
        posts: posts,
        nextCursor: FeedCursor.fromPost(posts.last),
        hasMore: posts.length == kFeedPageSize,
      );

      expect(page.posts.length, kFeedPageSize);
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, isNotNull);
    });
  });
}
