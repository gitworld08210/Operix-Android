import '../models/comment.dart';
import '../models/conversation.dart';
import '../models/notification_item.dart';
import '../models/post.dart';
import '../models/post_attachment.dart';
import '../models/story.dart';
import '../models/user_profile.dart';

/// Static seed data used by the in-memory repositories. All image URLs point at
/// picsum.photos placeholders so nothing binary needs to be bundled.
abstract final class MockData {
  const MockData._();

  // -- Profiles ------------------------------------------------------------

  static const UserProfile currentUser = UserProfile(
    id: 'u_me',
    username: 'you',
    displayName: 'You',
    bio: 'Building things on Oneleven. Coffee, code, and shipping. ',
    avatarUrl: 'https://picsum.photos/seed/you/200/200',
    bannerUrl: 'https://picsum.photos/seed/youbanner/900/300',
    verified: true,
    verificationKind: 'verified',
    followers: 1287,
    following: 342,
  );

  static const UserProfile aria = UserProfile(
    id: 'u_aria',
    username: 'aria.codes',
    displayName: 'Aria Chen',
    bio: 'Frontend engineer. Design systems & motion.',
    avatarUrl: 'https://picsum.photos/seed/aria/200/200',
    verified: true,
    verificationKind: 'creator',
    followers: 45200,
    following: 610,
  );

  static const UserProfile nova = UserProfile(
    id: 'u_nova',
    username: 'nova_labs',
    displayName: 'Nova Labs',
    bio: 'Independent research collective.',
    avatarUrl: 'https://picsum.photos/seed/nova/200/200',
    verified: true,
    verificationKind: 'brand',
    followers: 982000,
    following: 12,
  );

  static const UserProfile marco = UserProfile(
    id: 'u_marco',
    username: 'marco',
    displayName: 'Marco Rossi',
    bio: 'Photographer. Light chaser.',
    avatarUrl: 'https://picsum.photos/seed/marco/200/200',
    followers: 3120,
    following: 890,
  );

  static const UserProfile citydesk = UserProfile(
    id: 'u_citydesk',
    username: 'citydesk',
    displayName: 'City Desk',
    bio: 'Local news, filed hourly.',
    avatarUrl: 'https://picsum.photos/seed/citydesk/200/200',
    verified: true,
    verificationKind: 'media',
    followers: 210000,
    following: 45,
  );

  static const UserProfile jules = UserProfile(
    id: 'u_jules',
    username: 'jules',
    displayName: 'Jules',
    bio: 'Runner. Reader. Occasional poster.',
    avatarUrl: 'https://picsum.photos/seed/jules/200/200',
    followers: 512,
    following: 400,
  );

  static const UserProfile devrel = UserProfile(
    id: 'u_devrel',
    username: 'priya.dev',
    displayName: 'Priya Nair',
    bio: 'DevRel. Talks about @nova_labs and open source.',
    avatarUrl: 'https://picsum.photos/seed/priya/200/200',
    verified: true,
    verificationKind: 'founder',
    followers: 67000,
    following: 1200,
  );

  static const List<UserProfile> profiles = <UserProfile>[
    currentUser,
    aria,
    nova,
    marco,
    citydesk,
    jules,
    devrel,
  ];

  // -- Safety (blocks / mutes) ---------------------------------------------

  /// Seed set of user ids the current user has blocked. Deliberately EMPTY so
  /// the default feed is unchanged (existing feed assertions must not shift)
  /// and the [SafetyRepository] block filter is a pure pass-through until the
  /// user blocks someone. Blocks are also server-backed (public.blocks); this
  /// is only the offline/mock seed.
  static Set<String> blockedUserIds() => <String>{};

  /// Seed set of user ids the current user has muted. Deliberately EMPTY (see
  /// [blockedUserIds]). Mute is client-authoritative this phase (no server
  /// table), so this is the sole source of truth offline.
  static Set<String> mutedUserIds() => <String>{};

  /// Seed set of muted keywords. Deliberately EMPTY so an empty
  /// [SafetyRepository] keeps the feed a pure pass-through (existing feed
  /// assertions must not shift). The keyword-mute surface (FEAT-007) reads and
  /// writes this list; it is client-authoritative and in-memory only.
  static Set<String> muteWords() => <String>{};

  /// Seed set of post ids the current user has SAVED/bookmarked. Deliberately
  /// EMPTY so an empty [SaveRepository] leaves the default feed unchanged
  /// (existing bookmark/feed assertions must not shift). Saves are server-backed
  /// (public.saves); this is only the offline/mock seed.
  static Set<String> savedPostIds() => <String>{};

