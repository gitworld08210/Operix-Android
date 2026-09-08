import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/data/load_status.dart';
import 'package:oneleven/data/profile_repository.dart';

/// These tests exercise the parts of [ProfileRepository] that do NOT require a
/// booted Supabase client. The repository is now fully Supabase-backed with no
/// mock fallback: a fresh instance starts with no current user, an empty
/// profile list, and [LoadStatus.idle]. Follow/updateProfile/load require a
/// live client and are covered by manual/integration verification.
void main() {
  late ProfileRepository repo;

  setUp(() {
    repo = ProfileRepository();
  });

  group('initial state', () {
    test('starts idle with no current user and no profiles', () {
      expect(repo.status, LoadStatus.idle);
      expect(repo.currentUser, isNull);
      expect(repo.profiles, isEmpty);
      expect(repo.followingIds, isEmpty);
      expect(repo.error, isNull);
    });

    test('isFollowing is false for any id before loading', () {
      expect(repo.isFollowing('anyone'), isFalse);
    });

    test('profiles returns an unmodifiable view', () {
      final list = repo.profiles;
      expect(() => list.clear(), throwsUnsupportedError);
    });
  });

  group('clear', () {
    test('resets to the idle empty state and notifies', () {
      var notified = 0;
      repo.addListener(() => notified++);
      repo.clear();
      expect(repo.status, LoadStatus.idle);
      expect(repo.currentUser, isNull);
      expect(repo.profiles, isEmpty);
      expect(notified, 1);
    });
  });
}
