import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/data/mock_data.dart';
import 'package:oneleven/data/safety_repository.dart';
import 'package:oneleven/models/post.dart';
import 'package:oneleven/models/user_profile.dart';

UserProfile _author(String id) =>
    UserProfile(id: id, username: id, displayName: id);

Post _post(String id, String authorId) => Post(
      id: id,
      author: _author(authorId),
      content: 'c',
      createdAt: DateTime(2024, 1, 1),
    );

void main() {
  // Use a fresh repository per test so the shared singleton's mutable state
  // never leaks between cases (mirrors the other repository tests).
  late SafetyRepository repo;

  setUp(() {
    repo = SafetyRepository();
  });

  group('seed', () {
    test('defaults to empty block/mute sets so the feed is unchanged', () {
      expect(repo.blockedIds, isEmpty);
      expect(repo.mutedIds, isEmpty);
      expect(MockData.blockedUserIds(), isEmpty);
      expect(MockData.mutedUserIds(), isEmpty);
    });

    test('exposes unmodifiable views', () {
      expect(() => repo.blockedIds.add('x'), throwsUnsupportedError);
      expect(() => repo.mutedIds.add('x'), throwsUnsupportedError);
    });
  });

  group('block / unblock', () {
    test('flips the set and reflects via isBlocked', () {
      expect(repo.isBlocked('u_aria'), isFalse);
      repo.block('u_aria');
      expect(repo.isBlocked('u_aria'), isTrue);
      expect(repo.blockedIds, contains('u_aria'));
      repo.unblock('u_aria');
      expect(repo.isBlocked('u_aria'), isFalse);
      expect(repo.blockedIds, isEmpty);
    });

    test('notifies exactly once on a real change', () {
      var notified = 0;
      repo.addListener(() => notified++);
      repo.block('u_aria');
      expect(notified, 1);
      repo.unblock('u_aria');
      expect(notified, 2);
    });

    test('is idempotent (no notify when already in desired state)', () {
      repo.block('u_aria');
      var notified = 0;
      repo.addListener(() => notified++);
      repo.block('u_aria'); // already blocked
      expect(notified, 0);
      repo.unblock('u_nova'); // never blocked
      expect(notified, 0);
    });

    test('guarded persistence does not throw on the mock/offline path', () {
      expect(() => repo.block('u_aria'), returnsNormally);
      expect(() => repo.unblock('u_aria'), returnsNormally);
    });
  });

  group('mute / unmute', () {
    test('flips the set and reflects via isMuted', () {
      expect(repo.isMuted('u_marco'), isFalse);
      repo.mute('u_marco');
      expect(repo.isMuted('u_marco'), isTrue);
      expect(repo.mutedIds, contains('u_marco'));
      repo.unmute('u_marco');
      expect(repo.isMuted('u_marco'), isFalse);
    });

    test('notifies exactly once on a real change and is idempotent', () {
      var notified = 0;
      repo.addListener(() => notified++);
      repo.mute('u_marco');
      expect(notified, 1);
      repo.mute('u_marco'); // idempotent
      expect(notified, 1);
      repo.unmute('u_marco');
      expect(notified, 2);
      repo.unmute('u_marco'); // idempotent
      expect(notified, 2);
    });
  });

  group('report', () {
    test('throws ReportValidationError on an empty reason', () async {
      await expectLater(
        repo.report(targetType: 'post', targetId: 'p1', reason: '   '),
        throwsA(isA<ReportValidationError>()),
      );
    });

    test('throws ReportValidationError when the reason exceeds the limit',
        () async {
      final tooLong = 'x' * (SafetyRepository.maxReasonLength + 1);
      await expectLater(
        repo.report(targetType: 'post', targetId: 'p1', reason: tooLong),
        throwsA(isA<ReportValidationError>()),
      );
    });

    test('does not throw on a valid reason on the mock/offline path',
        () async {
      await expectLater(
        repo.report(targetType: 'post', targetId: 'p1', reason: 'spam'),
        completes,
      );
      // A reason exactly at the limit is valid.
      await expectLater(
        repo.report(
          targetType: 'profile',
          targetId: 'u_aria',
          reason: 'x' * SafetyRepository.maxReasonLength,
        ),
        completes,
      );
    });
  });

  group('filterHidden (pure)', () {
    final posts = <Post>[
      _post('p1', 'u_aria'),
      _post('p2', 'u_nova'),
      _post('p3', 'u_marco'),
    ];

    test('is identity (same instance) when both sets are empty', () {
      final result = filterHidden(
        posts,
        blocked: const <String>{},
        muted: const <String>{},
      );
      expect(identical(result, posts), isTrue);
    });

    test('removes blocked authors and preserves order', () {
      final result = filterHidden(
        posts,
        blocked: <String>{'u_nova'},
        muted: const <String>{},
      );
      expect(result.map((p) => p.id), <String>['p1', 'p3']);
    });

    test('removes muted authors and preserves order', () {
      final result = filterHidden(
        posts,
        blocked: const <String>{},
        muted: <String>{'u_aria'},
      );
      expect(result.map((p) => p.id), <String>['p2', 'p3']);
    });

    test('removes the union of blocked and muted authors', () {
      final result = filterHidden(
        posts,
        blocked: <String>{'u_aria'},
        muted: <String>{'u_marco'},
      );
      expect(result.map((p) => p.id), <String>['p2']);
    });

    test('never hides the viewer\'s own post even when self-blocked/muted', () {
      // A (nonsensical) self-block/self-mute must not drop the author's own
      // post from their own feed — the viewerId exemption keeps it visible.
      final result = filterHidden(
        posts,
        blocked: <String>{'u_aria'},
        muted: <String>{'u_aria'},
        viewerId: 'u_aria',
      );
      expect(result.map((p) => p.id), <String>['p1', 'p2', 'p3']);
    });

    test('viewer exemption is scoped: other blocked authors still filtered', () {
      final result = filterHidden(
        posts,
        blocked: <String>{'u_aria', 'u_nova'},
        muted: const <String>{},
        viewerId: 'u_aria',
      );
      // u_aria is exempt (viewer); u_nova is still removed.
      expect(result.map((p) => p.id), <String>['p1', 'p3']);
    });
  });
}
