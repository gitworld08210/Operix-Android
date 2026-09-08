/// An immutable social profile.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    this.bio = '',
    this.avatarUrl,
    this.bannerUrl,
    this.verified = false,
    this.verificationKind = 'verified',
    this.followers = 0,
    this.following = 0,
    this.isPrivate = false,
  });

  /// Stable unique id.
  final String id;

  /// Handle without the leading '@'.
  final String username;

  /// Display name shown in bold.
  final String displayName;

  /// Short bio.
  final String bio;

  /// Optional avatar image URL.
  final String? avatarUrl;

  /// Optional banner image URL.
  final String? bannerUrl;

  /// Whether the account carries a verification badge.
  final bool verified;

  /// Kind of verification: verified, creator, gov, brand, founder, media.
  final String verificationKind;

  /// Follower count.
  final int followers;

  /// Following count.
  final int following;

  /// Whether the account is private (maps to `profiles.is_private`, added in
  /// migration 0002). A private account gates follow requests and content
  /// visibility server-side; the client mirrors the flag for the settings UI.
  final bool isPrivate;

  /// Convenience: '@username'.
  String get handle => '@$username';

  UserProfile copyWith({
    String? id,
    String? username,
    String? displayName,
    String? bio,
    String? avatarUrl,
    String? bannerUrl,
    bool? verified,
    String? verificationKind,
    int? followers,
    int? following,
    bool? isPrivate,
  }) {
    return UserProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      verified: verified ?? this.verified,
      verificationKind: verificationKind ?? this.verificationKind,
      followers: followers ?? this.followers,
      following: following ?? this.following,
      isPrivate: isPrivate ?? this.isPrivate,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is UserProfile && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
