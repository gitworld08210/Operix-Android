# Oneleven

A modern-X (current Twitter/X) styled social and creator app for Android, built with Flutter.

Oneleven is dark-first: true-black background, X-blue accent (`#1D9BF0`), clean Inter/Chirp-like sans, no gradients or glassmorphism.

## Status

> **Not compiled in this environment.** This project was authored **by hand without an available Flutter/Dart/Android toolchain and with no network access**, so it has **not** been compiled, analyzed, or run in-sandbox. A developer must run `flutter pub get` and `flutter run` on a Flutter-equipped machine to build, verify, and launch it. Every file was written and cross-checked manually; treat the first real `flutter analyze` as the source of truth.
>
> **CI builds the APK.** A GitHub Actions workflow (`.github/workflows/android.yml`) runs `flutter pub get` / `analyze` / `test` and `flutter build apk --release` on every push and pull request (and via manual dispatch), then uploads the APK as a downloadable build artifact (`oneleven-release-apk`). It needs no secrets: `lib/supabase_config.dart` bakes in the public Supabase URL + publishable key defaults (optional `SUPABASE_URL` / `SUPABASE_ANON_KEY` repo secrets override them via `--dart-define`). This is where the APK actually compiles. See [Building the APK](#building-the-apk).

The app is a fully Supabase-backed social app. It was built across an initial UI/backend pass and then a de-mock rebuild that removed the last of the in-memory sample data:

- **UI + backend foundation:** standard Flutter project files, a complete `android/` Gradle scaffold (namespace / applicationId `com.oneleven.app`, label "Oneleven"), the centralized theme (`lib/theme/`), the data models (`lib/models/`), `lib/main.dart`, reusable widgets (`lib/widgets/`), all screens (`lib/screens/`), the Supabase email-OTP auth screen + auth gate, `lib/supabase_config.dart`, `lib/data/auth_repository.dart`, `lib/data/storage_service.dart`, and the `supabase/migrations/` schema.
- **Data-layer de-mock:** `lib/data/mock_data.dart` was **deleted**. Every repository (`PostRepository`, `ProfileRepository`, `NotificationRepository`, `MessageRepository`) is now 100% Supabase-backed with explicit load-state (`lib/data/load_status.dart`) and **no mock fallback**. Row -> model parsing lives in pure helpers (`lib/data/mappers.dart`) so it is unit-testable without a client.
- **Content + notifications + DMs:** post detail with threaded replies, a real bookmarks screen, real follow/unfollow, DB-backed search RPCs, start-a-DM from a profile, real notifications, and Supabase Realtime on posts/messages/notifications/conversations. See **Backend (Supabase)** below.

## Folder structure

```
oneleven_app/
  android/                     # Gradle scaffold (com.oneleven.app, label "Oneleven")
  lib/
    main.dart                  # App entry; MaterialApp + dark theme + home shell
    theme/                     # app_colors, app_text_styles, app_theme (+ spacing/radii)
    models/                    # post, user_profile, notification_item, conversation
    data/                      # post/profile/notification/message/auth repositories (ChangeNotifier singletons),
                               #   load_status, mappers (pure row->model helpers), storage_service
    supabase_config.dart       # Supabase URL/anon-key + initSupabase()
    utils/                     # format.dart (fmtCount, timeAgo), ids.dart (client UUIDs)
    widgets/                   # avatar, verified_badge, action_button, post_card, app_scaffold
    screens/                   # home_feed, search, compose, notifications, messages,
                               #   conversation, profile, post_detail, bookmarks
```

## Implemented vs scaffold

**Implemented (functional against live Supabase data):**

- Bottom navigation shell with 5 destinations: Home, Search, Compose, Notifications, Messages. Compose opens a full-screen modal route; Profile is reachable from the Home top-bar avatar. Unread badges on Notifications / Messages reflect the real `NotificationRepository.unreadNotifications` and `MessageRepository.unreadMessages`.
- **Home feed** with **For You / Following** tabs, listing `PostCard`s from `PostRepository`. Each tab renders real **loading / empty / error (+ Retry)** states off `repo.status` and supports pull-to-refresh. Like / Repost / Bookmark write to their join tables and reflect the DB-owned counts. **Following** filters to authors the signed-in user actually follows.
- **PostCard** mirroring the web design: avatar + content columns, bold display name + verification badge + `@handle` + relative time + more menu, `#hashtag` / `@mention` linkification in X-blue, "Show more" truncation, optional rounded media (image, or a play-icon placeholder for video), and the full action row (Reply, Repost, Like, Views, Bookmark, Share). Tapping a post opens the **post detail**; tapping an author opens their real profile. All `Image.network` calls have loading + error fallbacks so a blocked network never crashes the app.
- **Post detail + replies** (`post_detail_screen.dart`): the parent post plus its threaded replies (`PostRepository.replies`) with loading/empty/error, and a reply composer that inserts a real reply (`addReply`, sets `parent_id`); the parent `reply_count` follows the DB trigger. **Share** copies a post link to the clipboard (pure Flutter SDK, no share package).
- **Search / Explore:** a debounced field backed by the DB. People come from the `search_profiles` RPC and posts from the `search_posts` RPC; results navigate to real profiles / post detail. The idle state shows suggested people to follow. Real loading / no-results / error states. **No fabricated trends.**
- **Compose:** author avatar, multiline field, a media button that attaches a photo (gallery/camera) or a video (uploaded as a reel) via `image_picker`, an image preview, character counter, and a Post button that uploads any attached image to the `post-media` bucket then inserts a real `posts` row (with `media_url` / `media_type`) and reloads the feed so DB defaults/counters are authoritative.
- **Notifications:** typed activity rows (like / reply / repost / follow / mention) from the `notifications` table with unread highlighting, real "Mark all read" (a DB update), tap-to-navigate to the target post/profile, and live realtime inserts.
- **Messages + Conversation:** the thread list and chat view read/write the `conversations` / `conversation_participants` / `messages` tables. Sending inserts a real message row (preview/updated_at/unread are trigger-maintained); bubble side derives from `Message.fromMe`; a **Message** button on other users' profiles starts a new DM. Realtime keeps threads and unread badges live.
- **Bookmarks** (`bookmarks_screen.dart`): the signed-in user's bookmarked posts, reachable from their profile.
- **Profile:** Supabase-backed for **any** user: banner, overlapping avatar, name + badge, bio, follower/following counts, a real Follow/Following button (`toggleFollow`) for other users or Edit profile (name/bio persist) plus tap-to-change avatar (picked via `image_picker`, uploaded to the `avatars` bucket) for the current user, and Posts / Media tabs reading that profile's real posts.

**Out of scope for this Android app (not built):** Wallet, Premium, Verification purchase flow, Creator Hub, and Live. Media picking (avatar / post image / reel video) is now fully wired via `image_picker`; see [Media upload note](#media-upload-note). There are no mock placeholders and no "not available in this demo" snackbars for the core feed / reply / share / follow / search / DM actions.

## Web-only surfaces (excluded from Android)

**Ads Manager** and **Admin-OS** are **web-only** and are intentionally **not** part of this Android Flutter app. They remain in the React/Vite web project only.

## Building the APK

Locally, on a Flutter-equipped machine (Flutter `>=3.22`, Dart `>=3.3`, JDK 17
for the Android toolchain):

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```

The release build is debug-signed (see `android/app/build.gradle`), so it
produces an installable APK without any signing secrets. Supabase config has
public defaults baked into `lib/supabase_config.dart`; override them if needed
with `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.

In CI, `.github/workflows/android.yml` runs the same steps on every push /
pull request (and on manual `workflow_dispatch`) and publishes the APK as the
`oneleven-release-apk` artifact on the workflow run, so you can download it
straight from the GitHub Actions tab without a local toolchain.

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
- **`reels`** — the reel-compose flow picks a video with `image_picker`,
  uploads it to the `reels` bucket, and inserts a first-class row into the
  **`reels` table** via `StorageService.insertReel`, then surfaces the reel as a
  video post.
- **Storage** — `StorageService.uploadAvatar` (bucket `avatars`),
  `StorageService.uploadReel` (bucket `reels`), and
  `StorageService.uploadPostImage` (bucket `post-media`, for images attached to
  posts).

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

**Unit tests** were rewritten for the no-mock architecture. The old tests
depended on the deleted `MockData` seed; they now exercise the offline-safe
surface of the repositories (initial `idle` / empty state, unknown-id toggles
returning null, `clear()`) plus the pure row -> model mapping in
`lib/data/mappers.dart` (see the **Tests** section). The Supabase-dependent
paths (`load`, `replies`, DM send, notifications) are verified manually / via
the MCP tooling because the tests never boot a Supabase client.

### Media upload note

Media picking is now **fully wired** with the [`image_picker`](https://pub.dev/packages/image_picker)
package (`^1.1.2`), so the previous byte-source seam is closed:

- **Avatar** (`profile_screen.dart`) — tapping the current user's profile photo
  opens the gallery, uploads the picked image via `StorageService.uploadAvatar`
  (bucket `avatars`), and persists the returned public URL onto
  `profiles.avatar_url` through `ProfileRepository.updateProfile(avatarUrl:)`,
  then reloads the profile.
- **Post image** (`compose_screen.dart`) — the media button offers a photo
  (gallery or camera); the picked image is previewed, then uploaded to the
  dedicated public **`post-media`** bucket via
  `StorageService.uploadPostImage` on Post, and the post row is created with
  `media_url` + `media_type = image`.
- **Reel video** (`compose_screen.dart`) — picking a video (gallery) uploads it
  to the `reels` bucket, inserts a first-class row into the `reels` table
  (`StorageService.insertReel`), and surfaces it as a video post.

The `post-media` bucket is created by `supabase/migrations/0008_post_media_bucket.sql`
with owner-scoped write RLS (objects keyed `<userId>/<file>`) mirroring the
`avatars` / `reels` buckets; reads are public via the CDN. Android permissions
for camera capture (`CAMERA`) and Android 13+ media reads
(`READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO`) are declared in the manifest.

## Tests

Pure, network-independent logic is covered by unit tests under `test/` (run
with `flutter test`). Because the repositories are now fully Supabase-backed
with no mock fallback, the tests never boot a client; they target only pure /
synchronous logic:

- `test/format_test.dart` — `fmtCount` K/M/B thresholds and trailing-`.0` trimming; `timeAgo` buckets (`now` / `m` / `h` / `d` / short date). Unchanged.
- `test/mappers_test.dart` — the pure row -> model helpers in `lib/data/mappers.dart`: `asInt` / `parseDate` coercion, `mediaTypeFromName` / `notificationTypeFromName` enum mapping, `profileFromRow` (including the unknown-profile fallback), `postFromRow` (joined author + DB-owned counters, never deriving engagement flags), `notificationFromRow`, and `messageFromRow` **`fromMe` derivation** (sender vs current uid, including signed-out).
- `test/post_repository_test.dart` — the offline-safe `PostRepository` surface: it starts `idle` with empty `forYou` / `following`, returns unmodifiable views, `toggleLike` / `toggleRepost` / `toggleBookmark` return null for an unknown id without touching the network, and `clear()` resets and notifies.
- `test/profile_repository_test.dart` — the offline-safe `ProfileRepository` surface: `idle` with no `currentUser` / empty `profiles`, `isFollowing` false before loading, unmodifiable `profiles` view, and `clear()`.

`MockData` was removed, so no test references `package:oneleven/data/mock_data.dart`. Like the rest of the project, these tests were authored by hand and have **not** been executed in-sandbox (no Dart toolchain); run `flutter test` on a Flutter-equipped machine, which is the source of truth.

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
