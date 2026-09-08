import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/data/profile_repository.dart';

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
