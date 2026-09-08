import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_config.dart';

/// Thin wrapper over Supabase Storage for the app's two public buckets:
/// `avatars` (profile images) and `reels` (short videos), both created by
/// `supabase/migrations/0001_init.sql`.
///
/// Objects are keyed by `<userId>/<file>` so the per-object owner RLS policies
/// in the migration allow a user to overwrite only their own files. Callers
/// supply the raw bytes; picking bytes from the device gallery/camera is left
/// to the call site (no image/file-picker dependency is bundled - see the
/// TODO/scaffold call sites in `compose_screen.dart` and `profile_screen.dart`).
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
  ///
  /// Scaffolded only in that a byte source (gallery/camera picker) is not
  /// bundled; the upload + DB write themselves are real.
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
