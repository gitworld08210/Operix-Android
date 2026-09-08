/// Pure, network-independent mapping helpers that translate raw Supabase row
/// maps into the app's immutable models.
///
/// These live as top-level functions (rather than private repository methods)
/// so the parsing/derivation logic can be unit tested without booting a
/// Supabase client. The repositories delegate to them, so the app behavior is
/// identical; there is no fabricated data here, only structural mapping.
library;

import '../models/conversation.dart';
import '../models/notification_item.dart';
import '../models/post.dart';
import '../models/user_profile.dart';

/// A fallback profile used when a row has no embedded/joined profile.
const UserProfile kUnknownProfile =
    UserProfile(id: '', username: 'user', displayName: 'User');

/// Coerces a dynamic JSON value into an int, tolerating ints, other numbers,
/// numeric strings, and null (which maps to 0).
int asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

/// Parses a timestamp value (a [DateTime], an ISO-8601 string, or null) into a
/// [DateTime], falling back to [fallback] (or "now") when unparseable.
DateTime parseDate(Object? value, {DateTime? fallback}) {
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '') ??
      (fallback ?? DateTime.now());
}

/// Maps a `posts.media_type` string to a [MediaType]; unknown/absent -> none.
MediaType mediaTypeFromName(String? name) {
  switch (name) {
    case 'image':
      return MediaType.image;
    case 'video':
      return MediaType.video;
    default:
      return MediaType.none;
  }
}

/// Maps a `notifications.type` string to a [NotificationType]; unknown/absent
/// falls back to [NotificationType.like].
NotificationType notificationTypeFromName(String? name) {
  switch (name) {
    case 'like':
      return NotificationType.like;
    case 'reply':
      return NotificationType.reply;
    case 'repost':
      return NotificationType.repost;
    case 'follow':
      return NotificationType.follow;
    case 'mention':
      return NotificationType.mention;
    default:
      return NotificationType.like;
  }
}

/// Maps a `profiles` row map to a [UserProfile]. A null / non-map value yields
/// [kUnknownProfile] so an absent embed never crashes the UI.
UserProfile profileFromRow(Object? profile) {
  if (profile is Map) {
    final p = profile.cast<String, dynamic>();
    final username = (p['username'] as String?) ?? 'user';
    return UserProfile(
      id: p['id']?.toString() ?? '',
      username: username,
      displayName: (p['display_name'] as String?) ?? username,
      bio: (p['bio'] as String?) ?? '',
      avatarUrl: p['avatar_url'] as String?,
      bannerUrl: p['banner_url'] as String?,
      verified: (p['verified'] as bool?) ?? false,
      verificationKind: (p['verification_kind'] as String?) ?? 'verified',
      followers: asInt(p['followers']),
      following: asInt(p['following']),
    );
  }
  return kUnknownProfile;
}

/// Maps a `posts` row to a [Post] using the given already-mapped [author].
/// DB-owned counters (reply/repost/like/view) are read, never derived.
Post postFromRowWithAuthor(Map<String, dynamic> row, UserProfile author) {
  return Post(
    id: row['id']?.toString() ?? '',
    author: author,
    content: (row['content'] as String?) ?? '',
    mediaUrl: row['media_url'] as String?,
    mediaType: mediaTypeFromName(row['media_type'] as String?),
    createdAt: parseDate(row['created_at']),
    replyCount: asInt(row['reply_count']),
    repostCount: asInt(row['repost_count']),
    likeCount: asInt(row['like_count']),
    viewCount: asInt(row['view_count']),
  );
}

/// Maps a `posts` row joined to `profiles(*)` to a [Post], resolving the
/// embedded author profile.
Post postFromRow(Map<String, dynamic> row) =>
    postFromRowWithAuthor(row, profileFromRow(row['profiles']));

/// Maps a `notifications` row joined to the actor `profiles(*)` to a
/// [NotificationItem].
NotificationItem notificationFromRow(Map<String, dynamic> row) {
  return NotificationItem(
    id: row['id']?.toString() ?? '',
    type: notificationTypeFromName(row['type'] as String?),
    actor: profileFromRow(row['actor']),
    preview: row['preview'] as String?,
    postId: row['post_id']?.toString(),
    createdAt: parseDate(row['created_at']),
    read: (row['read'] as bool?) ?? false,
  );
}

/// Maps a `messages` row to a [Message], deriving [Message.fromMe] by comparing
/// the row's `sender` to the current auth uid ([myId]). A null [myId]
/// (signed out) always yields `fromMe == false`.
Message messageFromRow(Map<String, dynamic> row, String? myId) {
  return Message(
    id: row['id']?.toString() ?? '',
    fromMe: myId != null && row['sender']?.toString() == myId,
    text: (row['text'] as String?) ?? '',
    sentAt: parseDate(row['sent_at']),
  );
}
