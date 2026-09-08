import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/data/mock_data.dart';
import 'package:oneleven/models/comment.dart';
import 'package:oneleven/models/user_profile.dart';
import 'package:oneleven/utils/comment_tree.dart';

/// Builds a bare comment for tree tests. [minutesAgo] controls ordering
/// (larger = older) so newest-first assertions are deterministic.
Comment _c(
  String id, {
  String postId = 'p1',
  String? parentId,
  required int minutesAgo,
}) {
  return Comment(
    id: id,
    postId: postId,
    author: const UserProfile(id: 'u', username: 'u', displayName: 'U'),
    parentId: parentId,
    content: 'c-$id',
    createdAt: DateTime(2024, 1, 1, 12).subtract(Duration(minutes: minutesAgo)),
  );
}

void main() {
  group('buildThread', () {
    test('nests cm2 under cm1 and keeps cm3 top-level (mock seed)', () {
      final flat =
          MockData.comments().where((c) => c.postId == 'p1').toList();
      final tree = buildThread(flat);

      // Top-level: cm1 and cm3 (cm2 is a reply to cm1).
      final topIds = tree.map((n) => n.comment.id).toList();
      expect(topIds, containsAll(<String>['cm1', 'cm3']));
      expect(topIds, isNot(contains('cm2')));

      final cm1 = tree.firstWhere((n) => n.comment.id == 'cm1');
      expect(cm1.replies.map((n) => n.comment.id), <String>['cm2']);
      expect(cm1.replies.single.depth, 1);
      expect(cm1.depth, 0);

      final cm3 = tree.firstWhere((n) => n.comment.id == 'cm3');
      expect(cm3.replies, isEmpty);
    });

    test('orders top-level comments newest-first', () {
      final flat = <Comment>[
        _c('a', minutesAgo: 30),
        _c('b', minutesAgo: 10),
        _c('c', minutesAgo: 20),
      ];
      final tree = buildThread(flat);
      expect(tree.map((n) => n.comment.id), <String>['b', 'c', 'a']);
    });

    test('orders replies newest-first under their parent', () {
      final flat = <Comment>[
        _c('root', minutesAgo: 100),
        _c('r1', parentId: 'root', minutesAgo: 30),
        _c('r2', parentId: 'root', minutesAgo: 10),
      ];
      final tree = buildThread(flat);
      final root = tree.single;
      expect(root.replies.map((n) => n.comment.id), <String>['r2', 'r1']);
    });

    test('surfaces an orphan reply (missing parent) as top-level, dropping nothing',
        () {
      final flat = <Comment>[
        _c('top', minutesAgo: 20),
        _c('orphan', parentId: 'ghost', minutesAgo: 10),
      ];
      final tree = buildThread(flat);
      final ids = tree.map((n) => n.comment.id).toSet();
      // Both survive; nothing is dropped even though 'ghost' is absent.
      expect(ids, <String>{'top', 'orphan'});
      final orphan = tree.firstWhere((n) => n.comment.id == 'orphan');
      expect(orphan.depth, 0);
    });

    test('preserves deep nesting data but clamps visual depth at maxThreadDepth',
        () {
      // Build a chain deeper than the cap: a > b > c > d.
      final flat = <Comment>[
        _c('a', minutesAgo: 40),
        _c('b', parentId: 'a', minutesAgo: 30),
        _c('c', parentId: 'b', minutesAgo: 20),
        _c('d', parentId: 'c', minutesAgo: 10),
      ];
      final tree = buildThread(flat);
      final nodes = flattenThread(tree);
      final depths = <String, int>{
        for (final n in nodes) n.comment.id: n.depth,
      };
      // Data nesting preserved: all four present.
      expect(depths.keys, containsAll(<String>['a', 'b', 'c', 'd']));
      expect(depths['a'], 0);
      expect(depths['b'], 1);
      // Visual depth clamps at the cap.
      expect(depths['c'], maxThreadDepth);
      expect(depths['d'], maxThreadDepth);
      // The 'd' node is still nested under 'c' (data preserved).
      final aNode = tree.single;
      final bNode = aNode.replies.single;
      final cNode = bNode.replies.single;
      expect(cNode.replies.single.comment.id, 'd');
    });

    test('flattenThread emits parent immediately before its reply subtree', () {
      final flat = <Comment>[
        _c('root', minutesAgo: 100),
        _c('r1', parentId: 'root', minutesAgo: 10),
        _c('other', minutesAgo: 5),
      ];
      final order = flattenThread(buildThread(flat))
          .map((n) => n.comment.id)
          .toList();
      // newest-first top level => other, root; root's reply r1 follows root.
      expect(order, <String>['other', 'root', 'r1']);
    });

    test('returns an empty list for no comments', () {
      expect(buildThread(const <Comment>[]), isEmpty);
    });
  });
}
