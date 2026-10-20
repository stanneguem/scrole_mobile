import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';
import '../../externe/repositories/social_repository.dart';

class ContactModel {
  final String id;
  final String name;
  final String username;
  final String? avatarUrl;
  final bool isOnline;
  final bool isCertified;

  ContactModel({
    required this.id,
    required this.name,
    required this.username,
    this.avatarUrl,
    this.isOnline = false,
    this.isCertified = false,
  });
}

class FriendRequestModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String status;
  final String otherUserId;
  final String otherName;
  final String otherUsername;
  final String? otherPhotoUrl;
  final DateTime? nextRetryAt;
  final DateTime createdAt;

  FriendRequestModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    required this.otherUserId,
    required this.otherName,
    required this.otherUsername,
    this.otherPhotoUrl,
    this.nextRetryAt,
    required this.createdAt,
  });
}

class ContactsController extends GetxController {
  final SocialRepository _socialRepository = SocialRepository();
  final AppDatabase _db = Get.find<AppDatabase>();
  final SupabaseClient _client = Supabase.instance.client;

  final RxList<ContactModel> contacts = <ContactModel>[].obs;
  final RxList<FriendRequestModel> friendRequests = <FriendRequestModel>[].obs;
  final RxString searchQuery = ''.obs;
  final RxBool isLoading = false.obs;
  final RxBool isLoadingRequests = false.obs;
  final RxString error = ''.obs;

  String? get _userId => _client.auth.currentUser?.id;

  @override
  void onInit() {
    super.onInit();
    unawaited(loadContacts());
    unawaited(loadFriendRequests());
  }

  Future<void> loadContacts() async {
    final uid = _userId;
    if (uid == null) return;

    error.value = '';
    final cached = await _restoreCachedContacts(uid);

    if (cached.isNotEmpty) {
      isLoading.value = false;
      unawaited(_refreshContactsInBackground(uid));
      return;
    }

    isLoading.value = true;
    await _refreshContactsInBackground(uid, showErrors: true);
    isLoading.value = false;
  }

