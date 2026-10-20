import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';
import 'package:scrole/modules/module_principale/centre/models/post_comment.dart';

void main() {
  group('PostComment state reconciliation', () {
    const comment = PostComment(
      id: 'comment-1',
      authorName: 'Test',
      authorId: 'user-1',
      authorColor: Colors.blue,
      timeAgo: 'now',
      content: 'Comment',
      likesCount: 3,
      userReaction: PostReaction.like,
      repliesCount: 2,
    );

    test('changing the server ID preserves reaction and reply count', () {
      final reconciled = comment.copyWith(id: 'server-comment-1');

      expect(reconciled.id, 'server-comment-1');
      expect(reconciled.likesCount, 3);
      expect(reconciled.userReaction, PostReaction.like);
      expect(reconciled.repliesCount, 2);
    });

    test('reply count can be updated optimistically', () {
      final updated = comment.copyWith(repliesCount: 3);

      expect(updated.repliesCount, 3);
      expect(updated.id, comment.id);
      expect(updated.userReaction, PostReaction.like);
    });
  });
}
