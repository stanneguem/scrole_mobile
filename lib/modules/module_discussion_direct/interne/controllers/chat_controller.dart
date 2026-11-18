import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:scrole/modules/module_discussion_direct/centre/services/chat_media_cache.dart';
import '../../../../app/local_storage/fast/fast_cache_service.dart';
import '../../../../app/routes/app_pages.dart';
import '../../../../app/service_global/notification_service.dart';
import '../../../../app/service_global/media_image_processor.dart';
import 'package:scrole/modules/module_discussion_direct/centre/models/message_model.dart';
import 'package:scrole/modules/module_discussion_direct/centre/repositories/messaging_repository.dart';
import 'package:scrole/modules/module_discussion_direct/centre/models/message.dart';
import '../../../../shared/widgets/media_gallery_sheet.dart';

enum RecordingState { idle, recording, reviewing }

class ChatController extends GetxController {
  ChatController(this._repository);
  final MessagingRepository _repository;
  String conversationId = Get.parameters['chatId'] ?? '';
  String otherUserId = Get.arguments?['userId']?.toString() ?? '';
  final RxString otherUserName = ((Get.arguments?['name']?.toString().trim().isNotEmpty ?? false)
          ? Get.arguments!['name'].toString()
          : 'Ami')
      .obs;
  final Color otherUserColor = Get.arguments?['color'] is Color ? Get.arguments['color'] as Color : Colors.blue;
  final RxnString otherUserAvatar = RxnString(Get.arguments?['avatar']?.toString());
  final TextEditingController messageController = TextEditingController();
  final RxList<MessageModel> messages = <MessageModel>[].obs;
  final RxBool isTyping = false.obs;
  final RxBool isOtherUserTyping = false.obs;
  final RxBool blockedByOtherUser = false.obs;
  final RxBool blockedByMe = false.obs;
  final RxBool conversationNotificationsEnabled = true.obs;
  final RxBool saveIncomingMediaToGallery = true.obs;
  final RxBool _conversationPreferencesLoaded = false.obs;
  final Set<String> _autoSavedMediaMessageIds = <String>{};
  final Set<String> _knownMessageIds = <String>{};
  bool _hasInitialMessageSnapshot = false;
  final List<MessageModel> _pendingIncomingMedia = <MessageModel>[];
  final RxBool showEmojiPicker = false.obs;
  final Rxn<MessageModel> repliedMessage = Rxn<MessageModel>();
  final Rxn<MessageModel> editingMessage = Rxn<MessageModel>();
  final RxBool isLoading = true.obs;
  final RxBool isUploading = false.obs;
  final RxInt unreadCount = 0.obs;
  final RxnString firstUnreadMessageId = RxnString();
  final Rxn<DateTime> lastReadAt = Rxn<DateTime>();
  final RxnString lastReadMessageId = RxnString();
  final AudioRecorder audioRecorder = AudioRecorder();
  final AudioPlayer audioPlayer = AudioPlayer();
  final Rx<RecordingState> recordingState = RecordingState.idle.obs;
  final RxInt recordingDuration = 0.obs;
  final RxDouble swipeOffset = 0.0.obs;
  final RxBool isPlayingReview = false.obs;
  String? _lastWatchedId;
  StreamSubscription<List<Message>>? _messagesSub;
  StreamSubscription<bool>? _typingSub;
  StreamSubscription? _audioSub;
  Timer? _typingTimer;
  Timer? _readDebounce;
  Timer? _recordingTimer;
  Timer? _otherUserTypingTimer;
  final Set<String> _pendingReadIds = {};
  StreamSubscription<Uint8List>? _recordingStreamSub;
  final List<int> _recordingChunks = <int>[];
  String? get currentUserId => _repository.currentUserId;
  bool get isDraftConversation => conversationId.startsWith('draft_');

  final RxString selectedWallpaper = 'fond1'.obs;

  void _loadWallpaper() {
    if (!Get.isRegistered<FastCacheService>()) return;
    final cache = Get.find<FastCacheService>();
    final targetId = conversationId.isNotEmpty ? conversationId : otherUserId;
    if (targetId.isEmpty) return;
    selectedWallpaper.value = cache.get<String>('chat_wallpaper_$targetId') ?? 'fond1';
  }

  Future<void> setWallpaper(String wallpaperKey) async {
    selectedWallpaper.value = wallpaperKey;
    selectedWallpaper.refresh();
    final targetId = conversationId.isNotEmpty ? conversationId : otherUserId;
    if (Get.isRegistered<FastCacheService>() && targetId.isNotEmpty) {
      await Get.find<FastCacheService>().set('chat_wallpaper_$targetId', wallpaperKey);
    }
  }

