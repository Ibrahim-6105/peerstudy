// Serialization tests for the Supabase-backed Community models.
//
// These tests use plain maps only, so they never contact the hosted database.

import 'package:flutter_test/flutter_test.dart';
import 'package:peerstudy/models/community_attachment.dart';
import 'package:peerstudy/providers/academic_provider.dart';

void main() {
  // One exact UTC time keeps every date assertion deterministic.
  final createdAt = DateTime.utc(2026, 8, 22, 12, 30, 45);

  group('CommunityPost Supabase serialization', () {
    test('round-trips ownership and administrator audit fields', () {
      // Attachment metadata is loaded separately and combined with the post.
      final attachment = CommunityAttachment(
        id: 'attachment-1',
        postId: 'post-1',
        uploadedBy: '22222222-2222-4222-8222-222222222222',
        fileName: 'lesson.pdf',
        storagePath: 'private/path/lesson.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 1024,
        status: 'ready',
        createdAt: createdAt,
      );
      final post = CommunityPost(
        id: 'post-1',
        communityId: '11111111-1111-4111-8111-111111111111',
        authorId: '22222222-2222-4222-8222-222222222222',
        author: 'Amina Student',
        body: 'A useful academic explanation.',
        createdAt: createdAt,
        updatedAt: createdAt.add(const Duration(minutes: 3)),
        comments: const <CommunityComment>[],
        attachments: <CommunityAttachment>[attachment],
        isReported: true,
      );

      // Supabase/PostgREST rows use snake_case names and ISO-8601 dates.
      final map = post.toSupabaseRow();
      final restored = CommunityPost.fromSupabaseRow(
        map,
        id: post.id,
        attachments: <CommunityAttachment>[attachment],
      );

      expect(restored.id, post.id);
      expect(restored.communityId, post.communityId);
      expect(restored.authorId, post.authorId);
      expect(restored.author, 'Amina Student');
      expect(restored.body, post.body);
      expect(restored.createdAt.isAtSameMomentAs(createdAt), isTrue);
      expect(restored.isReported, isTrue);
      expect(restored.isRemoved, isFalse);
      expect(restored.attachments.single.fileName, 'lesson.pdf');
      expect(map['created_at'], createdAt.toIso8601String());
      expect(map, isNot(contains('createdAt')));
    });
  });

  group('CommunityComment Supabase serialization', () {
    test('round-trips UID ownership and soft-removal audit fields', () {
      // A removed comment remains available for protected report history.
      final comment = CommunityComment(
        id: 'comment-1',
        authorId: '33333333-3333-4333-8333-333333333333',
        author: 'Omar Student',
        body: 'Reply text.',
        createdAt: createdAt,
        attachments: <CommunityAttachment>[
          CommunityAttachment(
            id: 'attachment-2',
            commentId: 'comment-1',
            uploadedBy: '33333333-3333-4333-8333-333333333333',
            fileName: 'answer.png',
            storagePath: 'private/path/answer.png',
            mimeType: 'image/png',
            sizeBytes: 200,
            status: 'ready',
            createdAt: createdAt,
          ),
        ],
        isRemoved: true,
        removedAt: createdAt.add(const Duration(minutes: 5)),
        removedBy: '44444444-4444-4444-8444-444444444444',
        removalReason: 'Removed by admin',
      );

      final map = comment.toSupabaseRow();
      final restored = CommunityComment.fromSupabaseRow(
        map,
        id: comment.id,
        attachments: comment.attachments,
      );

      expect(restored.authorId, comment.authorId);
      expect(restored.isRemoved, isTrue);
      expect(restored.removedBy, comment.removedBy);
      expect(restored.removalReason, 'Removed by admin');
      expect(restored.removedAt, isNotNull);
      expect(restored.attachments.single.commentId, comment.id);
      expect(map['created_at'], createdAt.toIso8601String());
    });
  });

  group('Community report API values', () {
    test('maps every student-facing reason to the database contract', () {
      expect(
        communityReportReasonWireValue(CommunityReportReason.spam),
        'spam',
      );
      expect(
        communityReportReasonWireValue(CommunityReportReason.harassment),
        'harassment',
      );
      expect(
        communityReportReasonWireValue(CommunityReportReason.misinformation),
        'misinformation',
      );
      expect(
        communityReportReasonWireValue(
          CommunityReportReason.inappropriateContent,
        ),
        'inappropriate',
      );
      expect(
        communityReportReasonWireValue(CommunityReportReason.copyright),
        'copyright',
      );
      expect(
        communityReportReasonWireValue(CommunityReportReason.other),
        'other',
      );
    });

    test('parses current, legacy, and unknown values safely', () {
      expect(
        communityReportReasonFromWireValue('inappropriate'),
        CommunityReportReason.inappropriateContent,
      );
      expect(
        communityReportReasonFromWireValue('inappropriateContent'),
        CommunityReportReason.inappropriateContent,
      );
      expect(
        communityReportReasonFromWireValue('future-reason'),
        CommunityReportReason.other,
      );
    });
  });
}
