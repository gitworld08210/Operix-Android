import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/data/safety_repository.dart';
import 'package:oneleven/models/post.dart';
import 'package:oneleven/models/user_profile.dart';

UserProfile _author(String id) =>
    UserProfile(id: id, username: id, displayName: id);

Post _post(String id, String content) => Post(
      id: id,
      author: _author('a'),
      content: content,
      createdAt: DateTime(2024, 1, 1),
    );

void main() {
  group('contentMatchesMuteWords (pure)', () {
    test('empty word set matches nothing', () {
      expect(contentMatchesMuteWords('anything at all', <String>{}), isFalse);
    });

    test('is case-insensitive', () {
      expect(contentMatchesMuteWords('The ART show', <String>{'art'}), isTrue);
      expect(contentMatchesMuteWords('the art show', <String>{'ART'}), isTrue);
    });

    test('respects word boundaries (matches whole word only)', () {
      expect(contentMatchesMuteWords('the art show', <String>{'art'}), isTrue);
      expect(contentMatchesMuteWords('a startup story', <String>{'art'}), isFalse);
    });

    test('matches a word at the start/end of the string', () {
      expect(contentMatchesMuteWords('art is great', <String>{'art'}), isTrue);
      expect(contentMatchesMuteWords('i love art', <String>{'art'}), isTrue);
    });

    test('matches when any of several words is present', () {
      final words = <String>{'crypto', 'spoiler'}; // multiword set
      expect(
        contentMatchesMuteWords('major spoiler ahead', words),
        isTrue,
      );
      expect(
        contentMatchesMuteWords('a calm day', words),
        isFalse,
      );
    });

    test('empty content never matches', () {
      expect(contentMatchesMuteWords('', <String>{'art'}), isFalse);
    });
  });

  group('SafetyRepository mute words', () {
    late SafetyRepository repo;

    setUp(() {
      repo = SafetyRepository();
    });

    test('defaults to empty so the feed is unchanged', () {
      expect(repo.muteWords, isEmpty);
      expect(repo.muteWordSet, isEmpty);
    });

    test('exposes an unmodifiable, sorted view', () {
      repo.addMuteWord('zebra');
      repo.addMuteWord('apple');
      expect(repo.muteWords, <String>['apple', 'zebra']);
      expect(() => repo.muteWords.add('x'), throwsUnsupportedError);
    });

    test('addMuteWord normalizes (trim + lower-case) and notifies once', () {
      var notified = 0;
      repo.addListener(() => notified++);
      repo.addMuteWord('  Spoilers  ');
      expect(repo.muteWords, <String>['spoilers']);
      expect(notified, 1);
    });

    test('addMuteWord is idempotent (de-duped, no second notify)', () {
      repo.addMuteWord('spoilers');
      var notified = 0;
      repo.addListener(() => notified++);
      repo.addMuteWord('SPOILERS'); // same after normalization
      expect(notified, 0);
      expect(repo.muteWords, <String>['spoilers']);
    });

    test('addMuteWord ignores empty/whitespace input', () {
      var notified = 0;
      repo.addListener(() => notified++);
      repo.addMuteWord('   ');
      expect(notified, 0);
      expect(repo.muteWords, isEmpty);
    });

    test('removeMuteWord removes (normalized) and notifies once, idempotent',
        () {
      repo.addMuteWord('spoilers');
      var notified = 0;
      repo.addListener(() => notified++);
      repo.removeMuteWord('  SPOILERS ');
      expect(repo.muteWords, isEmpty);
      expect(notified, 1);
      repo.removeMuteWord('spoilers'); // nothing to remove
      expect(notified, 1);
    });
  });

  group('filterHidden with mute words (pure)', () {
    final posts = <Post>[
      _post('p1', 'the art show was lovely'),
      _post('p2', 'a startup story'),
      _post('p3', 'nothing to see here'),
    ];

    test('is identity when all sets are empty', () {
      final result = filterHidden(
        posts,
        blocked: const <String>{},
        muted: const <String>{},
      );
      expect(identical(result, posts), isTrue);
    });

    test('hides posts matching a mute word on a word boundary', () {
      final result = filterHidden(
        posts,
        blocked: const <String>{},
        muted: const <String>{},
        muteWords: <String>{'art'},
      );
      // p1 hidden ('art'), p2 kept ('startup' is not 'art'), p3 kept.
      expect(result.map((p) => p.id), <String>['p2', 'p3']);
    });

    test('composes with blocked/muted author filtering', () {
      final result = filterHidden(
        posts,
        blocked: const <String>{},
        muted: const <String>{},
        muteWords: <String>{'here'},
      );
      expect(result.map((p) => p.id), <String>['p1', 'p2']);
    });

    test('does not hide the viewer\'s own post matching a muted word', () {
      // All posts here are authored by 'a'; a self-authored post that matches
      // a muted word must remain visible to its author (review issues 1 & 4).
      final result = filterHidden(
        posts,
        blocked: const <String>{},
        muted: const <String>{},
        muteWords: <String>{'art'},
        viewerId: 'a',
      );
      expect(result.map((p) => p.id), <String>['p1', 'p2', 'p3']);
    });
  });
}