  @override
  void onInit() {
    super.onInit();
    _loadWallpaper();
    unawaited(refreshBlockStatus());
    unawaited(loadConversationPreferences());
    _bindConversation();
    messageController.addListener(_composerChanged);
    _audioSub = audioPlayer.playerStateStream.listen((state) => isPlayingReview.value = state.playing);
  }

  void _bindConversation() {
    if (_lastWatchedId != null) {
      unawaited(_repository.stopWatchingConversation(_lastWatchedId!));
    }
    _messagesSub?.cancel();
    _typingSub?.cancel();
    final id = conversationId;
    if (id.isEmpty || id.startsWith('draft_')) {
      _lastWatchedId = null;
      NotificationService.instance.setActiveConversation(null);
      isLoading.value = false;
      return;
    }

    _lastWatchedId = id;
    NotificationService.instance.setActiveConversation(id);
    isLoading.value = true;
    _messagesSub = _repository.watchConversation(id).listen((items) {
      final converted = items.map(MessageModel.fromMessage).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final newlyReceived = converted
          .where((message) => _knownMessageIds.add(message.id))
          .toList(growable: false);
      messages.assignAll(converted);
      if (_hasInitialMessageSnapshot && newlyReceived.isNotEmpty) {
        _pendingIncomingMedia.addAll(newlyReceived);
        unawaited(_autoSaveIncomingMedia(newlyReceived));
      }
      _hasInitialMessageSnapshot = true;
      _recalculateUnread();
      isLoading.value = false;
    }, onError: (_) => isLoading.value = false);
    _typingSub = _repository.watchTyping(id).listen((value) {
      _otherUserTypingTimer?.cancel();
      isOtherUserTyping.value = value;
      if (value) {
        _otherUserTypingTimer = Timer(const Duration(seconds: 4), () => isOtherUserTyping.value = false);
      }
    });
    unawaited(_initialize(id));
  }

  Future<void> loadConversationPreferences() async {
    final uid = currentUserId;
    if (uid == null || otherUserId.isEmpty || uid == otherUserId) return;
    try {
      final row = await Supabase.instance.client
          .from('direct_conversation_preferences')
          .select('notifications_enabled,save_media_to_gallery')
          .eq('user_id', uid)
          .eq('other_user_id', otherUserId)
          .maybeSingle();
      if (row == null) {
        _conversationPreferencesLoaded.value = true;
        if (_pendingIncomingMedia.isNotEmpty) {
          final pending = List<MessageModel>.from(_pendingIncomingMedia);
          _pendingIncomingMedia.clear();
          unawaited(_autoSaveIncomingMedia(pending));
        }
        return;
      }
      conversationNotificationsEnabled.value =
          row['notifications_enabled'] as bool? ?? true;
      saveIncomingMediaToGallery.value =
          row['save_media_to_gallery'] as bool? ?? true;
      _conversationPreferencesLoaded.value = true;
      if (saveIncomingMediaToGallery.value && _pendingIncomingMedia.isNotEmpty) {
        final pending = List<MessageModel>.from(_pendingIncomingMedia);
        _pendingIncomingMedia.clear();
        unawaited(_autoSaveIncomingMedia(pending));
      } else {
        _pendingIncomingMedia.clear();
      }
    } catch (e) {
      _conversationPreferencesLoaded.value = false;
      _pendingIncomingMedia.clear();
      debugPrint('[ChatPreferences] load failed: $e');
    }
  }

