import 'dart:async';
import 'dart:io';
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

  Future<void> markDelivered(String id) => _client.rpc('mark_direct_message_delivered', params: {'p_message_id': id});
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

  Future<String?> uploadFile(String localPath, String folder, {String? contentType}) async {
    final uid = currentUserId;
    if (uid == null) return null;
    final file = File(localPath);
    if (!await file.exists()) return null;
    final name = file.uri.pathSegments.last;
    final path = '$uid/chat/$folder/${DateTime.now().microsecondsSinceEpoch}_$name';
    await _client.storage.from('chat-media').upload(path, file, fileOptions: FileOptions(contentType: contentType, upsert: false));
    return path;
  }
}
