// Supabase-backed Community models and state for PeerStudy.
//
// Beginner note:
// This file intentionally keeps the small models and their database controller
// together. A student can therefore follow the complete Community flow without
// jumping through a deep folder structure.

import 'dart:async';

import 'package:peerstudy/models/community_attachment.dart';
import 'package:peerstudy/models/subject.dart';
import 'package:peerstudy/services/backend_api_service.dart';
import 'package:peerstudy/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Each request loads a bounded page so busy subjects remain fast.
const int defaultCommunityPostLimit = 25;

// Comments are bounded per loaded feed to avoid an unbounded phone download.
const int defaultCommunityCommentLimit = 100;

// CommunityState contains every value needed to draw one subject feed.
class CommunityState {
  // The constructor makes the post list immutable for predictable UI updates.
  CommunityState({
    List<CommunityPost> posts = const <CommunityPost>[],
    this.activeCommunityId,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMorePosts = false,
    this.isLive = false,
    this.errorMessage,
  }) : posts = List<CommunityPost>.unmodifiable(posts);

  // Posts are ordered from newest to oldest.
  final List<CommunityPost> posts;

  // This is the single Community row owned by the selected Subject.
  final String? activeCommunityId;

  // The first load displays a full progress indicator.
  final bool isLoading;

  // Older-page loading uses a smaller button progress state.
  final bool isLoadingMore;

  // This flag tells the screen whether another page could exist.
  final bool hasMorePosts;

  // True means the current rows came from the real Supabase backend.
  final bool isLive;

  // Friendly failures are shown directly by the Community screen.
  final String? errorMessage;

