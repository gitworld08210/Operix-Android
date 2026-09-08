# Oneleven

A modern-X (current Twitter/X) styled social and creator app for Android, built with Flutter.

Oneleven is dark-first: true-black background, X-blue accent (`#1D9BF0`), clean Inter/Chirp-like sans, no gradients or glassmorphism.

## Status

> **Not compiled in this environment.** This project was authored **by hand without an available Flutter/Dart/Android toolchain and with no network access**, so it has **not** been compiled, analyzed, or run in-sandbox. A developer must run `flutter pub get` and `flutter run` on a Flutter-equipped machine to build, verify, and launch it. Every file was written and cross-checked manually; treat the first real `flutter analyze` as the source of truth.

The app is feature-complete for a first pass across three increments:

- **FEAT-001 (foundation):** standard Flutter project files, a complete `android/` Gradle scaffold (namespace / applicationId `com.oneleven.app`, label "Oneleven"), the centralized theme (`lib/theme/`), the data models (`lib/models/`), and in-memory mock repositories with sample data (`lib/data/`).
- **FEAT-002 (UI):** `lib/main.dart`, reusable widgets (`lib/widgets/`), and all screens (`lib/screens/`) wired to the repositories, plus the Supabase email-OTP auth screen (`lib/screens/auth_screen.dart`) and auth gate.
- **FEAT-003 (Supabase backend):** `lib/supabase_config.dart`, `lib/data/auth_repository.dart`, `lib/data/storage_service.dart`, the `supabase/migrations/` schema, and the fully Supabase-backed repositories (`PostRepository`, `ProfileRepository`, `NotificationRepository`, `MessageRepository`) with explicit load-state and no mock fallback. See **Backend (Supabase)** below.

## Folder structure

```
oneleven_app/
  android/                     # Gradle scaffold (com.oneleven.app, label "Oneleven")
  lib/
    main.dart                  # App entry; MaterialApp + dark theme + home shell
    theme/                     # app_colors, app_text_styles, app_theme (+ spacing/radii)
    models/                    # post, user_profile, notification_item, conversation
    data/                      # post/profile/notification/message/auth repositories (ChangeNotifier singletons), load_status, storage_service
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
- **PostCard** mirroring the web design: avatar + content columns, bold display name + verification badge + `@handle` + relative time + more menu, `#hashtag` / `@mention` linkification in X-blue, "Show more" truncation, optional rounded media (image, or a play-icon placeholder for video), and the full action row (Reply, Repost, Like, Views, Bookmark, Share). All `Image.network` calls have loading + error fallbacks so a blocked network never crashes the app.
- **Search / Explore:** search field, trending chips, and a "Trends for you" list.
- **Compose:** author avatar, multiline field, mock media/GIF/poll toolbar, character counter, and a Post button that adds to the feed.
- **Notifications:** typed activity rows (like / reply / repost / follow / mention) with unread highlighting and "Mark all read".
- **Messages + Conversation:** thread list with unread dots, and a chat view with left/right bubbles and a local send composer.
- **Profile:** banner, overlapping avatar, name + badge, bio, follower/following counts, Edit/Follow button, and Posts / Media tabs.

**Out of scope for this Android app (not built):** Wallet, Premium, Verification purchase flow, Creator Hub, and Live. Media attachment, replies, and share are intentionally mocked (they surface a snackbar).

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

### Data layer (fully Supabase-backed)

As of the data-layer rebuild there is **no `MockData` fallback**. Every
repository is a `ChangeNotifier` singleton that starts empty in a
`LoadStatus.idle` state (see `lib/data/load_status.dart`), loads from Supabase
via `load()` after sign-in, and exposes a real `loading` / `loaded` / `error`
status plus an empty-state (a `loaded` status with an empty cache is a genuine
"no data yet", not an error). `main.dart`'s `AuthGate` calls `load()` on every
repository after sign-in and `clear()` on sign-out, so a fresh login never
shows a previous user's cache.

- **Auth** — email OTP sign-up / login / sign-out.
- **`profiles`** (`ProfileRepository`) — `currentUser` / `profiles` load from
  the `profiles` table; `updateProfile` persists `display_name` / `bio`
  (optimistic, reverts on failure). Real follow/unfollow via `toggleFollow`
  (insert/delete in `follows`, never writing the DB-owned follower/following
  counters), plus `isFollowing`, `followingIds`, `profileById`,
  `profileByUsername`.
- **`posts`** (`PostRepository`) — the main feed loads **top-level posts only**
  (`parent_id is null`) joining `profiles` for the author, then hydrates the
  current user's `liked` / `reposted` / `bookmarked` flags. `following()`
  filters to authors the user actually follows (from the `follows` table).
  Composing a post inserts into `posts` with a **client-generated UUID**
  (`lib/utils/ids.dart`) so the in-memory id equals the DB row id.
- **`likes` / `reposts` / `bookmarks`** — `toggleLike` / `toggleRepost` /
  `toggleBookmark` are optimistic then insert/delete rows in the corresponding
  join table, reverting the optimistic change and surfacing `lastError` on
  failure. **The DB owns `like_count` / `repost_count` / `reply_count`**
  (recompute-from-`count(*)` triggers); the client never writes those columns.
