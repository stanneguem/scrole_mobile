import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/repository_global/location_repository.dart';
import '../../../../app/service_global/media_service.dart';
import '../../../module_authentification/centre/services/auth_service.dart';
import '../../../../app/routes/app_pages.dart';
import '../../centre/repositories/event_repository.dart';
import 'package:image_picker/image_picker.dart';

class CreateEventController extends GetxController {
  final PageController pageController = PageController();
  final RxInt currentStep = 0.obs;

  final MediaService _mediaService = Get.find<MediaService>();
  final EventRepository _repository;

  CreateEventController({
    EventRepository? repository,
  }) : _repository = repository ?? Get.find<EventRepository>();

  // --- Données du formulaire ---
  final nameController = TextEditingController();
  final slugController = TextEditingController();
  final RxString name = ''.obs;
  final RxString slug = ''.obs;
  final descriptionController = TextEditingController();
  final Rx<File?> coverFile = Rx<File?>(null);

  final RxBool isVirtual = false.obs;
  final Rx<LocationOption?> selectedCountry = Rx<LocationOption?>(null);
  final Rx<LocationOption?> selectedCity = Rx<LocationOption?>(null);
  final RxList<LocationOption> countries = <LocationOption>[].obs;
  final RxList<LocationOption> cities = <LocationOption>[].obs;
  final RxBool isLoadingCountries = false.obs;
  final RxBool isLoadingCities = false.obs;
  
  final addressController = TextEditingController();
  final onlineUrlController = TextEditingController(); // Nouveau: Lien virtuel

  final RxBool isFree = true.obs;
  final RxBool isPublic = true.obs;
  final RxBool isRecent = true.obs; // §3: Récent (true) vs Existe déjà (false)
  final Rx<DateTime?> realCreatedAt = Rx<DateTime?>(null); // §3: Date d'origine

  final Rx<DateTime?> startDate = Rx<DateTime?>(null);
  final Rx<DateTime?> endDate = Rx<DateTime?>(null);
  
  final RxBool isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    _loadCountries();
    
    // Ajout de listeners pour forcer la mise à jour de l'UI (Obx) quand le texte change
    nameController.addListener(() => name.value = nameController.text);
    slugController.addListener(() => slug.value = slugController.text);
  }

  Future<void> _loadCountries() async {
    isLoadingCountries.value = true;
    try {
      final repo = Get.find<LocationRepository>();
      final result = await repo.getCountries();
      countries.assignAll(result);
    } catch (e) {
      print('[Error] CreateEventController._loadCountries: $e');
    } finally {
      isLoadingCountries.value = false;
    }
  }

  void onCountryChanged(LocationOption country) {
    if (selectedCountry.value?.id == country.id) return;
    selectedCountry.value = country;
    selectedCity.value = null;
    _loadCities(country.id);
  }

  Future<void> _loadCities(String countryId) async {
    isLoadingCities.value = true;
    try {
      final repo = Get.find<LocationRepository>();
      final result = await repo.getCitiesForCountry(countryId);
      cities.assignAll(result);
    } catch (e) {
      print('[Error] CreateEventController._loadCities: $e');
    } finally {
      isLoadingCities.value = false;
    }
  }

  void onCityChanged(LocationOption city) => selectedCity.value = city;

  Future<void> pickImage(ImageSource source) async {
    final file = await _mediaService.pickCoverImage(source: source);
    if (file != null) {
      coverFile.value = file;
    }
  }

  void removeCover() {
    coverFile.value = null;
  }

  @override
  void onClose() {
    nameController.dispose();
    slugController.dispose();
    descriptionController.dispose();
    addressController.dispose();
    pageController.dispose();
    super.onClose();
  }

  void nextStep() {
    if (currentStep.value < 3) {
      pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void previousStep() {
    if (currentStep.value > 0) {
      pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  bool get isBasicInfoValid => 
    name.value.trim().isNotEmpty && 
    slug.value.trim().isNotEmpty &&
    coverFile.value != null &&
    (!isRecent.value || realCreatedAt.value != null);

  bool get isLocationValid => 
    (isVirtual.value && onlineUrlController.text.trim().isNotEmpty) ||
    (!isVirtual.value && selectedCountry.value != null && selectedCity.value != null && addressController.text.trim().isNotEmpty);

  bool get isDatesValid => 
    startDate.value != null &&
    (endDate.value == null || endDate.value!.isAfter(startDate.value!));

  Future<void> createEvent() async {
    if (isLoading.value) return;
    isLoading.value = true;

    try {
      final userId = Get.find<AuthService>().userId;
      if (userId == null) throw 'err_user_not_connected'.tr;

      String? coverUrl;
      if (coverFile.value != null) {
        coverUrl = await _repository.uploadCover(userId, coverFile.value!);
      }

      final newEvent = await _repository.createEventOptimistic(userId, {
        'name': nameController.text.trim(),
        'slug': slugController.text.trim(),
        'description': descriptionController.text.trim(),
        'photo': coverUrl,
        'is_virtual': isVirtual.value,
        'virtual_link': isVirtual.value ? onlineUrlController.text.trim() : null,
        'country_id': !isVirtual.value ? selectedCountry.value?.id : null,
        'city_id': !isVirtual.value ? selectedCity.value?.id : null,
        'address': !isVirtual.value ? addressController.text.trim() : null,
        'starts_at': startDate.value?.toUtc().toIso8601String(),
        'ends_at': endDate.value?.toUtc().toIso8601String(),
        'is_free': isFree.value,
        'is_public': isPublic.value,
        'real_created_at': isRecent.value ? realCreatedAt.value?.toUtc().toIso8601String() : null,
      });
      
      Get.back();
      Get.toNamed(AppPages.eventPreview.replaceFirst(':id', newEvent.id), arguments: newEvent);
      
      Get.snackbar(
        'Succès 🎉',
        'event_created_pending_validation'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar('error'.tr, e.toString());
    } finally {
      isLoading.value = false;
    }
  }
}
