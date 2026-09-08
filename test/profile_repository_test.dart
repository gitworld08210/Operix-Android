import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/data/profile_repository.dart';
import 'package:oneleven/models/notification_item.dart';

void main() {
  late ProfileRepository repo;

  setUp(() {
    repo = ProfileRepository();
  });

  group('notifications', () {
    test('are returned newest-first', () {
      final list = repo.notifications();
      expect(list, isNotEmpty);
      for (var i = 0; i < list.length - 1; i++) {
        expect(
          list[i].createdAt.isAfter(list[i + 1].createdAt) ||
              list[i].createdAt.isAtSameMomentAs(list[i + 1].createdAt),
          isTrue,
        );
      }
    });

    test('unreadNotifications counts only unread entries', () {
      final unread = repo.notifications().where((n) => !n.read).length;
      expect(repo.unreadNotifications, unread);
      expect(repo.unreadNotifications, greaterThan(0));
    });

    test('markNotificationsRead clears the unread count and notifies', () {
      var notified = 0;
      repo.addListener(() => notified++);

      expect(repo.unreadNotifications, greaterThan(0));
      repo.markNotificationsRead();

      expect(repo.unreadNotifications, 0);
      expect(notified, 1);
      for (final n in repo.notifications()) {
        expect(n.read, isTrue);
      }
    });

    test('markNotificationsRead persistence path stays guarded on mock fallback',
        () {
      // With Supabase uninitialized (test/offline), the guarded persistence
      // helper must be a no-op that never throws, while the in-memory read
      // state still flips. A second call is idempotent and does not notify
      // again (nothing left to change).
      repo.markNotificationsRead();
      expect(repo.unreadNotifications, 0);

      var notified = 0;
      repo.addListener(() => notified++);
      repo.markNotificationsRead();
      expect(repo.unreadNotifications, 0);
      // Nothing changed, so no extra notify. (The optimistic-only path still
      // never throws even though Supabase is unavailable.)
      expect(notified, 0);
    });

    test('covers the FEAT-002 notification types including follow_request '
        'and system', () {
      final types = repo.notifications().map((n) => n.type).toSet();
      expect(types.contains(NotificationType.followRequest), isTrue);
      expect(types.contains(NotificationType.system), isTrue);
    });

    test('NotificationType covers all seven FEAT-002 types', () {
      expect(NotificationType.values, hasLength(7));
      expect(NotificationType.values, containsAll(<NotificationType>[
        NotificationType.like,
        NotificationType.reply,
        NotificationType.repost,
        NotificationType.follow,
        NotificationType.mention,
        NotificationType.followRequest,
        NotificationType.system,
      ]));
    });
  });

  group('conversations', () {
    test('are returned most-recently-updated first', () {
      final list = repo.conversations();
      expect(list, isNotEmpty);
      for (var i = 0; i < list.length - 1; i++) {
        expect(
          list[i].updatedAt.isAfter(list[i + 1].updatedAt) ||
              list[i].updatedAt.isAtSameMomentAs(list[i + 1].updatedAt),
          isTrue,
        );
      }
    });

    test('unreadMessages sums unread across conversations', () {
      final expected =
          repo.conversations().fold<int>(0, (sum, c) => sum + c.unread);
      expect(repo.unreadMessages, expected);
    });

    test('conversationById returns a match or null', () {
      final first = repo.conversations().first;
      expect(repo.conversationById(first.id), isNotNull);
      expect(repo.conversationById('missing-id'), isNull);
    });
  });

  group('updateProfile', () {
    test('updates editable fields and notifies', () {
      var notified = 0;
      repo.addListener(() => notified++);

      repo.updateProfile(displayName: 'New Name', bio: 'New bio');

      expect(repo.currentUser.displayName, 'New Name');
      expect(repo.currentUser.bio, 'New bio');
      expect(notified, 1);
    });
  });
}
