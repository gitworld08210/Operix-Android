import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/data/profile_repository.dart';
import 'package:oneleven/models/user_profile.dart';

void main() {
  group('UserProfile.isPrivate', () {
    test('defaults to false', () {
      const p = UserProfile(id: 'u1', username: 'u', displayName: 'U');
      expect(p.isPrivate, isFalse);
    });

    test('copyWith(isPrivate:) round-trips and leaves other fields unchanged',
        () {
      const p = UserProfile(
        id: 'u1',
        username: 'u',
        displayName: 'U',
        bio: 'hi',
        followers: 10,
        following: 3,
        verified: true,
      );
      final updated = p.copyWith(isPrivate: true);
      expect(updated.isPrivate, isTrue);
      // Unchanged fields.
      expect(updated.id, 'u1');
      expect(updated.username, 'u');
      expect(updated.displayName, 'U');
      expect(updated.bio, 'hi');
      expect(updated.followers, 10);
      expect(updated.following, 3);
      expect(updated.verified, isTrue);
      // Original is immutable / untouched.
      expect(p.isPrivate, isFalse);
    });

    test('copyWith without isPrivate preserves the existing value', () {
      const p = UserProfile(
        id: 'u1',
        username: 'u',
        displayName: 'U',
        isPrivate: true,
      );
      final updated = p.copyWith(displayName: 'New');
      expect(updated.isPrivate, isTrue);
      expect(updated.displayName, 'New');
    });
  });

  group('setAccountPrivate', () {
    late ProfileRepository repo;

    setUp(() {
      repo = ProfileRepository();
    });

    test('flips currentUser.isPrivate and notifies exactly once', () {
      expect(repo.currentUser.isPrivate, isFalse);
      var notified = 0;
      repo.addListener(() => notified++);

      repo.setAccountPrivate(true);

      expect(repo.currentUser.isPrivate, isTrue);
      expect(notified, 1);
    });

    test('is idempotent: a second identical call does not notify', () {
      repo.setAccountPrivate(true);
      expect(repo.currentUser.isPrivate, isTrue);

      var notified = 0;
      repo.addListener(() => notified++);
      repo.setAccountPrivate(true);

      expect(repo.currentUser.isPrivate, isTrue);
      expect(notified, 0);
    });

    test('setting back to false toggles and notifies again', () {
      repo.setAccountPrivate(true);
      var notified = 0;
      repo.addListener(() => notified++);

      repo.setAccountPrivate(false);

      expect(repo.currentUser.isPrivate, isFalse);
      expect(notified, 1);
    });

    test('guarded persistence never throws on the mock fallback path', () {
      // Supabase is uninitialized under tests; the guarded helper must no-op.
      expect(() => repo.setAccountPrivate(true), returnsNormally);
    });
  });

  group('exportMyData', () {
    late ProfileRepository repo;

    setUp(() {
      repo = ProfileRepository();
    });

    test('assembles the current user profile into a well-formed payload',
        () async {
      final export = await repo.exportMyData();
      final me = repo.currentUser;

      expect(export.profile['id'], me.id);
      expect(export.profile['username'], me.username);
      expect(export.profile['display_name'], me.displayName);
      expect(export.profile['is_private'], me.isPrivate);
      expect(export.posts, isA<List<Map<String, dynamic>>>());
      expect(export.comments, isA<List<Map<String, dynamic>>>());
    });

    test('produces valid JSON with the expected top-level keys', () async {
      final export = await repo.exportMyData();
      final decoded = jsonDecode(export.toJsonString()) as Map<String, dynamic>;

      expect(decoded.keys,
          containsAll(<String>['generated_at', 'profile', 'posts', 'comments']));
      expect(decoded['profile'], isA<Map<String, dynamic>>());
    });

    test('buildDataExport includes the injected posts and comments', () {
      final export = repo.buildDataExport(
        posts: <Map<String, dynamic>>[
          <String, dynamic>{'id': 'p1', 'content': 'hello'},
        ],
        comments: <Map<String, dynamic>>[
          <String, dynamic>{'id': 'c1', 'content': 'nice'},
        ],
      );
      expect(export.posts, hasLength(1));
      expect(export.posts.first['id'], 'p1');
      expect(export.comments, hasLength(1));
      expect(export.comments.first['id'], 'c1');
      expect(export.profile['id'], repo.currentUser.id);
    });
  });

  group('requestAccountDeletion', () {
    test('returns a scaffolded not-available result, never claiming success',
        () async {
      final repo = ProfileRepository();
      final result = await repo.requestAccountDeletion();

      expect(result.status, AccountActionStatus.notAvailable);
      expect(result.succeeded, isFalse);
      expect(result.message, isNotEmpty);
      expect(result.message.toLowerCase(), contains('not available'));
    });
  });
}