- **Replies** — `replies(parentId)` loads child posts; `addReply` inserts a
  `posts` row with `parent_id` set. The parent's `reply_count` is
  trigger-maintained.
- **Notifications** (`NotificationRepository`) — loads the current user's
  `notifications` (joined to the actor profile), exposes `unreadNotifications`
  and `markNotificationsRead`, and `createNotification(...)` is fired as a side
  effect of like/reply/repost/follow (self-notifications are skipped per the
  `actor <> recipient` RLS rule).
- **Direct messages** (`MessageRepository`) — loads the conversations the user
  participates in (with the other participant's profile and per-user unread),
  `loadMessages`, `sendMessage`, `openOrCreateConversationWith`, and
  `resetUnread`. `Message.fromMe` is derived by comparing `messages.sender` to
  the current auth uid. `last_preview` / `updated_at` / `unread` are
  trigger-maintained.
- **`reels`** — the reel-compose flow uploads the video to the `reels` bucket
  and inserts a first-class row into the **`reels` table** via
  `StorageService.insertReel`, then surfaces the reel as a video post. Wiring a
  gallery/camera picker (the raw byte source) is the only remaining step.
- **Storage** — `StorageService.uploadAvatar` (bucket `avatars`) and
  `StorageService.uploadReel` (bucket `reels`).

### Backend schema extension — `0002_backend.sql` / `0003_harden_functions.sql`

The initial `0001_init.sql` covered `profiles`, `posts`, `reels`, `likes`,
`follows`. `0002_backend.sql` extends the backend so the previously mock-only
features have real tables, and `0003_harden_functions.sql` locks down the
`SECURITY DEFINER` trigger functions (revokes their RPC `EXECUTE` so they can
only run from their triggers, clearing the database-linter warnings). Added:

- **Replies** — `posts.parent_id` (self-referencing FK); a trigger
  (`sync_post_reply_count`) keeps `posts.reply_count` server-authoritative.
- **Reposts** — `reposts` join table + `sync_post_repost_count` trigger.
- **Bookmarks** — `bookmarks` join table (**private:** owner-scoped SELECT), so
  `Post.bookmarked` can persist per user.
- **Follower/following counts** — `sync_follow_counts` trigger keeps
  `profiles.followers` / `profiles.following` in sync from `follows`.
- **Notifications** — `notifications` table + `notification_type` enum
  (`like`/`reply`/`repost`/`follow`/`mention`), recipient-scoped RLS.
- **Direct messages** — `conversations`, `conversation_participants`, and
  `messages` tables with participant-scoped RLS (via the
  `is_conversation_participant` helper). A `handle_new_message` trigger updates
  the conversation preview/`updated_at` and bumps each recipient's `unread`.

All tables have RLS enabled. The migrations have been applied to the hosted
Oneleven project and verified end-to-end (new-user, like/reply/repost/follow
counters, and message unread all confirmed via a smoke test).

### Data-layer extension — `0004`–`0006`

`0004_search_realtime_indexes.sql` adds the search + realtime plumbing the
Supabase-backed data layer needs: a `pg_trgm` extension (in the `extensions`
schema) with GIN trigram indexes on `profiles.username` / `profiles.display_name`
/ `posts.content`; two `SECURITY INVOKER` search RPCs (`search_profiles`,
`search_posts`, both with a fixed `search_path` and granted to `authenticated`
only); FK-covering indexes on `likes` / `reposts` / `bookmarks` (`post_id`),
`follows` (`followee`), `messages` (`sender`), and `notifications`
(`actor` / `post_id`); and membership of `posts`, `messages`, `notifications`,
`conversations`, and `conversation_participants` in the `supabase_realtime`
publication.

`0005_optimize_rls_initplan.sql` addresses the performance advisor: it wraps
`auth.uid()` in `(select auth.uid())` across every RLS policy (so it is
evaluated once per statement rather than once per row) and adds a covering
index on `reels.owner`.

`0006_profile_embed_fkeys.sql` adds foreign keys from `posts.owner`,
`notifications.actor`, `conversation_participants.user_id`, and
`messages.sender` to `public.profiles(id)` (alongside the existing
`auth.users(id)` FKs) so PostgREST can embed the author/actor/participant
profile (`select('*, profiles(*)')`).

After each DDL change the security and performance advisors were re-run. The
remaining findings are pre-existing and justified: the `is_conversation_participant`
and Supabase-managed `rls_auto_enable` `SECURITY DEFINER` warnings (the former
must stay `EXECUTE`-able by `authenticated` because it is used inside RLS
policies), and `unused_index` INFO notices (expected while the tables are still
empty; the indexes back queries the app issues at runtime).

**Unit tests** exercise the offline-safe surface of the repositories (initial
`idle` / empty state, unknown-id toggles returning null, and `clear()`); the
Supabase-dependent paths are verified manually / via the MCP tooling because
the tests never boot a Supabase client.

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