  Future<void> updateConversationPreference({
    bool? notificationsEnabled,
    bool? saveMediaToGallery,
  }) async {
    final uid = currentUserId;
    if (uid == null || otherUserId.isEmpty || uid == otherUserId) {
      throw StateError('Utilisateur invalide.');
    }
    final nextNotifications =
        notificationsEnabled ?? conversationNotificationsEnabled.value;
    final nextMedia = saveMediaToGallery ?? saveIncomingMediaToGallery.value;
    await Supabase.instance.client
        .from('direct_conversation_preferences')
        .upsert({
          'user_id': uid,
          'other_user_id': otherUserId,
          'notifications_enabled': nextNotifications,
          'save_media_to_gallery': nextMedia,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id,other_user_id');
    conversationNotificationsEnabled.value = nextNotifications;
    saveIncomingMediaToGallery.value = nextMedia;
    _conversationPreferencesLoaded.value = true;
  }

  Future<void> _autoSaveIncomingMedia(List<MessageModel> currentMessages) async {
    if (!_conversationPreferencesLoaded.value) return;
    if (!saveIncomingMediaToGallery.value) {
      _pendingIncomingMedia.clear();
      return;
    }
    for (final message in currentMessages) {
      if (message.senderId == currentUserId ||
          message.type != MessageType.image ||
          message.mediaUrls == null ||
          message.mediaUrls!.isEmpty ||
          !_autoSavedMediaMessageIds.add(message.id)) {
        continue;
      }
      _pendingIncomingMedia.removeWhere((pending) => pending.id == message.id);
      for (final mediaUrl in message.mediaUrls!) {
        try {
          final localPath = await _repository.resolveLocalMedia(message.id, mediaUrl) ??
              await _repository.cacheMedia(message.id, mediaUrl).then(
                (result) => result.success ? result.data : null,
              );
          if (localPath == null || !saveIncomingMediaToGallery.value) continue;
          final rawPath = Uri.tryParse(mediaUrl)?.path ?? mediaUrl;
          final extension = rawPath.split('/').last.contains('.')
              ? '.${rawPath.split('/').last.split('.').last.toLowerCase()}'
              : '.jpg';
          final safeExtension = const {'.jpg', '.jpeg', '.png', '.webp'}.contains(extension)
              ? extension
              : '.jpg';
          await ChatMediaCache.instance.saveToGallery(
            sourcePath: localPath,
            fileName: 'scrole_chat_${DateTime.now().millisecondsSinceEpoch}$safeExtension',
          );
        } catch (e) {
          debugPrint('[ChatMedia] auto-save failed: $e');
        }
      }
    }
  }

  Future<void> _initialize(String id) async {
    final cursor = await _repository.getLocalReadCursor(id);
    if (cursor != null) {
      lastReadAt.value = cursor.$1;
      lastReadMessageId.value = cursor.$2;
    }
    await _repository.syncConversation(id);
  }

  Future<bool> _ensureRealConversation() async {
    if (!isDraftConversation) return true;
    final result = await _repository.resolveConversationForFirstMessage(
      otherUserId,
      conversationId,
      otherUserName: otherUserName.value,
      otherUserAvatar: otherUserAvatar.value,
    );
    if (!result.success || result.data == null) {
      _showError(result.message);
      return false;
    }
    conversationId = result.data!.id;
    final peer = result.data!;
    if (peer.peerId(currentUserId)?.isNotEmpty == true) {
      otherUserId = peer.peerId(currentUserId)!;
    }
    if (peer.name != null && peer.name!.trim().isNotEmpty) {
      otherUserName.value = peer.name!;
    }
    if (peer.avatarUrl != null && peer.avatarUrl!.trim().isNotEmpty) {
      otherUserAvatar.value = peer.avatarUrl;
    }
    messages.clear();
    _bindConversation();
    return true;
  }

  void _composerChanged() {
    final active = messageController.text.trim().isNotEmpty;
    isTyping.value = active;
    _typingTimer?.cancel();
    if (isDraftConversation) return;
    _typingTimer = Timer(const Duration(milliseconds: 450), () => unawaited(_repository.setTyping(conversationId, active)));
  }

  void _recalculateUnread() {
    final uid = currentUserId;
    if (uid == null) return;
    final cursor = lastReadAt.value;
    final unread = messages.where((m) => m.senderId != uid && !m.isDeleted && (cursor == null || m.createdAt.isAfter(cursor))).toList();
    unreadCount.value = unread.length;
    firstUnreadMessageId.value = unread.isEmpty ? null : unread.last.id;
  }

  void queueVisibleMessageAsRead(MessageModel message) {
    if (isDraftConversation || message.senderId == currentUserId || message.isDeleted || message.id.isEmpty) return;
    _pendingReadIds.add(message.id);
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 450), _flushReads);
  }

  Future<void> _flushReads() async {
    if (_pendingReadIds.isEmpty || isDraftConversation) return;
    final candidates = messages.where((m) => _pendingReadIds.contains(m.id) && m.senderId != currentUserId && !m.isDeleted).toList();
    _pendingReadIds.clear();
    if (candidates.isEmpty) return;
    candidates.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final last = candidates.last;
    if (lastReadAt.value != null && !last.createdAt.isAfter(lastReadAt.value!)) return;
    lastReadAt.value = last.createdAt;
    lastReadMessageId.value = last.id;
    await _repository.markConversationRead(conversationId, last.id, last.createdAt);
    _recalculateUnread();
  }

