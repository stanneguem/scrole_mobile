import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/app_controller.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/user_certified_badge.dart';
import 'package:scrole/shared/widgets/media_gallery_sheet.dart';
import 'package:scrole/modules/module_communautes/interne/controllers/community/community_feed_controller.dart';
import 'package:scrole/modules/module_communautes/centre/services/community_service.dart';
import 'package:scrole/modules/module_communautes/centre/models/news/community_hashtag.dart';
import 'community_poll_composer_screen.dart';
import 'community_post_hashtag_selection_screen.dart';
import 'community_post_settings_screen.dart';

class CreateCommunityPostScreen extends StatefulWidget {
  final String communityName;
  final String? communityId;
  final String? prefilledText;
  final String? prefilledMediaUrl;

  const CreateCommunityPostScreen({
    super.key,
    required this.communityName,
    this.communityId,
    this.prefilledText,
    this.prefilledMediaUrl,
  });

  @override
  State<CreateCommunityPostScreen> createState() => _CreateCommunityPostScreenState();
}

class _CreateCommunityPostScreenState extends State<CreateCommunityPostScreen> {
  late final TextEditingController _textController;
  final List<File> _selectedFiles = [];
  String? _prefilledUrl;
  Map<String, dynamic>? _pollData;
  bool _isPublishing = false;

  bool _commentsEnabled = true;
  bool _sharingEnabled = true;
  bool _reactionsEnabled = true;
  String _audience = 'public'; // 'public' | 'followers' | 'friends'
  bool _allowPromotion = true; // For community posts: toggle "Garder ce post uniquement dans la communauté" -> p_allow_promotion: false

