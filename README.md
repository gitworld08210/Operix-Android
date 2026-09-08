# Oneleven

A modern-X (current Twitter/X) styled social and creator app for Android, built with Flutter.

Oneleven is dark-first: true-black background, X-blue accent (`#1D9BF0`), clean Inter/Chirp-like sans, no gradients or glassmorphism.

## Status

> **Not compiled in this environment.** This project was authored **by hand without an available Flutter/Dart/Android toolchain and with no network access**, so it has **not** been compiled, analyzed, or run in-sandbox. A developer must run `flutter pub get` and `flutter run` on a Flutter-equipped machine to build, verify, and launch it. Every file was written and cross-checked manually; treat the first real `flutter analyze` as the source of truth.

The app is feature-complete for a first pass across three increments:

- **FEAT-001 (foundation):** standard Flutter project files, a complete `android/` Gradle scaffold (namespace / applicationId `com.oneleven.app`, label "Oneleven"), the centralized theme (`lib/theme/`), the data models (`lib/models/`), and in-memory mock repositories with sample data (`lib/data/`).
- **FEAT-002 (UI):** `lib/main.dart`, reusable widgets (`lib/widgets/`), and all screens (`lib/screens/`) wired to the repositories, plus the Supabase email-OTP auth screen (`lib/screens/auth_screen.dart`) and auth gate.
- **FEAT-003 (Supabase backend):** `lib/supabase_config.dart`, `lib/data/auth_repository.dart`, `lib/data/storage_service.dart`, the `supabase/migrations/0001_init.sql` schema, and Supabase-backed `PostRepository` / `ProfileRepository` (with a `MockData` fallback). See **Backend (Supabase)** below.

## Folder structure

```
oneleven_app/
  android/                     # Gradle scaffold (com.oneleven.app, label "Oneleven")
  lib/
    main.dart                  # App entry; MaterialApp + dark theme + home shell
    theme/                     # app_colors, app_text_styles, app_theme (+ spacing/radii)
    models/                    # post, user_profile, notification_item, conversation
    data/                      # mock_data, post/profile/auth repositories (ChangeNotifier singletons), storage_service
    supabase_config.dart       # Supabase URL/anon-key + initSupabase()
    utils/                     # format.dart (fmtCount, timeAgo)
    widgets/                   # avatar, verified_badge, action_button, post_card, app_scaffold
    screens/                   # home_feed, search, compose, notifications, messages,
                               #   conversation, profile
```

## Implemented vs scaffold

**Implemented (functional against mock data):**

- Bottom navigation shell with 5 destinations: Home, Search, Compose, Notifications, Messages. Compose opens a full-screen modal route; Profile is reachable from the Home top-bar avatar.
- **Home feed** with **For You / Following** tabs, listing `PostCard`s from `PostRepository`. Like / Repost / Bookmark toggle live counts and filled icons through the repository.
- **PostCard** mirroring the web design: avatar + content columns, bold display name + verification badge + `@handle` + relative time + more menu, `#hashtag` / `@mention` linkification in X-blue, "Show more" truncation, optional rounded media (single image, a play-icon placeholder for video, or a swipeable multi-image **carousel** with dot indicators + a `1/N` counter — see **Content model** below), and the full action row (Reply, Repost, Like, Views, Bookmark, Share). All `Image.network` calls have loading + error fallbacks so a blocked network never crashes the app.
- **Search / Explore:** search field, trending chips, and a "Trends for you" list.
- **Compose:** author avatar, multiline field, media/GIF/poll toolbar, character counter, and a Post button that adds to the feed. The **Photos** button appends demo URL-based image attachments (so a single-image post or a multi-image carousel can be assembled and previewed) — see the Phase 4 seam in **Content model**.
- **Notifications:** typed activity rows (like / reply / repost / follow / mention) with unread highlighting and "Mark all read".
- **Messages + Conversation:** thread list with unread dots, and a chat view with left/right bubbles and a local send composer.
- **Profile:** banner, overlapping avatar, name + badge, bio, follower/following counts, Edit/Follow button, and Posts / Media tabs.

**Out of scope for this Android app (not built):** Wallet, Premium, Verification purchase flow, Creator Hub, and Live. GIF/Poll and share are intentionally mocked (they surface a snackbar).

## Content model (polymorphic posts)

Post content is modeled **polymorphically** rather than as a single hardcoded
media slot, so text, single-image, single-video, and multi-image **carousel**
posts share one abstraction and new content kinds can be added without
rewriting every consumer:

