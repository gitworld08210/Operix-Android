import 'user_profile.dart';

/// The kind of activity a [NotificationItem] represents.
///
/// Mirrors the `type` check constraint on the Supabase `notifications` table
/// (migration `0002_authz_and_core_tables.sql`), which allows
/// `('like','reply','repost','follow','mention','follow_request','system')`.
enum NotificationType { like, reply, repost, follow, mention, followRequest, system }

/// An immutable notification/activity entry.
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.actor,
    this.preview,
    required this.createdAt,
    this.read = false,
  });

  final String id;
  final NotificationType type;
  final UserProfile actor;

  /// Optional preview text (e.g. the post that was liked/replied to).
  final String? preview;

  final DateTime createdAt;
  final bool read;

  NotificationItem copyWith({
    String? id,
    NotificationType? type,
    UserProfile? actor,
    String? preview,
    DateTime? createdAt,
    bool? read,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      type: type ?? this.type,
      actor: actor ?? this.actor,
      preview: preview ?? this.preview,
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
