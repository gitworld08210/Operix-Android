import '../models/comment.dart';
import '../models/conversation.dart';
import '../models/notification_item.dart';
import '../models/post.dart';
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
    ];
  }

  /// A subset used for the "Following" tab (authors the current user follows).
  static List<Post> followingPosts() {
    final all = posts();
    return all
        .where((p) => p.author.id == aria.id || p.author.id == jules.id)
        .toList();
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
