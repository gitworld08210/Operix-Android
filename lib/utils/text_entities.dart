/// Pure hashtag/mention extraction from post content.
///
/// These functions parse a post's caption for `#hashtags` and `@mentions`
/// using the SAME token grammar the PostCard linkifier uses (see
/// `lib/widgets/post_card.dart` `_linkify`, `RegExp r'([#@][A-Za-z0-9_\.]+)'`)
/// so the highlighted entities and the extracted relations never disagree:
///
///   * a hashtag body is `[A-Za-z0-9_]+` (letters/digits/underscore, no dot —
///     a trailing `.` therefore ends the tag), and
///   * a mention body is `[A-Za-z0-9_\.]+` (a username may contain dots).
///
/// Both return NORMALIZED, de-duped tokens: lower-cased and stripped of the
/// leading sigil (`#`/`@`). These sets feed the `post_hashtags` /
/// `post_mentions` relations (see migration `0007_relations.sql`) that a later
/// search/discovery phase indexes, and they are intentionally Supabase-free so
/// they are fully unit-testable.
library;

/// Matches a `#hashtag` and captures its body (`[A-Za-z0-9_]+`, no dot).
final RegExp _hashtagPattern = RegExp(r'#([A-Za-z0-9_]+)');

/// Matches an `@mention` and captures its body (`[A-Za-z0-9_\.]+`, dots ok).
final RegExp _mentionPattern = RegExp(r'@([A-Za-z0-9_\.]+)');

/// Extracts the set of NORMALIZED hashtags from [content].
///
/// Tokens are lower-cased and returned WITHOUT the leading `#`, de-duped so
/// `#Design and #design` yields a single `design`. Returns an empty set when
/// there are no hashtags. Feeds the `post_hashtags` relation.
Set<String> extractHashtags(String content) {
  final result = <String>{};
  for (final match in _hashtagPattern.allMatches(content)) {
    final body = match.group(1);
    if (body != null && body.isNotEmpty) {
      result.add(body.toLowerCase());
    }
  }
  return result;
}

/// Extracts the set of NORMALIZED mentions from [content].
///
/// Tokens are lower-cased and returned WITHOUT the leading `@`, de-duped.
/// Returns an empty set when there are no mentions. Feeds the `post_mentions`
/// relation (resolved from username to user id server-side / on persist).
Set<String> extractMentions(String content) {
  final result = <String>{};
  for (final match in _mentionPattern.allMatches(content)) {
    final body = match.group(1);
    if (body != null && body.isNotEmpty) {
      result.add(body.toLowerCase());
    }
  }
  return result;
}
