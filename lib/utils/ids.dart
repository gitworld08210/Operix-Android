import 'dart:math';

/// ID helpers shared across the app.
///
/// The `posts` table's primary key is `uuid primary key default
/// gen_random_uuid()`. When we compose a post we generate the UUID
/// client-side and insert it explicitly, so the in-memory [Post.id] and the
/// persisted row id agree immediately (no divergence until the next load()).
/// This avoids adding a `uuid` package dependency (deps are kept minimal).
///
/// Generates an RFC 4122 version-4 (random) UUID string, e.g.
/// `f47ac10b-58cc-4372-a567-0e02b2c3d479`. Uses [Random.secure] when
/// available and falls back to a plain [Random] if the platform has no secure
/// source (either is fine for a client-side row id).
String newUuidV4() {
  final rng = _rng;
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));

  // Set the version (4) and variant (RFC 4122) bits.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).toList();
  return '${hex[0]}${hex[1]}${hex[2]}${hex[3]}-'
      '${hex[4]}${hex[5]}-'
      '${hex[6]}${hex[7]}-'
      '${hex[8]}${hex[9]}-'
      '${hex[10]}${hex[11]}${hex[12]}${hex[13]}${hex[14]}${hex[15]}';
}

final Random _rng = _createRng();

Random _createRng() {
  try {
    return Random.secure();
  } catch (_) {
    return Random();
  }
}
