import 'dart:async';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import '../../../../app/media/media_asset.dart';
import '../../../../app/repository_global/r2_media_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../centre/models/message.dart';
import '../../centre/models/conversation.dart';

class SupabaseMessagingService {
  SupabaseMessagingService(this._client);
  final SupabaseClient _client;
  final Map<RealtimeChannel, Completer<void>> _typingReady = {};
  String? get currentUserId => _client.auth.currentUser?.id;

  Future<Conversation?> getOrCreateConversation(String otherUserId) async {
    final response = await _client.rpc('get_or_create_direct_conversation', params: {'p_other_user_id': otherUserId});
    if (response is Map) return _conversationFromRow(Map<String, dynamic>.from(response), otherUserId);
    if (response is List && response.isNotEmpty) {
      return _conversationFromRow(Map<String, dynamic>.from(response.first as Map), otherUserId);
    }
    if (response is String && response.isNotEmpty) {
      return Conversation(
        id: response,
        participantIds: [otherUserId],
        updatedAt: DateTime.now().toUtc(),
      );
    }
    return null;
  }

  Conversation _conversationFromRow(Map<String, dynamic> json, [String? fallbackOtherUserId]) {
    final first = json['other_first_name'] as String?;
    final last = json['other_last_name'] as String?;
    final username = json['other_username'] as String?;
    final display = [first, last].where((e) => e != null && e.trim().isNotEmpty).join(' ').trim();
    final other = '${json['other_user_id'] ?? fallbackOtherUserId ?? ''}';
    final participants = json['participant_ids'] is List
        ? List<String>.from(json['participant_ids'])
        : <String>[if (other.isNotEmpty) other];
    return Conversation(
      id: '${json['id']}',
      participantIds: participants,
      name: display.isNotEmpty
          ? display
          : (username ?? json['name'] as String?),
      avatarUrl: (json['other_photo_url'] ?? json['avatar_url']) as String?,
      updatedAt: json['updated_at'] == null ? DateTime.now().toUtc() : DateTime.parse('${json['updated_at']}').toUtc(),
    );
  }

  Future<List<Message>> fetchMessages(String conversationId, {int limit = 50, DateTime? before}) async {
    final response = await _client.rpc('get_direct_messages', params: {
      'p_conversation_id': conversationId,
      'p_limit': limit,
      'p_before': before?.toUtc().toIso8601String()
    });
    if (response is! List) return const [];
    return response.map((row) => Message.fromJson(Map<String, dynamic>.from(row as Map))).toList();
  }

  Future<List<Message>> fetchMissedMessages(String conversationId, DateTime? after) async {
    final response = await _client.rpc('get_direct_messages_after', params: {
      'p_conversation_id': conversationId,
      'p_after': after?.toUtc().toIso8601String(),
      'p_limit': 500
    });
    if (response is! List) return const [];
    return response.map((row) => Message.fromJson(Map<String, dynamic>.from(row as Map))).toList();
  }

  Future<List<Conversation>> fetchConversations() async {
    final response = await _client.rpc('get_my_direct_conversations');
    if (response is! List) return const [];
    return response.map((row) {
      final json = Map<String, dynamic>.from(row as Map);
      final other = '${json['other_user_id']}';
      final first = json['other_first_name'] as String?;
      final last = json['other_last_name'] as String?;
      final username = json['other_username'] as String?;
      final display = [first, last].where((e) => e != null && e.trim().isNotEmpty).join(' ').trim();
      final at = json['last_message_at'] as String?;
      final preview = json['last_message_text'] == null || at == null
          ? null
          : Message(
        id: '${json['last_message_id'] ?? ''}',
        localId: '${json['last_message_id'] ?? ''}',
        conversationId: '${json['id']}',
        senderId: '${json['last_message_sender_id'] ?? ''}',
        content: json['last_message_text'] as String?,
        type: MessageType.values.firstWhere((e) => e.name == json['last_message_type'], orElse: () => MessageType.text),
        sentAt: DateTime.parse(at).toUtc(),
      );
      return Conversation(
        id: '${json['id']}',
        participantIds: [other],
        lastMessagePreview: preview,
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.parse('${at ?? DateTime.now().toIso8601String()}').toUtc(),
        name: display.isNotEmpty ? display : username,
        avatarUrl: json['other_photo_url'] as String?,
      );
    }).toList();
  }

  Future<void> deleteConversationForMe(String conversationId) async {
    if (conversationId.isEmpty) throw ArgumentError('conversationId');
    await _client.rpc('delete_my_direct_conversation', params: {'p_conversation_id': conversationId});
  }