  final List<CommunityHashtag> _selectedHashtags = [];
  List<Map<String, dynamic>> _selectedMentions = [];
  List<String> _selectedMentionIds = [];
  final Set<String> _selectedCommunityIds = {};
  final Set<String> _selectedEventIds = {};
  final LayerLink _mentionLayerLink = LayerLink();
  OverlayEntry? _mentionOverlay;
  Timer? _mentionSearchDebounce;
  List<Map<String, dynamic>> _mentionSuggestions = [];
  String? _activeMentionType;
  int _mentionStart = -1;
  int _mentionRequest = 0;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.prefilledText ?? '');
    _prefilledUrl = widget.prefilledMediaUrl;
  }

  @override
  void dispose() {
    _mentionOverlay?.remove();
    _mentionSearchDebounce?.cancel();
    _textController.dispose();
    super.dispose();
  }

  bool get _canPublish =>
      _textController.text.trim().isNotEmpty ||
      _selectedFiles.isNotEmpty ||
      (_prefilledUrl != null && _prefilledUrl!.isNotEmpty) ||
      _pollData != null;

  void _removeMentionOverlay() {
    _mentionOverlay?.remove();
    _mentionOverlay = null;
    _activeMentionType = null;
    _mentionSuggestions = [];
  }

  void _onPostTextChanged(String value) {
    final cursor = _textController.selection.baseOffset;
    if (cursor < 0 || cursor > value.length) {
      _removeMentionOverlay();
      return;
    }
    final prefix = value.substring(0, cursor);
    final match = RegExp(r'(^|\s)([@*~])([^\s@*~]*)$').firstMatch(prefix);
    if (match == null) {
      _removeMentionOverlay();
      setState(() {});
      return;
    }
    final trigger = match.group(2)!;
    _activeMentionType = trigger == '@' ? 'user' : trigger == '*' ? 'event' : 'community';
    _mentionStart = cursor - trigger.length - (match.group(3) ?? '').length;
    final query = match.group(3) ?? '';
    _mentionSearchDebounce?.cancel();
    _mentionSearchDebounce = Timer(const Duration(milliseconds: 180), () {
      _searchPostMentionSuggestions(query, _activeMentionType!);
    });
    setState(() {});
  }

  Future<void> _searchPostMentionSuggestions(String query, String type) async {
    final request = ++_mentionRequest;
    try {
      final client = Supabase.instance.client;
      List<Map<String, dynamic>> results = [];
      if (type == 'user') {
        final rows = await client.from('user_profiles')
            .select('user_id, username, first_name, last_name, photo_url, is_verified')
            .eq('account_status', 'active').isFilter('deleted_at', null)
            .or('username.ilike.%$query%,first_name.ilike.%$query%,last_name.ilike.%$query%')
            .order('username').limit(7);
        results = rows.map((r) => Map<String, dynamic>.from(r)).toList();
      } else if (type == 'community') {
        final rows = await client.from('communities')
            .select('id, name, photo_profile, visibility')
            .eq('status', 'active').ilike('name', '%$query%')
            .order('name').limit(7);
        results = rows.map((r) => Map<String, dynamic>.from(r)).toList();
      } else {
        final rows = await client.from('events')
            .select('id, name, photo, starts_at, status')
            .ilike('name', '%$query%').order('starts_at').limit(12);
        results = rows.map((r) => Map<String, dynamic>.from(r))
            .where((r) => !const {'deleted', 'cancelled', 'archived'}.contains((r['status'] ?? '').toString().toLowerCase()))
            .take(7).toList();
      }
      if (!mounted || request != _mentionRequest || _activeMentionType != type) return;
      setState(() => _mentionSuggestions = results);
      _showPostMentionOverlay();
    } catch (e) {
      debugPrint('[MENTIONS] Post suggestion search failed: $e');
      if (request == _mentionRequest) _removeMentionOverlay();
    }
  }

  void _showPostMentionOverlay() {
    if (_mentionSuggestions.isEmpty || _activeMentionType == null) {
      _removeMentionOverlay();
      return;
    }
    _mentionOverlay ??= OverlayEntry(builder: (overlayContext) {
      final type = _activeMentionType;
      final items = List<Map<String, dynamic>>.from(_mentionSuggestions);
      return Positioned(
        width: MediaQuery.of(context).size.width - 32,
        child: CompositedTransformFollower(
          link: _mentionLayerLink, showWhenUnlinked: false,
          targetAnchor: Alignment.topLeft, followerAnchor: Alignment.bottomLeft,
          offset: const Offset(0, -8),
          child: Material(
            elevation: 12, color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14), clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.separated(
                padding: EdgeInsets.zero, shrinkWrap: true, itemCount: items.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: Theme.of(context).dividerColor.withValues(alpha: .35)),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isUser = type == 'user';
                  final title = isUser
                      ? ((item['username'] ?? '').toString().isNotEmpty ? '@${item['username']}' : '${item['first_name'] ?? ''} ${item['last_name'] ?? ''}'.trim())
                      : (item['name'] ?? '').toString();
                  final subtitle = isUser ? '${item['first_name'] ?? ''} ${item['last_name'] ?? ''}'.trim()
                      : type == 'event' ? (item['starts_at'] ?? '').toString().replaceFirst('T', ' ') : 'Communauté';
                  final image = (item[isUser ? 'photo_url' : type == 'event' ? 'photo' : 'photo_profile'] ?? '').toString();
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundImage: image.startsWith('http') ? NetworkImage(image) : null,
                      child: image.startsWith('http') ? null : Icon(isUser ? Icons.person_outline : type == 'event' ? Icons.event_outlined : Icons.groups_outlined, size: 19),
                    ),
                    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                    onTap: () => _insertPostMention(type!, item),
                  );
                },
              ),
            ),
          ),
        ),
      );
    });
    final overlay = Overlay.of(context);
    if (!_mentionOverlay!.mounted) overlay.insert(_mentionOverlay!);
    else _mentionOverlay!.markNeedsBuild();
  }

  void _insertPostMention(String type, Map<String, dynamic> item) {
    final id = (item[type == 'user' ? 'user_id' : 'id'] ?? '').toString();
    final token = type == 'user' ? '@${item['username'] ?? item['first_name'] ?? 'utilisateur'}'
        : type == 'event' ? '*${item['name'] ?? 'événement'}' : '~${item['name'] ?? 'communauté'}';
    final text = _textController.text;
    final cursor = _textController.selection.baseOffset.clamp(0, text.length);
    final start = _mentionStart.clamp(0, cursor);
    _textController.value = TextEditingValue(
      text: text.replaceRange(start, cursor, '$token '),
      selection: TextSelection.collapsed(offset: start + token.length + 1),
    );
    if (id.isNotEmpty) {
      if (type == 'user') {
        _selectedMentions.removeWhere((m) => (m['user_id'] ?? '').toString() == id);
        _selectedMentions.add(item);
        _selectedMentionIds = _selectedMentions.map((m) => (m['user_id'] ?? m['id'] ?? '').toString()).where((x) => x.isNotEmpty).toList();
      } else if (type == 'event') {
        _selectedEventIds.add(id);
      } else {
        _selectedCommunityIds.add(id);
      }
    }
    _removeMentionOverlay();
    setState(() {});
  }

  Future<void> _openMentions() async {
    final cId = widget.communityId ?? Get.parameters['id'] ?? '';
    final result = await Get.to<List<Map<String, dynamic>>>(
      () => const CommunityPostMentionsScreen(),
      arguments: {'communityId': cId, 'initialSelected': _selectedMentionIds},
    );
    if (result != null) {
      setState(() {
        _selectedMentions = result;
        _selectedMentionIds = result.map((m) => (m['user_id'] ?? m['id'] ?? '').toString()).toList();
      });
    }
  }

  Future<void> _openPollCreator() async {
    if (_selectedFiles.isNotEmpty || (_prefilledUrl != null && _prefilledUrl!.isNotEmpty)) {
      Get.snackbar('Attention', 'Un sondage ne peut pas contenir de photos.', backgroundColor: Colors.black87, colorText: Colors.white);
      return;
    }
    final pollMap = await Get.to<Map<String, dynamic>>(() => const CommunityPollComposerScreen(), transition: Transition.rightToLeft);
    if (pollMap != null) {
      setState(() {
        _pollData = pollMap;
      });
    }
  }

  void _publish() {
    if (!_canPublish) return;

    List<File> filesToPublish = List.from(_selectedFiles);
    if (filesToPublish.isEmpty && _prefilledUrl != null && _prefilledUrl!.isNotEmpty && !_prefilledUrl!.startsWith('http')) {
      filesToPublish.add(File(_prefilledUrl!));
    }

    final content = _textController.text.trim();

    if (content.isEmpty && filesToPublish.isEmpty && _pollData == null) {
      Get.snackbar('Publication vide', 'Une publication doit contenir du texte, un média ou un sondage.', backgroundColor: Colors.black87, colorText: Colors.white);
      return;
    }

    if (filesToPublish.length > 4) {
      Get.snackbar('Limite dépassée', 'Maximum 4 photos autorisées.', backgroundColor: Colors.black87, colorText: Colors.white);
      return;
    }

    Get.back();

    CommunityFeedController? feedController;
    try {
      if (widget.communityId != null && widget.communityId!.isNotEmpty) {
        feedController = Get.find<CommunityFeedController>(tag: widget.communityId);
      } else {
        feedController = Get.find<CommunityFeedController>();
      }
    } catch (_) {
      try {
        feedController = Get.find<CommunityFeedController>();
      } catch (_) {}
    }

    final postContent = content.isNotEmpty ? content : null;
    final postId = const Uuid().v4();
    final hashtagsList = _selectedHashtags.map((h) => h.name).toList();
    final mentionsList = _selectedMentionIds;
    final isCommunity = widget.communityId != null && widget.communityId!.isNotEmpty;
    final cId = widget.communityId ?? '';

    final service = Get.isRegistered<CommunityService>() ? Get.find<CommunityService>() : Get.put(CommunityService());

    unawaited(() async {
      try {
        await service.createCommunityPost(
      requestedPostId: postId,
      communityId: cId,
      content: postContent,
      imageFiles: filesToPublish,
      audience: isCommunity ? 'public' : _audience,
      commentsEnabled: _commentsEnabled,
      sharingEnabled: _sharingEnabled,
      reactionsEnabled: _reactionsEnabled,
      hashtags: hashtagsList,
      mentions: mentionsList,
      poll: _pollData,
      allowPromotion: isCommunity ? _allowPromotion : true,
        );
        if (_selectedCommunityIds.isNotEmpty || _selectedEventIds.isNotEmpty) {
          await Supabase.instance.client.rpc('save_content_entity_mentions', params: {
            'p_source_type': 'post',
            'p_source_id': postId,
            'p_community_ids': _selectedCommunityIds.toList(),
            'p_event_ids': _selectedEventIds.toList(),
          });
        }
      } catch (e) {
        debugPrint('[MENTIONS] Post publish/entity mention error: $e');
      }
    }());
  }

  Future<void> _openGallery() async {
    if (_pollData != null) {
      Get.snackbar('Attention', 'Un sondage ne peut pas contenir de photos.', backgroundColor: Colors.black87, colorText: Colors.white);
      return;
    }

    final maxAllowed = 4 - _selectedFiles.length;
    if (maxAllowed <= 0) {
      Get.snackbar(
        'Limite atteinte',
        'Vous ne pouvez pas ajouter plus de 4 photos.',
        backgroundColor: Colors.black87,
        colorText: Colors.white,
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MediaGallerySheet(
        maxSelection: maxAllowed,
        onSelected: (files) {
          if (files.isNotEmpty) {
            setState(() {
              _selectedFiles.addAll(files.map((f) => File(f.path)));
              if (_selectedFiles.length > 4) {
                _selectedFiles.removeRange(4, _selectedFiles.length);
              }
              _prefilledUrl = null;
            });
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appController = Get.find<AppController>();
    final profileRaw = appController.profile.value ?? {};
    final profile = (profileRaw['profile'] is Map)
        ? Map<String, dynamic>.from(profileRaw['profile'] as Map)
        : profileRaw;
    final firstName = profile['first_name']?.toString() ?? profile['prenom']?.toString() ?? '';
    final lastName = profile['last_name']?.toString() ?? profile['nom']?.toString() ?? '';
    final fullName = "$firstName $lastName".trim();
    final username = profile['username']?.toString() ?? '';
    final displayName = fullName.isEmpty ? (username.isEmpty ? 'profile_default_username'.tr : username) : fullName;
    final avatarUrl = profile['photo_url']?.toString() ?? '';
    final isCertified = profile['is_certified'] == true || profile['is_verified'] == true || profile['is_certified'] == 1 || profile['is_verified'] == 1;

    final isCommunity = widget.communityId != null && widget.communityId!.isNotEmpty;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        centerTitle: false,
        title: const Text('Créer une publication'),
        titleTextStyle: AppTextStyles.h5.copyWith(color: colorScheme.onSurface),
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.close_rounded, size: 28),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: TextButton(
              onPressed: _canPublish && !_isPublishing ? _publish : null,
              style: TextButton.styleFrom(
                foregroundColor: _canPublish ? colorScheme.primary : colorScheme.outline,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: _isPublishing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(
                      'Publier',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _canPublish ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.6),
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profil + Badge Communauté ou Audience Selector
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: colorScheme.surfaceContainerHighest),
                            child: ClipOval(
                              child: avatarUrl.isNotEmpty
                                  ? AppCachedImage(imageUrl: avatarUrl, width: 44, height: 44, fit: BoxFit.cover)
                                  : Icon(Icons.person, color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: RichText(
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        text: TextSpan(
                                          style: AppTextStyles.h6.copyWith(fontWeight: FontWeight.bold, fontSize: 15, color: colorScheme.onSurface),
                                          children: [
                                            TextSpan(text: displayName),
                                            if (username.isNotEmpty)
                                              TextSpan(
                                                text: ' @$username',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.normal,
                                                  fontSize: 13.5,
                                                  color: colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (isCertified) ...[
                                      const SizedBox(width: 4),
                                      const UserCertifiedBadge(size: 15),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                if (isCommunity)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Dans ${widget.communityName}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  )
                                else
                                  // Audience Selector for general posts
                                  DropdownButton<String>(
                                    value: _audience,
                                    isDense: true,
                                    underline: const SizedBox.shrink(),
                                    items: const [
                                      DropdownMenuItem(value: 'public', child: Text('Public')),
                                      DropdownMenuItem(value: 'followers', child: Text('Followers')),
                                      DropdownMenuItem(value: 'friends', child: Text('Amis')),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) setState(() => _audience = val);
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Community Promotion Toggle if community post
                    if (isCommunity)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: SwitchListTile(
                          title: const Text('Garder ce post uniquement dans la communauté', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          value: !_allowPromotion,
                          onChanged: (val) => setState(() => _allowPromotion = !val),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),

                    // Champ de texte
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: CompositedTransformTarget(
                        link: _mentionLayerLink,
                        child: TextField(
                        controller: _textController,
                        autofocus: true,
                        maxLines: null,
                        maxLength: 5000,
                        style: AppTextStyles.bodyXL.copyWith(fontSize: 18, height: 1.4, color: colorScheme.onSurface),
                        decoration: InputDecoration(
                          hintText: _pollData != null ? 'Posez votre question pour le sondage...' : 'Quoi de neuf ? (max 5000 chars)',
                          hintStyle: AppTextStyles.bodyXL.copyWith(fontSize: 18, color: colorScheme.outline.withValues(alpha: 0.5)),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          filled: false,
                          counterText: '',
                        ),
                        onChanged: _onPostTextChanged,
                      ),
                      ),
                    ),

                    if (_selectedHashtags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: _selectedHashtags.map((h) => Chip(
                            label: Text('#${h.name}'),
                            onDeleted: () => setState(() => _selectedHashtags.removeWhere((item) => item.name.toLowerCase() == h.name.toLowerCase())),
                            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                            labelStyle: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
                          )).toList(),
                        ),
                      ),

                    if (_selectedMentions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: _selectedMentions.map((m) {
                            final username = m['username'] ?? m['user_profiles']?['username'] ?? 'membre';
                            return Chip(
                              label: Text('@$username'),
                              onDeleted: () => setState(() {
                                final uId = (m['user_id'] ?? m['id'] ?? '').toString();
                                _selectedMentions.removeWhere((item) => (item['user_id'] ?? item['id']).toString() == uId);
                                _selectedMentionIds.remove(uId);
                              }),
                              backgroundColor: colorScheme.surfaceContainerHighest,
                              labelStyle: TextStyle(color: colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.bold),
                            );
                          }).toList(),
                        ),
                      ),

                    // Poll Preview Card
                    if (_pollData != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colorScheme.primary.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.poll_rounded, color: colorScheme.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Sondage (${_pollData!['kind']})', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary)),
                                    Text('${(_pollData!['options'] as List).length} options', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => setState(() => _pollData = null),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Media Preview Grid (Max 4 photos)
                    if (_selectedFiles.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: _selectedFiles.length == 1 ? 1 : 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: _selectedFiles.length == 1 ? 1.6 : 1.2,
                          ),
                          itemCount: _selectedFiles.length > 4 ? 4 : _selectedFiles.length,
                          itemBuilder: (context, index) {
                            final file = _selectedFiles[index];
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(file, width: double.infinity, height: double.infinity, fit: BoxFit.cover),
                                ),
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: GestureDetector(
                                    onTap: () => setState(() => _selectedFiles.removeAt(index)),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      )
                    else if (_prefilledUrl != null && _prefilledUrl!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _prefilledUrl!.startsWith('http')
                                  ? AppCachedImage(imageUrl: _prefilledUrl!, width: double.infinity, height: 280, fit: BoxFit.cover)
                                  : Image.file(File(_prefilledUrl!), width: double.infinity, height: 280, fit: BoxFit.cover),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: IconButton.filled(
                                onPressed: () => setState(() => _prefilledUrl = null),
                                icon: const Icon(Icons.close),
                                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Bottom action bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    onPressed: _openGallery,
                    icon: Icon(Icons.camera_alt_rounded, color: colorScheme.onSurface, size: 24),
                    tooltip: 'Photos (max 4)',
                  ),
                  IconButton(
                    onPressed: _openPollCreator,
                    icon: Icon(Icons.poll_rounded, color: _pollData != null ? colorScheme.primary : colorScheme.onSurface, size: 24),
                    tooltip: 'Sondage',
                  ),
                  IconButton(
                    onPressed: () async {
                      final result = await Get.to<List<CommunityHashtag>>(() => CommunityPostHashtagSelectionScreen(
                        initialSelected: _selectedHashtags,
                      ));
                      if (result != null) {
                        setState(() {
                          _selectedHashtags.clear();
                          _selectedHashtags.addAll(result);
                        });
                      }
                    },
                    icon: Icon(Icons.tag_rounded, color: _selectedHashtags.isNotEmpty ? colorScheme.primary : colorScheme.onSurface, size: 24),
                    tooltip: 'Hashtags',
                  ),
                  IconButton(
                    onPressed: () async {
                      final result = await Get.to<Map<String, dynamic>>(() => CommunityPostSettingsScreen(
                        initialCommentsEnabled: _commentsEnabled,
                        initialSharingEnabled: _sharingEnabled,
                      ));
                      if (result != null) {
                        setState(() {
                          _commentsEnabled = result['commentsEnabled'] ?? true;
                          _sharingEnabled = result['sharingEnabled'] ?? true;
                        });
                      }
                    },
                    icon: Icon(Icons.settings_outlined, color: colorScheme.onSurface, size: 24),
                    tooltip: 'Paramètres',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
