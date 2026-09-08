import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_config.dart';

/// Thin wrapper over Supabase Storage for the app's public buckets:
/// `avatars` (profile images), `reels` (short videos), and `post-media`
/// (images attached to posts). `avatars` / `reels` are created by
/// `supabase/migrations/0001_init.sql`; `post-media` by
/// `supabase/migrations/0008_post_media_bucket.sql`.
///
/// Objects are keyed by `<userId>/<file>` so the per-object owner RLS policies
/// in the migrations allow a user to overwrite only their own files. Callers
/// supply the raw bytes; the byte source (gallery/camera) is wired at the call
/// sites via `image_picker` (see `compose_screen.dart` and
/// `profile_screen.dart`).
///
/// Reel metadata (owner, video_url, caption) is persisted into the first-class
/// `public.reels` table via [insertReel]; the `reels` bucket holds only the
/// video bytes.
abstract final class StorageService {
  const StorageService._();

  /// Uploads (or overwrites) the current user's avatar and returns its public
  /// URL. Store the returned URL on `profiles.avatar_url`.
  static Future<String> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    String ext = 'jpg',
  }) async {
    const bucket = 'avatars';
    final path = '$userId/avatar.$ext';
    await supabase.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return supabase.storage.from(bucket).getPublicUrl(path);
  }

  /// Uploads a reel video for the current user and returns its public URL.
  ///
  /// This stores only the video bytes in the `reels` bucket. The reel's
  /// metadata (owner, url, caption) belongs in the `reels` table: call
  /// [insertReel] with the returned URL to persist it there. The compose reel
  /// flow (`compose_screen.dart`) does both, so the `reels` table is the real
  /// home for reel metadata rather than dead schema.
  static Future<String> uploadReel({
    required String userId,
    required Uint8List bytes,
    String ext = 'mp4',
  }) async {
    const bucket = 'reels';
    // A unique key per upload so multiple reels per user do not collide.
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await supabase.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return supabase.storage.from(bucket).getPublicUrl(path);
  }

  /// Uploads an image attached to a post for the current user and returns its
  /// public URL. Store the returned URL on `posts.media_url` (with
  /// `media_type = 'image'`).
  ///
  /// Uses the dedicated public `post-media` bucket (see
  /// `supabase/migrations/0008_post_media_bucket.sql`) so post images are kept
  /// separate from `avatars` and `reels`. A unique key per upload lets a user
  /// attach many images without collisions.
  static Future<String> uploadPostImage({
    required String userId,
    required Uint8List bytes,
    String ext = 'jpg',
  }) async {
    const bucket = 'post-media';
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await supabase.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return supabase.storage.from(bucket).getPublicUrl(path);
  }

  /// Inserts a row into the first-class `public.reels` table so reel metadata
  /// lives in its own table (not just as an object in the `reels` bucket or a
  /// `posts` row). `owner` must equal the acting user for the RLS insert
  /// policy to allow the write.
  ///
  /// Fire-and-forget friendly: fully guarded so it never throws into the UI
  /// (e.g. when Supabase is uninitialized under tests or the user is signed
  /// out), matching the repositories' pattern.
  static Future<void> insertReel({
    required String userId,
    required String videoUrl,
    String caption = '',
    String? thumbUrl,
  }) async {
    try {
      await supabase.from('reels').insert(<String, dynamic>{
        'owner': userId,
        'video_url': videoUrl,
        'thumb_url': thumbUrl,
        'caption': caption,
      });
    } catch (_) {
      // Ignore persistence failures; the video bytes are already uploaded and
      // the reel is surfaced locally as a video post.
    }
  }
}