  /// Seed set of comment ids the current user has LIKED. Deliberately EMPTY so
  /// an empty viewer comment-like state leaves the seeded [comments] like
  /// counts unchanged (existing comment_repository_test.dart assertions must
  /// not shift). Comment likes are server-backed (public.comment_likes, added
  /// in migration 0008); this is only the offline/mock seed.
  static Set<String> likedCommentIds() => <String>{};

  // -- Relationships (follow edges / requests) -----------------------------

  /// Seed of the current user's OUTGOING follow edges, keyed by followee id
  /// with a follow status ('pending' | 'accepted'). Deliberately EMPTY so the
  /// profile 'Follow' button starts at [FollowState.none] for every account and
  /// no existing feed/notification assertion shifts. Follow edges are also
  /// server-backed (public.follows); this is only the offline/mock seed.
  static Map<String, String> followEdges() => <String, String>{};

  /// Seed of INCOMING pending follow requests (accounts asking to follow the
  /// current user). Mirrors the `followRequest` notification already present in
  /// [notifications] (from [citydesk]) so the requests UI has something to show
  /// on the mock/offline path. Newest-first is enforced by the repository.
  static List<UserProfile> pendingFollowRequests() => <UserProfile>[citydesk];

  // -- Posts ---------------------------------------------------------------

