import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/utils/text_post.dart';

void main() {
  group('kMaxTextPostChars', () {
    test('is the X-standard 280', () {
      expect(kMaxTextPostChars, 280);
    });
  });

  group('validateTextPost', () {
    test('empty string is empty and not valid', () {
      final v = validateTextPost('');
      expect(v.isEmpty, isTrue);
      expect(v.length, 0);
      expect(v.remaining, kMaxTextPostChars);
      expect(v.isOverLimit, isFalse);
      expect(v.isValid, isFalse);
    });

    test('whitespace-only string is empty and not valid', () {
      final v = validateTextPost('   \n\t  ');
      expect(v.isEmpty, isTrue);
      expect(v.isValid, isFalse);
      // length still counts the raw (untrimmed) characters, matching the
      // composer counter which counts what is typed.
      expect(v.length, '   \n\t  '.characters.length);
    });

    test('a normal short tweet is valid with correct remaining', () {
      const content = 'hello world';
      final v = validateTextPost(content);
      expect(v.isEmpty, isFalse);
      expect(v.length, content.characters.length);
      expect(v.remaining, kMaxTextPostChars - content.characters.length);
      expect(v.isOverLimit, isFalse);
      expect(v.isValid, isTrue);
    });

    test('exactly at the limit (280) is valid with 0 remaining', () {
      final content = 'a' * kMaxTextPostChars;
      final v = validateTextPost(content);
      expect(v.length, kMaxTextPostChars);
      expect(v.remaining, 0);
      expect(v.isOverLimit, isFalse);
      expect(v.isValid, isTrue);
    });

    test('one over the limit (281) is over-limit and not valid', () {
      final content = 'a' * (kMaxTextPostChars + 1);
      final v = validateTextPost(content);
      expect(v.length, kMaxTextPostChars + 1);
      expect(v.remaining, -1);
      expect(v.isOverLimit, isTrue);
      expect(v.isValid, isFalse);
    });

    test('counts by grapheme clusters, not UTF-16 code units', () {
      // A family emoji is a single grapheme cluster built from multiple code
      // points joined with ZWJ; a flag is a pair of regional-indicator code
      // points; 'é' as base + combining accent is one grapheme cluster.
      const content = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u{1F1FA}\u{1F1F8}e\u0301';
      final v = validateTextPost(content);
      // 3 grapheme clusters: family, flag, accented e.
      expect(v.length, 3);
      expect(v.length, content.characters.length);
      expect(v.length, lessThan(content.length));
      expect(v.isValid, isTrue);
    });

    test('respects a custom maxChars', () {
      final v = validateTextPost('abcdef', maxChars: 5);
      expect(v.length, 6);
      expect(v.remaining, -1);
      expect(v.isOverLimit, isTrue);
      expect(v.isValid, isFalse);
    });

    test('value equality on TextPostValidation', () {
      expect(validateTextPost('hello'), validateTextPost('hello'));
    });
  });
}
