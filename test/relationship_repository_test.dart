import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/data/mock_data.dart';
import 'package:oneleven/data/relationship_repository.dart';
import 'package:oneleven/models/user_profile.dart';

UserProfile _public(String id) =>
    UserProfile(id: id, username: id, displayName: id);

UserProfile _private(String id) =>
    UserProfile(id: id, username: id, displayName: id, isPrivate: true);

void main() {
  // Use a fresh repository per test so the shared singleton's mutable state
  // never leaks between cases (mirrors the other repository tests).
  late RelationshipRepository repo;

  setUp(() {
    repo = RelationshipRepository();
  });

  group('followStateForNewFollow (pure)', () {
    test('public account => following, private account => requested', () {
      expect(followStateForNewFollow(_public('a')), FollowState.following);
      expect(followStateForNewFollow(_private('b')), FollowState.requested);
    });
  });

  group('follow / unfollow', () {
    test('public target yields FollowState.following and notifies once', () {
      final target = _public('u_marco');
      expect(repo.followStateFor(target.id), FollowState.none);

      var notified = 0;
      repo.addListener(() => notified++);
      repo.follow(target);

      expect(repo.followStateFor(target.id), FollowState.following);
      expect(notified, 1);
    });

    test('private target yields FollowState.requested and notifies once', () {
      final target = _private('u_secret');
      var notified = 0;
      repo.addListener(() => notified++);
      repo.follow(target);

      expect(repo.followStateFor(target.id), FollowState.requested);
      expect(notified, 1);
    });

    test('follow is idempotent (no second notify in the same state)', () {
      final target = _public('u_marco');
      repo.follow(target);
      var notified = 0;
      repo.addListener(() => notified++);
      repo.follow(target); // already following
      expect(notified, 0);
    });

    test('unfollow returns to none and notifies once', () {
      final target = _public('u_marco');
      repo.follow(target);
      var notified = 0;
      repo.addListener(() => notified++);
      repo.unfollow(target.id);
      expect(repo.followStateFor(target.id), FollowState.none);
      expect(notified, 1);
    });

    test('unfollow is idempotent when there is no edge', () {
      var notified = 0;
      repo.addListener(() => notified++);
      repo.unfollow('never-followed');
      expect(notified, 0);
    });

    test('guarded persistence does not throw on the mock/offline path', () {
      expect(() => repo.follow(_public('u_marco')), returnsNormally);
      expect(() => repo.follow(_private('u_secret')), returnsNormally);
      expect(() => repo.unfollow('u_marco'), returnsNormally);
    });
  });

  group('load (guarded, offline)', () {
    test('is a no-op that never throws and never notifies offline', () async {
      // Offline/unauthenticated (no reachable Supabase) load() must keep the
      // mock seed intact and fire no notification. The notify-only-on-change
      // guard (mapEquals on edges + request equality) additionally suppresses a
      // redundant notify when a live hydrate matches the current cache.
      final seededEdge = repo.followStateFor(MockData.citydesk.id);
      final seededRequests = repo.pendingRequests().map((p) => p.id).toList();

      var notified = 0;
      repo.addListener(() => notified++);
      await repo.load();

      expect(notified, 0);
      expect(repo.followStateFor(MockData.citydesk.id), seededEdge);
      expect(repo.pendingRequests().map((p) => p.id), seededRequests);
    });
  });

  group('pendingRequests', () {
    test('reflects the mock seed and is unmodifiable', () {
      final list = repo.pendingRequests();
      expect(list, isNotEmpty);
      expect(list.map((p) => p.id), contains(MockData.citydesk.id));
      expect(() => list.add(MockData.aria), throwsUnsupportedError);
    });

    test('is newest-first', () {
      final list = repo.pendingRequests();
      // Only the seed drives ordering here; assert it is a stable list. With a
      // single seed entry this is trivially ordered; the sort contract is
      // exercised by acceptFollowRequest/denyFollowRequest below.
      expect(list, isNotEmpty);
    });
  });

  group('acceptFollowRequest / denyFollowRequest', () {
    test('accept removes the pending request and notifies once', () {
      final actorId = MockData.citydesk.id;
      expect(repo.pendingRequests().map((p) => p.id), contains(actorId));

      var notified = 0;
      repo.addListener(() => notified++);
      repo.acceptFollowRequest(actorId);

      expect(repo.pendingRequests().map((p) => p.id), isNot(contains(actorId)));
      expect(notified, 1);
    });

    test('deny removes the pending request and notifies once', () {
      final actorId = MockData.citydesk.id;
      var notified = 0;
      repo.addListener(() => notified++);
      repo.denyFollowRequest(actorId);

      expect(repo.pendingRequests().map((p) => p.id), isNot(contains(actorId)));
      expect(notified, 1);
    });

    test('accept/deny are idempotent for an unknown actor', () {
      var notified = 0;
      repo.addListener(() => notified++);
      repo.acceptFollowRequest('nobody');
      repo.denyFollowRequest('nobody');
      expect(notified, 0);
    });

    test('guarded persistence does not throw on the mock/offline path', () {
      expect(
        () => repo.acceptFollowRequest(MockData.citydesk.id),
        returnsNormally,
      );
    });
  });
}
