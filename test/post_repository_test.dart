import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/data/mock_data.dart';
import 'package:oneleven/data/post_repository.dart';
import 'package:oneleven/data/save_repository.dart';
import 'package:oneleven/models/post.dart';
import 'package:oneleven/models/post_attachment.dart';

/// A representative `posts` row (with joined `profiles(*)`) as PostgREST would
/// return it, used to exercise the row->model mapping directly.
Map<String, dynamic> _row(String id) => <String, dynamic>{
      'id': id,
      'content': 'hello',
      'media_url': null,
      'media_type': 'none',
      'created_at': '2024-01-01T00:00:00.000Z',
      'reply_count': 2,
      'repost_count': 3,
      'like_count': 4,
      'view_count': 5,
      'profiles': <String, dynamic>{
        'id': 'author-1',
        'username': 'ada',
        'display_name': 'Ada',
      },
    };

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

  group('mapPostRow', () {
    test('maps server-owned counts and author from the row', () {
      final post = PostRepository.mapPostRow(_row('p1'));
      expect(post.id, 'p1');
      expect(post.content, 'hello');
      expect(post.author.id, 'author-1');
      expect(post.author.username, 'ada');
      expect(post.replyCount, 2);
      expect(post.repostCount, 3);
      expect(post.likeCount, 4);
      expect(post.viewCount, 5);
    });

    test('defaults liked/reposted to false without viewer engagement', () {
      final post = PostRepository.mapPostRow(_row('p1'));
      expect(post.liked, isFalse);
      expect(post.reposted, isFalse);
    });

    test('hydrates liked when the row id is in the viewer like set', () {
      final post = PostRepository.mapPostRow(
        _row('p1'),
        likedIds: <String>{'p1', 'other'},
      );
      expect(post.liked, isTrue);
      expect(post.reposted, isFalse);
    });

    test('hydrates reposted when the row id is in the viewer repost set', () {
      final post = PostRepository.mapPostRow(
        _row('p1'),
        repostedIds: <String>{'p1'},
      );
      expect(post.reposted, isTrue);
      expect(post.liked, isFalse);
    });

    test('hydrates both flags independently and leaves counts untouched', () {
      final post = PostRepository.mapPostRow(
        _row('p1'),
        likedIds: <String>{'p1'},
        repostedIds: <String>{'p1'},
      );
      expect(post.liked, isTrue);
      expect(post.reposted, isTrue);
      // Per-viewer state must not alter the server-owned counts.
      expect(post.likeCount, 4);
      expect(post.repostCount, 3);
    });

    test('does not hydrate flags for a row id absent from the sets', () {
      final post = PostRepository.mapPostRow(
        _row('p2'),
        likedIds: <String>{'p1'},
        repostedIds: <String>{'p1'},
      );
      expect(post.liked, isFalse);
      expect(post.reposted, isFalse);
    });
  });

  group('mapPostRow attachments (polymorphic content)', () {
    Map<String, dynamic> attachment(String id, int position, String type) =>
        <String, dynamic>{
          'id': id,
          'post_id': 'p1',
          'position': position,
          'type': type,
          'url': 'https://example.com/$id.jpg',
        };

    test('maps a 3-attachment array into an ordered carousel post', () {
      final row = _row('p1')
        ..['post_attachments'] = <Map<String, dynamic>>[
          // Deliberately out of order to prove the mapper sorts by position.
          attachment('a2', 2, 'image'),
          attachment('a0', 0, 'image'),
          attachment('a1', 1, 'image'),
        ];
      final post = PostRepository.mapPostRow(row);
      expect(post.kind, PostKind.carousel);
      expect(post.attachments.length, 3);
      expect(
        post.attachments.map((a) => a.position).toList(),
        <int>[0, 1, 2],
      );
      expect(post.attachments.map((a) => a.id).toList(), <String>['a0', 'a1', 'a2']);
      // Legacy shim reflects the first attachment.
      expect(post.mediaUrl, post.attachments.first.url);
      expect(post.hasMedia, isTrue);
    });

    test('maps a single image attachment to kind=image', () {
      final row = _row('p1')
        ..['post_attachments'] = <Map<String, dynamic>>[
          attachment('a0', 0, 'image'),
        ];
      final post = PostRepository.mapPostRow(row);
      expect(post.kind, PostKind.image);
      expect(post.attachments.length, 1);
      expect(post.mediaType, MediaType.image);
    });

    test('maps a single video attachment to kind=video', () {
      final row = _row('p1')
        ..['post_attachments'] = <Map<String, dynamic>>[
          attachment('a0', 0, 'video'),
        ];
      final post = PostRepository.mapPostRow(row);
      expect(post.kind, PostKind.video);
      expect(post.attachments.single.type, AttachmentType.video);
      expect(post.mediaType, MediaType.video);
    });

    test('falls back to legacy media_url/media_type for a pre-0005 row', () {
      final row = _row('p1')
        ..['media_url'] = 'https://example.com/legacy.jpg'
        ..['media_type'] = 'image';
      // No post_attachments key present at all.
      final post = PostRepository.mapPostRow(row);
      expect(post.kind, PostKind.image);
      expect(post.attachments.length, 1);
      expect(post.attachments.first.url, 'https://example.com/legacy.jpg');
      expect(post.mediaUrl, 'https://example.com/legacy.jpg');
    });

    test('falls back to a legacy video row via media_type=video', () {
      final row = _row('p1')
        ..['media_url'] = 'https://example.com/clip.mp4'
        ..['media_type'] = 'video';
      final post = PostRepository.mapPostRow(row);
      expect(post.kind, PostKind.video);
      expect(post.attachments.single.type, AttachmentType.video);
    });

    test('maps a row with no media to kind=text with empty attachments', () {
      // The base _row has media_url=null, media_type='none', no attachments.
      final post = PostRepository.mapPostRow(_row('p1'));
      expect(post.kind, PostKind.text);
      expect(post.attachments, isEmpty);
      expect(post.hasMedia, isFalse);
      expect(post.mediaUrl, isNull);
      expect(post.mediaType, MediaType.none);
    });

    test('prefers the post_attachments array over legacy media columns', () {
      final row = _row('p1')
        ..['media_url'] = 'https://example.com/legacy.jpg'
        ..['media_type'] = 'image'
        ..['post_attachments'] = <Map<String, dynamic>>[
          attachment('a0', 0, 'image'),
          attachment('a1', 1, 'image'),
        ];
      final post = PostRepository.mapPostRow(row);
      expect(post.kind, PostKind.carousel);
      expect(post.attachments.length, 2);
      expect(post.attachments.first.id, 'a0');
    });
  });

  group('react / clearReaction', () {
    test('sets myReaction and increments the right bucket with one notify', () {
      final post = firstPost();
      var notified = 0;
      repo.addListener(() => notified++);

      final updated = repo.react(post.id, ReactionType.love);
      expect(updated, isNotNull);
      expect(updated!.myReaction, ReactionType.love);
      expect(updated.reactionCounts[ReactionType.love], 1);
      // A non-like reaction leaves the legacy liked view false.
      expect(updated.liked, isFalse);
      expect(notified, 1);
    });

    test('switching reactions moves the count between buckets', () {
      final post = firstPost();
      repo.react(post.id, ReactionType.love);
      final switched = repo.react(post.id, ReactionType.laugh);
      expect(switched!.myReaction, ReactionType.laugh);
      expect(switched.reactionCounts.containsKey(ReactionType.love), isFalse);
      expect(switched.reactionCounts[ReactionType.laugh], 1);
    });

    test('clearReaction removes myReaction and empties the bucket', () {
      final post = firstPost();
      repo.react(post.id, ReactionType.wow);
      final cleared = repo.clearReaction(post.id);
      expect(cleared!.myReaction, isNull);
      expect(cleared.reactionCounts.containsKey(ReactionType.wow), isFalse);
    });

    test('react to the same type again is a no-op (no bucket growth)', () {
      final post = firstPost();
      repo.react(post.id, ReactionType.sad);
      final again = repo.react(post.id, ReactionType.sad);
      expect(again!.reactionCounts[ReactionType.sad], 1);
    });

    test('returns null for an unknown id', () {
      expect(repo.react('nope', ReactionType.like), isNull);
      expect(repo.clearReaction('nope'), isNull);
    });
  });

  group('toggleLike via the react wrapper', () {
    test('still flips liked and moves likeCount +/-1', () {
      final post = firstPost();
      final startLiked = post.liked;
      final startCount = post.likeCount;

      final afterFirst = repo.toggleLike(post.id);
      expect(afterFirst!.liked, !startLiked);
      expect(afterFirst.likeCount, startCount + (!startLiked ? 1 : -1));
      // The wrapper routes through the like reaction bucket.
      expect(afterFirst.myReaction, afterFirst.liked ? ReactionType.like : null);

      final afterSecond = repo.toggleLike(post.id);
      expect(afterSecond!.liked, startLiked);
      expect(afterSecond.likeCount, startCount);
    });

    test('tapping like while a non-like reaction is set switches to like', () {
      final post = firstPost();
      // Normalize to a known "no reaction" baseline so the assertions do not
      // depend on the seed's initial like state.
      repo.clearReaction(post.id);
      final baseCount = repo.forYou().firstWhere((p) => p.id == post.id).likeCount;
      repo.react(post.id, ReactionType.love);
      final liked = repo.toggleLike(post.id);
      expect(liked!.myReaction, ReactionType.like);
      expect(liked.liked, isTrue);
      // love -> like: the like bucket gains 1 over the no-reaction baseline.
      expect(liked.likeCount, baseCount + 1);
      expect(liked.reactionCounts.containsKey(ReactionType.love), isFalse);
    });
  });

  group('mapPostRow reactions + location', () {
    test('populates reactionCounts from a grouped reactions join', () {
      final row = _row('p1')
        ..['reactions'] = <Map<String, dynamic>>[
          <String, dynamic>{'type': 'like', 'count': 3},
          <String, dynamic>{'type': 'love', 'count': 2},
        ];
      final post = PostRepository.mapPostRow(row);
      expect(post.reactionCounts[ReactionType.like], 3);
      expect(post.reactionCounts[ReactionType.love], 2);
    });

    test('populates reactionCounts from a reaction_counts map', () {
      final row = _row('p1')
        ..['reaction_counts'] = <String, dynamic>{'laugh': 5};
      final post = PostRepository.mapPostRow(row);
      expect(post.reactionCounts[ReactionType.laugh], 5);
    });

    test('stays empty when no reactions join is present', () {
      final post = PostRepository.mapPostRow(_row('p1'));
      expect(post.reactionCounts, isEmpty);
      expect(post.myReaction, isNull);
      expect(post.liked, isFalse);
    });

    test('hydrates myReaction from an explicit viewer reaction field', () {
      final row = _row('p1')..['my_reaction'] = 'love';
      final post = PostRepository.mapPostRow(row);
      expect(post.myReaction, ReactionType.love);
      expect(post.liked, isFalse);
    });

    test('legacy likedIds still hydrates myReaction=like', () {
      final post = PostRepository.mapPostRow(
        _row('p1'),
        likedIds: <String>{'p1'},
      );
      expect(post.myReaction, ReactionType.like);
      expect(post.liked, isTrue);
    });

    test('hydrates the viewer reaction TYPE from viewerReactions (reactions '
        'table read path)', () {
      // Review v1, issue 1: the viewer's own reaction is now read from
      // public.reactions and carries the real type, so a non-like reaction
      // survives a reload (not forced to `like`).
      final post = PostRepository.mapPostRow(
        _row('p1'),
        viewerReactions: <String, ReactionType>{'p1': ReactionType.love},
      );
      expect(post.myReaction, ReactionType.love);
      expect(post.liked, isFalse);
    });

    test('a viewer LIKE from viewerReactions lights the legacy liked view', () {
      final post = PostRepository.mapPostRow(
        _row('p1'),
        viewerReactions: <String, ReactionType>{'p1': ReactionType.like},
      );
      expect(post.myReaction, ReactionType.like);
      expect(post.liked, isTrue);
    });

    test('does not hydrate a reaction for a post absent from viewerReactions',
        () {
      final post = PostRepository.mapPostRow(
        _row('p2'),
        viewerReactions: <String, ReactionType>{'p1': ReactionType.love},
      );
      expect(post.myReaction, isNull);
      expect(post.liked, isFalse);
    });

    test('populates reactionCounts from a plain reactions(type) join', () {
      // The load()/loadMore() select now joins `reactions(type)` (un-aggregated
      // rows); each row counts as one so reactionCounts still hydrates.
      final row = _row('p1')
        ..['reactions'] = <Map<String, dynamic>>[
          <String, dynamic>{'type': 'like'},
          <String, dynamic>{'type': 'like'},
          <String, dynamic>{'type': 'love'},
        ];
      final post = PostRepository.mapPostRow(row);
      expect(post.reactionCounts[ReactionType.like], 2);
      expect(post.reactionCounts[ReactionType.love], 1);
    });

    test('a like made this session round-trips through a server reload '
        '(issue 1)', () {
      // Review v1, issue 1 (BLOCKING): a like/reaction is persisted to
      // public.reactions, so a later server-backed reload reads it back from
      // reactions (via viewerReactions) and re-hydrates myReaction. Before the
      // fix, load() read the dormant likes table and the like rendered as
      // un-liked after reload. Simulate the full round-trip:
      //   1. viewer reacts (love) in-session;
      final post = firstPost();
      repo.clearReaction(post.id); // normalize to a known baseline
      final reacted = repo.react(post.id, ReactionType.love);
      expect(reacted!.myReaction, ReactionType.love);
      //   2. a server reload maps the fresh row; the reactions read returns the
      //      viewer's own reaction TYPE for that post;
      final reloaded = PostRepository.mapPostRow(
        _row(post.id),
        viewerReactions: <String, ReactionType>{post.id: ReactionType.love},
      );
      //   3. the reaction survives the reload with the correct (non-like) type.
      expect(reloaded.myReaction, ReactionType.love);
      expect(reloaded.liked, isFalse);

      // And a plain like round-trips as a lit `liked` view.
      final likedReload = PostRepository.mapPostRow(
        _row(post.id),
        viewerReactions: <String, ReactionType>{post.id: ReactionType.like},
      );
      expect(likedReload.liked, isTrue);
      expect(likedReload.myReaction, ReactionType.like);
    });

    test('maps optional location/lat/lng from the row', () {
      final row = _row('p1')
        ..['location'] = 'Lisbon'
        ..['lat'] = 38.72
        ..['lng'] = -9.13;
      final post = PostRepository.mapPostRow(row);
      expect(post.location, 'Lisbon');
      expect(post.lat, 38.72);
      expect(post.lng, -9.13);
    });
  });

  group('Post.copyWith reaction resolution (review v1, nit 2)', () {
    Post base() => Post(
          id: 'c1',
          author: MockData.currentUser,
          content: 'x',
          createdAt: DateTime(2024),
        );

    test('clearMyReaction lowers a non-like reaction to null (liked stays '
        'false)', () {
      final reacted = base().copyWith(myReaction: ReactionType.love);
      expect(reacted.myReaction, ReactionType.love);
      expect(reacted.liked, isFalse);
      final cleared = reacted.copyWith(clearMyReaction: true);
      expect(cleared.myReaction, isNull);
      expect(cleared.liked, isFalse);
    });

    test('setting a non-like reaction reads liked=false without a liked arg',
        () {
      final liked = base().copyWith(liked: true);
      expect(liked.liked, isTrue);
      // Switching to a non-like reaction lowers liked to false on its own.
      final switched = liked.copyWith(myReaction: ReactionType.laugh);
      expect(switched.myReaction, ReactionType.laugh);
      expect(switched.liked, isFalse);
    });

    test('liked:false clears any reaction under like-implies-liked', () {
      final liked = base().copyWith(myReaction: ReactionType.love);
      final lowered = liked.copyWith(liked: false);
      expect(lowered.myReaction, isNull);
      expect(lowered.liked, isFalse);
    });

    test('a bare copyWith carries the existing reaction unchanged', () {
      final reacted = base().copyWith(myReaction: ReactionType.wow);
      final unchanged = reacted.copyWith(content: 'y');
      expect(unchanged.myReaction, ReactionType.wow);
    });
  });

  group('toggleBookmark drives SaveRepository', () {
    test('flips bookmarked (via SaveRepository) without touching counts', () {
      final post = firstPost();
      final startSaved = SaveRepository.instance.isSaved(post.id);
      final startLikeCount = post.likeCount;

      final updated = repo.toggleBookmark(post.id);
      expect(updated, isNotNull);
      expect(updated!.bookmarked, !startSaved);
      expect(SaveRepository.instance.isSaved(post.id), !startSaved);
      expect(updated.likeCount, startLikeCount);

      final reverted = repo.toggleBookmark(post.id);
      expect(reverted!.bookmarked, startSaved);
      expect(SaveRepository.instance.isSaved(post.id), startSaved);
    });

    test('returns null for an unknown id', () {
      expect(repo.toggleBookmark('nope'), isNull);
    });
  });
}