  Future<void> sendMessage() async {
    if (editingMessage.value != null) {
      await saveEditedMessage();
      return;
    }
    final text = messageController.text.trim();
    final uid = currentUserId;
    if (text.isEmpty || uid == null || conversationId.isEmpty) return;
    if (!await _ensureRealConversation()) return;
    _stopTyping();
    final localId = _repository.generateLocalId();
    final message = MessageModel(id: localId, localId: localId, conversationId: conversationId, senderId: uid, text: text, type: MessageType.text, createdAt: DateTime.now().toUtc(), status: MessageStatus.sending, repliedToId: repliedMessage.value?.id);
    messageController.clear();
    clearReply();
    final result = await _repository.sendMessage(message);
    if (!result.success) {
      _showError(result.message);
    } else {
      unawaited(_repository.syncConversations());
    }
  }

  void beginEditing(MessageModel message) {
    if (message.senderId != currentUserId || message.type != MessageType.text || message.text == null) return;
    editingMessage.value = message;
    clearReply();
    messageController.text = message.text!;
    messageController.selection = TextSelection.collapsed(offset: messageController.text.length);
    Future<void>.delayed(const Duration(milliseconds: 50), () => FocusManager.instance.primaryFocus?.requestFocus());
  }

  void cancelEditing() { editingMessage.value = null; messageController.clear(); }

  Future<void> saveEditedMessage() async {
    final message = editingMessage.value;
    final content = messageController.text.trim();
    if (message == null || content.isEmpty) return;
    final result = await _repository.editMessage(message.id, content);
    if (result.success) { editingMessage.value = null; messageController.clear(); } else { _showError(result.message); }
  }

  Future<void> retryMessage(String localId) async {
    final result = await _repository.retryMessage(localId);
    if (!result.success) _showError(result.message);
  }

  Future<void> deleteMessageForMe(String id) async { final result = await _repository.deleteForMe(id); if (!result.success) _showError(result.message); }
  Future<void> deleteMessageForEveryone(String id) async { final result = await _repository.deleteForEveryone(id); if (!result.success) _showError(result.message); }
  Future<void> deleteMessage(String id) => deleteMessageForEveryone(id);
  void setReply(MessageModel message) { if (editingMessage.value != null) cancelEditing(); repliedMessage.value = message; }
  void clearReply() => repliedMessage.value = null;
  void onBack() => Get.back();
  void goToOtherUserProfile() { if (otherUserId.isNotEmpty) Get.toNamed(AppPages.externalProfilePath(otherUserId)); }

  Future<void> refreshBlockStatus() async {
    if (otherUserId.isEmpty) return;
    try {
      final result = await Supabase.instance.client.rpc(
        'scrole_get_direct_block_status',
        params: {'p_other_user_id': otherUserId},
      );
      final row = result is List && result.isNotEmpty ? result.first : result;
      if (row is Map) {
        blockedByMe.value = row['blocked_by_me'] == true;
        blockedByOtherUser.value = row['blocked_me'] == true;
      }
    } catch (_) {
      // Keep the chat available if status lookup fails; server still rejects blocked sends.
    }
  }

  Future<void> toggleBlockOtherUser() async {
    if (otherUserId.isEmpty) throw StateError('Utilisateur invalide.');
    if (blockedByMe.value) {
      await Supabase.instance.client.rpc(
        'scrole_unblock_direct_user',
        params: {'p_other_user_id': otherUserId},
      );
    } else {
      await Supabase.instance.client.rpc(
        'scrole_block_direct_user',
        params: {'p_other_user_id': otherUserId},
      );
    }
    await refreshBlockStatus();
    if (!blockedByMe.value && !blockedByOtherUser.value) {
      // Status is now clear on both sides; the composer can become available again.
      blockedByMe.refresh();
      blockedByOtherUser.refresh();
    }
  }

  Future<void> reportOtherUser(String reason, String? details) async {
    if (otherUserId.isEmpty) throw StateError('Utilisateur invalide.');
    await Supabase.instance.client.rpc('scrole_report_direct_user', params: {
      'p_reported_user_id': otherUserId,
      'p_reason': reason,
      'p_details': details,
    });
  }

  Future<void> clearConversationForMe() async {
    if (conversationId.isEmpty || isDraftConversation) return;
    final result = await _repository.deleteConversation(conversationId);
    if (!result.success) throw StateError(result.message ?? 'Impossible de supprimer la discussion.');
    messages.clear();
  }

