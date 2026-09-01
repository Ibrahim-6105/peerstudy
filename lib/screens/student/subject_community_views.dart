// Subject Community posts and comments for one subject workspace.
//
// Beginner note:
// Reads and writes use one plain Supabase-backed controller. Keeping the
// screen focused on posts, comments, and reports matches the corrected FYP.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:peerstudy/models/app_user.dart';
import 'package:peerstudy/models/community_attachment.dart';
import 'package:peerstudy/models/subject.dart';
import 'package:peerstudy/providers/academic_provider.dart';
import 'package:peerstudy/services/backend_api_service.dart';
import 'package:peerstudy/services/auth_service.dart';
import 'package:peerstudy/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

// SubjectCommunityView renders the post feed, comments, reports, and publishing.
class SubjectCommunityView extends StatefulWidget {
  const SubjectCommunityView({required this.subject, super.key});

  final StudySubject subject;

  @override
  State<SubjectCommunityView> createState() => _SubjectCommunityViewState();
}

// This ordinary State object owns one ordinary Community controller.
class _SubjectCommunityViewState extends State<SubjectCommunityView> {
  // The controller is created in initState so it lives exactly as long as the page.
  late final CommunityController _communityController;

  @override
  void initState() {
    super.initState();

    // A tiny callback replaces a state-management package: it just calls setState.
    _communityController = CommunityController(
      onChanged: () {
        if (mounted) setState(() {});
      },
    );

    // Loading after the first frame keeps build free of network work.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _communityController.watchCommunity(widget.subject);
    });
  }

  @override
  void didUpdateWidget(covariant SubjectCommunityView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Reuse the widget safely if its parent opens another Subject.
    if (oldWidget.subject.id != widget.subject.id) {
      _communityController.watchCommunity(widget.subject);
    }
  }

  @override
  void dispose() {
    // Stop the realtime subscription before the page is removed.
    _communityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final community = _communityController.state;
    final user = AuthService.instance.currentUser;
    final canPublishPost = user?.role == 'student';
    final posts = community.posts
        .where((post) => !post.isRemoved)
        .toList(growable: false);

    Future<void> createPost() async {
      final created = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => _CreatePostSheet(subject: widget.subject),
      );
      if (created == true && context.mounted) {
        // Reload immediately; realtime is also kept as a second safe refresh.
        await _communityController.watchCommunity(widget.subject);
      }
      if (created == true && context.mounted) {
        _showMessage(context, 'Your post was published.');
      }
    }

    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppTheme.contentWidth),
          child: RefreshIndicator(
            onRefresh: () =>
                _communityController.watchCommunity(widget.subject),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _CommunityHeader(
                    icon: Icons.people_alt_outlined,
                    title: 'Community',
                    message: 'Share subject questions and help other students.',
                    action: canPublishPost
                        ? FilledButton.icon(
                            onPressed: community.isLive ? createPost : null,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Post'),
                          )
                        : null,
                  ),
                ),
                if (community.errorMessage != null)
                  SliverToBoxAdapter(
                    child: _InlineError(
                      message: community.errorMessage!,
                      onRetry: () =>
                          _communityController.watchCommunity(widget.subject),
                    ),
                  ),
                if (community.isLoading && posts.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: SizedBox.square(
                        dimension: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  )
                else if (!community.isLive)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyCommunityState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Live posts unavailable',
                      message:
                          'Reconnect to read or publish Community content.',
                    ),
                  )
                else if (posts.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyCommunityState(
                      icon: Icons.post_add_outlined,
                      title: 'No posts yet',
                      message: canPublishPost
                          ? 'Create the first post for this subject.'
                          : 'No student posts are available for this subject.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                    sliver: SliverList.separated(
                      itemCount: posts.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) => _PostCard(
                        key: ValueKey<String>(posts[index].id),
                        subject: widget.subject,
                        controller: _communityController,
                        post: posts[index],
                        currentUser: user,
                      ),
                    ),
                  ),
                if (community.hasMorePosts)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: OutlinedButton(
                        onPressed: community.isLoadingMore
                            ? null
                            : _communityController.loadMorePosts,
                        child: Text(
                          community.isLoadingMore
                              ? 'Loading older posts...'
                              : 'Load older posts',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// One post card owns its comment input so text is not shared between posts.
class _PostCard extends StatefulWidget {
  const _PostCard({
    super.key,
    required this.subject,
    required this.controller,
    required this.post,
    required this.currentUser,
  });

  final StudySubject subject;
  final CommunityController controller;
  final CommunityPost post;
  final AppUser? currentUser;

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  // Each post card owns its simple comment text and attachment selection.
  final TextEditingController _commentController = TextEditingController();
  final BackendApiService _backend = BackendApiService();
  final List<CommunityAttachmentDraft> _commentAttachments =
      <CommunityAttachmentDraft>[];
  int _uploadedCommentAttachmentCount = 0;
  bool _isCommenting = false;
  String? _commentUploadMessage;
  String? _pendingCommentBody;
  String? _pendingCommentIdempotencyKey;
  String? _pendingCommentTargetId;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    final user = widget.currentUser;
    final body = _commentController.text.trim();
    if (user == null || body.isEmpty || _isCommenting) return;
    if (_pendingCommentBody != body || _pendingCommentIdempotencyKey == null) {
      _pendingCommentBody = body;
      _pendingCommentIdempotencyKey =
          'comment_${DateTime.now().microsecondsSinceEpoch}';
    }
    setState(() {
      _isCommenting = true;
      _commentUploadMessage = _pendingCommentTargetId == null
          ? 'Posting comment...'
          : 'Retrying attachments...';
    });
    try {
      // Create the text first because attachments require its real UUID.
      _pendingCommentTargetId ??= await widget.controller.addComment(
        postId: widget.post.id,
        authorId: user.uid,
        author: user.fullName,
        body: body,
        idempotencyKey: _pendingCommentIdempotencyKey!,
      );

      // Upload one file at a time so the student always sees exact progress.
      var uploadedCount = 0;
      final totalCount = _commentAttachments.length;
      while (_commentAttachments.isNotEmpty) {
        final draft = _commentAttachments.first;
        if (mounted) {
          setState(() {
            _commentUploadMessage =
                'Uploading attachment ${uploadedCount + 1} of $totalCount...';
          });
        }
        await _backend.uploadCommunityAttachment(
          subjectId: widget.subject.workspaceId,
          targetType: 'comment',
          targetId: _pendingCommentTargetId!,
          fileName: draft.fileName,
          mimeType: draft.mimeType,
          bytes: draft.bytes,
          idempotencyKey: draft.idempotencyKey,
        );
        uploadedCount += 1;
        if (mounted) {
          setState(() {
            _uploadedCommentAttachmentCount += 1;
            _commentAttachments.removeAt(0);
          });
        }
      }

      // One canonical refresh draws all newly ready attachment metadata.
      await widget.controller.refresh();
      if (mounted) {
        _commentController.clear();
        _pendingCommentBody = null;
        _pendingCommentIdempotencyKey = null;
        _pendingCommentTargetId = null;
        _uploadedCommentAttachmentCount = 0;
        _commentUploadMessage = null;
        _showMessage(context, 'Your comment was posted.');
      }
    } catch (error) {
      if (mounted) {
        final prefix = _pendingCommentTargetId == null
            ? ''
            : 'The comment is saved. ';
        _showMessage(context, '$prefix${error.toString()}');
        setState(() {
          _commentUploadMessage = _pendingCommentTargetId == null
              ? null
              : 'Comment saved. Retry the remaining attachments.';
        });
      }
    } finally {
      if (mounted) setState(() => _isCommenting = false);
    }
  }

  // Open the system picker and retain only reviewed, readable local files.
  Future<void> _pickCommentAttachments() async {
    if (_isCommenting) return;
    final picked = await _pickCommunityAttachmentFiles(
      context,
      existingCount:
          _uploadedCommentAttachmentCount + _commentAttachments.length,
    );
    if (!mounted || picked == null) return;
    setState(() => _commentAttachments.addAll(picked));
  }

  // An owner can hide one attachment without deleting the post or comment text.
  Future<void> _removeAttachment(CommunityAttachment attachment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove attachment?'),
        content: Text('Remove "${attachment.fileName}" from this Community?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _backend.removeCommunityAttachment(attachment);
      await widget.controller.refresh();
      if (mounted) _showMessage(context, 'Attachment removed.');
    } catch (error) {
      if (mounted) _showMessage(context, error.toString());
    }
  }

  Future<void> _removeOwnPost() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this post?'),
        content: const Text(
          'The post will disappear from the feed, but its audit history is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.removePost(widget.post.id);
    } catch (error) {
      if (mounted) _showMessage(context, error.toString());
    }
  }

  // Lets an owner revise the text of their own Community post.
  Future<void> _editOwnPost() async {
    final editedBody = await _requestEditedText(
      title: 'Edit Community post',
      initialValue: widget.post.body,
      maxLength: 5000,
    );
    if (editedBody == null ||
        editedBody == widget.post.body.trim() ||
        !mounted) {
      return;
    }
    try {
      await widget.controller.updatePost(
        postId: widget.post.id,
        body: editedBody,
      );
    } catch (error) {
      if (mounted) _showMessage(context, error.toString());
    }
  }

  // A comment owner gets the same versioned soft-delete protection as a post.
  Future<void> _removeOwnComment(CommunityComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this comment?'),
        content: const Text('It will leave the post, while its audit is kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.removeComment(comment.id, postId: widget.post.id);
    } catch (error) {
      if (mounted) _showMessage(context, error.toString());
    }
  }

  // Lets an owner revise comment text with backend version protection.
  Future<void> _editOwnComment(CommunityComment comment) async {
    final editedBody = await _requestEditedText(
      title: 'Edit comment',
      initialValue: comment.body,
      maxLength: 2000,
    );
    if (editedBody == null || editedBody == comment.body.trim() || !mounted) {
      return;
    }
    try {
      await widget.controller.updateComment(
        comment.id,
        body: editedBody,
        postId: widget.post.id,
      );
    } catch (error) {
      if (mounted) _showMessage(context, error.toString());
    }
  }

  // Uses a keyboard-safe sheet so a multi-line editor is not squeezed in a dialog.
  Future<String?> _requestEditedText({
    required String title,
    required String initialValue,
    required int maxLength,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: maxLength,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Text',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final text = controller.text.trim();
                      if (text.isNotEmpty) Navigator.pop(sheetContext, text);
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final isMine = post.authorId == widget.currentUser?.uid;
    final comments = post.comments
        .where((comment) => !comment.isRemoved)
        .toList(growable: false);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(
                    post.author.trim().isEmpty
                        ? '?'
                        : post.author.trim()[0].toUpperCase(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              post.author,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _formatMoment(post.createdAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Post actions',
                  onSelected: (action) {
                    if (action == 'edit') {
                      _editOwnPost();
                    } else if (action == 'remove') {
                      _removeOwnPost();
                    } else if (action == 'report') {
                      _openReport(
                        context,
                        subjectId: widget.subject.workspaceId,
                        targetType: 'post',
                        targetId: post.id,
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    if (isMine)
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit my post'),
                      ),
                    if (isMine)
                      const PopupMenuItem(
                        value: 'remove',
                        child: Text('Remove my post'),
                      )
                    else
                      const PopupMenuItem(
                        value: 'report',
                        child: Text('Report privately'),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(post.body),
            if (post.attachments.isNotEmpty) ...[
              const SizedBox(height: 10),
              _CommunityAttachmentList(
                attachments: post.attachments,
                currentUserId: widget.currentUser?.uid,
                onRemove: _removeAttachment,
              ),
            ],
            const Divider(height: 18),
            ExpansionTile(
              dense: true,
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              leading: const Icon(Icons.comment_outlined),
              title: Text('${comments.length} comments'),
              children: [
                for (final comment in comments)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Row(
                      children: [Flexible(child: Text(comment.author))],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(comment.body),
                        if (comment.attachments.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _CommunityAttachmentList(
                            attachments: comment.attachments,
                            currentUserId: widget.currentUser?.uid,
                            onRemove: _removeAttachment,
                            compact: true,
                          ),
                        ],
                      ],
                    ),
                    trailing: comment.authorId == widget.currentUser?.uid
                        ? PopupMenuButton<String>(
                            tooltip: 'My comment actions',
                            onSelected: (action) {
                              if (action == 'edit') {
                                _editOwnComment(comment);
                              } else if (action == 'remove') {
                                _removeOwnComment(comment);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit my comment'),
                              ),
                              PopupMenuItem(
                                value: 'remove',
                                child: Text('Remove my comment'),
                              ),
                            ],
                          )
                        : IconButton(
                            tooltip: 'Report comment privately',
                            onPressed: () => _openReport(
                              context,
                              subjectId: widget.subject.workspaceId,
                              targetType: 'comment',
                              targetId: comment.id,
                              parentId: post.id,
                            ),
                            icon: const Icon(Icons.flag_outlined),
                          ),
                  ),
                if (_commentAttachments.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _SelectedCommunityAttachmentList(
                    attachments: _commentAttachments,
                    enabled: !_isCommenting,
                    onRemove: (index) {
                      setState(() => _commentAttachments.removeAt(index));
                    },
                  ),
                ],
                if (_commentUploadMessage != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (_isCommenting) ...[
                        const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 7),
                      ],
                      Expanded(
                        child: Text(
                          _commentUploadMessage!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        enabled:
                            !_isCommenting && _pendingCommentTargetId == null,
                        onChanged: (_) {
                          _pendingCommentBody = null;
                          _pendingCommentIdempotencyKey = null;
                        },
                        maxLength: 2000,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Add a comment',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Attach files',
                      onPressed:
                          _isCommenting ||
                              _uploadedCommentAttachmentCount +
                                      _commentAttachments.length >=
                                  communityAttachmentMaxCount
                          ? null
                          : _pickCommentAttachments,
                      icon: const Icon(Icons.attach_file_rounded),
                    ),
                    const SizedBox(width: 2),
                    IconButton.filledTonal(
                      tooltip: _pendingCommentTargetId == null
                          ? 'Post comment'
                          : 'Retry remaining attachments',
                      onPressed: _isCommenting ? null : _addComment,
                      icon: _isCommenting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// This bottom sheet creates one text post with up to three private attachments.
class _CreatePostSheet extends StatefulWidget {
  const _CreatePostSheet({required this.subject});

  final StudySubject subject;

  @override
  State<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<_CreatePostSheet> {
  final TextEditingController _bodyController = TextEditingController();
  final BackendApiService _backend = BackendApiService();
  final List<CommunityAttachmentDraft> _attachments =
      <CommunityAttachmentDraft>[];
  int _uploadedAttachmentCount = 0;
  String? _postIdempotencyKey;
  String? _createdPostId;
  bool _isPublishing = false;
  String? _errorMessage;
  String? _progressMessage;

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  // Select more reviewed files without exceeding the three-file limit.
  Future<void> _pickAttachments() async {
    final picked = await _pickCommunityAttachmentFiles(
      context,
      existingCount: _uploadedAttachmentCount + _attachments.length,
    );
    if (!mounted || picked == null) return;
    setState(() => _attachments.addAll(picked));
  }

  Future<void> _publish() async {
    final body = _bodyController.text.trim();
    if (body.isEmpty || _isPublishing) {
      setState(() => _errorMessage = 'Write a post before publishing.');
      return;
    }

    setState(() {
      _isPublishing = true;
      _errorMessage = null;
      _progressMessage = _createdPostId == null
          ? 'Publishing post...'
          : 'Retrying attachments...';
    });

    try {
      // Keep this key after an ambiguous response so an exact retry cannot
      // create a duplicate post.
      _postIdempotencyKey ??= 'post_${DateTime.now().microsecondsSinceEpoch}';

      // Create text once; a failed file can retry without duplicating the post.
      _createdPostId ??= await _backend.createPost(
        subjectId: widget.subject.workspaceId,
        body: body,
        idempotencyKey: _postIdempotencyKey!,
      );

      // Upload sequentially and remove only successful drafts from the list.
      var uploadedCount = 0;
      final totalCount = _attachments.length;
      while (_attachments.isNotEmpty) {
        final draft = _attachments.first;
        if (mounted) {
          setState(() {
            _progressMessage =
                'Uploading attachment ${uploadedCount + 1} of $totalCount...';
          });
        }
        await _backend.uploadCommunityAttachment(
          subjectId: widget.subject.workspaceId,
          targetType: 'post',
          targetId: _createdPostId!,
          fileName: draft.fileName,
          mimeType: draft.mimeType,
          bytes: draft.bytes,
          idempotencyKey: draft.idempotencyKey,
        );
        uploadedCount += 1;
        if (mounted) {
          setState(() {
            _uploadedAttachmentCount += 1;
            _attachments.removeAt(0);
          });
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _createdPostId == null
            ? error.toString()
            : 'Your post is saved. ${error.toString()} Retry the remaining attachments.';
        _isPublishing = false;
        _progressMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope(
      // Do not let a system back gesture interrupt bytes currently uploading.
      canPop: !_isPublishing,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'New Community post',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(widget.subject.name),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyController,
              // After text is saved, the sheet retries only pending files.
              enabled: !_isPublishing && _createdPostId == null,
              onChanged: (_) => _postIdempotencyKey = null,
              minLines: 3,
              maxLines: 7,
              maxLength: 4000,
              decoration: const InputDecoration(
                labelText: 'Post text',
                hintText: 'Ask a question or share subject guidance',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed:
                  _isPublishing ||
                      _uploadedAttachmentCount + _attachments.length >=
                          communityAttachmentMaxCount
                  ? null
                  : _pickAttachments,
              icon: const Icon(Icons.attach_file_rounded),
              label: Text(
                _attachments.isEmpty
                    ? 'Add attachments (optional)'
                    : 'Add another attachment',
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Up to 3 files, 10 MB each: JPG, PNG, WebP, PDF, or TXT.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_attachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              _SelectedCommunityAttachmentList(
                attachments: _attachments,
                enabled: !_isPublishing,
                onRemove: (index) {
                  setState(() => _attachments.removeAt(index));
                },
              ),
            ],
            if (_progressMessage != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_progressMessage!)),
                ],
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: FilledButton.icon(
                onPressed: _isPublishing ? null : _publish,
                icon: _isPublishing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.publish_rounded),
                label: Text(
                  _isPublishing
                      ? 'Publishing...'
                      : _createdPostId == null
                      ? 'Publish post'
                      : _attachments.isEmpty
                      ? 'Finish'
                      : 'Retry attachments',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// This safe bottom sheet sends a report without exposing reporter data.
class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.subjectId,
    required this.targetType,
    required this.targetId,
    this.parentId,
  });

  final String subjectId;
  final String targetType;
  final String targetId;
  final String? parentId;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final TextEditingController _detailsController = TextEditingController();
  CommunityReportReason _reason = CommunityReportReason.spam;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await BackendApiService().reportContent(
        subjectId: widget.subjectId,
        targetType: widget.targetType,
        targetId: widget.targetId,
        parentId: widget.parentId,
        reason: communityReportReasonWireValue(_reason),
        details: _detailsController.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Report privately',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<CommunityReportReason>(
            initialValue: _reason,
            decoration: const InputDecoration(labelText: 'Reason'),
            items: [
              for (final reason in CommunityReportReason.values)
                DropdownMenuItem(
                  value: reason,
                  child: Text(_reportReasonLabel(reason)),
                ),
            ],
            onChanged: _isSubmitting
                ? null
                : (reason) {
                    if (reason != null) setState(() => _reason = reason);
                  },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _detailsController,
            enabled: !_isSubmitting,
            maxLength: 500,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Details (optional)',
              alignLabelWithHint: true,
            ),
          ),
          if (_errorMessage != null)
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: Text(_isSubmitting ? 'Sending...' : 'Send report'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/*
The former AlertDialog implementation was replaced by the sheet above because
the reason and details fields need room to stay visible above the phone keyboard.
*/

// Opens the reusable safe report sheet and confirms successful submissions.
Future<void> _openReport(
  BuildContext context, {
  required String subjectId,
  required String targetType,
  required String targetId,
  String? parentId,
}) async {
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ReportSheet(
      subjectId: subjectId,
      targetType: targetType,
      targetId: targetId,
      parentId: parentId,
    ),
  );
  if (submitted == true && context.mounted) {
    _showMessage(context, 'Report sent privately for admin review.');
  }
}

// Open the phone file picker and return only complete, locally valid files.
Future<List<CommunityAttachmentDraft>?> _pickCommunityAttachmentFiles(
  BuildContext context, {
  required int existingCount,
}) async {
  final remainingCount = communityAttachmentMaxCount - existingCount;
  if (remainingCount <= 0) {
    _showMessage(context, 'A post or comment can contain up to 3 attachments.');
    return null;
  }

  try {
    // withData keeps Android, iOS, desktop, and web selections equally simple.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: communityAttachmentAllowedExtensions,
      allowMultiple: true,
      withData: true,
    );
    if (!context.mounted || result == null || result.files.isEmpty) return null;

    // Reject an oversized selection instead of silently ignoring chosen files.
    if (result.files.length > remainingCount) {
      _showMessage(
        context,
        'You can select $remainingCount more attachment${remainingCount == 1 ? '' : 's'}.',
      );
      return null;
    }

    final drafts = <CommunityAttachmentDraft>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) {
        _showMessage(
          context,
          '"${file.name}" could not be read. Choose it again.',
        );
        return null;
      }
      final validationMessage = validateCommunityAttachment(
        fileName: file.name,
        sizeBytes: bytes.length,
      );
      if (validationMessage != null) {
        _showMessage(context, '${file.name}: $validationMessage');
        return null;
      }
      final mimeType = communityAttachmentMimeTypeForFileName(file.name);
      if (mimeType == null) {
        _showMessage(context, '${file.name}: unsupported file type.');
        return null;
      }
      drafts.add(
        CommunityAttachmentDraft(
          idempotencyKey: const Uuid().v4(),
          fileName: file.name.trim(),
          mimeType: mimeType,
          bytes: bytes,
        ),
      );
    }
    return drafts;
  } on Object {
    if (context.mounted) {
      _showMessage(context, 'The file picker could not open. Please retry.');
    }
    return null;
  }
}

// Draw local files before publishing and let the student remove mistakes.
class _SelectedCommunityAttachmentList extends StatelessWidget {
  const _SelectedCommunityAttachmentList({
    required this.attachments,
    required this.enabled,
    required this.onRemove,
  });

  final List<CommunityAttachmentDraft> attachments;
  final bool enabled;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var index = 0; index < attachments.length; index++) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
              child: Row(
                children: [
                  Icon(
                    _attachmentIcon(attachments[index].mimeType),
                    size: 20,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachments[index].fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        Text(
                          formatCommunityAttachmentSize(
                            attachments[index].sizeBytes,
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove selected file',
                    visualDensity: VisualDensity.compact,
                    onPressed: enabled ? () => onRemove(index) : null,
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
            ),
          ),
          if (index != attachments.length - 1) const SizedBox(height: 5),
        ],
      ],
    );
  }
}

// Draw ready server attachments below their exact post or comment.
class _CommunityAttachmentList extends StatelessWidget {
  const _CommunityAttachmentList({
    required this.attachments,
    required this.currentUserId,
    required this.onRemove,
    this.compact = false,
  });

  final List<CommunityAttachment> attachments;
  final String? currentUserId;
  final Future<void> Function(CommunityAttachment attachment) onRemove;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < attachments.length; index++) ...[
          _CommunityAttachmentTile(
            key: ValueKey<String>(attachments[index].id),
            attachment: attachments[index],
            compact: compact,
            onRemove: attachments[index].uploadedBy == currentUserId
                ? () => onRemove(attachments[index])
                : null,
          ),
          if (index != attachments.length - 1)
            SizedBox(height: compact ? 4 : 6),
        ],
      ],
    );
  }
}

// One tile requests a temporary link only when the student taps it.
class _CommunityAttachmentTile extends StatefulWidget {
  const _CommunityAttachmentTile({
    super.key,
    required this.attachment,
    required this.compact,
    this.onRemove,
  });

  final CommunityAttachment attachment;
  final bool compact;
  final Future<void> Function()? onRemove;

  @override
  State<_CommunityAttachmentTile> createState() =>
      _CommunityAttachmentTileState();
}

class _CommunityAttachmentTileState extends State<_CommunityAttachmentTile> {
  final BackendApiService _backend = BackendApiService();
  bool _isOpening = false;

  // Ask for one-minute access, then open or download through the system app.
  Future<void> _openSecurely({bool download = false}) async {
    if (_isOpening) return;
    setState(() => _isOpening = true);
    try {
      final uri = await _backend.requestCommunityAttachmentAccess(
        widget.attachment.id,
        download: download,
      );
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        throw StateError('No app is available to open this attachment.');
      }
      if (download && mounted) {
        _showMessage(context, 'Secure download started.');
      }
    } on Object {
      if (mounted) {
        _showMessage(
          context,
          download
              ? 'This attachment could not be downloaded securely. Please retry.'
              : 'This attachment could not be opened securely. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _isOpening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.primaryContainer.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: _isOpening ? null : () => _openSecurely(),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: widget.compact ? 6 : 8,
                ),
                child: Row(
                  children: [
                    if (_isOpening)
                      const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        _attachmentIcon(widget.attachment.mimeType),
                        size: 21,
                        color: colors.primary,
                      ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.attachment.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          Text(
                            '${formatCommunityAttachmentSize(widget.attachment.sizeBytes)} • Open securely',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.open_in_new_rounded, size: 17),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Download attachment securely',
            visualDensity: VisualDensity.compact,
            onPressed: _isOpening ? null : () => _openSecurely(download: true),
            icon: const Icon(Icons.download_outlined, size: 20),
          ),
          if (widget.onRemove != null)
            IconButton(
              tooltip: 'Remove attachment',
              visualDensity: VisualDensity.compact,
              onPressed: _isOpening ? null : widget.onRemove,
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
            ),
        ],
      ),
    );
  }
}

// Pick a familiar icon without inspecting or trusting file contents on-device.
IconData _attachmentIcon(String mimeType) {
  if (mimeType.startsWith('image/')) return Icons.image_outlined;
  if (mimeType == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (mimeType == 'text/plain') return Icons.description_outlined;
  return Icons.article_outlined;
}

// Compact heading shared by Community states.
class _CommunityHeader extends StatelessWidget {
  const _CommunityHeader({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 3),
                Text(message),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 10), action!],
        ],
      ),
    );
  }
}

// Visible, retryable stream error instead of a silent empty screen.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: Text(message),
      leading: const Icon(Icons.error_outline_rounded),
      actions: [TextButton(onPressed: onRetry, child: const Text('Retry'))],
    );
  }
}

// Clear empty state used only after a successful empty real-time snapshot.
class _EmptyCommunityState extends StatelessWidget {
  const _EmptyCommunityState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 5),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// Stable English labels are stored separately from enum names shown in code.
String _reportReasonLabel(CommunityReportReason reason) {
  return switch (reason) {
    CommunityReportReason.spam => 'Spam',
    CommunityReportReason.harassment => 'Harassment',
    CommunityReportReason.misinformation => 'Misinformation',
    CommunityReportReason.inappropriateContent => 'Inappropriate content',
    CommunityReportReason.copyright => 'Copyright concern',
    CommunityReportReason.other => 'Other',
  };
}

// A dependency-free timestamp keeps this beginner project easy to run.
String _formatMoment(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

// Snackbars keep operation feedback visible without exposing server internals.
void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
