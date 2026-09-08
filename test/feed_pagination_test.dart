import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/data/feed_page.dart';
import 'package:oneleven/data/feed_ranking.dart';
import 'package:oneleven/data/post_repository.dart';
import 'package:oneleven/models/post.dart';
import 'package:oneleven/models/user_profile.dart';

/// Pure, Supabase-free coverage of the infinity-feed pagination primitives:
/// the keyset-min cursor, the keyset predicate string, the fresh-dedupe filter,
/// monotonic cursor chaining, the ranking/pagination decoupling, and the footer
/// state machine.

const UserProfile _author = UserProfile(
  id: 'a1',
  username: 'ada',
  displayName: 'Ada',
);

Post _post(String id, DateTime createdAt) => Post(
      id: id,
      author: _author,
      content: id,
      createdAt: createdAt,
    );

void main() {
  group('keysetMinCursor', () {
    test('returns null for an empty list', () {
      expect(PostRepository.keysetMinCursor(<Post>[]), isNull);
    });

    test('returns the OLDEST post by created_at (keyset tail)', () {
      final posts = <Post>[
        _post('new', DateTime.utc(2024, 1, 3)),
        _post('mid', DateTime.utc(2024, 1, 2)),
        _post('old', DateTime.utc(2024, 1, 1)),
      ];
      final cursor = PostRepository.keysetMinCursor(posts);
      expect(cursor, isNotNull);
      expect(cursor!.id, 'old');
      expect(cursor.createdAt, DateTime.utc(2024, 1, 1));
    });

    test('breaks equal-created_at ties by the SMALLEST id (id desc order)', () {
      final ts = DateTime.utc(2024, 1, 1);
      final posts = <Post>[
        _post('c', ts),
        _post('a', ts),
        _post('b', ts),
      ];
      // Under (created_at desc, id desc) the row that sorts LAST is the one with
      // the smallest id, i.e. 'a'.
      final cursor = PostRepository.keysetMinCursor(posts);
      expect(cursor!.id, 'a');
    });

    test('is independent of input order', () {
      final a = _post('a', DateTime.utc(2024, 1, 1));
      final b = _post('b', DateTime.utc(2024, 1, 2));
      final c = _post('c', DateTime.utc(2024, 1, 3));
      expect(
        PostRepository.keysetMinCursor(<Post>[a, b, c])!.id,
        PostRepository.keysetMinCursor(<Post>[c, a, b])!.id,
      );
    });
  });

  group('keysetPredicate', () {
    test('produces the expected PostgREST or() string for a cursor', () {
      final cursor = FeedCursor(
        createdAt: DateTime.utc(2024, 1, 2, 3, 4, 5),
        id: 'p9',
      );
      expect(
        PostRepository.keysetPredicate(cursor),
        'created_at.lt.2024-01-02T03:04:05.000Z,'
        'and(created_at.eq.2024-01-02T03:04:05.000Z,id.lt.p9)',
      );
    });

    test('normalizes a non-UTC timestamp to UTC ISO-8601', () {
      final cursor = FeedCursor(
        // A local time is converted to UTC in the predicate string.
        createdAt: DateTime.utc(2024, 6, 1, 12).toLocal(),
        id: 'x',
      );
      expect(
        PostRepository.keysetPredicate(cursor),
        contains('created_at.lt.2024-06-01T12:00:00.000Z'),
      );
    });
  });

  group('freshPosts (no-duplicate append)', () {
    test('drops ids already present and keeps only new ones, in order', () {
      final page = <Post>[
        _post('p1', DateTime.utc(2024, 1, 3)),
        _post('p2', DateTime.utc(2024, 1, 2)),
        _post('p3', DateTime.utc(2024, 1, 1)),
      ];
      final fresh = PostRepository.freshPosts(page, <String>{'p1', 'p3'});
      expect(fresh.map((p) => p.id).toList(), <String>['p2']);
    });

    test('returns all when nothing overlaps', () {
      final page = <Post>[_post('a', DateTime.utc(2024))];
      expect(PostRepository.freshPosts(page, <String>{'z'}).length, 1);
    });

    test('returns empty when everything overlaps', () {
      final page = <Post>[_post('a', DateTime.utc(2024))];
      expect(PostRepository.freshPosts(page, <String>{'a'}), isEmpty);
    });
  });

  group('monotonic cursor chaining', () {
    test('chaining keysetMinCursor across two pages strictly decreases', () {
      // Page 1: newer rows. Page 2: strictly older rows.
      final page1 = <Post>[
        _post('p1', DateTime.utc(2024, 1, 10)),
        _post('p2', DateTime.utc(2024, 1, 9)),
        _post('p3', DateTime.utc(2024, 1, 8)),
      ];
      final page2 = <Post>[
        _post('p4', DateTime.utc(2024, 1, 7)),
        _post('p5', DateTime.utc(2024, 1, 6)),
      ];
      final c1 = PostRepository.keysetMinCursor(page1)!;
      final c2 = PostRepository.keysetMinCursor(page2)!;
      // c2 sorts strictly AFTER c1 (older / later in the feed): compareTo > 0.
      expect(c2.compareTo(c1) > 0, isTrue);
      // ...and c1 sorts strictly BEFORE c2.
      expect(c1.compareTo(c2) < 0, isTrue);
    });

    test('equal-created_at pages still decrease by the id tie-break', () {
      final ts = DateTime.utc(2024, 1, 1);
      final page1 = <Post>[_post('m', ts), _post('n', ts)];
      final page2 = <Post>[_post('a', ts), _post('b', ts)];
      final c1 = PostRepository.keysetMinCursor(page1)!; // id 'm'
      final c2 = PostRepository.keysetMinCursor(page2)!; // id 'a'
      expect(c2.compareTo(c1) > 0, isTrue);
    });
  });

  group('cursor is derived from the KEYSET tail, not the ranked display tail',
      () {
    test('keysetMinCursor is identical under chronological vs engagement rank',
        () {
      // Engagement ranking would reorder the DISPLAY so the "last" shown post
      // differs from the chronological last; the keyset cursor must not follow
      // that reorder.
      final posts = <Post>[
        // Newest but low engagement.
        Post(
          id: 'new',
          author: _author,
          content: 'new',
          createdAt: DateTime.utc(2024, 1, 3),
          likeCount: 0,
        ),
        // Middle age, HIGH engagement (engagement rank floats it to the top).
        Post(
          id: 'hot',
          author: _author,
          content: 'hot',
          createdAt: DateTime.utc(2024, 1, 2),
          likeCount: 9999,
        ),
        // Oldest, high-ish engagement (engagement rank would NOT put it last).
        Post(
          id: 'old',
          author: _author,
          content: 'old',
          createdAt: DateTime.utc(2024, 1, 1),
          likeCount: 500,
        ),
      ];

      final chronoRanked = const ChronologicalRanking().rank(posts);
      final engagementRanked = const EngagementRanking().rank(posts);

      // Prove the display order really differs between the two strategies.
      expect(
        chronoRanked.map((p) => p.id).toList(),
        isNot(equals(engagementRanked.map((p) => p.id).toList())),
      );
      // The ranked DISPLAY tails differ...
      expect(
        chronoRanked.last.id,
        isNot(equals(engagementRanked.last.id)),
      );

      // ...but the KEYSET min cursor is identical regardless of ranking, and is
      // always the true oldest row ('old'). Paging off the ranked tail would
      // corrupt pagination; paging off this cannot.
      final fromChrono = PostRepository.keysetMinCursor(chronoRanked)!;
      final fromEngagement = PostRepository.keysetMinCursor(engagementRanked)!;
      final fromRaw = PostRepository.keysetMinCursor(posts)!;
      expect(fromChrono, fromEngagement);
      expect(fromChrono, fromRaw);
      expect(fromChrono.id, 'old');
    });
  });

  group('footerStateFor', () {
    test('empty takes precedence over everything', () {
      expect(
        footerStateFor(
          loadingMore: true,
          hasMore: true,
          hasError: true,
          isEmpty: true,
        ),
        FeedFooterState.empty,
      );
    });

    test('error beats loading and end when non-empty', () {
      expect(
        footerStateFor(
          loadingMore: true,
          hasMore: false,
          hasError: true,
          isEmpty: false,
        ),
        FeedFooterState.error,
      );
    });

    test('loadingNext when a fetch is in flight and no error', () {
      expect(
        footerStateFor(
          loadingMore: true,
          hasMore: true,
          hasError: false,
          isEmpty: false,
        ),
        FeedFooterState.loadingNext,
      );
    });

    test('endOfFeed when not loading, no more, non-empty, no error', () {
      expect(
        footerStateFor(
          loadingMore: false,
          hasMore: false,
          hasError: false,
          isEmpty: false,
        ),
        FeedFooterState.endOfFeed,
      );
    });

    test('idle when more remains, not loading, no error', () {
      expect(
        footerStateFor(
          loadingMore: false,
          hasMore: true,
          hasError: false,
          isEmpty: false,
        ),
        FeedFooterState.idle,
      );
    });
  });

  group('FeedPage error/failure signalling', () {
    test('empty page carries no error and no more', () {
      expect(FeedPage.empty.error, isFalse);
      expect(FeedPage.empty.hasMore, isFalse);
      expect(FeedPage.empty.posts, isEmpty);
    });

    test('failure page signals an error but keeps hasMore for retry', () {
      expect(FeedPage.failure.error, isTrue);
      expect(FeedPage.failure.hasMore, isTrue);
      expect(FeedPage.failure.posts, isEmpty);
    });
  });
}