  static List<Post> posts() {
    final now = DateTime.now();
    return <Post>[
      Post(
        id: 'p1',
        author: aria,
        content:
            'Shipped a new motion system today. Tiny spring curves make the '
            'whole app feel alive. #design #flutter cc @nova_labs',
        mediaUrl: 'https://picsum.photos/seed/motion/900/600',
        mediaType: MediaType.image,
        createdAt: now.subtract(const Duration(minutes: 12)),
        replyCount: 34,
        repostCount: 128,
        likeCount: 1900,
        viewCount: 84200,
        liked: true,
      ),
      Post(
        id: 'p2',
        author: nova,
        content:
            'We are open-sourcing our internal charting toolkit next week. '
            'Follow along for the release. #opensource',
        createdAt: now.subtract(const Duration(minutes: 47)),
        replyCount: 210,
        repostCount: 940,
        likeCount: 12400,
        viewCount: 512000,
        reposted: true,
      ),
      Post(
        id: 'p3',
        author: marco,
        content: 'Golden hour over the harbor never gets old.',
        mediaUrl: 'https://picsum.photos/seed/harbor/900/700',
        mediaType: MediaType.image,
        createdAt: now.subtract(const Duration(hours: 2)),
        replyCount: 12,
        repostCount: 44,
        likeCount: 860,
        viewCount: 21000,
      ),
      Post(
        id: 'p4',
        author: citydesk,
        content:
            'BREAKING: New transit line opens ahead of schedule. Free rides '
            'all weekend. More at #CityTransit',
        createdAt: now.subtract(const Duration(hours: 3, minutes: 20)),
        replyCount: 88,
        repostCount: 512,
        likeCount: 3400,
        viewCount: 190000,
      ),
      Post(
        id: 'p5',
        author: jules,
        content:
            'First 10k of the year done. Slow, but done. Consistency beats '
            'intensity, apparently.',
        createdAt: now.subtract(const Duration(hours: 5)),
        replyCount: 6,
        repostCount: 2,
        likeCount: 140,
        viewCount: 5200,
      ),
      Post(
        id: 'p6',
        author: devrel,
        content:
            'Reminder: good docs are a feature. If your @nova_labs users cant '
            'find it, it does not exist. #devrel #docs',
        mediaUrl: 'https://picsum.photos/seed/docs/900/500',
        mediaType: MediaType.image,
        createdAt: now.subtract(const Duration(hours: 7, minutes: 15)),
        replyCount: 41,
        repostCount: 220,
        likeCount: 2600,
        viewCount: 96000,
        bookmarked: true,
      ),
      Post(
        id: 'p7',
        author: aria,
        content:
            'Hot take: most loading spinners should be skeleton screens '
            'instead. Perceived performance is real performance.',
        createdAt: now.subtract(const Duration(hours: 9)),
        replyCount: 302,
        repostCount: 611,
        likeCount: 8800,
        viewCount: 340000,
      ),
      Post(
        id: 'p8',
        author: marco,
        content: 'Behind the scenes from yesterday\'s shoot. Short clip.',
        mediaUrl: 'https://picsum.photos/seed/bts/900/600',
        mediaType: MediaType.video,
        createdAt: now.subtract(const Duration(hours: 12)),
        replyCount: 18,
        repostCount: 33,
        likeCount: 540,
        viewCount: 47000,
      ),
      Post(
        id: 'p9',
        author: nova,
        content:
            'Thread on how we cut cold-start latency by 60%. 1/ It started with '
            'measuring the right thing. #performance',
        createdAt: now.subtract(const Duration(hours: 16)),
        replyCount: 76,
        repostCount: 402,
        likeCount: 5100,
        viewCount: 260000,
      ),
      Post(
        id: 'p10',
        author: jules,
        content:
            'Currently reading three books at once and finishing none of them. '
            'Recommendations welcome @aria.codes',
        createdAt: now.subtract(const Duration(days: 1, hours: 2)),
        replyCount: 22,
        repostCount: 4,
        likeCount: 210,
        viewCount: 9800,
      ),
      // p11: a MULTI-IMAGE CAROUSEL post exercising the polymorphic content
      // model (kind is derived as PostKind.carousel from >1 attachment). Placed
      // LAST with the OLDEST createdAt so the newest-first feed ordering and
      // the existing p1..p10 order/count assertions in post_repository_test.dart
      // are unaffected. `marco` (not aria/jules) keeps the Following tab subset
      // unchanged. Attachments are carried BY URL (picsum placeholders) — real
      // capture/upload is Phase 4 (see PostAttachment's PHASE 4 SEAM note). kind
      // is derived automatically by the Post constructor via deriveKind.
      Post(
        id: 'p11',
        author: marco,
        content: 'A few frames from the harbor series. Swipe through. #photography',
        attachments: const <PostAttachment>[
          PostAttachment(
            id: 'p11_a0',
            postId: 'p11',
            position: 0,
            type: AttachmentType.image,
            url: 'https://picsum.photos/seed/harbor1/900/600',
          ),
          PostAttachment(
            id: 'p11_a1',
            postId: 'p11',
            position: 1,
            type: AttachmentType.image,
            url: 'https://picsum.photos/seed/harbor2/900/600',
          ),
          PostAttachment(
            id: 'p11_a2',
            postId: 'p11',
            position: 2,
            type: AttachmentType.image,
            url: 'https://picsum.photos/seed/harbor3/900/600',
          ),
        ],
        createdAt: now.subtract(const Duration(days: 1, hours: 6)),
        replyCount: 9,
        repostCount: 12,
        likeCount: 430,
        viewCount: 15600,
      ),
      // p12: a FIRST-CLASS TEXT-ONLY tweet (zero attachments => kind text). It
      // deliberately carries a #hashtag followed by a dot AND an @mention with
      // a dot to exercise the UNIFIED linkify/extract grammar (hashtag body
      // excludes dots, so '#design.system' highlights/extracts 'design'; a
      // mention body allows dots, so '@first.last' is one entity). Placed LAST
      // with the OLDEST createdAt so the newest-first feed ordering and the
      // existing p1..p11 order/relative-count assertions in
      // post_repository_test.dart are unaffected. `citydesk` (not aria/jules)
      // keeps the Following tab subset unchanged.
      Post(
        id: 'p12',
        author: citydesk,
        content:
            'Style guide is live. Everything ships through our #design.system '
            'now — questions to @first.last on the platform team.',
        createdAt: now.subtract(const Duration(days: 1, hours: 9)),
        replyCount: 4,
        repostCount: 7,
        likeCount: 96,
        viewCount: 4100,
      ),
      // p13: a QUOTE-POST exercising the model. It quotes p2 (nova's
      // open-sourcing announcement) via `quotedPostId: 'p2'` with the SAME seed
      // Post object hydrated into `quotedPost` for immediate rendering, plus a
      // short commentary body. Authored by `marco` (OUTSIDE {aria, jules}) so
      // the Following tab subset is unchanged, and it quotes a DIFFERENT post
      // (never itself) so the self-quote check is respected. Placed LAST with
      // the OLDEST createdAt (older than p12) so the newest-first feed ordering
      // and the existing p1..p12 order/relative-count assertions in
      // post_repository_test.dart are unaffected.
      Post(
        id: 'p13',
        author: marco,
        content: 'This toolkit is going to save so many teams weeks of work.',
        quotedPostId: 'p2',
        quotedPost: Post(
          id: 'p2',
          author: nova,
          content:
              'We are open-sourcing our internal charting toolkit next week. '
              'Follow along for the release. #opensource',
          createdAt: now.subtract(const Duration(minutes: 47)),
          replyCount: 210,
          repostCount: 940,
          likeCount: 12400,
          viewCount: 512000,
          reposted: true,
        ),
        createdAt: now.subtract(const Duration(days: 1, hours: 12)),
        replyCount: 3,
        repostCount: 5,
        likeCount: 64,
        viewCount: 2800,
      ),
    ];
  }

