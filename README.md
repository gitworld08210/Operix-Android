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

> **`repost_count` limitation:** there is no `reposts` join table, so
> `repost_count` is still written from the client (`_persistRepostCount`) and
> can drift under concurrent clients (last-writer-wins). A production version
> should add a `reposts` join table plus a trigger mirroring
> `sync_post_like_count`. This is intentionally deferred to keep the schema
> scope minimal for this pass (documented in `0001_init.sql` and the code).

**Still mock (`lib/data/mock_data.dart`):**

- Notifications (`ProfileRepository.notifications()` / `unreadNotifications` /
  `markNotificationsRead`) — no notifications table yet.
- Conversations / direct messages (`conversations()` / `unreadMessages` /
  `conversationById`) — no messaging table yet.

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
