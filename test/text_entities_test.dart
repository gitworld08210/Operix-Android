import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/utils/text_entities.dart';

void main() {
  group('extractHashtags', () {
    test('returns an empty set when there are no hashtags', () {
      expect(extractHashtags('just a plain caption'), isEmpty);
      expect(extractHashtags(''), isEmpty);
    });

    test('strips the # sigil and lower-cases', () {
      expect(extractHashtags('love this #Design'), <String>{'design'});
    });

    test('de-dupes case-insensitively', () {
      expect(
        extractHashtags('#Design and #design and #DESIGN'),
        <String>{'design'},
      );
    });

    test('extracts multiple distinct tags', () {
      expect(
        extractHashtags('#flutter #dart #open_source'),
        <String>{'flutter', 'dart', 'open_source'},
      );
    });

    test('matches the linkifier grammar: # body excludes dots', () {
      // r'#([A-Za-z0-9_]+)' stops at a dot, so '#hello.world' => 'hello'.
      expect(extractHashtags('#hello.world'), <String>{'hello'});
    });

    test('respects punctuation boundaries', () {
      expect(
        extractHashtags('done! #ship, and #win.'),
        <String>{'ship', 'win'},
      );
    });

    test('allows digits and underscores in the body', () {
      expect(extractHashtags('#web3 #build_2024'),
          <String>{'web3', 'build_2024'});
    });

    test('does not treat a bare # as a tag', () {
      expect(extractHashtags('a # b #real'), <String>{'real'});
    });
  });

  group('extractMentions', () {
    test('returns an empty set when there are no mentions', () {
      expect(extractMentions('nobody here'), isEmpty);
      expect(extractMentions(''), isEmpty);
    });

    test('strips the @ sigil and lower-cases', () {
      expect(extractMentions('cc @Nova_Labs'), <String>{'nova_labs'});
    });

    test('de-dupes case-insensitively', () {
      expect(
        extractMentions('@ada @Ada @ADA'),
        <String>{'ada'},
      );
    });

    test('matches the linkifier grammar: @ body allows dots', () {
      // r'@([A-Za-z0-9_\.]+)' includes dots, so '@first.last' is one mention.
      expect(extractMentions('ping @first.last'), <String>{'first.last'});
    });

    test('extracts multiple distinct mentions', () {
      expect(
        extractMentions('@ada, @nova and @grace'),
        <String>{'ada', 'nova', 'grace'},
      );
    });

    test('respects punctuation boundaries', () {
      expect(extractMentions('hey @ada! what?'), <String>{'ada'});
    });

    test('does not treat a bare @ as a mention', () {
      expect(extractMentions('email a @ b @real'), <String>{'real'});
    });
  });

  group('hashtags and mentions are independent', () {
    test('a mixed caption yields both sets separately', () {
      const caption = 'Shipping #Design with @Nova and #design polish @nova';
      expect(extractHashtags(caption), <String>{'design'});
      expect(extractMentions(caption), <String>{'nova'});
    });
  });

  group('shared linkify/extract grammar (FEAT-012)', () {
    // The PostCard linkifier and the extractors reference the SAME exported
    // patterns, so a highlighted span and its extracted/linked entity are
    // byte-identical. This proves they never disagree on the tricky
    // '#design.system @first.last' case: the hashtag body excludes dots (the
    // trailing '.' ends the tag => 'design'), while the mention body allows
    // dots (=> 'first.last').
    const caption = '#design.system @first.last';

    test('hashtagPattern highlights and extracts the same body', () {
      final match = hashtagPattern.firstMatch(caption)!;
      // The highlighted span is the full match; the extracted entity is the
      // captured body. Dot ends the hashtag.
      expect(match.group(0), '#design');
      expect(match.group(1), 'design');
      expect(extractHashtags(caption), <String>{'design'});
    });

    test('mentionPattern highlights and extracts the same body', () {
      final match = mentionPattern.firstMatch(caption)!;
      // Dot is allowed in a mention body.
      expect(match.group(0), '@first.last');
      expect(match.group(1), 'first.last');
      expect(extractMentions(caption), <String>{'first.last'});
    });

    test('combined linkify alternation colors both kinds byte-identically', () {
      // Mirrors post_card.dart _linkify: hashtag OR mention alternation over
      // the shared pattern sources.
      final combined = RegExp(
        '(?:${hashtagPattern.pattern})|(?:${mentionPattern.pattern})',
      );
      final highlighted =
          combined.allMatches(caption).map((m) => m.group(0)).toList();
      expect(highlighted, <String>['#design', '@first.last']);
    });
  });
}