  Future<void> pickMedia() => pickGalleryMedia();
  Future<void> pickCameraMedia() async { final file = await ImagePicker().pickImage(source: ImageSource.camera); if (file != null) await _sendMedia([file]); }
  Future<void> pickGalleryMedia() async {
    await Get.bottomSheet<void>(
      MediaGallerySheet(
        maxSelection: 4,
        onSelected: (files) {
          Get.back();
          unawaited(_sendMedia(files));
        },
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
    );
  }

  Future<void> _sendMedia(List<XFile> files) async {
    final uid = currentUserId;
    if (uid == null || conversationId.isEmpty) return;
    if (!await _ensureRealConversation()) return;
    isUploading.value = true;
    try {
      final localId = _repository.generateLocalId();
      final persistedMedia = <String>[];
      var hasVideo = false;
      for (final picked in files) {
        final pickedName = picked.name.isNotEmpty ? picked.name : 'attachment';
        final pickedExtension = pickedName.contains('.') ? pickedName.split('.').last.toLowerCase() : '';
        final pickedIsVideo = picked.mimeType?.startsWith('video/') == true ||
            const {'mp4', 'mov', 'webm'}.contains(pickedExtension);
        final file = pickedIsVideo || pickedExtension == 'gif'
            ? picked
            : await compressSelectedImage(picked, quality: 82);
        final name = file.name.isNotEmpty ? file.name : pickedName;
        final extension = name.contains('.') ? name.split('.').last.toLowerCase() : '';
        final mime = file.mimeType ??
            (const {'mp4': 'video/mp4', 'mov': 'video/quicktime', 'webm': 'video/webm'}
                    .containsKey(extension)
                ? const {'mp4': 'video/mp4', 'mov': 'video/quicktime', 'webm': 'video/webm'}[extension]!
                : const {'png': 'image/png', 'webp': 'image/webp', 'gif': 'image/gif'}
                        .containsKey(extension)
                    ? const {'png': 'image/png', 'webp': 'image/webp', 'gif': 'image/gif'}[extension]!
                    : 'image/jpeg');
        hasVideo = hasVideo || mime.startsWith('video/');
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) throw StateError('Le fichier sélectionné est vide.');
        if (bytes.lengthInBytes > 30 * 1024 * 1024) {
          throw StateError('Chaque pièce jointe doit faire au maximum 30 Mo.');
        }
        final encodedName = Uri.encodeComponent(name);
        persistedMedia.add('data:$mime;name=$encodedName;base64,${base64Encode(bytes)}');
      }
      final message = MessageModel(
        id: localId,
        localId: localId,
        conversationId: conversationId,
        senderId: uid,
        type: hasVideo ? MessageType.video : MessageType.image,
        mediaUrls: persistedMedia,
        createdAt: DateTime.now().toUtc(),
        status: MessageStatus.sending,
        repliedToId: repliedMessage.value?.id,
      );
      clearReply();
      final result = await _repository.sendMediaMessage(message);
      if (!result.success) {
        _showError(result.message);
      } else {
        unawaited(_repository.syncConversations());
      }
    } finally { isUploading.value = false; }
  }