- **`PostKind` discriminator** (`text` | `image` | `carousel` | `video`) on
  `Post`, kept consistent with an **ordered `List<PostAttachment>` attachments**
  relation via `deriveKind(attachments)` (0 attachments ⇒ `text`; 1 image ⇒
  `image`; 1 video ⇒ `video`; more than 1 ⇒ `carousel`). The constructor and
  `copyWith` always derive `kind` from the attachment list, so the two can
  never disagree.
- **Compatibility shim:** the legacy `mediaUrl` / `mediaType` / `hasMedia`
  getters on `Post` are preserved and computed from `attachments.first`, so
  single-media consumers behave identically.
- **Backend:** migration `0005_content_attachments.sql` adds `posts.kind` and a
  `post_attachments` table (indexed by `(post_id, position)`) whose SELECT RLS
  **inherits the parent post's author visibility** (mirroring the
  comments/reposts policies from `0002`). The client row-mapper reads the joined
  `post_attachments` array (ordered by position) and **falls back** to the
  legacy `media_url` / `media_type` columns for pre-`0005` rows.

### First-class text posts (the X core)

A **text-only tweet** is simply a `Post` with zero attachments
(`PostKind.text`), and it is a first-class citizen of the feed:

- **280-character limit (X standard).** `lib/utils/text_post.dart` exposes the
  single canonical constant `kMaxTextPostChars = 280` and a **pure, Supabase-free
  validator** `validateTextPost(content)` returning
  `length` / `remaining` / `isEmpty` / `isOverLimit` / `isValid`. Length is
  counted in **Unicode grapheme clusters** (`content.characters.length`) so
  emoji and combining marks count exactly as the composer shows them. A post is
  postable when the **trimmed** content is non-empty **and** within the limit.
  The composer reads this one source of truth for `_maxChars`, `_canPost`, and
  the live character counter (which turns to the over-limit color and disables
  **Post** past 280). Attachment posts remain postable as before.
- **Unified `#`/`@` linkify + extract grammar.** The PostCard linkifier and the
  `extractHashtags` / `extractMentions` extractors both reference the **same
  exported patterns** (`hashtagPattern` / `mentionPattern` in
  `lib/utils/text_entities.dart`), so a highlighted span and its
  extracted/linked entity are **byte-identical**. A hashtag body excludes dots
  (a trailing `.` ends the tag, so `#design.system` ⇒ `design`) while a mention
  body allows dots (`@first.last` is one mention). Entities render in the
  X-blue accent (`#1D9BF0`).
- **No empty media frame.** PostCard gates its media block on `post.hasMedia`,
  so a text post renders **header + linkified caption + action row only** — no
  empty `AspectRatio` / `ClipRRect` frame.

> **Phase 4 seam — no real capture/upload yet.** Attachments are carried **by
> URL/reference** only. There is no device gallery/camera capture of bytes: the
> mock seed and the compose **Photos** button use hosted picsum placeholder
> URLs, and each URL is rendered with the existing `Image.network` +
> loading/error placeholder pattern. Real capture + upload to the storage
> bucket (populating the attachment URLs from device bytes) is Phase 4; the seam
> is marked in code with `// PHASE 4 SEAM: ...`.

### Quote-posts

A **quote-post** is a post that embeds/references another post. It is optional
and fully backward compatible: existing posts carry a null reference and render
exactly as before. Quoting is **orthogonal to media kind** — you can quote with
a text body or with media.

- **Model.** `Post` carries a nullable `quotedPostId` (the durable FK) and a
  nullable `quotedPost` (the hydrated embed used for rendering). `quotedPost`
  may be null even when `quotedPostId` is set (the quoted post is not cached or
  not viewable). It is **not** part of `==` / `hashCode`, which stay id-based;
  `copyWith` exposes `clearQuotedPost` / `clearQuotedPostId` escape hatches
  (mirroring `clearMyReaction`) since a null arg is indistinguishable from
  "unchanged".
- **Migration `0010_quote_posts.sql`.** Adds a nullable self-referencing FK
  `posts.quoted_post_id uuid references public.posts(id) on delete set null`
  (deleting a quoted post degrades the quoting post to a normal post rather than
  cascading a delete), a guarded `posts_no_self_quote` CHECK (a post may not
  quote itself), and an index for reverse lookups. **No new RLS is required:**
  the existing `posts_select_viewable` policy already gates every posts row by
  `can_view_profile(auth.uid(), owner)`, and a joined quoted post is its own
  posts row under the same policy, so an unviewable quoted post simply yields a
  null embed. Live application is **UNVERIFIED** in this environment (no
  reachable Supabase) and validated by structural review only.
