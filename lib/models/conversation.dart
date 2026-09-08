import 'user_profile.dart';

/// A single direct message within a [Conversation].
class Message {
  const Message({
    required this.id,
    required this.fromMe,
    required this.text,
    required this.sentAt,
  });

  final String id;

  /// Whether the current user sent this message.
  final bool fromMe;

  final String text;
  final DateTime sentAt;
}

/// A direct-message thread with a single participant.
class Conversation {
  const Conversation({
    required this.id,
    required this.participant,
    required this.messages,
    required this.lastPreview,
    required this.updatedAt,
    this.unread = 0,
  });

  final String id;
  final UserProfile participant;
  final List<Message> messages;
  final String lastPreview;
  final DateTime updatedAt;
  final int unread;

  Conversation copyWith({
    String? id,
    UserProfile? participant,
    List<Message>? messages,
    String? lastPreview,
    DateTime? updatedAt,
    int? unread,
  }) {
    return Conversation(
      id: id ?? this.id,
      participant: participant ?? this.participant,
      messages: messages ?? this.messages,
      lastPreview: lastPreview ?? this.lastPreview,
      updatedAt: updatedAt ?? this.updatedAt,
      unread: unread ?? this.unread,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Conversation && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
