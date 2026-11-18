import 'package:supabase_flutter/supabase_flutter.dart';

import '../media/media_asset.dart';
import 'r2_media_repository.dart';

/// Storage multiplateforme pour les nouveaux flux basés sur MediaAsset.
/// Les anciennes méthodes File de StorageRepository restent disponibles
/// pendant la migration progressive des contrôleurs.
class MediaAssetStorageRepository {
  MediaAssetStorageRepository({SupabaseClient? client, R2MediaRepository? r2})
      : _client = client ?? Supabase.instance.client,
        _r2 = r2 ?? R2MediaRepository();

  final SupabaseClient _client;
  final R2MediaRepository _r2;

  String _requireCurrentUser(String userId, String message) {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null || currentUser.id != userId) {
      throw Exception(message);
    }
    return currentUser.id;
  }

  Future<void> deletePublicFile({
    required String bucket,
    required String publicUrl,
  }) async {
    // Les médias R2 sont supprimés via leur clé détenue, pas via Supabase Storage.
    await _r2.deleteReplacedPublicMedia(publicUrl);
  }

  Future<String> uploadProfilePicture(String userId, MediaAsset media) async {
    _requireCurrentUser(userId, 'Vous ne pouvez téléverser que votre propre photo de profil.');
    final uploaded = await _r2.uploadMediaAsset(
      media: media,
      category: 'profile_avatar',
      mediaType: 'image',
      entityId: userId,
    );
    final url = uploaded.publicUrl;
    if (url == null || url.isEmpty || !uploaded.isPublic) {
      throw StateError('Cloudflare R2 n’a pas retourné une URL publique pour la photo de profil.');
    }
    return url;
  }

  Future<String> uploadProfileCover(String userId, MediaAsset media) async {
    _requireCurrentUser(userId, 'Vous ne pouvez téléverser que votre propre couverture de profil.');
    final uploaded = await _r2.uploadMediaAsset(
      media: media,
      category: 'profile_cover',
      mediaType: 'image',
      entityId: userId,
    );
    final url = uploaded.publicUrl;
    if (url == null || url.isEmpty || !uploaded.isPublic) {
      throw StateError('Cloudflare R2 n’a pas retourné une URL publique pour la couverture du profil.');
    }
    return url;
  }

  Future<String> uploadCommunityAvatar(MediaAsset media, {required String communityId}) async {
    final uploaded = await _r2.uploadMediaAsset(
      media: media,
      category: 'community_avatar',
      mediaType: 'image',
      entityId: communityId,
    );
    final url = uploaded.publicUrl;
    if (url == null || url.isEmpty || !uploaded.isPublic) {
      throw StateError('Cloudflare R2 n’a pas retourné une URL publique pour l’avatar de communauté.');
    }
    return url;
  }

  Future<String> uploadCommunityBanner(MediaAsset media, {required String communityId}) async {
    final uploaded = await _r2.uploadMediaAsset(
      media: media,
      category: 'community_cover',
      mediaType: 'image',
      entityId: communityId,
    );
    final url = uploaded.publicUrl;
    if (url == null || url.isEmpty || !uploaded.isPublic) {
      throw StateError('Cloudflare R2 n’a pas retourné une URL publique pour la couverture de communauté.');
    }
    return url;
  }

  Future<String> uploadBugReportScreenshot(String userId, MediaAsset media) async {
    _requireCurrentUser(userId, 'Vous ne pouvez téléverser que votre propre capture.');
    final uploaded = await _r2.uploadMediaAsset(
      media: media,
      category: 'bug_report',
      mediaType: 'image',
      entityId: userId,
    );
    if (uploaded.isPublic || !uploaded.objectKey.startsWith('bug-reports/$userId/')) {
      throw StateError('La capture de bug doit être stockée dans le bucket privé Cloudflare R2.');
    }
    return uploaded.objectKey;
  }
}