  Future<void> loadFriendRequests() async {
    final uid = _userId;
    if (uid == null) return;

    isLoadingRequests.value = true;
    try {
      final rawRequests = await _socialRepository.getMyFriendRequests();
      final peopleMap = <String, Map<String, dynamic>>{};

      final otherUserIds = rawRequests.map((r) {
        final s = (r['sender_id'] ?? '').toString();
        final rec = (r['receiver_id'] ?? '').toString();
        return s == uid ? rec : s;
      }).toSet().toList();

      if (otherUserIds.isNotEmpty) {
        final people = await _socialRepository.dao.getPeople(otherUserIds);
        for (final p in people) {
          peopleMap[p['user_id'].toString()] = p;
        }
      }

      final parsed = rawRequests.map((r) {
        final s = (r['sender_id'] ?? '').toString();
        final rec = (r['receiver_id'] ?? '').toString();
        final otherId = s == uid ? rec : s;
        final profile = peopleMap[otherId];

        String oName = 'Utilisateur';
        String oUsername = '';
        String? oPhoto;

        if (profile != null) {
          final first = (profile['first_name'] ?? '').toString();
          final last = (profile['last_name'] ?? '').toString();
          oUsername = (profile['username'] ?? '').toString();
          oName = '$first $last'.trim();
          if (oName.isEmpty) oName = oUsername.isNotEmpty ? oUsername : 'Utilisateur';
          oPhoto = profile['photo_url']?.toString();
        }

        return FriendRequestModel(
          id: (r['id'] ?? '').toString(),
          senderId: s,
          receiverId: rec,
          status: (r['status'] ?? 'pending').toString(),
          otherUserId: otherId,
          otherName: oName,
          otherUsername: oUsername,
          otherPhotoUrl: oPhoto,
          nextRetryAt: r['next_retry_at'] != null ? DateTime.tryParse(r['next_retry_at'].toString()) : null,
          createdAt: r['created_at'] != null ? DateTime.tryParse(r['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
        );
      }).toList();

      friendRequests.assignAll(parsed);
    } catch (e) {
      debugPrint('[Contacts] loadFriendRequests error: $e');
    } finally {
      isLoadingRequests.value = false;
    }
  }

  Future<void> sendFriendRequest(String targetUserId) async {
    try {
      await _socialRepository.sendFriendRequest(targetUserId);
      Get.snackbar('Demande d\'ami', 'Demande envoyée !');
      await loadFriendRequests();
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
    }
  }

  Future<void> respondFriendRequest(String requestId, bool accept, String senderId) async {
    try {
      await _socialRepository.respondFriendRequest(requestId, accept, senderId: senderId);
      Get.snackbar('Demande d\'ami', accept ? 'Demande acceptée !' : 'Demande refusée.');
      await loadContacts();
      await loadFriendRequests();
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
    }
  }

  Future<void> cancelFriendRequest(String requestId) async {
    try {
      await _socialRepository.cancelFriendRequest(requestId);
      friendRequests.removeWhere((r) => r.id == requestId);
      Get.snackbar('Demande d\'ami', 'Demande annulée.');
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
    }
  }

  Future<void> removeFriendship(String otherUserId) async {
    try {
      await _socialRepository.removeFriendship(otherUserId);
      contacts.removeWhere((c) => c.id == otherUserId);
      Get.snackbar('Amis', 'Ami retiré.');
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
    }
  }

  Future<List<ContactModel>> _restoreCachedContacts(String uid) async {
    try {
      final db = await _db.database;
      final rows = await db.query('direct_chat_contacts', where: 'user_id = ?', whereArgs: [uid], orderBy: 'name COLLATE NOCASE ASC');
      final cached = rows.map((row) => ContactModel(
        id: row['contact_id']?.toString() ?? '',
        name: row['name']?.toString() ?? '',
        username: row['username']?.toString() ?? '',
        avatarUrl: row['avatar_url']?.toString(),
        isOnline: (row['is_online'] as num?)?.toInt() == 1,
        isCertified: (row['is_certified'] as num?)?.toInt() == 1 || row['is_certified'] == true,
      )).where((contact) => contact.id.isNotEmpty).toList();
      contacts.assignAll(cached);
      return cached;
    } catch (e) {
      debugPrint('[Contacts] local cache load failed: $e');
      return [];
    }
  }

  Future<void> _refreshContactsInBackground(String uid, {bool showErrors = false}) async {
    try {
      final list = await _socialRepository.getAcceptedConnections();
      final fresh = list.map(_fromJson).toList();
      fresh.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final db = await _db.database;
      await db.transaction((txn) async {
        await txn.delete('direct_chat_contacts', where: 'user_id = ?', whereArgs: [uid]);
        for (final contact in fresh) {
          await txn.insert('direct_chat_contacts', {
            'user_id': uid,
            'contact_id': contact.id,
            'name': contact.name,
            'username': contact.username,
            'avatar_url': contact.avatarUrl,
            'is_online': contact.isOnline ? 1 : 0,
            'is_certified': contact.isCertified ? 1 : 0,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      contacts.assignAll(fresh);
      error.value = '';
    } catch (e) {
      debugPrint('[Contacts] background refresh failed: $e');
      if (showErrors && contacts.isEmpty) error.value = 'Impossible de charger les connexions.';
    }
  }

  ContactModel _fromJson(Map<String, dynamic> json) {
    final first = (json['first_name'] as String? ?? '').trim();
    final last = (json['last_name'] as String? ?? '').trim();
    final username = (json['username'] as String? ?? '').trim();
    final name = '$first $last'.trim();
    final isCertified = json['is_certified'] == true || json['is_verified'] == true || json['is_certified'] == 1 || json['is_verified'] == 1;
    return ContactModel(
      id: json['user_id'] as String,
      name: name.isEmpty ? username : name,
      username: username,
      avatarUrl: json['photo_url'] as String?,
      isCertified: isCertified,
    );
  }

  List<ContactModel> get filteredContacts {
    final query = searchQuery.value.trim().toLowerCase();
    if (query.isEmpty) return contacts.toList();
    return contacts.where((c) => c.name.toLowerCase().contains(query) || c.username.toLowerCase().contains(query)).toList();
  }

  List<FriendRequestModel> get incomingRequests {
    final uid = _userId;
    if (uid == null) return [];
    return friendRequests.where((r) => r.receiverId == uid && r.status == 'pending').toList();
  }

  List<FriendRequestModel> get outgoingRequests {
    final uid = _userId;
    if (uid == null) return [];
    return friendRequests.where((r) => r.senderId == uid && r.status == 'pending').toList();
  }

  void onBack() => Get.back();
}
