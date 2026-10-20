import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:share_plus/share_plus.dart';
import 'package:scrole/app/theme/app_colors.dart';
import '../../centre/models/community_post.dart';
import '../../externe/repositories/home_feed_repository.dart';
import '../../../module_authentification/centre/services/auth_service.dart';
import '../../../../shared/widgets/user_certified_badge.dart';
import '../../../../shared/widgets/user_identity_row.dart';
import '../pages/create_story_screen.dart';
import '../../../module_communautes/interne/pages/community_post_mentions_screen.dart';

class CommunityCommentsSheet extends StatefulWidget {
  final CommunityPost post;
  final dynamic controller;

  const CommunityCommentsSheet({
    super.key,
    required this.post,
    required this.controller,
  });

  @override
  State<CommunityCommentsSheet> createState() => _CommunityCommentsSheetState();
}

class _CommunityCommentsSheetState extends State<CommunityCommentsSheet> {
  final HomeFeedRepository _repo = HomeFeedRepository();
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();

  bool _isLoading = true;
  List<Map<String, dynamic>> _comments = [];
  String? _nextCursor;
  bool _hasMore = false;

  final Map<String, List<Map<String, dynamic>>> _repliesMap = {};
  final Map<String, bool> _expandedReplies = {};
  final Map<String, bool> _loadingReplies = {};
  final Map<String, String?> _repliesNextCursor = {};
  final Map<String, bool> _repliesHasMore = {};

  Map<String, dynamic>? _replyingTo;
  final List<Map<String, dynamic>> _selectedMentions = [];

  final Map<String, PostReaction> _commentReactions = {};
  final Map<String, int> _commentLikeCounts = {};
  final Map<String, int> _commentDislikeCounts = {};

  Future<void> _toggleCommentReaction(String commentId, PostReaction reaction, int baseLikes, int baseDislikes) async {
    final current = _commentReactions[commentId] ?? PostReaction.none;
    final newReaction = current == reaction ? null : (reaction == PostReaction.like ? 'like' : 'dislike');

    setState(() {
      final likes = _commentLikeCounts[commentId] ?? baseLikes;
      final dislikes = _commentDislikeCounts[commentId] ?? baseDislikes;

      if (current == reaction) {
        _commentReactions[commentId] = PostReaction.none;
        if (reaction == PostReaction.like) _commentLikeCounts[commentId] = (likes > 0) ? likes - 1 : 0;
        if (reaction == PostReaction.dislike) _commentDislikeCounts[commentId] = (dislikes > 0) ? dislikes - 1 : 0;
      } else {
        if (current == PostReaction.like) _commentLikeCounts[commentId] = (likes > 0) ? likes - 1 : 0;
        if (current == PostReaction.dislike) _commentDislikeCounts[commentId] = (dislikes > 0) ? dislikes - 1 : 0;

        _commentReactions[commentId] = reaction;
        if (reaction == PostReaction.like) _commentLikeCounts[commentId] = likes + 1;
        if (reaction == PostReaction.dislike) _commentDislikeCounts[commentId] = dislikes + 1;
      }
    });

    try {
      await _repo.setCommentReaction(commentId, newReaction);
    } catch (e) {
      debugPrint('[POST_ACTIONS] Error setting comment reaction: $e');
      setState(() {
        _commentReactions[commentId] = current;
        _commentLikeCounts[commentId] = baseLikes;
        _commentDislikeCounts[commentId] = baseDislikes;
      });
    }
  }