- **One-level embed hydrate.** `PostRepository` fetches the quoted post one
  level deep via the aliased self-embed `quoted:quoted_post_id(*, profiles(*),
  post_attachments(*))`; `mapPostRow` maps the nested `quoted` object into
  `quotedPost` but **never recurses** — the embedded post's own `quotedPost` is
  always null. Absence of the join is tolerated gracefully (null embed).
- **Rendering.** `PostCard` renders a compact bordered quoted-post card after
  the caption (small avatar + name/handle + verified badge, truncated caption
  linkified with the shared `#`/`@` grammar, and a thumbnail when the quoted
  post has media). When `quotedPostId` is set but the embed can't be resolved it
  shows a subtle **"This post is unavailable"** placeholder. The embedded card
  never nests a second-level embed.
- **Compose.** `ComposeScreen(quoted: post)` opens the composer pre-attached to
  a quoted post (from the PostCard overflow menu's **Quote** action), shows a
  read-only preview, and builds the post with `quotedPostId` + `quotedPost`. A
  quote-post is postable **even with an empty body** when a quote is attached.

## Stories (24h ephemeral)

Instagram-style **stories** live at the top of the home feed:

- **Story ring** (`StoryRing`) — a horizontally-scrollable row of author tiles
  above the For You / Following tabs. A **gradient ring** marks a group with
  **unseen** stories, a **muted/gray ring** marks an all-seen group, and the
  current user's **own tile leads** with a `+` add affordance. It rebuilds via
  an `AnimatedBuilder` over `StoryRepository.instance` and is placed above the
  `TabBarView` so it never interferes with the feeds' infinite-scroll lists.
- **Full-screen viewer** (`StoryViewerScreen`) — a tap-through viewer with
  **segmented progress bars** (Instagram-style): tap right to advance, tap left
  to go back, with per-story auto-advance driven by a single
  `AnimationController` (disposed on close). Showing a story marks it **seen**.
- **Model + repository:** an immutable `Story` (`id`, `author`, `mediaUrl`,
  `type`, `createdAt`, `expiresAt`, `seen`) with `isActive(now)` and a
  `Story.ephemeral(ttl: 24h)` factory; `StoryRepository` is a `ChangeNotifier`
  singleton over a `MockData` seed exposing `activeStoryGroups` (grouped by
  author, **own group first**, expired stories filtered out), `activeStoriesFor`,
  and an idempotent single-notify `markSeen`, plus guarded fire-and-forget
  `load()` / persistence — the same offline-no-op pattern as the other repos.
- **Backend:** migration `0006_stories.sql` adds `public.stories` (with an
  `expires_at` expiry column) and a `public.story_views` seen-tracking table.
  Story SELECT RLS is **author-inherited AND not-expired**
  (`expires_at > now() and public.can_view_profile(auth.uid(), owner)`),
  mirroring the comments/reposts visibility pattern; writes are owner-scoped.

> **Media by reference (Phase 4 seam).** Like posts, stories carry media **by
> URL/reference** only — real device capture/upload lands in Phase 4 (marked in
> code with `// PHASE 4 SEAM: ...`).
>
> **Server-expiry unverified (ENV RISK).** Ephemerality is **client-filtered**
> via `Story.isActive(now)`; the migration adds the matching server RLS time
> predicate, but it has **not** been applied/exercised against a live Supabase
> project here (structural review only). True enforcement needs that server RLS
> plus a **scheduled sweep** of expired rows (a later ops concern). Treat live
> expiry/RLS behavior as the largest known risk for this feature.

## Discovery relations (saves, reactions, hashtags, mentions, location)

First-class, **indexed** relations that make a later search/discovery phase
cheap (migration `0007_relations.sql`):

- **Saves / bookmarks (server-backed).** `SaveRepository` is a `ChangeNotifier`
  singleton over an in-memory set seeded EMPTY from `MockData.savedPostIds()`,
  exposing synchronous `isSaved` / `savedIds` and an optimistic single-notify
  `toggleSave` that persists to `public.saves` (keyed by `(user_id, post_id)`)
  via a guarded fire-and-forget helper — the same offline-no-op pattern as the
  other repos. `PostRepository.toggleBookmark` and the `PostCard` bookmark
  action now drive it (the card reflects `SaveRepository.isSaved`). Indexed by
  `idx_saves_user (user_id, created_at desc)` for a "my saves" screen.
- **Richer reactions.** A `ReactionType` of `{like, love, laugh, wow, sad,
  angry}`; `Post` carries a server-owned `reactionCounts` map plus the viewer's
  `myReaction`. The legacy `liked` / `likeCount` surface is kept as a
  **compatibility view** under the **like-implies-liked** rule
  (`liked == (myReaction == like)`). `PostRepository.react` / `clearReaction`
  persist to `public.reactions`; `toggleLike` is a thin wrapper over them so the
  quick like/unlike tap is unchanged. `PostCard` adds a **6-type reaction
  picker** via **long-press** on the like button (a plain tap stays quick
  like/unlike). Indexed by `idx_reactions_post_type (post_id, type)`.
- **Hashtags + mentions (indexed).** A pure, tested extractor
  (`utils/text_entities.dart`) parses `#hashtags` / `@mentions` from the caption
  using the SAME grammar the `PostCard` linkifier highlights (normalized,
  lower-cased, de-duped). On compose these feed `public.hashtags` +
  `public.post_hashtags` and `public.post_mentions`, indexed by
  `idx_post_hashtags_hashtag` ("posts for #tag") and `idx_post_mentions_user`
  ("posts mentioning me").
- **Location tags.** Compose has an optional **free-text location** field;
  `posts.location` (+ optional `lat`/`lng`) is added with a partial
  `idx_posts_location`. A real place-picker / geocoder is a **Phase 4/5 seam**
  (marked in code); this phase is free text only.

> **Reactions-vs-likes coexistence (no double-counting).** `public.reactions`
> is the general table and the ONLY client-writable reaction store for all six
> types **including `like`**. `posts.like_count` is recomputed from
> `reactions where type='like'` by the new `sync_post_reaction_like_count`
> trigger. The 0001 `public.likes` table and its `sync_post_like_count` trigger
> are left **untouched but dormant** (the client no longer writes `likes`), so
> `like_count` has exactly one writer going forward — there is no
> double-counting. See the head comment of `0007_relations.sql`.
>
> **Reaction-path like notifications (migration `0009_reaction_notify.sql`).**
> Because the client now writes likes only to `public.reactions`, the 0002
> `notify_on_like` trigger (which fires on `public.likes`) no longer runs on the
> going-forward path. `0009_reaction_notify.sql` adds `notify_on_reaction_like`,
> a trigger on `public.reactions` that mirrors `notify_on_like` exactly for
> `type='like'` (self-notify guard, `is_blocked` suppression, byte-identical
> `type='like' + entity_type='post'` payload), so a like made via a reaction
> notifies the post owner again. Only `like` notifies; the other five affect
> types are a deliberate, documented later-phase concern.
>
> **ENV RISK (largest known risk).** `0007_relations.sql` and
> `0009_reaction_notify.sql` are **UNVERIFIED**
> against a live Supabase project (no reachable/administerable instance, no
> service-role key here) — it has had **structural review only**. Live RLS
> enforcement, the reaction-count trigger, FK/uniqueness constraints, and index
> creation must be validated on a real project before relying on them.

## Comment threading + interactive likes

The comments subsystem is now first-class threaded with interactive likes
(migration `0008_comment_likes.sql`):

- **Nested replies.** A pure, tested assembler
  (`utils/comment_tree.dart` — `buildThread(List<Comment>)`) groups the flat
  newest-first comment list into a `CommentNode` tree: top-level comments
  newest-first, each comment's direct replies nested (also newest-first) under
  it, and **orphan replies** (a reply whose parent is absent/filtered) surfaced
  as top-level so nothing a viewer may see is dropped. Visual nesting is
  clamped to `maxThreadDepth` (2) while the underlying data nesting is
  preserved. `comments_screen` renders `flattenThread(buildThread(...))`,
  indenting each tile by `CommentNode.depth`.
- **Reply affordance.** Each comment tile has a **Reply** button that focuses
  the composer and shows a `Replying to @handle · cancel` banner above it;
  sending calls `CommentRepository.addComment(postId, text, parentId:)` so the
  reply is stored with its `parent_id` and nests under the parent on the next
  `buildThread`.
- **Interactive comment likes.** `CommentRepository` exposes
  `isCommentLiked(id)` + an optimistic single-notify `toggleCommentLike(id)`
  that flips the viewer's liked flag and adjusts the **display** `like_count`
  by +/-1, mirroring `PostRepository.toggleLike`. The viewer's like set is
  seeded EMPTY from `MockData.likedCommentIds()` and hydrated from
  `public.comment_likes` by `load` (a `setEquals` change-guard keeps offline a
  zero-notify no-op). The client records only the join row (insert/delete keyed
  by `(user_id, comment_id)`) and **never writes `comments.like_count`**.
- **Server-owned count.** `comments.like_count` is recomputed from `count(*)`
  over `public.comment_likes` by the `sync_comment_like_count` (SECURITY
  DEFINER) trigger, mirroring `sync_post_like_count`. The optimistic +/-1 is a
  display-only estimate reconciled on the next `load`.
- **Notification parity.** `0008` also adds a `notify_on_comment_like` trigger
  that notifies the liked comment's author (guarded against self-notify +
  blocked pairs), mirroring `notify_on_like`. Because the `notifications.type`
  check (0002) has no `comment_like` value, the row is emitted as type `like`
  with `entity_type = 'comment'`. RLS on `comment_likes` inherits the comment's
  post-author visibility (join `comments → posts` + `can_view_profile`),
  mirroring `comments_select_viewable`; writes are self-scoped. Indexed by
  `idx_comment_likes_comment`.

