import 'package:get/get.dart';
import '../../shared/models/user_models.dart';
import '../local_storage/fast/fast_cache_service.dart';

class PrivacyService extends GetxService {
  final FastCacheService _cache = Get.find<FastCacheService>();
  
  static const String _cacheKey = 'user_privacy';
  
  final Rx<AppPrivacy> privacy = AppPrivacy.defaultValues().obs;

  Future<PrivacyService> init() async {
    final cached = _cache.get<Map<String, dynamic>>(_cacheKey);
    if (cached != null) {
      privacy.value = AppPrivacy.fromJson(cached);
    }
    return this;
  }

  void applyPrivacy(AppPrivacy newPrivacy) {
    privacy.value = newPrivacy;
    _cache.set(_cacheKey, newPrivacy.toJson());
  }

  Future<void> clearCache() async {
    await _cache.remove(_cacheKey);
    privacy.value = AppPrivacy.defaultValues();
  }
}
