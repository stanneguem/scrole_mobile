import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'app_cache_database.dart';

class PreferencesLocalDao {
  final AppDatabase _appDb;

  PreferencesLocalDao(this._appDb);

  Future<Database> get _db => _appDb.database;

  Future<void> savePreferences(Map<String, dynamic> prefs) async {
    final db = await _db;
    await db.insert(
      'user_preferences',
      {
        'user_id': prefs['user_id'] ?? 'current',
        'language': prefs['language'] ?? 'fr',
        'theme': prefs['theme'] ?? 'system',
        'notifications_enabled': (prefs['notifications_enabled'] == true || prefs['notifications_enabled'] == 1) ? 1 : 0,
        'privacy_profile_visibility': prefs['privacy_profile_visibility'] ?? 'public',
        'updated_at': prefs['updated_at'] ?? DateTime.now().toIso8601String(),
        'sync_status': prefs['sync_status'] ?? 'synced',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- Accumulateur de modifications en attente (pending_changes) ---

  Future<Map<String, dynamic>> getPendingChanges(String userId) async {
    final db = await _db;
    final rows = await db.query(
      'user_preferences_outbox',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'id ASC',
    );
    final merged = <String, dynamic>{};
    for (final row in rows) {
      final payload = Map<String, dynamic>.from(jsonDecode(row['payload'].toString()));
      merged.addAll(payload);
    }
    return merged;
  }

  Future<void> addPendingChanges(String userId, Map<String, dynamic> changes) async {
    final db = await _db;
    await db.insert('user_preferences_outbox', {
      'user_id': userId,
      'payload': jsonEncode(changes),
      'attempts': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> clearPendingChanges(String userId) async {
    final db = await _db;
    await db.delete('user_preferences_outbox', where: 'user_id = ?', whereArgs: [userId]);
  }
}