> **ENV RISK (largest known risk).** `0008_comment_likes.sql` is **UNVERIFIED**
> against a live Supabase project (no reachable/administerable instance, no
> service-role key here) — **structural review only**. Live RLS enforcement,
> the `sync_comment_like_count` count trigger, the `notify_on_comment_like`
> producer, FK/uniqueness constraints, and index creation must be validated on
> a real project before relying on them.

## Web-only surfaces (excluded from Android)

**Ads Manager** and **Admin-OS** are **web-only** and are intentionally **not** part of this Android Flutter app. They remain in the React/Vite web project only.

## Palette

| Token          | Hex        |
| -------------- | ---------- |
| background     | `#000000`  |
| surface/hover  | `#16181C`  |
| border         | `#2F3336`  |
| primary text   | `#E7E9EA`  |
| secondary text | `#71767B`  |
| accent (X blue)| `#1D9BF0`  |
| like (rose)    | `#F91880`  |
| repost (green) | `#00BA7C`  |

## Running (on a Flutter-equipped machine)

```sh
cd oneleven_app
flutter pub get
flutter run   # Android device or emulator
```

Requires the Flutter SDK (stable channel, Dart `>=3.3`, Flutter `>=3.22`) and the Android SDK.

## Backend (Supabase)

Oneleven uses [Supabase](https://supabase.com) for authentication, the primary
database (profiles, posts, reels), and object storage (avatars, reel videos).

### Configuration

The project URL and public (anon / publishable) key ship with sensible
defaults in `lib/supabase_config.dart`:

| Setting          | Default                                          | Override                                   |
| ---------------- | ------------------------------------------------ | ------------------------------------------ |
| `SUPABASE_URL`   | `https://xyuzzjwmpyckuhtiygpk.supabase.co`       | `--dart-define=SUPABASE_URL=...`           |
| `SUPABASE_ANON_KEY` | the project's publishable key                 | `--dart-define=SUPABASE_ANON_KEY=...`      |

To point the app at a different project without editing source:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://YOURPROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY
```

The anon key is a public, client-safe key. Never embed a `service_role`/secret
key in the app.

Supabase is initialized in `main.dart` (`WidgetsFlutterBinding.ensureInitialized()`
→ `await initSupabase()` → `runApp`).

### Database migration

Before the first launch, run the schema migration once in the Supabase SQL
editor:

1. Open your project in the Supabase dashboard → **SQL Editor** → **New query**.
2. Paste the full contents of [`supabase/migrations/0001_init.sql`](supabase/migrations/0001_init.sql).
3. Run it.

That migration creates the `profiles`, `posts`, `reels`, `likes`, and `follows`
tables with row-level-security policies, a trigger that auto-creates a
`profiles` row for every new auth user (collision-tolerant on `username`), a
trigger (`sync_post_like_count`) that keeps `posts.like_count` in sync with the
`likes` table, and the public `avatars` and `reels` storage buckets with
owner-scoped write policies.

#### Migration 0002 (authorization + core tables)

After 0001, run [`supabase/migrations/0002_authz_and_core_tables.sql`](supabase/migrations/0002_authz_and_core_tables.sql)
the same way (SQL Editor → New query → paste → Run). It **must be applied after
0001** and is **idempotent / re-runnable** (every statement uses
`if not exists` / `drop ... if exists` / `on conflict do nothing` / a guarded
`DO` block), so re-running it is safe. It adds:

- **New tables:** `comments` (post replies, with a server-owned `reply_count`),
  `notifications` (centralized activity feed), `reposts` (a like-style join
  table), and `blocks` (mutual blocking). It also adds `profiles.is_private`
  (private accounts) and `follows.status` (`'pending' | 'accepted'` follow
  requests).
- **Server-authoritative read authorization (privacy + blocking).** 0001 let
  **any** authenticated user read **every** row (`*_select_authenticated using
  (true)`) — an IDOR/privacy gap. 0002 replaces those permissive SELECT
  policies with ones that call two `SECURITY DEFINER` helpers:
  `is_blocked(a, b)` (true if either user has blocked the other) and
  `can_view_profile(viewer, target)` (true for yourself, or when neither has
  blocked the other **and** the target is public **or** the viewer has an
  `'accepted'` follow). `profiles`/`posts`/`reels`/`comments`/`reposts`/`likes`
  SELECT visibility now flows through these helpers, so privacy and blocking are
  enforced **in the database**, not trusted to the client. The owner-scoped
  insert/update/delete policies from 0001 are unchanged.
- **Follow requests.** A follow of a **public** account is created as
  `'accepted'`; a follow of a **private** account is created by the client as
  `'pending'` and flipped to `'accepted'` by the followee. Private content only
  becomes visible once the follow is `'accepted'` (the Dart change to create
  `'pending'` follows lands in a later increment).
- **Notifications via triggers (not client inserts).** There is deliberately
  **no** client insert policy on `notifications`; letting authenticated users
  insert arbitrary `recipient` rows would allow spoofed notifications.
  Notifications are produced **only** by `SECURITY DEFINER` triggers on
  like/comment/repost/follow inserts, each guarding against self-notification
  (`actor <> recipient`) and against blocked actors.
- **Server-owned counters.** `posts.reply_count` and `posts.repost_count` are
  now recomputed by triggers (`sync_post_reply_count`, `sync_post_repost_count`)
  from `count(*)` of the `comments` / `reposts` tables, mirroring
  `sync_post_like_count`. This retires the client-write `repost_count` drift
  debt documented in 0001. The client stops writing these counts in a later
  increment.
- **Indexes** for high-frequency queries and keyset-pagination-friendly
  ordering (`posts(owner)`, `posts(created_at desc)`, a composite
  `posts(created_at desc, id)` for keyset pagination, `comments(post_id,
  created_at)`, `likes(post_id)`, `reposts(post_id)`, `follows(follower,
  status)`, `follows(followee, status)`, `notifications(recipient, created_at
  desc)`, `blocks(blocked)`).

> **Unverified in this environment.** 0002 was authored and structurally
> reviewed by hand; there is no reachable Supabase project in this sandbox, so
> its live application and runtime RLS/trigger behavior have **not** been
> executed. Apply and exercise it against a real project before relying on it.

### Phase 2 client wiring (privacy, safety, follow requests, mute words)

Phase 2 wires the FEAT-002 server primitives into the Flutter client. Each
piece keeps the repository contract (synchronous getters over a `MockData`
seed, optimistic single-notify mutations, guarded fire-and-forget persistence)
and is covered by pure unit tests.

- **Private-account toggle.** `SettingsScreen` exposes a "Private account"
  switch bound to `ProfileRepository.setAccountPrivate`, which flips
  `currentUser.isPrivate` optimistically and persists `profiles.is_private`
  (guarded).
- **Block / mute / report.** `SafetyRepository` owns the viewer's blocked and
  muted account sets and abuse reports. Blocks persist to `public.blocks`
  (insert/delete keyed by `blocker = auth.uid()`); mutes are
  client-authoritative (in-memory, private "hide from my feed"); reports insert
  into `public.reports`. A pure `filterHidden` helper hides blocked/muted
  authors from the feed and is identity on empty sets. Post/profile overflow
  menus drive these actions and a Privacy & Safety settings section manages the
  blocked/muted lists.
- **Follow-request flow (`pending` → `accepted`).** `RelationshipRepository`
  owns the viewer's outgoing follow edges and incoming pending requests. A
  follow of a **public** account is created as `FollowState.following` (server
  row `status = 'accepted'`); a follow of a **private** account is created as
  `FollowState.requested` (server row `status = 'pending'`) and later flipped
  to `accepted` by the followee. The profile "Follow" button reflects
  **Follow / Requested / Following** and shows a lock affordance for private
  accounts; a private account's tab content is gated behind a "This account is
  private" empty-state until the follow is accepted. Follow-request
  notifications render **Accept / Deny** buttons wired to
  `acceptFollowRequest` / `denyFollowRequest` (guarded update / delete on
  `public.follows`). Notifications now hydrate from the `notifications` table
  (mock fallback preserved).
- **Keyword / mute-word filtering** (a product differentiator). `SafetyRepository`
  holds a persisted-in-memory, normalized (trimmed + lower-cased + de-duped)
  mute-words list managed from a Settings **"Muted words"** screen. A pure
  `contentMatchesMuteWords` matcher is case-insensitive and respects **word
  boundaries** (muting `art` hides "the art show" but not "startup"); it is
  composed into the feed filter so matching posts are hidden while empty word
  sets keep the feed a pure pass-through.

> **Live Supabase behavior is UNVERIFIED in this environment.** There is no
> reachable/administerable Supabase project and no service-role key in this
> sandbox, so the live enforcement of these features has **not** been executed:
> the `follows.status` `pending` → `accepted` transitions, the
> `can_view_profile` visibility gate for private accounts (the client "private
> account" gate and the mute filter are OPTIMISTIC UX mirrors; the server is the
> true gate), and the follow-accept notification trigger (migration 0003) all
> remain to be exercised against a real project. All client persistence is
> guarded and no-ops cleanly offline; verification here is limited to
> `flutter analyze` + `flutter test` on the mock-fallback path.

**Storage read model:** both buckets are intentionally `public: true`. The app
loads media with plain URL fetches (`Image.network`, video URLs) using
`getPublicUrl()`, which serves objects over the public CDN path. Because that
path bypasses RLS for reads, there is deliberately **no** authenticated-only
SELECT policy on `storage.objects` (it would be silently bypassed and only
imply a gate that does not exist). Reads are public by design; writes remain
owner-scoped. To make media private in a future version, flip the bucket
`public` flag to `false` and switch the client from `getPublicUrl()` to
`createSignedUrl()`.

### Authentication (email OTP)

Sign-up and login use **email one-time codes** (no passwords):

1. The user enters an email on the auth screen; the app calls
   `supabase.auth.signInWithOtp(email: ...)` (via `AuthRepository.sendOtp`).
   Supabase emails a 6-digit code and, for a new email, creates the auth user
   (and, through the trigger, a `profiles` row).
2. The user enters the code; the app calls
   `supabase.auth.verifyOTP(type: OtpType.email, email: ..., token: ...)`
   (via `AuthRepository.verifyOtp`), which establishes the session.
3. `main.dart`'s auth gate listens to auth state and shows the app shell when a
   session exists, otherwise the auth screen. Signing out
   (`AuthRepository.signOut`) returns to the auth screen.

**Phone OTP is out of scope** for this app; only email OTP is wired.

#### Required Supabase email template (6-digit code, not a magic link)

The auth UI collects a **6-digit code**, so the Supabase project's email
template must send the token/code and not (only) a magic link. Configure it
once in the dashboard:

1. **Authentication → Email Templates → Magic Link** (this is the template
   `signInWithOtp(email:)` uses).
2. Ensure the template body includes the token variable **`{{ .Token }}`**,
   e.g. `Your Oneleven code is {{ .Token }}`. If the template only contains
   `{{ .ConfirmationURL }}` (the default magic-link), the email will not carry
   a 6-digit code and the code-entry step in `auth_screen.dart` cannot succeed.
3. (Optional) Under **Authentication → Providers → Email**, keep "Enable email
   provider" on; a password is not required for the OTP flow.

The client verifies with `verifyOTP(type: OtpType.email, ...)`, which expects
the numeric token from `{{ .Token }}`. Magic-link click-through is **not** the
flow used here.

### Live vs. mock

**Live against Supabase (when reachable + signed in):**

- Auth (email OTP sign-up / login / sign-out).
- `profiles` — `ProfileRepository.currentUser` / `profiles` hydrate from the
  `profiles` table; `updateProfile` persists `display_name` / `bio`.
- `posts` — `PostRepository` hydrates from `posts` (joining `profiles` for the
  author); composing a post inserts into `posts` with a **client-generated
  UUID** (see `lib/utils/ids.dart`) sent as the row `id`, so the in-memory post
  id and the DB row id are identical (a later like/repost on the just-composed
  post targets the correct row instead of a not-yet-existing one).
- `likes` — like toggles perform a fire-and-forget insert/delete on the
  `likes` join table only. **`posts.like_count` is owned by the database:** an
  `after insert or delete` trigger (`sync_post_like_count`) recomputes it from
  `count(*)`, so concurrent clients cannot drift the count. The client never
  writes `like_count` directly.
- `reels` — the reel-compose flow uploads the video to the `reels` bucket and
  inserts a first-class row into the **`reels` table** (`owner`, `video_url`,
  `caption`) via `StorageService.insertReel`, then also surfaces the reel in
  the timeline as a video post. Wiring a gallery/camera picker (the raw byte
  source) is the only remaining step; the upload + DB write are real.
- Storage — `StorageService.uploadAvatar` (bucket `avatars`) and
  `StorageService.uploadReel` (bucket `reels`) via `uploadBinary` +
  `getPublicUrl`.

> **`repost_count` / `reply_count` are now server-owned (migration 0002).**
> Migration 0002 adds a `reposts` join table and a `comments` table, plus
> triggers (`sync_post_repost_count`, `sync_post_reply_count`) that recompute
> `posts.repost_count` / `posts.reply_count` from `count(*)`, mirroring
> `sync_post_like_count`. This retires the client-write `repost_count` drift
> debt that 0001 documented. The Dart client still writes `repost_count`
> optimistically for now; the change to stop writing it (and to insert/delete on
> `reposts` instead) lands in a later increment. Once 0002 is applied and that
> client change ships, the counters are drift-free under concurrent clients.

**Still mock (`lib/data/mock_data.dart`):**

- Conversations / direct messages (`conversations()` / `unreadMessages` /
  `conversationById`) — no messaging table yet.

> Notifications now hydrate from the `notifications` table (with a mock
> fallback), and follow requests / blocks / follow edges persist to
> `public.follows` / `public.blocks`. Mute accounts and mute words remain
> client-authoritative in-memory (no server table this phase). See
> **Phase 2 client wiring** above for the full live-vs-mock breakdown and the
> unverified-live-Supabase caveat.

**Graceful fallback:** the repositories seed their in-memory caches from
`MockData` at construction and hydrate from Supabase asynchronously
(fire-and-forget, guarded). If Supabase is uninitialized, unreachable, or the
user is signed out, the queries are caught and the app keeps showing mock data
instead of failing. This same fallback is what lets the unit tests
(which never boot Supabase) run against `PostRepository()` / `ProfileRepository()`.

### Media upload note

To keep the dependency surface minimal, **no image/file-picker package is
bundled**. `StorageService` provides the upload helpers, and there are clearly
marked scaffold call sites (`compose_screen.dart` for reels,
`profile_screen.dart` for avatars). The **only** missing piece is the raw byte
source (gallery/camera). For reels the rest of the flow is real: once bytes are
supplied, `_uploadReel` uploads to the `reels` bucket, inserts a row into the
`reels` table (`StorageService.insertReel`), and surfaces the reel as a video
post; no picker means it is not yet triggered from a button.

## Tests

Pure logic is covered by unit tests under `test/` (run with `flutter test`):

- `test/format_test.dart` — `fmtCount` K/M/B thresholds and trailing-`.0` trimming; `timeAgo` buckets (`now` / `m` / `h` / `d` / short date).
- `test/post_repository_test.dart` — `forYou` ordering, `following` filtering, `toggleLike` / `toggleRepost` / `toggleBookmark` flipping state and adjusting counts, and `addPost` prepending.
- `test/profile_repository_test.dart` — notification/conversation ordering, unread counts, `markNotificationsRead`, and `updateProfile`.
- `test/safety_repository_test.dart` — block/mute idempotence + single-notify, report validation, and the pure `filterHidden` feed filter (identity on empty sets).
- `test/relationship_repository_test.dart` — the `follow` status decision (public → following, private → requested), `unfollow`, `acceptFollowRequest` / `denyFollowRequest` removing pending requests, all single-notify + idempotent.
- `test/mute_words_test.dart` — the pure `contentMatchesMuteWords` matcher (case-insensitive, word-boundary aware, empty set matches nothing), `addMuteWord` / `removeMuteWord` normalize + de-dupe + notify-once, and mute-word feed hiding via `filterHidden`.

Like the rest of the project, these were authored by hand and have not been executed in-sandbox (no Dart toolchain); run `flutter test` on a Flutter-equipped machine.

## Dependencies

Minimal and mainstream only:

- `cupertino_icons`
- `google_fonts` (Inter)
- `intl`
- `supabase_flutter` (auth, database, and storage; `^2.5.0`)

### Offline typography

The target device may be offline, and `google_fonts` fetches Inter from Google's
CDN at runtime. Rather than bundle a binary `.ttf` (not authorable in this
sandbox), every style in `lib/theme/app_text_styles.dart` declares a
`fontFamilyFallback` chain to platform system-sans families (Roboto, San
Francisco, Helvetica Neue, Arial, `sans-serif`). When Inter can be fetched the
intended Chirp-like type renders; when offline the type degrades gracefully to a
clean system sans instead of disappearing. `AppTextStyles.configureFonts()` is
called from `main()` to set up google_fonts' runtime-fetch behavior.
