// Unit tests for Community attachment metadata and local file validation.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerstudy/models/community_attachment.dart';

void main() {
  group('Community attachment validation', () {
    test('accepts every reviewed extension with its exact MIME type', () {
      expect(
        communityAttachmentMimeTypeForFileName('lecture.PDF'),
        'application/pdf',
      );
      expect(
        communityAttachmentMimeTypeForFileName('diagram.jpeg'),
        'image/jpeg',
      );
      expect(communityAttachmentMimeTypeForFileName('archive.docx'), isNull);
      expect(
        validateCommunityAttachment(fileName: 'notes.txt', sizeBytes: 12),
        isNull,
      );
    });

    test('rejects unsupported, empty, unsafe, and oversized files', () {
      expect(
        validateCommunityAttachment(fileName: 'program.exe', sizeBytes: 20),
        contains('JPG'),
      );
      expect(
        validateCommunityAttachment(fileName: 'empty.pdf', sizeBytes: 0),
        contains('empty'),
      );
      expect(
        validateCommunityAttachment(fileName: '../notes.pdf', sizeBytes: 20),
        contains('simple name'),
      );
      expect(
        validateCommunityAttachment(
          fileName: 'large.pdf',
          sizeBytes: communityAttachmentMaxBytes + 1,
        ),
        contains('10 MB'),
      );
    });

    test('draft size always comes from its real bytes', () {
      final draft = CommunityAttachmentDraft(
        idempotencyKey: '11111111-1111-4111-8111-111111111111',
        fileName: 'photo.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      );
      expect(draft.sizeBytes, 4);
      expect(draft.idempotencyKey, '11111111-1111-4111-8111-111111111111');
    });
  });

  group('Community attachment metadata', () {
    test('round-trips private snake_case metadata without a public URL', () {
      final attachment = CommunityAttachment(
        id: '11111111-1111-4111-8111-111111111111',
        postId: '22222222-2222-4222-8222-222222222222',
        uploadedBy: '33333333-3333-4333-8333-333333333333',
        fileName: 'week-one.pdf',
        storagePath: 'private/server/generated/path.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 2048,
        status: 'ready',
        createdAt: DateTime.utc(2026, 8, 30, 8),
      );

      final row = attachment.toSupabaseRow()..['id'] = attachment.id;
      final restored = CommunityAttachment.fromSupabaseRow(row);

      expect(restored.id, attachment.id);
      expect(restored.postId, attachment.postId);
      expect(restored.commentId, isNull);
      expect(restored.isReady, isTrue);
      expect(restored.fileName, 'week-one.pdf');
      expect(row, isNot(contains('signed_url')));
      expect(row, isNot(contains('public_url')));
    });

    test('formats compact student-facing file sizes', () {
      expect(formatCommunityAttachmentSize(500), '500 B');
      expect(formatCommunityAttachmentSize(2048), '2.0 KB');
      expect(formatCommunityAttachmentSize(2 * 1024 * 1024), '2.0 MB');
    });
  });
}
