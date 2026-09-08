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
}