  Future<Message?> insertMessage(Message message) async {
    final response = await _client.rpc('insert_direct_message', params: {
      'p_message_id': message.id,
      'p_conversation_id': message.conversationId,
      'p_text': message.content,
      'p_type': message.type.name,
      'p_audio_url': message.audioUrl,
      'p_media_urls': message.mediaUrls ?? <String>[],
      'p_replied_to_id': message.repliedToId
    });
    if (response is Map) return Message.fromJson(Map<String, dynamic>.from(response));
    if (response is List && response.isNotEmpty) return Message.fromJson(Map<String, dynamic>.from(response.first as Map));
    return null;
  }

  Future<Message?> editMessage(String id, String content) async {
    final response = await _client.rpc('edit_direct_message', params: {'p_message_id': id, 'p_text': content});
    if (response is Map) return Message.fromJson(Map<String, dynamic>.from(response));
    if (response is List && response.isNotEmpty) return Message.fromJson(Map<String, dynamic>.from(response.first as Map));
    return null;
  }

  Future<Message?> deleteForEveryone(String id) async {
    final response = await _client.rpc('delete_direct_message', params: {'p_message_id': id});
    if (response is Map) return Message.fromJson(Map<String, dynamic>.from(response));
    if (response is List && response.isNotEmpty) return Message.fromJson(Map<String, dynamic>.from(response.first as Map));
    return null;
  }

