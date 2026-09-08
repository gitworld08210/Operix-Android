import '../models/comment.dart';

/// A node in the assembled comment thread: a [comment] together with its
/// direct [replies] (each itself a [CommentNode]) and the visual [depth] at
/// which the UI should indent it.
///
/// This is a PURE view-model produced by [buildThread]; it holds no Supabase
/// state and is trivially unit-testable. Equality is intentionally NOT
/// overridden (nodes are transient render inputs, not cached domain objects).
class CommentNode {
  CommentNode({
    required this.comment,
    required this.depth,
    List<CommentNode>? replies,
  }) : replies = replies ?? <CommentNode>[];

  /// The comment this node represents.
  final Comment comment;

  /// The direct replies to [comment], ordered newest-first (see [buildThread]).
  final List<CommentNode> replies;

  /// The visual indentation depth, clamped to [maxThreadDepth]. Top-level
  /// comments are depth 0. The DATA nesting is preserved regardless of the
  /// clamp; only the rendered indent stops growing past the cap.
  final int depth;
}

/// The maximum VISUAL nesting depth for indentation. Data nesting is never
/// dropped — a reply-to-a-reply-to-a-reply is still nested in the tree — but
/// its [CommentNode.depth] is clamped here so deep chains do not indent off the
/// screen. Kept small (2) to match the compact reply UI.
const int maxThreadDepth = 2;

/// Assembles a FLAT list of [Comment]s into a nested [CommentNode] tree.
///
/// Rules (documented so the UI and tests agree on the shape):
///
///  * Top-level comments (those whose [Comment.parentId] is null) are returned
///    NEWEST-FIRST, matching the flat comments view.
///  * A comment's direct replies are nested under it, also NEWEST-FIRST, so a
///    reply thread reads in the same order as the top-level list.
///  * ORPHAN replies — a reply whose [Comment.parentId] points at a comment
///    that is absent from [flat] (e.g. filtered out by RLS, deleted, or simply
///    not loaded) — are SURFACED AS TOP-LEVEL rather than dropped, so nothing a
///    viewer is allowed to see silently disappears. They are ordered by
///    createdAt alongside the genuine top-level comments.
///  * Visual [CommentNode.depth] is clamped to [maxThreadDepth]; the underlying
///    nesting is preserved (a grandchild is still a child of its parent node),
///    only the reported indent level stops increasing.
///
/// The function is pure: it does not mutate [flat] and does no I/O. A cycle in
/// the parent pointers (which the DB schema's FK + app flow do not produce) is
/// tolerated — a comment is only ever attached to one parent, and the visited
/// set prevents infinite recursion.
List<CommentNode> buildThread(List<Comment> flat) {
  // Index every comment by id so parent lookups are O(1) and orphan detection
  // is a simple membership test.
  final byId = <String, Comment>{for (final c in flat) c.id: c};

  // Group direct children by their parent id.
  final childrenOf = <String, List<Comment>>{};
  final roots = <Comment>[];
  for (final c in flat) {
    final parentId = c.parentId;
    final isOrphan = parentId != null && !byId.containsKey(parentId);
    if (parentId == null || isOrphan) {
      // Genuine top-level comment, OR a reply whose parent is missing: surface
      // it at the top level so it is never dropped.
      roots.add(c);
    } else {
      (childrenOf[parentId] ??= <Comment>[]).add(c);
    }
  }

  int newestFirst(Comment a, Comment b) => b.createdAt.compareTo(a.createdAt);
  roots.sort(newestFirst);

  final visited = <String>{};

  List<CommentNode> nodesFor(List<Comment> comments, int depth) {
    final clampedDepth = depth > maxThreadDepth ? maxThreadDepth : depth;
    final out = <CommentNode>[];
    for (final c in comments) {
      if (!visited.add(c.id)) continue; // guard against pathological cycles
      final kids = (childrenOf[c.id] ?? <Comment>[])..sort(newestFirst);
      out.add(
        CommentNode(
          comment: c,
          depth: clampedDepth,
          replies: nodesFor(kids, depth + 1),
        ),
      );
    }
    return out;
  }

  return nodesFor(roots, 0);
}

/// Flattens a [CommentNode] tree into a depth-annotated linear list in
/// render order (parent immediately followed by its reply subtree). This is
/// what the comments screen iterates to emit one tile per node while still
/// indenting by [CommentNode.depth].
List<CommentNode> flattenThread(List<CommentNode> nodes) {
  final out = <CommentNode>[];
  void walk(List<CommentNode> ns) {
    for (final n in ns) {
      out.add(n);
      walk(n.replies);
    }
  }

  walk(nodes);
  return out;
}