  /// A subset used for the "Following" tab (authors the current user follows).
  static List<Post> followingPosts() {
    final all = posts();
    return all
        .where((p) => p.author.id == aria.id || p.author.id == jules.id)
        .toList();
  }

  // -- Stories (24h ephemeral) ---------------------------------------------

  /// Seed of ephemeral stories for the in-memory [StoryRepository] and the unit
  /// tests. Kept INDEPENDENT of [posts]/[comments]/[notifications] so no
  /// existing feed/comment/notification assertion shifts.
  ///
  /// Most seeds are ACTIVE: `createdAt = now - 2h` with the default 24h TTL, so
  /// they expire ~22h in the future. They span several existing profiles (aria,
  /// nova, marco) plus the current user, with a mix of seen/unseen so the
  /// story-ring's unseen-vs-seen affordance is exercised. The LAST entry is an
  /// already-EXPIRED story (created 26h ago, so `expiresAt` is ~2h in the past)
  /// so the `isActive` filter is exercised by tests and never surfaces it.
  static List<Story> stories() {
    final now = DateTime.now();
    return <Story>[
      // Current user's own active story (own tile shown first in the ring).
      Story.ephemeral(
        id: 's_me1',
        author: currentUser,
        mediaUrl: 'https://picsum.photos/seed/story_me1/720/1280',
        createdAt: now.subtract(const Duration(hours: 1)),
        seen: false,
      ),
      // Aria: two active stories, chronological within her group.
      Story.ephemeral(
        id: 's_aria1',
        author: aria,
        mediaUrl: 'https://picsum.photos/seed/story_aria1/720/1280',
        createdAt: now.subtract(const Duration(hours: 3)),
        seen: false,
      ),
      Story.ephemeral(
        id: 's_aria2',
        author: aria,
        mediaUrl: 'https://picsum.photos/seed/story_aria2/720/1280',
        createdAt: now.subtract(const Duration(hours: 2)),
        seen: false,
      ),
      // Nova: an active story already SEEN (its ring renders muted/gray).
      Story.ephemeral(
        id: 's_nova1',
        author: nova,
        mediaUrl: 'https://picsum.photos/seed/story_nova1/720/1280',
        type: StoryMediaType.video,
        createdAt: now.subtract(const Duration(hours: 4)),
        seen: true,
      ),
      // Marco: an active unseen story.
      Story.ephemeral(
        id: 's_marco1',
        author: marco,
        mediaUrl: 'https://picsum.photos/seed/story_marco1/720/1280',
        createdAt: now.subtract(const Duration(hours: 2)),
        seen: false,
      ),
      // An already-EXPIRED story (created 26h ago > 24h TTL): isActive is false,
      // so it must never appear in activeStoryGroups/activeStoriesFor.
      Story.ephemeral(
        id: 's_marco_expired',
        author: marco,
        mediaUrl: 'https://picsum.photos/seed/story_expired/720/1280',
        createdAt: now.subtract(const Duration(hours: 26)),
        seen: false,
      ),
    ];
  }

  // -- Comments ------------------------------------------------------------

  /// Seed comments used by the in-memory [CommentRepository] and the unit
  /// tests. Keyed by the post ids from [posts]. Threaded replies reference a
  /// parent comment via [Comment.parentId].
  static List<Comment> comments() {
    final now = DateTime.now();
    return <Comment>[
      Comment(
        id: 'cm1',
        postId: 'p1',
        author: nova,
        content: 'The spring curves feel incredible. What damping did you use?',
        likeCount: 42,
        createdAt: now.subtract(const Duration(minutes: 9)),
      ),
      Comment(
        id: 'cm2',
        postId: 'p1',
        author: marco,
        parentId: 'cm1',
        content: 'Seconding this, would love a write-up.',
        likeCount: 8,
        createdAt: now.subtract(const Duration(minutes: 6)),
      ),
      Comment(
        id: 'cm3',
        postId: 'p1',
        author: jules,
        content: 'Motion done right is invisible. Nice work.',
        likeCount: 15,
        createdAt: now.subtract(const Duration(minutes: 3)),
      ),
      Comment(
        id: 'cm4',
        postId: 'p2',
        author: devrel,
        content: 'Been waiting for this toolkit. Ship it!',
        likeCount: 21,
        createdAt: now.subtract(const Duration(minutes: 30)),
      ),
      Comment(
        id: 'cm5',
        postId: 'p7',
        author: citydesk,
        content: 'Skeleton screens changed how we ship dashboards.',
        likeCount: 63,
        createdAt: now.subtract(const Duration(hours: 8, minutes: 30)),
      ),
    ];
  }

