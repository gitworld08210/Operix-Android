import '../models/post.dart';
import '../models/user_profile.dart';

/// Modular feed ranking + keyset pagination primitives.
///
/// ## Current approach
/// The feed today is purely chronological (newest-first). That single sort
/// rule used to live inline inside [PostRepository]. Baking ranking into the
/// repository made it impossible to evolve the ordering (personalized,
/// engagement-weighted, "recommended") without rewriting the repository and its
/// tests.
///
/// ## Why modular
/// [FeedRankingStrategy] pulls the ordering decision out into a small, pure,
/// synchronous, dependency-free interface. The repository asks a strategy to
/// [FeedRankingStrategy.rank] a list of posts; it no longer knows *how* posts
/// are ordered. This keeps ranking:
///
///  * testable in isolation (no Supabase, no ChangeNotifier), and
///  * swappable at runtime (A/B a new strategy by handing the repository a
///    different instance).
///
/// ## How to extend
/// Add a new class implementing [FeedRankingStrategy]. A scored strategy should
/// compute a score per post from signals available on the [Post]/[UserProfile]
/// (engagement such as likes/reposts/replies, freshness from [Post.createdAt],
/// author affinity for the [viewer]) and sort descending by that score. See
/// [EngagementRanking] for a documented placeholder that shows exactly where
/// those signals plug in. The interface intentionally stays free of async and
/// of data-layer types so ranking never reaches back into the network.
abstract class FeedRankingStrategy {
  const FeedRankingStrategy();

  /// Returns a NEW list of [posts] in ranked order. Must be pure: it never
  /// mutates the input list and never performs I/O. [viewer] is the optional
  /// current user, available to personalized strategies.
  List<Post> rank(List<Post> posts, {UserProfile? viewer});
}

/// Newest-first ordering. This is the app's current, default behavior and the
/// contract the existing repository tests assert.
class ChronologicalRanking extends FeedRankingStrategy {
  const ChronologicalRanking();

  @override
  List<Post> rank(List<Post> posts, {UserProfile? viewer}) {
    final list = List<Post>.of(posts);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }
}

/// A placeholder scored strategy that blends engagement with freshness.
///
/// This is intentionally simple and deterministic so it can be unit-tested, but
/// it demonstrates the extension point for a real recommendation model: each
/// post gets a [_score] built from engagement counters and a recency term, and
/// the feed is sorted by that score descending (ties broken newest-first for
/// stability). Swap [_score] for a learned model, add author-affinity for the
/// [viewer], or weight the signals differently without touching the repository.
class EngagementRanking extends FeedRankingStrategy {
  const EngagementRanking();

  @override
  List<Post> rank(List<Post> posts, {UserProfile? viewer}) {
    final list = List<Post>.of(posts);
    list.sort((a, b) {
      final byScore = _score(b).compareTo(_score(a));
      if (byScore != 0) return byScore;
      // Stable tie-break: newest-first, matching the chronological baseline.
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  /// Engagement signal for a single post. A production model would replace this
  /// with a learned function over the same (and richer) signals; freshness,
  /// author affinity for a [viewer], dwell time, etc. would plug in here.
  double _score(Post post) {
    // Likes are the strongest positive signal, reposts amplify reach, replies
    // indicate conversation. Views are a weak baseline.
    return post.likeCount * 3.0 +
        post.repostCount * 2.0 +
        post.replyCount * 1.5 +
        post.viewCount * 0.01;
  }
}
