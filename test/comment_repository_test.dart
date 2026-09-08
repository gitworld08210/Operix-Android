import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/data/comment_repository.dart';
import 'package:oneleven/data/mock_data.dart';
import 'package:oneleven/utils/comment_tree.dart';

void main() {
  // Fresh repository per test so the shared singleton's mutable cache never
  // leaks between cases.
  late CommentRepository repo;

  setUp(() {
    repo = CommentRepository();
  });

  group('commentsFor', () {
    test('returns comments for the post, newest-first', () {
      final list = repo.commentsFor('p1');
      expect(list, isNotEmpty);
      for (final c in list) {
        expect(c.postId, 'p1');
      }
      for (var i = 0; i < list.length - 1; i++) {
        expect(
          list[i].createdAt.isAfter(list[i + 1].createdAt) ||
              list[i].createdAt.isAtSameMomentAs(list[i + 1].createdAt),
          isTrue,
          reason: 'expected descending createdAt order',
        );
      }
    });

    test('filters strictly by postId', () {
      final onlyP2 = repo.commentsFor('p2');
      expect(onlyP2, isNotEmpty);
      expect(onlyP2.every((c) => c.postId == 'p2'), isTrue);
      // A comment seeded on p1 must not appear under p2.
      expect(onlyP2.any((c) => c.postId == 'p1'), isFalse);
    });

    test('returns an empty list for an unknown post', () {
      expect(repo.commentsFor('does-not-exist'), isEmpty);
    });

    test('returns an unmodifiable view', () {
      final list = repo.commentsFor('p1');
      expect(() => list.add(list.first), throwsUnsupportedError);
    });
  });

  group('addComment validation', () {
    test('rejects empty content', () {
      expect(
        () => repo.addComment('p1', ''),
        throwsA(isA<CommentValidationError>()),
      );
    });

    test('rejects whitespace-only content', () {
      expect(
        () => repo.addComment('p1', '   \n\t '),
        throwsA(isA<CommentValidationError>()),
      );
    });

    test('rejects content over the max length', () {
      final tooLong = 'a' * (CommentRepository.maxContentLength + 1);
      expect(
        () => repo.addComment('p1', tooLong),
        throwsA(isA<CommentValidationError>()),
      );
    });

    test('accepts content at exactly the max length', () {
      final atLimit = 'a' * CommentRepository.maxContentLength;
      final added = repo.addComment('p1', atLimit);
      expect(added.content.length, CommentRepository.maxContentLength);
    });

    test('does not mutate the cache or notify on invalid input', () {
      final before = repo.commentsFor('p1').length;
      var notified = 0;
      repo.addListener(() => notified++);
      expect(() => repo.addComment('p1', ''), throwsA(anything));
      expect(repo.commentsFor('p1').length, before);
      expect(notified, 0);
    });
  });

  group('addComment success', () {
    test('prepends the new comment and orders it first', () {
      final before = repo.commentsFor('p1').length;
      final added = repo.addComment('p1', 'A fresh reply');

      final after = repo.commentsFor('p1');
      expect(after.length, before + 1);
      // Newest-first ordering: the just-added comment (DateTime.now()) sorts
      // to the front.
      expect(after.first.id, added.id);
      expect(after.first.content, 'A fresh reply');
      expect(after.first.postId, 'p1');
    });

    test('trims surrounding whitespace', () {
      final added = repo.addComment('p1', '  hello  ');
      expect(added.content, 'hello');
    });

    test('notifies listeners exactly once', () {
      var notified = 0;
      repo.addListener(() => notified++);
      repo.addComment('p1', 'Just once');
      expect(notified, 1);
    });

    test('preserves parentId for threaded replies', () {
      final added = repo.addComment('p1', 'A threaded reply', parentId: 'cm1');
      expect(added.parentId, 'cm1');
      expect(added.isTopLevel, isFalse);
    });

    test('attributes the comment to the current user', () {
      final added = repo.addComment('p1', 'Mine');
      expect(added.author.id, MockData.currentUser.id);
    });

    test('does not leak into another post', () {
      final p2Before = repo.commentsFor('p2').length;
      repo.addComment('p1', 'Only on p1');
      expect(repo.commentsFor('p2').length, p2Before);
    });

    test('a reply added with a parentId nests under its parent via buildThread',
        () {
      final reply = repo.addComment('p1', 'Nested reply', parentId: 'cm1');
      final tree = buildThread(repo.commentsFor('p1'));
      final cm1 = tree.firstWhere((n) => n.comment.id == 'cm1');
      // Both the seeded cm2 and the newly added reply appear under cm1.
      final replyIds = cm1.replies.map((n) => n.comment.id).toList();
      expect(replyIds, contains(reply.id));
      expect(replyIds, contains('cm2'));
    });
  });

  group('comment likes', () {
    test('viewer comment-like state starts empty (seed unchanged)', () {
      expect(MockData.likedCommentIds(), isEmpty);
      expect(repo.isCommentLiked('cm1'), isFalse);
    });

    test('toggleCommentLike flips liked and adjusts display like_count by +1',
        () {
      final before =
          repo.commentsFor('p1').firstWhere((c) => c.id == 'cm1').likeCount;
      final updated = repo.toggleCommentLike('cm1');
      expect(updated, isNotNull);
      expect(repo.isCommentLiked('cm1'), isTrue);
      expect(updated!.likeCount, before + 1);
      expect(
        repo.commentsFor('p1').firstWhere((c) => c.id == 'cm1').likeCount,
        before + 1,
      );
    });

    test('toggleCommentLike is reversible (un-like restores the count)', () {
      final before =
          repo.commentsFor('p1').firstWhere((c) => c.id == 'cm1').likeCount;
      repo.toggleCommentLike('cm1'); // like
      repo.toggleCommentLike('cm1'); // un-like
      expect(repo.isCommentLiked('cm1'), isFalse);
      expect(
        repo.commentsFor('p1').firstWhere((c) => c.id == 'cm1').likeCount,
        before,
      );
    });

    test('toggleCommentLike notifies listeners exactly once per toggle', () {
      var notified = 0;
      repo.addListener(() => notified++);
      repo.toggleCommentLike('cm1');
      expect(notified, 1);
    });

    test('toggleCommentLike returns null for an unknown comment', () {
      var notified = 0;
      repo.addListener(() => notified++);
      expect(repo.toggleCommentLike('does-not-exist'), isNull);
      expect(notified, 0);
    });

    test('offline load is a no-op firing zero notifications', () async {
      final fresh = CommentRepository();
      var notified = 0;
      fresh.addListener(() => notified++);
      await fresh.load();
      // Supabase is uninitialized under tests: load falls back to the mock
      // seed and the guarded comment-like hydration never notifies.
      expect(notified, 0);
      expect(fresh.isCommentLiked('cm1'), isFalse);
    });
  });
}