  Future<void> startRecording() async {
    try {
      // Sur le Web, le navigateur demande lui-même l’autorisation microphone
      // via getUserMedia. permission_handler n’est utilisé que sur mobile.
      if (!kIsWeb) {
        final permission = await Permission.microphone.request();
        if (!permission.isGranted) {
          _showError('L’accès au micro est nécessaire pour enregistrer.');
          return;
        }
      }
      await audioPlayer.stop();
      _recordingChunks.clear();
      final stream = await audioRecorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
      ));
      _recordingStreamSub?.cancel();
      _recordingStreamSub = stream.listen(
        _recordingChunks.addAll,
        onError: (Object error) {
          debugPrint('[ChatVoice] recording stream failed: $error');
          _showError('Une erreur est survenue pendant l’enregistrement.');
        },
      );
      recordingState.value = RecordingState.recording;
      recordingDuration.value = 0;
      swipeOffset.value = 0;
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => recordingDuration.value++,
      );
    } catch (e) {
      debugPrint('[ChatVoice] unable to start recording: $e');
      _showError('Impossible de démarrer l’enregistrement. Vérifie l’autorisation du micro.');
    }
  }

  void onRecordingDragUpdate(DragUpdateDetails details) {
    if (recordingState.value == RecordingState.recording) {
      swipeOffset.value += details.primaryDelta ?? 0;
      if (swipeOffset.value < -120) unawaited(cancelRecording());
    }
  }

  Future<void> stopRecording() async {
    if (recordingState.value != RecordingState.recording) return;
    _recordingTimer?.cancel();
    try {
      await audioRecorder.stop();
      await _recordingStreamSub?.cancel();
      _recordingStreamSub = null;
      if (_recordingChunks.isEmpty) {
        recordingState.value = RecordingState.idle;
        _showError('Aucun son n’a été capturé. Vérifie le micro du navigateur.');
        return;
      }
      recordingState.value = RecordingState.reviewing;
    } catch (e) {
      debugPrint('[ChatVoice] unable to stop recording: $e');
      recordingState.value = RecordingState.idle;
      _showError('Impossible de finaliser l’enregistrement.');
    }
  }

  Future<void> cancelRecording() async {
    _recordingTimer?.cancel();
    try {
      await audioRecorder.stop();
    } catch (_) {}
    await _recordingStreamSub?.cancel();
    _recordingStreamSub = null;
    _recordingChunks.clear();
    recordingState.value = RecordingState.idle;
    swipeOffset.value = 0;
    await audioPlayer.stop();
  }

  Uint8List _buildWavBytes(List<int> pcmBytes) {
    const sampleRate = 44100;
    const channels = 1;
    const bitsPerSample = 16;
    final dataLength = pcmBytes.length;
    final header = ByteData(44);
    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, 36 + dataLength, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * channels * bitsPerSample ~/ 8, Endian.little);
    header.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    header.setUint32(40, dataLength, Endian.little);

    return Uint8List.fromList(<int>[...header.buffer.asUint8List(), ...pcmBytes]);
  }

  String? get _recordingDataUri {
    if (_recordingChunks.isEmpty) return null;
    final wavBytes = _buildWavBytes(_recordingChunks);
    return 'data:audio/wav;name=scrole_voice.wav;base64,${base64Encode(wavBytes)}';
  }

  Future<void> playReview() async {
    final dataUri = _recordingDataUri;
    if (dataUri == null) return;
    if (isPlayingReview.value) {
      await audioPlayer.pause();
      return;
    }
    await audioPlayer.setUrl(dataUri);
    await audioPlayer.play();
  }

  Future<void> sendVoiceMessage() async {
    final uid = currentUserId;
    final audioPayload = _recordingDataUri;
    if (uid == null || audioPayload == null || conversationId.isEmpty) return;
    if (!await _ensureRealConversation()) return;
    final localId = _repository.generateLocalId();
    final message = MessageModel(
      id: localId,
      localId: localId,
      conversationId: conversationId,
      senderId: uid,
      type: MessageType.audio,
      audioUrl: audioPayload,
      audioDuration: Duration(seconds: recordingDuration.value),
      createdAt: DateTime.now().toUtc(),
      status: MessageStatus.sending,
      repliedToId: repliedMessage.value?.id,
    );
    recordingState.value = RecordingState.idle;
    _recordingChunks.clear();
    clearReply();
    final result = await _repository.sendMediaMessage(message);
    if (!result.success) _showError(result.message);
  }

  void toggleEmojiPicker() { showEmojiPicker.value = !showEmojiPicker.value; if (showEmojiPicker.value) FocusManager.instance.primaryFocus?.unfocus(); }
  void toggleReactionPanel() {}
  void disposeAudio() { _recordingTimer?.cancel(); _recordingStreamSub?.cancel(); _typingTimer?.cancel(); _readDebounce?.cancel(); _otherUserTypingTimer?.cancel(); _audioSub?.cancel(); audioRecorder.dispose(); audioPlayer.dispose(); }
  void _stopTyping() { _typingTimer?.cancel(); isTyping.value = false; if (!isDraftConversation) unawaited(_repository.setTyping(conversationId, false)); }
  void _showError(String? message) { if (message != null && message.isNotEmpty) Get.snackbar('Message', message); }

  @override
  void onClose() {
    if (_lastWatchedId != null) {
      unawaited(_repository.stopWatchingConversation(_lastWatchedId!));
    }
    NotificationService.instance.setActiveConversation(null);
    _messagesSub?.cancel();
    _typingSub?.cancel();
    messageController.removeListener(_composerChanged);
    messageController.dispose();
    disposeAudio();
    super.onClose();
  }
}