  // copyWith creates a new immutable state after one value changes.
  CommunityState copyWith({
    List<CommunityPost>? posts,
    String? activeCommunityId,
    bool clearActiveCommunity = false,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMorePosts,
    bool? isLive,
    String? errorMessage,
    bool clearError = false,
  }) {
    // Clear flags allow nullable fields to be deliberately reset.
    return CommunityState(
      posts: posts ?? this.posts,
      activeCommunityId: clearActiveCommunity
          ? null
          : activeCommunityId ?? this.activeCommunityId,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMorePosts: hasMorePosts ?? this.hasMorePosts,
      isLive: isLive ?? this.isLive,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

// CommunityPost represents one student post under one Subject Community.
class CommunityPost {
  // The constructor freezes the comment list for predictable UI updates.
  CommunityPost({
    required this.id,
    required this.communityId,
    required this.authorId,
    required this.author,
    required this.body,
    required this.createdAt,
    required List<CommunityComment> comments,
    List<CommunityAttachment> attachments = const <CommunityAttachment>[],
    this.version = 1,
    this.updatedAt,
    this.isReported = false,
    this.isRemoved = false,
    this.removedAt,
    this.removedBy,
    this.removalReason,
  }) : comments = List<CommunityComment>.unmodifiable(comments),
       attachments = List<CommunityAttachment>.unmodifiable(attachments);

  // Supabase UUID for this post.
  final String id;

  // UUID of the one Community owned by the Subject.
  final String communityId;

  // Supabase Auth user UUID used for ownership checks.
  final String authorId;

  // Backend-owned name snapshot shown in the feed.
  final String author;

  // Student-written post text.
  final String body;

  // Canonical database creation time.
  final DateTime createdAt;

  // Canonical time of the most recent edit.
  final DateTime? updatedAt;

  // Real comments loaded from community_comments.
  final List<CommunityComment> comments;

  // Ready private files belonging directly to this post.
  final List<CommunityAttachment> attachments;

  // Optimistic concurrency version owned by PostgreSQL.
  final int version;

  // True after at least one unresolved report targets this post.
  final bool isReported;

  // Soft removal preserves moderation history.
  final bool isRemoved;

  // Canonical removal time, when applicable.
  final DateTime? removedAt;

  // Admin or owner UUID that removed the post.
  final String? removedBy;

  // Human-readable audit reason.
  final String? removalReason;

  // copyWith combines a post with freshly loaded comments.
  CommunityPost copyWith({
    String? body,
    List<CommunityComment>? comments,
    List<CommunityAttachment>? attachments,
    DateTime? updatedAt,
    bool? isReported,
    bool? isRemoved,
    DateTime? removedAt,
    String? removedBy,
    String? removalReason,
    int? version,
  }) {
    // Preserve every unchanged immutable field.
    return CommunityPost(
      id: id,
      communityId: communityId,
      authorId: authorId,
      author: author,
      body: body ?? this.body,
      createdAt: createdAt,
      comments: comments ?? this.comments,
      attachments: attachments ?? this.attachments,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      isReported: isReported ?? this.isReported,
      isRemoved: isRemoved ?? this.isRemoved,
      removedAt: removedAt ?? this.removedAt,
      removedBy: removedBy ?? this.removedBy,
      removalReason: removalReason ?? this.removalReason,
    );
  }

  // Convert this model to the same snake_case shape returned by Supabase.
  Map<String, dynamic> toSupabaseRow() {
    // Dates use the ISO-8601 format returned by PostgREST.
    return <String, dynamic>{
      'community_id': communityId,
      'author_id': authorId,
      'author_name': author,
      'body': body,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt?.toUtc().toIso8601String(),
      'version': version,
      'is_reported': isReported,
      'is_removed': isRemoved,
      'removed_at': removedAt?.toUtc().toIso8601String(),
      'removed_by': removedBy,
      'removal_reason': removalReason,
    };
  }

  // Build one post directly from a Supabase community_posts row.
  factory CommunityPost.fromSupabaseRow(
    Map<String, dynamic> data, {
    required String id,
    String? communityId,
    List<CommunityComment> comments = const <CommunityComment>[],
    List<CommunityAttachment> attachments = const <CommunityAttachment>[],
  }) {
    // Only the current snake_case database fields are accepted.
    return CommunityPost(
      id: id,
      communityId:
          communityId ?? _stringValue(data['community_id'], fallback: ''),
      authorId: _stringValue(data['author_id'], fallback: ''),
      author: _stringValue(data['author_name'], fallback: 'Student'),
      body: _stringValue(data['body'], fallback: ''),
      createdAt: _dateValue(data['created_at']),
      updatedAt: _nullableDate(data['updated_at']),
      comments: comments,
      attachments: attachments,
      version: _positiveInt(data['version'], fallback: 1),
      isReported: _boolValue(data['is_reported']),
      isRemoved: _boolValue(data['is_removed']),
      removedAt: _nullableDate(data['removed_at']),
      removedBy: _nullableString(data['removed_by']),
      removalReason: _nullableString(data['removal_reason']),
    );
  }
}

// CommunityComment represents one student reply under one post.
class CommunityComment {
  // Database and UI fields are all immutable after construction.
  const CommunityComment({
    required this.id,
    required this.authorId,
    required this.author,
    required this.body,
    required this.createdAt,
    this.attachments = const <CommunityAttachment>[],
    this.version = 1,
    this.updatedAt,
    this.isRemoved = false,
    this.removedAt,
    this.removedBy,
    this.removalReason,
  });

  // Supabase UUID for this comment.
  final String id;

  // Supabase Auth UUID used for owner edit/delete checks.
  final String authorId;

  // Backend-owned name snapshot shown beside the reply.
  final String author;

  // Student-written comment text.
  final String body;

  // Canonical database creation time.
  final DateTime createdAt;

  // Ready private files belonging directly to this comment.
  final List<CommunityAttachment> attachments;

  // Concurrency version incremented by PostgreSQL.
  final int version;

  // Canonical latest edit time.
  final DateTime? updatedAt;

  // Soft removal keeps report and audit references valid.
  final bool isRemoved;

  // Canonical removal time.
  final DateTime? removedAt;

  // Owner or Admin UUID that removed the row.
  final String? removedBy;

  // Human-readable audit reason.
  final String? removalReason;

  // copyWith updates only changed comment values.
  CommunityComment copyWith({
    String? body,
    List<CommunityAttachment>? attachments,
    int? version,
    DateTime? updatedAt,
    bool? isRemoved,
    DateTime? removedAt,
    String? removedBy,
    String? removalReason,
  }) {
    // Preserve immutable ownership and creation data.
    return CommunityComment(
      id: id,
      authorId: authorId,
      author: author,
      body: body ?? this.body,
      createdAt: createdAt,
      attachments: attachments ?? this.attachments,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      isRemoved: isRemoved ?? this.isRemoved,
      removedAt: removedAt ?? this.removedAt,
      removedBy: removedBy ?? this.removedBy,
      removalReason: removalReason ?? this.removalReason,
    );
  }

  // Convert this model to the same snake_case shape returned by Supabase.
  Map<String, dynamic> toSupabaseRow() {
    // Dates use the ISO-8601 format returned by PostgREST.
    return <String, dynamic>{
      'author_id': authorId,
      'author_name': author,
      'body': body,
      'created_at': createdAt.toUtc().toIso8601String(),
      'version': version,
      'updated_at': updatedAt?.toUtc().toIso8601String(),
      'is_removed': isRemoved,
      'removed_at': removedAt?.toUtc().toIso8601String(),
      'removed_by': removedBy,
      'removal_reason': removalReason,
    };
  }

  // Build one comment directly from a Supabase community_comments row.
  factory CommunityComment.fromSupabaseRow(
    Map<String, dynamic> data, {
    required String id,
    List<CommunityAttachment> attachments = const <CommunityAttachment>[],
  }) {
    // Only the current snake_case database fields are accepted.
    return CommunityComment(
      id: id,
      authorId: _stringValue(data['author_id'], fallback: ''),
      author: _stringValue(data['author_name'], fallback: 'Student'),
      body: _stringValue(data['body'], fallback: ''),
      createdAt: _dateValue(data['created_at']),
      attachments: attachments,
      version: _positiveInt(data['version'], fallback: 1),
      updatedAt: _nullableDate(data['updated_at']),
      isRemoved: _boolValue(data['is_removed']),
      removedAt: _nullableDate(data['removed_at']),
      removedBy: _nullableString(data['removed_by']),
      removalReason: _nullableString(data['removal_reason']),
    );
  }
}

// The report reasons are the exact values accepted by the backend.
enum CommunityReportReason {
  spam,
  harassment,
  misinformation,
  inappropriateContent,
  copyright,
  other,
}

// Convert a friendly enum value into the PostgreSQL RPC value.
String communityReportReasonWireValue(CommunityReportReason reason) {
  // The backend stores a shorter value for inappropriate content.
  return switch (reason) {
    CommunityReportReason.spam => 'spam',
    CommunityReportReason.harassment => 'harassment',
    CommunityReportReason.misinformation => 'misinformation',
    CommunityReportReason.inappropriateContent => 'inappropriate',
    CommunityReportReason.copyright => 'copyright',
    CommunityReportReason.other => 'other',
  };
}

// Convert stored values back into a safe student-facing enum.
CommunityReportReason communityReportReasonFromWireValue(String? value) {
  // Unknown future values fall back to Other instead of crashing the UI.
  return switch (value?.trim()) {
    'spam' => CommunityReportReason.spam,
    'harassment' => CommunityReportReason.harassment,
    'misinformation' => CommunityReportReason.misinformation,
    'inappropriate' ||
    'inappropriateContent' => CommunityReportReason.inappropriateContent,
    'copyright' => CommunityReportReason.copyright,
    _ => CommunityReportReason.other,
  };
}

// CommunityRepository is a small mutation boundary around BackendApiService.
class CommunityRepository {
  // Tests can inject a backend while production uses the real Supabase gateway.
  CommunityRepository({BackendApiService? backend})
    : backend = backend ?? BackendApiService();

  // All protected writes travel through database RPCs or Edge Functions.
  final BackendApiService backend;

  // Add one text post and return its server-owned UUID.
  Future<String> addPost({
    required String subjectId,
    required String body,
    required String idempotencyKey,
  }) async {
    // The UUID can be used to attach private files after the post exists.
    return backend.createPost(
      subjectId: subjectId,
      body: body,
      idempotencyKey: idempotencyKey,
    );
  }

  // Edit an owned post only at the version shown on screen.
  Future<void> updatePost({
    required String subjectId,
    required String postId,
    required int expectedVersion,
    required String body,
  }) async {
    // PostgreSQL rejects stale versions and non-owners.
    await backend.editPost(
      subjectId: subjectId,
      postId: postId,
      expectedVersion: expectedVersion,
      body: body,
    );
  }

  // Soft-delete an owned post while preserving report history.
  Future<void> removePost({
    required String subjectId,
    required String postId,
    required int expectedVersion,
  }) async {
    // The database performs ownership and status checks atomically.
    await backend.deletePost(
      subjectId: subjectId,
      postId: postId,
      expectedVersion: expectedVersion,
    );
  }

  // Add one comment and return its server-owned UUID.
  Future<String> addComment({
    required String subjectId,
    required String postId,
    required String body,
    required String idempotencyKey,
  }) async {
    // The UUID can be used to attach private files after the comment exists.
    return backend.addComment(
      subjectId: subjectId,
      postId: postId,
      body: body,
      idempotencyKey: idempotencyKey,
    );
  }

  // Edit an owned comment at one exact version.
  Future<void> updateComment({
    required String subjectId,
    required String postId,
    required String commentId,
    required int expectedVersion,
    required String body,
  }) async {
    // The backend owns authorization and concurrency validation.
    await backend.editComment(
      subjectId: subjectId,
      postId: postId,
      commentId: commentId,
      expectedVersion: expectedVersion,
      body: body,
    );
  }

  // Soft-delete an owned comment without breaking report references.
  Future<void> removeComment({
    required String subjectId,
    required String postId,
    required String commentId,
    required int expectedVersion,
  }) async {
    // PostgreSQL confirms ownership before changing the row.
    await backend.deleteComment(
      subjectId: subjectId,
      postId: postId,
      commentId: commentId,
      expectedVersion: expectedVersion,
    );
  }
}

// CommunityController loads, paginates, refreshes, and changes one live feed.
class CommunityController {
  // Dependencies are injectable, while production resolves the shared client.
  CommunityController({
    SupabaseClient? client,
    CommunityRepository? repository,
    this.onChanged,
    this.postLimit = defaultCommunityPostLimit,
    this.commentLimit = defaultCommunityCommentLimit,
  }) : _client = client ?? _clientIfReady(),
       _repository = repository ?? CommunityRepository();

  // The owning StatefulWidget supplies this simple rebuild callback.
  final void Function()? onChanged;

  // This private field holds the latest values shown by the screen.
  CommunityState _state = CommunityState();

  // Screens read the current snapshot through this getter.
  CommunityState get state => _state;

  // Every assignment also asks the ordinary StatefulWidget to rebuild.
  set state(CommunityState value) {
    // Ignore a late database response after the owning page has closed.
    if (_isDisposed) return;
    _state = value;
    onChanged?.call();
  }

  // The authenticated Supabase connection performs RLS-protected reads.
  final SupabaseClient? _client;

  // The repository performs protected mutation RPCs.
  final CommunityRepository _repository;

  // Bounded page size makes feed loading predictable.
  final int postLimit;

  // Bounded comment limit protects the phone on very busy posts.
  final int commentLimit;

  // Current Subject supplies the subject UUID used by mutation RPCs.
  StudySubject? _activeSubject;

  // Realtime channel triggers canonical reloads after database changes.
  RealtimeChannel? _channel;

  // A short debounce combines bursts of post/comment events into one query.
  Timer? _refreshTimer;

  // Number of posts requested by the current paginated feed.
  int _requestedPostCount = defaultCommunityPostLimit;

  // Prevent overlapping feed queries from racing each other.
  bool _isRefreshing = false;

  // This flag stops late asynchronous work after the page is removed.
  bool _isDisposed = false;

  // Open the exactly one Community that belongs to the selected Subject.
  Future<void> watchCommunity(StudySubject subject) async {
    // A disposed page must never open a new realtime subscription.
    if (_isDisposed) return;

    // Stop the previous Subject subscription before changing labels or data.
    await _removeRealtimeChannel();

    // Leaving during cleanup means no new Subject work should begin.
    if (_isDisposed) return;

    // Save the selected Subject for later edits, comments, and reports.
    _activeSubject = subject;

    // Reset pagination whenever a new Subject is opened.
    _requestedPostCount = postLimit;

    // Clear old rows immediately so they never appear under the wrong Subject.
    state = CommunityState(
      activeCommunityId: subject.workspaceId,
      isLoading: true,
    );

    try {
      // Require a real initialized backend and signed-in account.
      final client = _requireClient();
      _requireSignedInUser(client);

      // Resolve the one Community row created atomically with the Subject.
      final communityRow = await client
          .from('communities')
          .select('id')
          .eq('subject_id', subject.id)
          .maybeSingle();

      // The student may have left while the database query was running.
      if (_isDisposed) return;

      // Missing Community means the catalog invariant was broken server-side.
      if (communityRow == null) {
        throw StateError('This Subject does not have a Community yet.');
      }

      // Read the canonical UUID returned by PostgreSQL.
      final communityId = communityRow['id']?.toString() ?? '';
      if (communityId.isEmpty) {
        throw StateError('The Community record is invalid.');
      }

      // Keep the canonical Community UUID in state for feed queries.
      state = state.copyWith(activeCommunityId: communityId);

      // Load posts and comments from Supabase before claiming the feed is live.
      await _loadFeed();

      // Do not subscribe when the owning page closed during the first load.
      if (_isDisposed) return;

      // Subscribe after the first successful load to avoid a duplicate query.
      _listenForDatabaseChanges(communityId);
    } catch (error) {
      // A failed network or RLS check becomes a clear retryable screen state.
      state = state.copyWith(
        posts: const <CommunityPost>[],
        isLoading: false,
        isLoadingMore: false,
        hasMorePosts: false,
        isLive: false,
        errorMessage: _friendlyError(error),
      );
    }
  }

  // Stop live work when leaving a Subject or signing out.
  Future<void> stopWatchingCommunity() async {
    // Cancel callbacks before clearing the selected Subject.
    await _removeRealtimeChannel();

    // Forget the old Subject so stale writes fail safely.
    _activeSubject = null;

    // Return the controller to a small empty state.
    state = CommunityState();
  }

  // Request one more bounded page of older posts.
  Future<void> loadMorePosts() async {
    // Ignore duplicate taps or a request after the last page.
    if (state.isLoadingMore || !state.hasMorePosts || _activeSubject == null) {
      return;
    }

    // Increase the requested window by exactly one page.
    _requestedPostCount += postLimit;

    // Keep current rows visible while older rows load.
    state = state.copyWith(isLoadingMore: true, clearError: true);

    // Reload the bounded canonical window.
    await _loadFeed();
  }

  // Add a new Student post to the active Subject.
  Future<String> addPost({
    required String authorId,
    required String author,
    required String body,
    required String idempotencyKey,
  }) async {
    // Community posts contain text only in the corrected FYP.
    var createdPostId = '';
    await _runWrite(() async {
      // Confirm that the supplied owner matches the authenticated account.
      _verifyCallerId(authorId);

      // Call the protected mutation RPC through the repository.
      createdPostId = await _repository.addPost(
        subjectId: _requireSubject().id,
        body: _requiredText(body, 'Post'),
        idempotencyKey: _requiredText(idempotencyKey, 'Request ID'),
      );
    });
    return createdPostId;
  }

  // Edit the currently signed-in Student's own post.
  Future<void> updatePost({
    required String postId,
    required String body,
  }) async {
    // Find the loaded version before sending the protected update.
    final post = _findPost(postId);

    // Execute and then reload the canonical database row.
    await _runWrite(() async {
      await _repository.updatePost(
        subjectId: _requireSubject().id,
        postId: post.id,
        expectedVersion: post.version,
        body: _requiredText(body, 'Post'),
      );
    });
  }

  // Soft-delete the signed-in Student's own post.
  Future<void> removePost(String postId) async {
    // Use the displayed version for safe optimistic concurrency.
    final post = _findPost(postId);

    // The RPC verifies ownership before changing the database.
    await _runWrite(() async {
      await _repository.removePost(
        subjectId: _requireSubject().id,
        postId: post.id,
        expectedVersion: post.version,
      );
    });
  }

  // Add a Student comment under one loaded post.
  Future<String> addComment({
    required String postId,
    required String authorId,
    required String author,
    required String body,
    required String idempotencyKey,
  }) async {
    // Confirm the parent exists in the visible canonical feed.
    _findPost(postId);

    // Run the protected comment mutation.
    var createdCommentId = '';
    await _runWrite(() async {
      _verifyCallerId(authorId);
      createdCommentId = await _repository.addComment(
        subjectId: _requireSubject().id,
        postId: postId,
        body: _requiredText(body, 'Comment'),
        idempotencyKey: _requiredText(idempotencyKey, 'Request ID'),
      );
    });
    return createdCommentId;
  }

  // Reload the visible canonical feed after one or more attachment uploads.
  Future<void> refresh() => _loadFeed();

  // Edit an owned loaded comment.
  Future<void> updateComment(
    String commentId, {
    required String body,
    String? postId,
  }) async {
    // Locate both parent and exact concurrency version.
    final located = _findComment(commentId, preferredPostId: postId);

    // Let PostgreSQL enforce ownership and status.
    await _runWrite(() async {
      await _repository.updateComment(
        subjectId: _requireSubject().id,
        postId: located.post.id,
        commentId: located.comment.id,
        expectedVersion: located.comment.version,
        body: _requiredText(body, 'Comment'),
      );
    });
  }

  // Soft-delete an owned loaded comment.
  Future<void> removeComment(String commentId, {String? postId}) async {
    // Locate both parent and exact concurrency version.
    final located = _findComment(commentId, preferredPostId: postId);

    // Let the backend preserve report references and audit details.
    await _runWrite(() async {
      await _repository.removeComment(
        subjectId: _requireSubject().id,
        postId: located.post.id,
        commentId: located.comment.id,
        expectedVersion: located.comment.version,
      );
    });
  }

  // Report one post through the same private report contract as the dialog.
  Future<void> reportPost(
    String postId,
    CommunityReportReason reason, {
    String details = '',
  }) async {
    // Only a loaded active post can be reported from this controller.
    _findPost(postId);

    // The reporter UUID is supplied by the Supabase session on the server.
    await _runWrite(() async {
      await BackendApiService().reportContent(
        subjectId: _requireSubject().id,
        targetType: 'post',
        targetId: postId,
        reason: communityReportReasonWireValue(reason),
        details: details.trim(),
      );
    });
  }

  // Load the requested post window and matching real comments.
  Future<void> _loadFeed() async {
    // Do not run or publish a query for a page that has already closed.
    if (_isDisposed) return;

    // Avoid racing a Realtime callback with a manual refresh.
    if (_isRefreshing) return;
    _isRefreshing = true;

    try {
      // Resolve the authenticated database client.
      final client = _requireClient();

      // Read the canonical Community UUID selected by watchCommunity.
      final communityId = state.activeCommunityId;
      if (communityId == null || communityId.isEmpty) {
        throw StateError('Choose a Subject Community first.');
      }

      // Ask for one extra post so hasMorePosts is exact without a count query.
      final requestedRows = _requestedPostCount + 1;
      final rawPosts = await client
          .from('community_posts')
          .select()
          .eq('community_id', communityId)
          .eq('is_removed', false)
          .order('created_at', ascending: false)
          .range(0, requestedRows - 1);

      // Convert PostgREST dynamic rows into normal string-keyed maps.
      final postRows = _mapList(rawPosts);

      // The extra row indicates that another bounded page exists.
      final hasMorePosts = postRows.length > _requestedPostCount;

      // Remove the extra row before drawing the feed.
      final visiblePostRows = postRows.take(_requestedPostCount).toList();

      // Collect loaded post UUIDs for the matching comment query.
      final postIds = visiblePostRows
          .map((row) => row['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(growable: false);

      // Keep raw comment rows until their matching attachments are loaded.
      final visibleCommentRows = <Map<String, dynamic>>[];
      if (postIds.isNotEmpty) {
        // PostgreSQL returns the oldest replies first for natural reading.
        final rawComments = await client
            .from('community_comments')
            .select()
            .inFilter('post_id', postIds)
            .eq('is_removed', false)
            .order('created_at')
            .limit(commentLimit);

        // Save normal typed maps for the attachment query and model builder.
        visibleCommentRows.addAll(_mapList(rawComments));
      }

      // Collect comment UUIDs so only visible-thread attachments are loaded.
      final commentIds = visibleCommentRows
          .map((row) => row['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(growable: false);

      // Ready rows are grouped by their one allowed target.
      final attachmentsByPost = <String, List<CommunityAttachment>>{};
      final attachmentsByComment = <String, List<CommunityAttachment>>{};

      // Load files attached directly to the currently visible posts.
      if (postIds.isNotEmpty) {
        final rawPostAttachments = await client
            .from('community_attachments')
            .select()
            .inFilter('post_id', postIds)
            .eq('status', 'ready')
            .order('created_at');
        for (final row in _mapList(rawPostAttachments)) {
          final attachment = CommunityAttachment.fromSupabaseRow(row);
          final targetId = attachment.postId;
          if (attachment.id.isEmpty || targetId == null) continue;
          attachmentsByPost.putIfAbsent(targetId, () => []).add(attachment);
        }
      }

      // Load files attached directly to the currently visible comments.
      if (commentIds.isNotEmpty) {
        final rawCommentAttachments = await client
            .from('community_attachments')
            .select()
            .inFilter('comment_id', commentIds)
            .eq('status', 'ready')
            .order('created_at');
        for (final row in _mapList(rawCommentAttachments)) {
          final attachment = CommunityAttachment.fromSupabaseRow(row);
          final targetId = attachment.commentId;
          if (attachment.id.isEmpty || targetId == null) continue;
          attachmentsByComment.putIfAbsent(targetId, () => []).add(attachment);
        }
      }

      // Build comments after their private-file metadata is available.
      final commentsByPost = <String, List<CommunityComment>>{};
      for (final row in visibleCommentRows) {
        final postId = row['post_id']?.toString() ?? '';
        final commentId = row['id']?.toString() ?? '';
        if (postId.isEmpty || commentId.isEmpty) continue;
        final comment = CommunityComment.fromSupabaseRow(
          row,
          id: commentId,
          attachments:
              attachmentsByComment[commentId] ?? const <CommunityAttachment>[],
        );
        commentsByPost.putIfAbsent(postId, () => []).add(comment);
      }

      // Build each typed post with its real loaded comment list.
      final posts = <CommunityPost>[];
      for (final row in visiblePostRows) {
        final postId = row['id']?.toString() ?? '';
        if (postId.isEmpty) continue;
        posts.add(
          CommunityPost.fromSupabaseRow(
            row,
            id: postId,
            communityId: communityId,
            comments: commentsByPost[postId] ?? const <CommunityComment>[],
            attachments:
                attachmentsByPost[postId] ?? const <CommunityAttachment>[],
          ),
        );
      }

      // Publish a server-backed live state only after both queries succeed.
      state = state.copyWith(
        posts: posts,
        isLoading: false,
        isLoadingMore: false,
        hasMorePosts: hasMorePosts,
        isLive: true,
        clearError: true,
      );
    } catch (error) {
      // Keep any already loaded rows visible but explain the refresh failure.
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        isLive: state.posts.isNotEmpty,
        errorMessage: _friendlyError(error),
      );
    } finally {
      // Future manual or Realtime refreshes may now run.
      _isRefreshing = false;
    }
  }

  // Subscribe to post and comment table changes for real-time refreshes.
  void _listenForDatabaseChanges(String communityId) {
    // Resolve the initialized client once for the channel builder.
    final client = _requireClient();

    // A unique channel name prevents two Subject workspaces from colliding.
    _channel = client
        .channel('community:$communityId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'community_posts',
          callback: (_) => _scheduleRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'community_comments',
          callback: (_) => _scheduleRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'community_attachments',
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();
  }

  // Combine rapid database events into one canonical feed reload.
  void _scheduleRefresh() {
    // Ignore database events delivered while a page is being removed.
    if (_isDisposed) return;

    // Replace any pending short debounce timer.
    _refreshTimer?.cancel();

    // Wait briefly so a post and related counter update arrive together.
    _refreshTimer = Timer(const Duration(milliseconds: 250), _loadFeed);
  }

  // Run one write and then refresh the canonical server state.
  Future<void> _runWrite(Future<void> Function() action) async {
    // Remove an old error before the new attempt starts.
    state = state.copyWith(clearError: true);

    try {
      // Perform the protected mutation.
      await action();

      // Reload real server timestamps, versions, and comment counts.
      await _loadFeed();
    } catch (error) {
      // Store the friendly message and rethrow for the screen snackbar.
      final message = _friendlyError(error);
      state = state.copyWith(errorMessage: message);
      throw StateError(message);
    }
  }

  // Locate one currently loaded post.
  CommunityPost _findPost(String postId) {
    // Search the bounded visible feed by UUID.
    for (final post in state.posts) {
      if (post.id == postId) return post;
    }

    // A missing row may have been removed by another client.
    throw StateError('The post is no longer available. Refresh and try again.');
  }

  // Locate a comment together with its required parent post.
  ({CommunityPost post, CommunityComment comment}) _findComment(
    String commentId, {
    String? preferredPostId,
  }) {
    // Search only the preferred parent when the screen already knows it.
    for (final post in state.posts) {
      if (preferredPostId != null && post.id != preferredPostId) continue;
      for (final comment in post.comments) {
        if (comment.id == commentId) return (post: post, comment: comment);
      }
    }

    // A missing row may have been deleted or paged out.
    throw StateError(
      'The comment is no longer available. Refresh and try again.',
    );
  }

  // Require the active Subject before any mutation.
  StudySubject _requireSubject() {
    // Nullable state is converted into a clear beginner-facing error.
    final subject = _activeSubject;
    if (subject == null) throw StateError('Choose a Subject first.');
    return subject;
  }

  // Require initialized Supabase before any backend work.
  SupabaseClient _requireClient() {
    // Startup configuration errors fail clearly instead of null-crashing.
    final client = _client;
    if (client == null) {
      throw StateError('Supabase is not configured. Restart PeerStudy.');
    }
    return client;
  }

  // Require an authenticated Student session.
  User _requireSignedInUser(SupabaseClient client) {
    // Supabase stores the current token and identity in the Auth client.
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in before opening Community.');
    return user;
  }

  // Prevent an old UI parameter from spoofing ownership.
  void _verifyCallerId(String suppliedId) {
    // Compare against the real authenticated Supabase UUID.
    final user = _requireSignedInUser(_requireClient());
    if (suppliedId.trim().isNotEmpty && suppliedId.trim() != user.id) {
      throw StateError('The selected account does not match your session.');
    }
  }

  // Remove the current Realtime channel and debounce timer.
  Future<void> _removeRealtimeChannel() async {
    // No delayed refresh should run for the old Subject.
    _refreshTimer?.cancel();
    _refreshTimer = null;

    // Remove the channel from the shared Supabase client.
    final channel = _channel;
    _channel = null;
    final client = _client;
    if (channel != null && client != null) {
      await client.removeChannel(channel);
    }
  }

  // The owning StatefulWidget calls this when it leaves the screen.
  void dispose() {
    // Mark closed before any pending Future gets another chance to continue.
    _isDisposed = true;

    // Synchronous timer cleanup prevents a callback after disposal.
    _refreshTimer?.cancel();

    // Channel removal is safe to finish asynchronously.
    unawaited(_removeRealtimeChannel());
  }
}

// Return the shared client only after main.dart initialized Supabase.
SupabaseClient? _clientIfReady() {
  // This keeps widget tests independent from network configuration.
  if (!SupabaseService.isReady) return null;
  return SupabaseService.client;
}

// Convert a PostgREST response into string-keyed maps.
List<Map<String, dynamic>> _mapList(dynamic value) {
  // A malformed response fails clearly instead of silently losing content.
  if (value is! Iterable) {
    throw StateError('The Community service returned invalid data.');
  }

  // Convert every dynamic map into a predictable Dart map.
  return value
      .map((row) {
        final map = _dynamicMap(row);
        if (map == null) {
          throw StateError('A Community row was invalid.');
        }
        return map;
      })
      .toList(growable: false);
}

// Parse a required date and use the Unix epoch for a malformed server row.
DateTime _dateValue(dynamic value) {
  // All canonical Supabase timestamps arrive as ISO-8601 strings.
  return _nullableDate(value) ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

// Parse nullable ISO or DateTime values.
DateTime? _nullableDate(dynamic value) {
  // Tests may already supply a DateTime.
  if (value is DateTime) return value;

  // PostgREST supplies ISO-8601 timestamp text.
  if (value is String) return DateTime.tryParse(value)?.toUtc();

  // Unknown values remain absent.
  return null;
}

// Read a non-empty string or return a safe fallback.
String _stringValue(dynamic value, {required String fallback}) {
  // Whitespace-only user-facing values are treated as missing.
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return fallback;
}

// Read an optional string without throwing on malformed data.
String? _nullableString(dynamic value) {
  // Empty optional values are normalized to null.
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

// Read an integer returned as any Dart numeric subtype.
int? _nullableInt(dynamic value) {
  // PostgreSQL integer JSON normally arrives as int but num is safer.
  return value is num ? value.toInt() : null;
}

// Keep concurrency versions positive for malformed server rows.
int _positiveInt(dynamic value, {required int fallback}) {
  // A non-positive version is never sent to a protected mutation.
  final parsed = _nullableInt(value);
  return parsed != null && parsed > 0 ? parsed : fallback;
}

// Treat only literal true as true for security-sensitive flags.
bool _boolValue(dynamic value) {
  // Strings such as "true" are deliberately not trusted.
  return value == true;
}

// Convert any dynamic JSON map into a string-keyed map.
Map<String, dynamic>? _dynamicMap(dynamic value) {
  // Fast path for the usual PostgREST response type.
  if (value is Map<String, dynamic>) return value;

  // Tolerate other Map implementations used by tests and JSON decoders.
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  // Non-map values are invalid rows.
  return null;
}

// Validate and trim required user text consistently.
String _requiredText(String value, String label) {
  // Empty content is rejected before a network request.
  final clean = value.trim();
  if (clean.isEmpty) throw StateError('$label cannot be empty.');
  return clean;
}

// Translate technical Supabase errors into useful screen messages.
String _friendlyError(Object error) {
  // BackendException already contains a reviewed message.
  if (error is BackendException) return error.message;

  // PostgREST messages are useful but never expose a stack trace.
  if (error is PostgrestException) {
    if (error.code == '42501') {
      return 'You do not have permission to perform this action.';
    }
    return error.message;
  }

  // Authentication failures should ask the user to sign in again.
  if (error is AuthException) return error.message;

  // Local validation errors already use beginner-friendly wording.
  if (error is StateError) return error.message;

  // Unknown network or parsing failures get one safe fallback.
  return 'Community is temporarily unavailable. Check your connection and retry.';
}
