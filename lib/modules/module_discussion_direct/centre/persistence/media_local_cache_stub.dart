import '../../../../app/local_storage/structured/app_cache_database.dart';

/// Browser adapter: remote media stays on its HTTPS URL. No File API or
/// duplicate full attachment download is performed by this SQLite metadata DAO.
class MediaLocalCachePlatform {
  MediaLocalCachePlatform(this._database);

  final AppDatabase _database;

  Future<String?> resolve({
    required String userId,
    required String messageId,
    required String remoteUrl,
  }) async => remoteUrl.isEmpty ? null : remoteUrl;

  Future<String?> download({
    required String userId,
    required String messageId,
    required String remoteUrl,
  }) async => remoteUrl.isEmpty ? null : remoteUrl;

  Future<void> deleteMessageMedia(String userId, String messageId) async {
    final db = await _database.database;
    await db.delete(
      'direct_chat_media_cache',
      where: 'user_id=? AND message_id=?',
      whereArgs: [userId, messageId],
    );
  }
}
