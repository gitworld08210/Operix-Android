import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/data/mappers.dart';
import 'package:oneleven/models/notification_item.dart';
import 'package:oneleven/models/post.dart';

/// Unit tests for the pure row -> model mapping helpers extracted from the
/// repositories. These exercise the real parsing/derivation logic without a
/// Supabase client and would fail if that logic were reverted.
void main() {
  group('asInt', () {
    test('passes ints through', () {
      expect(asInt(0), 0);
      expect(asInt(42), 42);
    });

    test('truncates other numbers', () {
      expect(asInt(3.9), 3);
    });

    test('parses numeric strings', () {
      expect(asInt('17'), 17);
    });

    test('null and unparseable strings fall back to 0', () {
      expect(asInt(null), 0);
      expect(asInt('not-a-number'), 0);
    });
  });

  group('parseDate', () {
    test('passes a DateTime through unchanged', () {
      final d = DateTime.utc(2024, 1, 2, 3, 4, 5);
      expect(parseDate(d), d);
    });

    test('parses an ISO-8601 string', () {
      expect(
        parseDate('2024-06-15T12:00:00.000Z'),
        DateTime.utc(2024, 6, 15, 12, 0, 0),
      );
    });

    test('uses the provided fallback for null/unparseable', () {
      final fallback = DateTime.utc(2000, 1, 1);
      expect(parseDate(null, fallback: fallback), fallback);
      expect(parseDate('garbage', fallback: fallback), fallback);
    });
  });

  group('mediaTypeFromName', () {
    test('maps known names', () {
      expect(mediaTypeFromName('image'), MediaType.image);
      expect(mediaTypeFromName('video'), MediaType.video);
    });

    test('unknown/null map to none', () {
      expect(mediaTypeFromName(null), MediaType.none);
      expect(mediaTypeFromName('gif'), MediaType.none);
    });
  });

  group('notificationTypeFromName', () {
    test('maps every known type', () {
      expect(notificationTypeFromName('like'), NotificationType.like);
      expect(notificationTypeFromName('reply'), NotificationType.reply);
      expect(notificationTypeFromName('repost'), NotificationType.repost);
      expect(notificationTypeFromName('follow'), NotificationType.follow);
      expect(notificationTypeFromName('mention'), NotificationType.mention);
    });

    test('unknown/null fall back to like', () {
      expect(notificationTypeFromName(null), NotificationType.like);
      expect(notificationTypeFromName('sneeze'), NotificationType.like);
    });
  });

  group('profileFromRow', () {
    test('maps a full profile row', () {
      final profile = profileFromRow(<String, dynamic>{
        'id': 'u1',
        'username': 'ada',
        'display_name': 'Ada Lovelace',
        'bio': 'first programmer',
        'avatar_url': 'https://example.com/a.png',
        'banner_url': 'https://example.com/b.png',
        'verified': true,
        'verification_kind': 'creator',
        'followers': 1200,
        'following': 42,
      });
      expect(profile.id, 'u1');
      expect(profile.username, 'ada');
      expect(profile.displayName, 'Ada Lovelace');
      expect(profile.bio, 'first programmer');
      expect(profile.avatarUrl, 'https://example.com/a.png');
      expect(profile.bannerUrl, 'https://example.com/b.png');
      expect(profile.verified, isTrue);
      expect(profile.verificationKind, 'creator');
      expect(profile.followers, 1200);
      expect(profile.following, 42);
    });

    test('display_name falls back to username when absent', () {
      final profile = profileFromRow(<String, dynamic>{
        'id': 'u2',
        'username': 'grace',
      });
      expect(profile.displayName, 'grace');
      expect(profile.verified, isFalse);
      expect(profile.verificationKind, 'verified');
      expect(profile.followers, 0);
    });

    test('a non-map value yields the unknown-profile fallback', () {
      final profile = profileFromRow(null);
      expect(profile, same(kUnknownProfile));
      expect(profile.id, '');
      expect(profile.username, 'user');
      expect(profile.displayName, 'User');
    });
  });

  group('postFromRow', () {
    test('maps a joined posts row including the embedded author', () {
      final post = postFromRow(<String, dynamic>{
        'id': 'p1',
        'content': 'hello world',
        'media_url': 'https://example.com/m.jpg',
        'media_type': 'image',
        'created_at': '2024-06-15T12:00:00.000Z',
        'reply_count': 3,
        'repost_count': 4,
        'like_count': 5,
        'view_count': 6,
        'profiles': <String, dynamic>{
          'id': 'u1',
          'username': 'ada',
          'display_name': 'Ada',
        },
      });
      expect(post.id, 'p1');
      expect(post.content, 'hello world');
      expect(post.mediaUrl, 'https://example.com/m.jpg');
      expect(post.mediaType, MediaType.image);
      expect(post.hasMedia, isTrue);
      expect(post.createdAt, DateTime.utc(2024, 6, 15, 12, 0, 0));
      expect(post.replyCount, 3);
      expect(post.repostCount, 4);
      expect(post.likeCount, 5);
      expect(post.viewCount, 6);
      expect(post.author.id, 'u1');
      expect(post.author.username, 'ada');
      // Engagement flags are hydrated separately, never from the row.
      expect(post.liked, isFalse);
      expect(post.reposted, isFalse);
      expect(post.bookmarked, isFalse);
    });

    test('a missing profiles embed yields the unknown author', () {
      final post = postFromRow(<String, dynamic>{
        'id': 'p2',
        'content': 'no author embed',
      });
      expect(post.author.id, '');
      expect(post.author.username, 'user');
      expect(post.mediaType, MediaType.none);
      expect(post.hasMedia, isFalse);
    });
  });

  group('notificationFromRow', () {
    test('maps a joined notification row with actor and post id', () {
      final item = notificationFromRow(<String, dynamic>{
        'id': 'n1',
        'type': 'reply',
        'preview': 'nice post',
        'post_id': 'p9',
        'created_at': '2024-06-15T12:00:00.000Z',
        'read': true,
        'actor': <String, dynamic>{
          'id': 'u2',
          'username': 'grace',
          'display_name': 'Grace',
        },
      });
      expect(item.id, 'n1');
      expect(item.type, NotificationType.reply);
      expect(item.preview, 'nice post');
      expect(item.postId, 'p9');
      expect(item.read, isTrue);
      expect(item.actor.username, 'grace');
    });

    test('follow notifications have a null post id and default read=false', () {
      final item = notificationFromRow(<String, dynamic>{
        'id': 'n2',
        'type': 'follow',
        'actor': <String, dynamic>{'id': 'u3', 'username': 'linus'},
      });
      expect(item.type, NotificationType.follow);
      expect(item.postId, isNull);
      expect(item.read, isFalse);
    });
  });

  group('messageFromRow (fromMe derivation)', () {
    final row = <String, dynamic>{
      'id': 'm1',
      'sender': 'me-uid',
      'text': 'hi',
      'sent_at': '2024-06-15T12:00:00.000Z',
    };

    test('fromMe is true when sender matches the current uid', () {
      final message = messageFromRow(row, 'me-uid');
      expect(message.fromMe, isTrue);
      expect(message.id, 'm1');
      expect(message.text, 'hi');
      expect(message.sentAt, DateTime.utc(2024, 6, 15, 12, 0, 0));
    });

    test('fromMe is false when sender is someone else', () {
      expect(messageFromRow(row, 'other-uid').fromMe, isFalse);
    });

    test('fromMe is false when signed out (null uid)', () {
      expect(messageFromRow(row, null).fromMe, isFalse);
    });
  });
}