  void _shareComment(Map<String, dynamic> comment) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareCommentSheetWidget(comment: comment, post: widget.post),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadComments({bool loadMore = false}) async {
    if (loadMore && (_isLoading || !_hasMore)) return;
    if (!loadMore) setState(() => _isLoading = true);

    try {
      final res = await _repo.getCommunityPostComments(
        widget.post.id,
        limit: 20,
        cursor: loadMore ? _nextCursor : null,
      );

      final items = res['items'] is List ? List<Map<String, dynamic>>.from(res['items']) : <Map<String, dynamic>>[];
      final nextCursor = res['next_cursor']?.toString();
      final hasMore = res['has_more'] == true;

      if (mounted) {
        setState(() {
          if (loadMore) {
            final existingIds = _comments.map((c) => c['id']?.toString()).toSet();
            for (final item in items) {
              if (!existingIds.contains(item['id']?.toString())) {
                _comments.add(item);
              }
            }
          } else {
            _comments = items;
          }
          _nextCursor = nextCursor;
          _hasMore = hasMore;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[POST_ACTIONS] Error loading comments: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadReplies(String commentId, {bool loadMore = false}) async {
    if (_loadingReplies[commentId] == true) return;
    if (loadMore && _repliesHasMore[commentId] != true) return;

    setState(() => _loadingReplies[commentId] = true);

    try {
      final cursor = loadMore ? _repliesNextCursor[commentId] : null;
      final res = await _repo.getCommunityCommentReplies(commentId, limit: 20, cursor: cursor);

      final items = res['items'] is List ? List<Map<String, dynamic>>.from(res['items']) : <Map<String, dynamic>>[];
      final nextCursor = res['next_cursor']?.toString();
      final hasMore = res['has_more'] == true;

      if (mounted) {
        setState(() {
          final existing = _repliesMap[commentId] ?? [];
          if (loadMore) {
            final existingIds = existing.map((r) => r['id']?.toString()).toSet();
            for (final item in items) {
              if (!existingIds.contains(item['id']?.toString())) {
                existing.add(item);
              }
            }
          } else {
            _repliesMap[commentId] = items;
          }
          _expandedReplies[commentId] = true;
          _repliesNextCursor[commentId] = nextCursor;
          _repliesHasMore[commentId] = hasMore;
          _loadingReplies[commentId] = false;
        });
      }
    } catch (e) {
      debugPrint('[POST_ACTIONS] Error loading replies: $e');
      if (mounted) setState(() => _loadingReplies[commentId] = false);
    }
  }

  Future<void> _openCommentMentions() async {
    final initialIds = _selectedMentions
        .map((m) => (m['user_id'] ?? m['id'] ?? m['user_profiles']?['user_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();
    final result = await Get.to<List<Map<String, dynamic>>>(
      () => const CommunityPostMentionsScreen(),
      arguments: {'communityId': widget.post.communityId ?? '', 'initialSelected': initialIds},
    );
    if (result == null || !mounted) return;
    setState(() {
      _selectedMentions
        ..clear()
        ..addAll(result);
    });
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final pId = const Uuid().v4();
    final currentUserId = Get.isRegistered<AuthService>() ? Get.find<AuthService>().userId ?? 'me' : 'me';

    final targetReplyTo = _replyingTo;
    final mentionIds = _selectedMentions
        .map((m) => (m['user_id'] ?? m['id'] ?? m['user_profiles']?['user_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final tempComment = {
      'id': pId,
      'post_id': widget.post.id,
      'author_id': currentUserId,
      'content': text,
      'created_at': DateTime.now().toIso8601String(),
      'parent_comment_id': targetReplyTo != null ? targetReplyTo['id']?.toString() : null,
      'replies_count': 0,
      'author': {
        'user_id': currentUserId,
        'username': 'Moi',
        'first_name': 'Moi',
      },
      'is_pending': true,
    };

    setState(() {
      if (targetReplyTo != null) {
        final parentId = targetReplyTo['id']?.toString();
        if (parentId != null) {
          _repliesMap[parentId] ??= [];
          _repliesMap[parentId]!.add(tempComment);
          _expandedReplies[parentId] = true;
        }
      } else {
        _comments.add(tempComment);
      }
      _commentController.clear();
      _replyingTo = null;
    });

    try {
      await _repo.commentCommunityPost(
        p_id: pId,
        postId: widget.post.id,
        content: text,
        mentions: mentionIds,
        parentCommentId: targetReplyTo != null ? targetReplyTo['id']?.toString() : null,
      );
      if (mounted) setState(() => _selectedMentions.clear());
      await _loadComments();
      if (targetReplyTo != null) {
        final parentId = targetReplyTo['id']?.toString();
        if (parentId != null) {
          await _loadReplies(parentId);
        }
      }
    } catch (e) {
      debugPrint('[POST_ACTIONS] Error submitting comment: $e');
      Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
      setState(() {
        if (targetReplyTo != null) {
          final parentId = targetReplyTo['id']?.toString();
          if (parentId != null) {
            _repliesMap[parentId]?.removeWhere((r) => r['id'] == pId);
          }
        } else {
          _comments.removeWhere((c) => c['id'] == pId);
        }
      });
    }
  }

  Future<void> _deleteComment(String commentId, bool isReply, String? parentId) async {
    try {
      await _repo.deleteCommunityComment(commentId);
      setState(() {
        if (isReply && parentId != null) {
          _repliesMap[parentId]?.removeWhere((r) => r['id'].toString() == commentId);
        } else {
          _comments.removeWhere((c) => c['id'].toString() == commentId);
          _repliesMap.remove(commentId);
        }
      });
      Get.snackbar('Succès', 'Commentaire supprimé', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  String _formatTime(String raw) {
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt != null) {
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.isNegative || diff.inSeconds < 60) return 'à l\'instant';
      if (diff.inMinutes < 60) return '${diff.inMinutes}min';
      if (diff.inHours < 24) return '${diff.inHours}h';
      if (diff.inDays < 7) return '${diff.inDays}j';
      return '${dt.day}/${dt.month}/${dt.year}';
    }
    return '';
  }

  Widget _buildHighlightedContent(String content, ColorScheme colorScheme) {
    if (!content.contains('@')) {
      return Text(content, style: TextStyle(fontSize: 13.5, color: colorScheme.onSurface, height: 1.35));
    }

    final words = content.split(' ');
    List<InlineSpan> spans = [];
    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      if (word.startsWith('@') && word.length > 1) {
        spans.add(TextSpan(
          text: '$word ',
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: colorScheme.primary, height: 1.35),
        ));
      } else {
        spans.add(TextSpan(
          text: '$word ',
          style: TextStyle(fontSize: 13.5, color: colorScheme.onSurface, height: 1.35),
        ));
      }
    }

    return RichText(text: TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!widget.post.commentsEnabled) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Commentaires désactivés', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Les commentaires sont désactivés sur cette publication.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer')),
          ],
        ),
      );
    }

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 15,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        bottom: true,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Commentaires', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Comments List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _comments.isEmpty
                        ? Center(
                            child: Text('Aucun commentaire pour le moment', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                          )
                        : RefreshIndicator(
                            onRefresh: () => _loadComments(),
                            child: ListView.builder(
                              itemCount: _comments.length + (_hasMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= _comments.length) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    child: Center(
                                      child: TextButton(
                                        onPressed: () => _loadComments(loadMore: true),
                                        child: const Text('Voir plus de commentaires'),
                                      ),
                                    ),
                                  );
                                }

                                final comment = _comments[index];
                                return _buildCommentItem(comment, isReply: false, parentId: null);
                              },
                            ),
                          ),
              ),

              // Replying banner
              if (_replyingTo != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Réponse à @${(_replyingTo!['author'] is Map ? _replyingTo!['author']['username'] : 'utilisateur')}',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colorScheme.primary),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _replyingTo = null),
                        child: Icon(Icons.close_rounded, size: 16, color: colorScheme.primary),
                      ),
                    ],
                  ),
                ),
              ],

              if (_selectedMentions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _selectedMentions.map((member) {
                      final profile = member['user_profiles'] is Map
                          ? Map<String, dynamic>.from(member['user_profiles'])
                          : member;
                      final username = (profile['username'] ?? member['username'] ?? 'membre').toString();
                      final id = (profile['user_id'] ?? profile['id'] ?? member['user_id'] ?? member['id'] ?? '').toString();
                      return InputChip(
                        label: Text('@$username'),
                        onDeleted: () => setState(() {
                          _selectedMentions.removeWhere((item) {
                            final nested = item['user_profiles'] is Map
                                ? Map<String, dynamic>.from(item['user_profiles'])
                                : item;
                            return (nested['user_id'] ?? nested['id'] ?? item['user_id'] ?? item['id'] ?? '').toString() == id;
                          });
                        }),
                      );
                    }).toList(),
                  ),
                ),

              // Modern Input field at bottom
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        focusNode: _commentFocusNode,
                        decoration: InputDecoration(
                          hintText: _replyingTo != null ? 'Écrire une réponse...' : 'Écrire un commentaire...',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        maxLines: null,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Mentionner des personnes',
                      visualDensity: VisualDensity.compact,
                      onPressed: _openCommentMentions,
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: _submitComment,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommentItem(Map<String, dynamic> comment, {required bool isReply, String? parentId}) {
    final colorScheme = Theme.of(context).colorScheme;
    final author = comment['author'] is Map ? Map<String, dynamic>.from(comment['author']) : <String, dynamic>{};
    final authorName = author['first_name'] != null ? '${author['first_name']} ${author['last_name'] ?? ''}'.trim() : (author['username']?.toString() ?? 'Utilisateur');
    final username = author['username']?.toString() ?? '';
    final avatar = author['photo_url']?.toString() ?? author['avatar_url']?.toString();
    final content = comment['content']?.toString() ?? '';
    final commentId = comment['id']?.toString() ?? '';
    final repliesCount = (comment['replies_count'] as num?)?.toInt() ?? 0;
    final isPending = comment['is_pending'] == true;
    final isCertified = author['is_certified'] == true || 
                        author['is_verified'] == true || 
                        author['is_certified'] == 1 || 
                        author['is_verified'] == 1 || 
                        author['certified'] == true || 
                        author['certified'] == 1 ||
                        author['is_certified']?.toString() == 'true' ||
                        author['is_verified']?.toString() == 'true';

    final currentUserId = Get.isRegistered<AuthService>() ? Get.find<AuthService>().userId : null;
    final isAuthor = currentUserId != null && currentUserId == comment['author_id']?.toString();
    final isPostAuthor = comment['author_id']?.toString() == widget.post.authorId;

    final baseLikes = (comment['likes_count'] as num?)?.toInt() ?? 0;
    final baseDislikes = (comment['dislikes_count'] as num?)?.toInt() ?? 0;
    final currentReaction = _commentReactions[commentId] ?? PostReaction.none;
    final currentLikes = _commentLikeCounts[commentId] ?? baseLikes;
    final currentDislikes = _commentDislikeCounts[commentId] ?? baseDislikes;

    return Padding(
      padding: EdgeInsets.only(left: isReply ? 36.0 : 0.0, top: 10, bottom: 10),
      child: Opacity(
        opacity: isPending ? 0.6 : 1.0,
        child: Container(
          padding: isReply ? const EdgeInsets.only(left: 12) : EdgeInsets.zero,
          decoration: isReply
              ? BoxDecoration(
                  border: Border(
                    left: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 2),
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserIdentityRow(
                name: authorName,
                username: username,
                avatarUrl: avatar,
                isCertified: isCertified,
                avatarRadius: isReply ? 15 : 18,
                subtitle: '· ${_formatTime(comment['created_at']?.toString() ?? '')}',
                nameStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: isReply ? 13 : 14, color: colorScheme.onSurface),
                usernameStyle: TextStyle(fontSize: isReply ? 11.5 : 12.5, color: colorScheme.onSurfaceVariant),
                trailing: isPostAuthor
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Auteur(ice)',
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: colorScheme.primary),
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 4),
              Padding(
                padding: EdgeInsets.only(left: (isReply ? 15 : 18) * 2 + 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHighlightedContent(content, colorScheme),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (isReply && parentId != null) {
                              final parent = _comments.firstWhereOrNull((c) => c['id'].toString() == parentId);
                              setState(() {
                                _replyingTo = parent ?? comment;
                                _commentController.text = '@$username ';
                                _commentController.selection = TextSelection.fromPosition(TextPosition(offset: _commentController.text.length));
                              });
                            } else {
                              setState(() {
                                _replyingTo = comment;
                                if (isReply && username.isNotEmpty) {
                                  _commentController.text = '@$username ';
                                  _commentController.selection = TextSelection.fromPosition(TextPosition(offset: _commentController.text.length));
                                }
                              });
                            }
                          },
                          child: Text(
                            'Répondre',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                        if (repliesCount > 0 && !isReply)
                          GestureDetector(
                            onTap: () {
                              if (_expandedReplies[commentId] == true) {
                                setState(() => _expandedReplies[commentId] = false);
                              } else {
                                _loadReplies(commentId);
                              }
                            },
                            child: Text(
                              _expandedReplies[commentId] == true ? 'Masquer' : '$repliesCount réponse(s)',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary),
                            ),
                          ),
                        if (isAuthor)
                          GestureDetector(
                            onTap: () => _deleteComment(commentId, isReply, parentId),
                            child: const Text(
                              'Supprimer',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.redAccent),
                            ),
                          ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () => _shareComment(comment),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Icon(Icons.ios_share_rounded, size: 15, color: colorScheme.onSurfaceVariant),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => _toggleCommentReaction(commentId, PostReaction.like, baseLikes, baseDislikes),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.north_rounded,
                                      size: 16,
                                      color: currentReaction == PostReaction.like ? AppColors.primary : colorScheme.onSurfaceVariant,
                                    ),
                                    if (currentLikes > 0) ...[
                                      const SizedBox(width: 2),
                                      Text('$currentLikes', style: TextStyle(fontSize: 11.5, color: currentReaction == PostReaction.like ? AppColors.primary : colorScheme.onSurfaceVariant, fontWeight: currentReaction == PostReaction.like ? FontWeight.bold : FontWeight.normal)),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () => _toggleCommentReaction(commentId, PostReaction.dislike, baseLikes, baseDislikes),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.south_rounded,
                                      size: 16,
                                      color: currentReaction == PostReaction.dislike ? Colors.orangeAccent : colorScheme.onSurfaceVariant,
                                    ),
                                    if (currentDislikes > 0) ...[
                                      const SizedBox(width: 2),
                                      Text('$currentDislikes', style: TextStyle(fontSize: 11.5, color: currentReaction == PostReaction.dislike ? Colors.orangeAccent : colorScheme.onSurfaceVariant, fontWeight: currentReaction == PostReaction.dislike ? FontWeight.bold : FontWeight.normal)),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Replies nested section
                    if (!isReply && repliesCount > 0 && _expandedReplies[commentId] == true)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          if (_loadingReplies[commentId] == true)
                            const Padding(
                              padding: EdgeInsets.only(top: 8, left: 16),
                              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                          if (_repliesMap[commentId] != null)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final reply in _repliesMap[commentId]!)
                                  _buildCommentItem(reply, isReply: true, parentId: commentId),
                                if (_repliesHasMore[commentId] == true)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 16, top: 4),
                                    child: TextButton(
                                      onPressed: () => _loadReplies(commentId, loadMore: true),
                                      child: const Text('Voir plus de réponses', style: TextStyle(fontSize: 12)),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareCommentSheetWidget extends StatelessWidget {
  final Map<String, dynamic> comment;
  final CommunityPost post;

  const _ShareCommentSheetWidget({
    required this.comment,
    required this.post,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final author = comment['author'] is Map ? Map<String, dynamic>.from(comment['author']) : <String, dynamic>{};
    final authorName = author['first_name'] != null ? '${author['first_name']} ${author['last_name'] ?? ''}'.trim() : (author['username']?.toString() ?? 'Utilisateur');
    final username = author['username']?.toString() ?? '';
    final content = comment['content']?.toString() ?? '';
    final commentId = comment['id']?.toString() ?? '';

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Partager le commentaire', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 16),

          // Compact Comment Preview
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(authorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    if (username.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text('@$username', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(content, style: TextStyle(fontSize: 12.5, color: colorScheme.onSurface), maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Destinations', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey), textAlign: TextAlign.left),
          const SizedBox(height: 14),

          // Horizontal Share Options Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // 1. Ma story
                _ShareCommentOptionItem(
                  svgAsset: 'assets/svg_icons/story-svgrepo-com.svg',
                  color: Colors.pink,
                  label: 'Ma story',
                  onTap: () {
                    Navigator.of(context).pop();
                    Get.to(() => CreateStoryScreen(
                          prefilledText: 'Commentaire de @$username : "$content"',
                        ));
                  },
                ),
                const SizedBox(width: 16),

                // 2. Republier sur mon fil
                _ShareCommentOptionItem(
                  svgAsset: 'assets/svg_icons/repost-round-svgrepo-com.svg',
                  color: colorScheme.primary,
                  label: 'Republier',
                  onTap: () async {
                    Navigator.of(context).pop();
                    final pId = const Uuid().v4();
                    try {
                      final repo = HomeFeedRepository();
                      await repo.shareComment(
                        p_id: pId,
                        p_comment_id: commentId,
                      );
                      Get.snackbar('Succès', 'Commentaire partagé sur votre fil avec succès !', snackPosition: SnackPosition.BOTTOM);
                    } catch (e) {
                      Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
                    }
                  },
                ),
                const SizedBox(width: 16),

                // 3. Communauté
                _ShareCommentOptionItem(
                  svgAsset: 'assets/svg_icons/ecosystem-svgrepo-com.svg',
                  color: Colors.purple,
                  label: 'Communauté',
                  onTap: () {
                    Navigator.of(context).pop();
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => _CommunityShareCommentSheet(commentId: commentId),
                    );
                  },
                ),
                const SizedBox(width: 16),

                // 4. Autres applications
                _ShareCommentOptionItem(
                  icon: Icons.ios_share_rounded,
                  color: Colors.green,
                  label: 'Autres apps',
                  onTap: () async {
                    Navigator.of(context).pop();
                    await Share.share('Commentaire de @$username sur Scrole : "$content"');
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _ShareCommentOptionItem extends StatelessWidget {
  final IconData? icon;
  final String? svgAsset;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ShareCommentOptionItem({
    this.icon,
    this.svgAsset,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
              ),
              alignment: Alignment.center,
              child: svgAsset != null
                  ? SvgPicture.asset(
                      svgAsset!,
                      width: 26,
                      height: 26,
                      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                    )
                  : Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityShareCommentSheet extends StatefulWidget {
  final String commentId;
  const _CommunityShareCommentSheet({required this.commentId});

  @override
  State<_CommunityShareCommentSheet> createState() => _CommunityShareCommentSheetState();
}

class _CommunityShareCommentSheetState extends State<_CommunityShareCommentSheet> {
  bool _isLoading = true;
  List<dynamic> _communities = [];

  @override
  void initState() {
    super.initState();
    _loadCommunities();
  }

  Future<void> _loadCommunities() async {
    try {
      final repo = HomeFeedRepository();
      final comms = await repo.client.rpc('get_my_communities');
      if (mounted) {
        setState(() {
          _communities = comms is List ? comms : [];
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Partager dans une communauté', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_communities.isEmpty)
            const Center(child: Text('Vous n\'avez rejoint aucune communauté'))
          else
            Expanded(
              child: ListView.builder(
                itemCount: _communities.length,
                itemBuilder: (context, index) {
                  final comm = _communities[index];
                  final commId = comm['id']?.toString() ?? '';
                  final commName = comm['name']?.toString() ?? 'Communauté';

                  return ListTile(
                    title: Text(commName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                    onTap: () async {
                      Navigator.of(context).pop();
                      final pId = const Uuid().v4();
                      try {
                        final repo = HomeFeedRepository();
                        await repo.shareComment(
                          p_id: pId,
                          p_comment_id: widget.commentId,
                          p_community_id: commId,
                        );
                        Get.snackbar('Succès', 'Commentaire partagé dans la communauté $commName !', snackPosition: SnackPosition.BOTTOM);
                      } catch (e) {
                        Get.snackbar('Erreur', e.toString().replaceFirst('Exception: ', '').tr, snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red, colorText: Colors.white);
                      }
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