  Future<void> markDelivered(String id, {bool cleanupMedia = true}) async {
    await _client.rpc('mark_direct_message_delivered', params: {'p_message_id': id});
    if (!cleanupMedia) return;

    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final response = await _client.functions.invoke(
          'delete-delivered-message-media',
          body: {'message_id': id},
        );
        if (response.status < 200 || response.status >= 300 ||
            response.data is! Map || (response.data as Map)['deleted'] != true) {
          throw StateError('Nettoyage média R2 refusé: ${response.data}');
        }
        return;
      } catch (error) {
        lastError = error;
        debugPrint('[Messaging] R2 media cleanup attempt $attempt/3 failed for $id: $error');
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
        }
      }
    }
    // Propagate failure so the incoming-message path and future sync/realtime
    // deliveries can retry instead of silently treating cleanup as complete.
    throw StateError('Nettoyage R2 différé après 3 tentatives: $lastError');
  }
  Future<void> markRead(String conversationId, DateTime at, String id) => _client.rpc('mark_direct_conversation_read_cursor', params: {
    'p_conversation_id': conversationId,
    'p_last_read_at': at.toUtc().toIso8601String(),
    'p_last_read_message_id': id
  });

  Future<void> sendTyping(RealtimeChannel channel, bool typing) async {
    final ready = _typingReady[channel];
    if (ready != null && !ready.isCompleted) await ready.future;
    if (typing) {
      await channel.track({
        'user_id': currentUserId,
        'typing': true,
        'updated_at': DateTime.now().toUtc().toIso8601String()
      });
    } else {
      await channel.untrack();
    }
  }

  RealtimeChannel subscribeInbox({
    required void Function(Message) onMessage,
    void Function(String messageId)? onDeleted,
    void Function(RealtimeSubscribeStatus status, Object? error)? onStatus,
  }) {
    final uid = currentUserId ?? 'anon';
    final channel = _client.channel('messaging-inbox:$uid');
    _bindMessageChanges(channel, onMessage: onMessage, onDeleted: onDeleted);
    channel.subscribe(onStatus);
    return channel;
  }

  RealtimeChannel subscribeMessages(
      String conversationId,
      void Function(Message) onMessage, {
        void Function(String messageId)? onDeleted,
        void Function(Map<String, dynamic>)? onReceipt,
        void Function(RealtimeSubscribeStatus status, Object? error)? onStatus,
      }) {
    final channel = _client.channel('messaging:$conversationId');
    _bindMessageChanges(
      channel,
      onMessage: onMessage,
      onDeleted: onDeleted,
      conversationId: conversationId,
    );
    if (onReceipt != null) {
      channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'direct_message_receipts',
          callback: (payload) {
            final record = payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord;
            if (record.isNotEmpty) onReceipt(Map<String, dynamic>.from(record));
          });
    }
    channel.subscribe(onStatus);
    return channel;
  }

  void _bindMessageChanges(
      RealtimeChannel channel, {
        required void Function(Message) onMessage,
        void Function(String messageId)? onDeleted,
        String? conversationId,
      }) {
    channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'direct_messages',
        filter: conversationId == null
            ? null
            : PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: conversationId),
        callback: (payload) {
          if (payload.eventType == PostgresChangeEvent.delete) {
            final id = payload.oldRecord['id']?.toString();
            if (id != null && id.isNotEmpty) onDeleted?.call(id);
            return;
          }
          final record = payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord;
          if (record.isNotEmpty) {
            onMessage(Message.fromJson(Map<String, dynamic>.from(record)));
          }
        });
  }

  RealtimeChannel subscribeTyping(String conversationId, void Function(bool) onTyping) {
    final channel = _client.channel('messaging-typing:$conversationId');
    final ready = Completer<void>();
    _typingReady[channel] = ready;
    void emit() {
      final uid = currentUserId;
      onTyping(channel.presenceState().expand((s) => s.presences).any((p) => p.payload['user_id']?.toString() != uid && p.payload['typing'] == true));
    }

    channel.onPresenceSync((_) => emit()).onPresenceJoin((_) => emit()).onPresenceLeave((_) => emit()).subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed && !ready.isCompleted) ready.complete();
      if (status == RealtimeSubscribeStatus.channelError && !ready.isCompleted) ready.completeError(error ?? Exception('typing_channel_error'));
    });
    return channel;
  }

  Future<void> unsubscribe(RealtimeChannel channel) async {
    _typingReady.remove(channel);
    await _client.removeChannel(channel);
  }

  /// Uploads a cross-platform media asset to private chat storage in R2.
  Future<String?> uploadMediaAsset(
    MediaAsset media,
    String folder, {
    String? contentType,
    String? conversationId,
    double? durationSeconds,
  }) async {
    if (conversationId == null || conversationId.isEmpty) {
      throw ArgumentError('conversationId is required for private chat media');
    }
    final type = (contentType ?? media.mimeType ?? '').toLowerCase();
    final mediaType = type.startsWith('video/')
        ? 'video'
        : type.startsWith('audio/')
            ? 'audio'
            : 'image';
    final uploaded = await R2MediaRepository().uploadMediaAsset(
      media: media,
      category: 'message_media',
      mediaType: mediaType,
      entityId: conversationId,
      videoDuration: durationSeconds == null
          ? null
          : Duration(milliseconds: (durationSeconds * 1000).round()),
    );
    return uploaded.isPublic ? uploaded.publicUrl : uploaded.objectKey;
  }

  /// Uploads chat media to Cloudflare R2. Images are compressed on-device first.
  /// [folder] may be a conversation ID or a descriptive folder; private R2
  /// authorization is bound to the conversation ID passed as [conversationId].
  Future<String?> uploadFile(
      String localPath,
      String folder, {
        String? contentType,
        String? conversationId,
        double? durationSeconds,
      }) async {
    if (localPath.startsWith('data:')) {
      final comma = localPath.indexOf(',');
      if (comma < 0) throw ArgumentError('Invalid media data URL');
      final header = localPath.substring(5, comma).split(';');
      final mime = header.first;
      final namePart = header.where((part) => part.startsWith('name=')).firstOrNull;
      final name = namePart == null ? 'voice_message.${_extensionForMime(mime)}' :
          Uri.decodeComponent(namePart.substring(5));
      final bytes = base64Decode(localPath.substring(comma + 1));
      return uploadMediaAsset(
        MediaAsset.fromXFile(XFile.fromData(bytes, name: name, mimeType: mime)),
        folder,
        contentType: mime,
        conversationId: conversationId,
        durationSeconds: durationSeconds,
      );
    }

    final uri = Uri.tryParse(localPath);
    final name = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : 'chat_attachment.bin';
    final bytes = await XFile(localPath).readAsBytes();
    final mime = (contentType ?? _mimeFromName(name)).toLowerCase();
    return uploadMediaAsset(
      MediaAsset.fromXFile(XFile.fromData(bytes, name: name, mimeType: mime)),
      folder,
      contentType: mime,
      conversationId: conversationId,
      durationSeconds: durationSeconds,
    );
  }

  String _mimeFromName(String name) {
    final extension = name.split('.').last.toLowerCase();
    return const {
      'm4a': 'audio/mp4',
      'aac': 'audio/aac',
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'webm': 'video/webm',
      'png': 'image/png',
      'webp': 'image/webp',
      'gif': 'image/gif',
    }[extension] ?? 'image/jpeg';
  }

  String _extensionForMime(String mime) => const {
    'audio/mp4': 'm4a',
    'audio/aac': 'aac',
    'audio/mpeg': 'mp3',
    'audio/wav': 'wav',
    'video/mp4': 'mp4',
    'video/quicktime': 'mov',
    'video/webm': 'webm',
    'image/png': 'png',
    'image/webp': 'webp',
    'image/gif': 'gif',
    'image/jpeg': 'jpg',
  }[mime.toLowerCase()] ?? 'bin';
}
