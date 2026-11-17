/// Contract commun du cache clé/valeur utilisé par les services Scrole.
///
/// Les implémentations restent responsables de leur persistance (Hive sur
/// mobile/Web, IndexedDB ou autre adaptateur si nécessaire). Les consommateurs
/// ne doivent dépendre ni de Hive ni du système de fichiers.
abstract interface class CacheStore {
  T? get<T>(String key, {Duration? maxAge});

  Future<void> set(String key, dynamic value);

  Future<void> remove(String key);

  Future<void> clear();

  Future<void> clearPattern(String pattern);
}
