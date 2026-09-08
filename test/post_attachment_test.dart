import 'package:flutter_test/flutter_test.dart';
import 'package:oneleven/models/post.dart';
import 'package:oneleven/models/post_attachment.dart';
import 'package:oneleven/models/user_profile.dart';

PostAttachment _att(String id, int position, AttachmentType type) =>
    PostAttachment(
      id: id,
      postId: 'p1',
      position: position,
      type: type,
      url: 'https://example.com/$id',
    );

void main() {
  group('deriveKind', () {
    test('0 attachments => text', () {
      expect(deriveKind(const <PostAttachment>[]), PostKind.text);
    });

    test('1 image => image', () {
      expect(
        deriveKind(<PostAttachment>[_att('a0', 0, AttachmentType.image)]),
        PostKind.image,
      );
    });

    test('1 video => video', () {
      expect(
        deriveKind(<PostAttachment>[_att('a0', 0, AttachmentType.video)]),
        PostKind.video,
      );
    });

    test('more than 1 => carousel (even mixed types)', () {
      expect(
        deriveKind(<PostAttachment>[
          _att('a0', 0, AttachmentType.image),
          _att('a1', 1, AttachmentType.image),
          _att('a2', 2, AttachmentType.image),
        ]),
        PostKind.carousel,
      );
      expect(
        deriveKind(<PostAttachment>[
          _att('a0', 0, AttachmentType.image),
          _att('a1', 1, AttachmentType.video),
        ]),
        PostKind.carousel,
      );
    });
  });

  group('PostAttachment copyWith', () {
    test('overrides only the provided fields', () {
      final a = _att('a0', 0, AttachmentType.image);
      final b = a.copyWith(id: 'a1', postId: 'p2', position: 3);
      expect(b.id, 'a1');
      expect(b.postId, 'p2');
      expect(b.position, 3);
      // Unchanged fields carry over.
      expect(b.type, AttachmentType.image);
      expect(b.url, a.url);
    });

    test('carries optional metadata', () {
      final a = _att('a0', 0, AttachmentType.image).copyWith(
        thumbUrl: 'https://example.com/thumb',
        width: 900,
        height: 600,
        altText: 'a harbor at dusk',
      );
      expect(a.thumbUrl, 'https://example.com/thumb');
      expect(a.width, 900);
      expect(a.height, 600);
      expect(a.altText, 'a harbor at dusk');
    });
  });

  group('PostAttachment equality', () {
    test('is id-based (like the other immutable models)', () {
      final a = _att('a0', 0, AttachmentType.image);
      final b = _att('a0', 9, AttachmentType.video); // same id, different fields
      final c = _att('a1', 0, AttachmentType.image);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  group('Post kind derivation via the constructor', () {
    test('an explicit attachments list drives kind', () {
      final post = Post(
        id: 'x1',
        author: const _StubProfile().profile,
        content: 'hi',
        attachments: <PostAttachment>[
          _att('a0', 0, AttachmentType.image).copyWith(postId: 'x1'),
          _att('a1', 1, AttachmentType.image).copyWith(postId: 'x1'),
        ],
        createdAt: DateTime(2024),
      );
      expect(post.kind, PostKind.carousel);
      expect(post.attachments.length, 2);
      // Legacy shim reflects attachments.first.
      expect(post.mediaUrl, post.attachments.first.url);
      expect(post.mediaType, MediaType.image);
    });

    test('legacy mediaUrl/mediaType constructor builds a single attachment', () {
      final post = Post(
        id: 'x2',
        author: const _StubProfile().profile,
        content: 'hi',
        mediaUrl: 'https://example.com/one.jpg',
        mediaType: MediaType.image,
        createdAt: DateTime(2024),
      );
      expect(post.kind, PostKind.image);
      expect(post.attachments.single.url, 'https://example.com/one.jpg');
      expect(post.hasMedia, isTrue);
    });

    test('no media => text with empty attachments and null shim', () {
      final post = Post(
        id: 'x3',
        author: const _StubProfile().profile,
        content: 'just text',
        createdAt: DateTime(2024),
      );
      expect(post.kind, PostKind.text);
      expect(post.attachments, isEmpty);
      expect(post.hasMedia, isFalse);
      expect(post.mediaUrl, isNull);
      expect(post.mediaType, MediaType.none);
    });

    test('copyWith with new attachments re-derives kind', () {
      final post = Post(
        id: 'x4',
        author: const _StubProfile().profile,
        content: 'hi',
        createdAt: DateTime(2024),
      );
      expect(post.kind, PostKind.text);
      final withImage = post.copyWith(
        attachments: <PostAttachment>[
          _att('a0', 0, AttachmentType.image).copyWith(postId: 'x4'),
        ],
      );
      expect(withImage.kind, PostKind.image);
    });
  });
}

/// A tiny stub author so these model tests do not depend on MockData.
class _StubProfile {
  const _StubProfile();
  UserProfile get profile =>
      const UserProfile(id: 'u1', username: 'u', displayName: 'U');
}
