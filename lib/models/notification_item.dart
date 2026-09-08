import 'user_profile.dart';

/// The kind of activity a [NotificationItem] represents.
enum NotificationType { like, reply, repost, follow, mention }

/// An immutable notification/activity entry.
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.actor,
    this.preview,
    this.postId,
    required this.createdAt,
    this.read = false,
  });

  final String id;
  final NotificationType type;
  final UserProfile actor;

  /// Optional preview text (e.g. the post that was liked/replied to).
  final String? preview;

  /// The id of the post this notification refers to, when applicable
  /// (like/reply/repost/mention). Null for follow notifications. Used to
  /// navigate to the relevant post detail on tap.
  final String? postId;

  final DateTime createdAt;
  final bool read;

  NotificationItem copyWith({
    String? id,
    NotificationType? type,
    UserProfile? actor,
    String? preview,
    String? postId,
    DateTime? createdAt,
    bool? read,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      type: type ?? this.type,
      actor: actor ?? this.actor,
      preview: preview ?? this.preview,
      postId: postId ?? this.postId,
      createdAt: createdAt ?? this.createdAt,
      read: read ?? this.read,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is NotificationItem && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