  // -- Notifications -------------------------------------------------------

  static List<NotificationItem> notifications() {
    final now = DateTime.now();
    return <NotificationItem>[
      NotificationItem(
        id: 'n1',
        type: NotificationType.like,
        actor: aria,
        preview: 'liked your post about skeleton screens',
        createdAt: now.subtract(const Duration(minutes: 8)),
      ),
      NotificationItem(
        id: 'n2',
        type: NotificationType.follow,
        actor: marco,
        preview: 'followed you',
        createdAt: now.subtract(const Duration(minutes: 40)),
      ),
      NotificationItem(
        id: 'n3',
        type: NotificationType.repost,
        actor: nova,
        preview: 'reposted your note on motion curves',
        createdAt: now.subtract(const Duration(hours: 1, minutes: 30)),
        read: true,
      ),
      NotificationItem(
        id: 'n4',
        type: NotificationType.reply,
        actor: devrel,
        preview: 'Totally agree, docs are underrated.',
        createdAt: now.subtract(const Duration(hours: 4)),
        read: true,
      ),
      NotificationItem(
        id: 'n5',
        type: NotificationType.mention,
        actor: jules,
        preview: 'mentioned you in a post',
        createdAt: now.subtract(const Duration(hours: 6)),
      ),
      NotificationItem(
        id: 'n6',
        type: NotificationType.followRequest,
        actor: citydesk,
        preview: 'requested to follow you',
        createdAt: now.subtract(const Duration(hours: 7)),
      ),
      NotificationItem(
        id: 'n7',
        type: NotificationType.system,
        actor: currentUser,
        preview: 'Your account is now verified.',
        createdAt: now.subtract(const Duration(hours: 9)),
        read: true,
      ),
    ];
  }

  // -- Conversations -------------------------------------------------------

  static List<Conversation> conversations() {
    final now = DateTime.now();
    return <Conversation>[
      Conversation(
        id: 'c1',
        participant: aria,
        lastPreview: 'Sounds good, ship it ',
        updatedAt: now.subtract(const Duration(minutes: 5)),
        unread: 2,
        messages: <Message>[
          Message(
            id: 'c1m1',
            fromMe: false,
            text: 'Did you see the new motion PR?',
            sentAt: now.subtract(const Duration(minutes: 20)),
          ),
          Message(
            id: 'c1m2',
            fromMe: true,
            text: 'Yep, reviewing now. Curves look great.',
            sentAt: now.subtract(const Duration(minutes: 14)),
          ),
          Message(
            id: 'c1m3',
            fromMe: false,
            text: 'Sounds good, ship it ',
            sentAt: now.subtract(const Duration(minutes: 5)),
          ),
        ],
      ),
      Conversation(
        id: 'c2',
        participant: devrel,
        lastPreview: 'Can you speak at the meetup?',
        updatedAt: now.subtract(const Duration(hours: 2)),
        unread: 0,
        messages: <Message>[
          Message(
            id: 'c2m1',
            fromMe: false,
            text: 'Can you speak at the meetup?',
            sentAt: now.subtract(const Duration(hours: 2)),
          ),
        ],
      ),
      Conversation(
        id: 'c3',
        participant: jules,
        lastPreview: 'Thanks for the book rec!',
        updatedAt: now.subtract(const Duration(days: 1)),
        unread: 0,
        messages: <Message>[
          Message(
            id: 'c3m1',
            fromMe: true,
            text: 'You should read Project Hail Mary.',
            sentAt: now.subtract(const Duration(days: 1, hours: 1)),
          ),
          Message(
            id: 'c3m2',
            fromMe: false,
            text: 'Thanks for the book rec!',
            sentAt: now.subtract(const Duration(days: 1)),
          ),
        ],
      ),
    ];
  }
}
