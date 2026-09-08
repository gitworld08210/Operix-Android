/// Pure, Supabase-free validation for first-class TEXT-ONLY tweets.
///
/// This library centralizes the canonical character limit and the postable
/// rule for text posts so the composer, any live counter, and unit tests all
/// read ONE source of truth instead of duplicating the ad-hoc length math.
///
/// CHAR LIMIT DECISION: the canonical text-post limit is 280 characters. 280
/// is the widely-recognized X/Twitter standard, it matches the limit the
/// composer already enforced (`compose_screen.dart _maxChars = 280`), and it
/// keeps text posts terse and scannable in an infinity feed. This is a
/// deliberate product decision; a more generous limit later would be a
/// deliberate product change, not a silent tweak.
library;

// Imports flutter/widgets for the `immutable` annotation AND the String
// `.characters` grapheme-cluster extension (re-exported from the `characters`
// package), matching how the composer counts characters.
import 'package:flutter/widgets.dart';

/// The canonical maximum length (in Unicode grapheme clusters) of a text post.
///
/// See the library doc comment for why 280 was chosen. The composer, the
/// character counter, and [validateTextPost] all read this single constant.
const int kMaxTextPostChars = 280;

/// The immutable result of validating a text post's content.
///
/// A text post is POSTABLE when the trimmed content is non-empty AND within the
/// character limit, i.e. [isValid] == (`!isEmpty && !isOverLimit`).
@immutable
class TextPostValidation {
  const TextPostValidation({
    required this.length,
    required this.remaining,
    required this.isEmpty,
    required this.isOverLimit,
  });

  /// The content length measured in Unicode grapheme clusters (matching the
  /// composer's `.characters.length` counting so emoji / combining marks count
  /// as the user sees them, not as UTF-16 code units).
  final int length;

  /// Characters remaining before the limit (`maxChars - length`). Negative when
  /// [isOverLimit] is true.
  final int remaining;

  /// True when the TRIMMED content is empty (no postable text).
  final bool isEmpty;

  /// True when [length] exceeds the limit.
  final bool isOverLimit;

  /// True when the content is postable: non-empty and within the limit.
  bool get isValid => !isEmpty && !isOverLimit;

  @override
  bool operator ==(Object other) =>
      other is TextPostValidation &&
      other.length == length &&
      other.remaining == remaining &&
      other.isEmpty == isEmpty &&
      other.isOverLimit == isOverLimit;

  @override
  int get hashCode => Object.hash(length, remaining, isEmpty, isOverLimit);

  @override
  String toString() =>
      'TextPostValidation(length: $length, remaining: $remaining, '
      'isEmpty: $isEmpty, isOverLimit: $isOverLimit, isValid: $isValid)';
}

/// Validates [content] as a text post against [maxChars] (default
/// [kMaxTextPostChars]).
///
/// [length] is the grapheme-cluster count of the RAW content (via
/// `content.characters.length`), matching what the composer counter shows.
/// [isEmpty] reflects the TRIMMED content so whitespace-only input is not
/// postable. [isOverLimit] is `length > maxChars`. The result is postable when
/// `!isEmpty && !isOverLimit`.
TextPostValidation validateTextPost(
  String content, {
  int maxChars = kMaxTextPostChars,
}) {
  final length = content.characters.length;
  return TextPostValidation(
    length: length,
    remaining: maxChars - length,
    isEmpty: content.trim().isEmpty,
    isOverLimit: length > maxChars,
  );
}
