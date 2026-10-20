import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrole/app/repository_global/location_repository.dart';
import 'package:scrole/app/service_global/centre_interrets_service.dart';
import 'package:scrole/shared/models/interest_model.dart';
import 'package:scrole/app_controller.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'profile_controller.dart';

class EditProfileController extends GetxController {
  late final ProfileController _profileController;
  late final AppController _appController;
  late final LocationRepository _locationRepository;
  late final InterestService _interestService;

  final formKey = GlobalKey<FormState>();

  final nomController = TextEditingController();
  final prenomController = TextEditingController();
  final usernameController = TextEditingController();
  final bioController = TextEditingController();

  final Rx<String?> selectedGender = Rx<String?>(null);
  final Rx<DateTime?> selectedBirthDate = Rx<DateTime?>(null);

  final Rx<LocationOption?> selectedCountry = Rx<LocationOption?>(null);
  final Rx<LocationOption?> selectedCity = Rx<LocationOption?>(null);

  final RxList<LocationOption> countries = <LocationOption>[].obs;
  final RxList<LocationOption> cities = <LocationOption>[].obs;

  final RxList<Interest> allInterests = <Interest>[].obs;
  final RxList<String> selectedInterestIds = <String>[].obs;

  final RxBool isLoadingCountries = false.obs;
  final RxBool isLoadingCities = false.obs;
  final RxBool isLoadingInterests = false.obs;
  final RxBool isSaving = false.obs;

  static const int _lockDays = 90;

  // Verrous individuels
  final RxBool canChangeUsername = true.obs;
  final RxBool canChangeGender = true.obs;
  final RxBool canChangeLocation = true.obs;
  final RxBool canChangeBirthDate = true.obs;

  final RxInt usernameDaysLeft = 0.obs;
  final RxInt genderDaysLeft = 0.obs;
  final RxInt locationDaysLeft = 0.obs;
  final RxInt birthDateDaysLeft = 0.obs;

  @override
  void onInit() {
    super.onInit();
    _appController = Get.find<AppController>();
    _profileController = Get.find<ProfileController>();
    _locationRepository = Get.find<LocationRepository>();
    _interestService = Get.find<InterestService>();
    _prefillFromProfile();
    _loadCountries();
    _loadInterests();
    _computeAllLocks();
  }

  void _prefillFromProfile() {
    nomController.text = _profileController.nom.value;
    prenomController.text = _profileController.prenom.value;
    usernameController.text = _profileController.username.value;
    bioController.text = _profileController.bio.value;

    final genre = _profileController.gender.value.toLowerCase();
    selectedGender.value = genre.isEmpty ? null : genre;

    selectedBirthDate.value = _profileController.birthDate.value;
    
    selectedInterestIds.assignAll(
      _profileController.userInterests.map((i) => i.id).toList(),
    );
  }

  Future<void> _loadInterests() async {
    try {
      isLoadingInterests.value = true;
      debugPrint('Début du chargement des intérêts...');
      
      // Utilisation du cache 5h (plus de forceRefresh systématique)
      final interests = await _interestService.getInterests();
      
      debugPrint('[OK] ${interests.length} intérêts récupérés');
      allInterests.assignAll(interests);
      
      if (interests.isEmpty) {
        debugPrint('[Warning] La liste des intérêts retournée par le service est VIDE');
      }
    } catch (e) {
      debugPrint('[Error] Erreur critique chargement intérêts: $e');
    } finally {
      isLoadingInterests.value = false;
    }
  }

  Future<void> goToInterestSelection() async {
    final result = await Get.toNamed(
      AppPages.interestSelection,
      arguments: {
        'allInterests': allInterests.toList(),
        'selectedIds': selectedInterestIds.toList(),
      },
    );

    if (result != null && result is List<String>) {
      selectedInterestIds.assignAll(result);
    }
  }

  void toggleInterest(String id) {
    if (selectedInterestIds.contains(id)) {
      selectedInterestIds.remove(id);
    } else {
      if (selectedInterestIds.length < 5) {
        selectedInterestIds.add(id);
      } else {
        Get.snackbar(
          'Limite atteinte',
          'Tu ne peux choisir que 5 centres d\'intérêt maximum.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
      }
    }
  }

  void _computeAllLocks() {
    _checkLock(_profileController.usernameUpdatedAt.value, canChangeUsername, usernameDaysLeft);
    _checkLock(_profileController.genderUpdatedAt.value, canChangeGender, genderDaysLeft);
    _checkLock(_profileController.locationUpdatedAt.value, canChangeLocation, locationDaysLeft);
    _checkLock(_profileController.birthDateUpdatedAt.value, canChangeBirthDate, birthDateDaysLeft);
  }

  void _checkLock(DateTime? lastUpdate, RxBool canChange, RxInt daysLeft) {
    if (lastUpdate == null) {
      canChange.value = true;
      daysLeft.value = 0;
      return;
    }
    final elapsed = DateTime.now().difference(lastUpdate).inDays;
    final remaining = _lockDays - elapsed;
    canChange.value = remaining <= 0;
    daysLeft.value = remaining > 0 ? remaining : 0;
  }

  Future<void> _loadCountries() async {
    isLoadingCountries.value = true;
    try {
      final result = await _locationRepository.getCountries().timeout(const Duration(seconds: 10));
      countries.assignAll(result);

      final currentCountry = _profileController.country.value;
      if (currentCountry.isNotEmpty) {
        // Chercher par nom ou par ID
        final match = result.firstWhereOrNull(
          (c) => c.nom.toLowerCase() == currentCountry.toLowerCase() || c.id == currentCountry,
        );

        if (match != null) {
          selectedCountry.value = match;
          // On n'attend pas forcément le chargement des villes pour libérer le loader pays
          isLoadingCountries.value = false;
          await _loadCities(match.id, preselectFromProfile: true);
          return; // Sortir pour éviter le second isLoadingCountries.value = false
        }
      }
    } catch (e) {
      debugPrint('[Error] Erreur chargement pays: $e');
      Get.snackbar(
        'edit_profile_error_title'.tr,
        'edit_profile_error_load_countries'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoadingCountries.value = false;
    }
  }

  Future<void> _loadCities(String countryId, {bool preselectFromProfile = false}) async {
    isLoadingCities.value = true;
    cities.clear();
    if (!preselectFromProfile) selectedCity.value = null;
    try {
      final result = await _locationRepository.getCitiesForCountry(countryId).timeout(const Duration(seconds: 10));
      cities.assignAll(result);

      if (preselectFromProfile) {
        final currentCity = _profileController.city.value;
        if (currentCity.isNotEmpty) {
          final match = result.firstWhereOrNull(
            (c) => c.nom.toLowerCase() == currentCity.toLowerCase() || c.id == currentCity,
          );
          if (match != null) selectedCity.value = match;
        }
      }
    } catch (e) {
      debugPrint('[Error] Erreur chargement villes: $e');
      Get.snackbar(
        'edit_profile_error_title'.tr,
        'edit_profile_error_load_cities'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoadingCities.value = false;
    }
  }

  void onCountryChanged(LocationOption country) {
    if (!canChangeLocation.value) return;
    if (selectedCountry.value?.id == country.id) return;
    selectedCountry.value = country;
    _loadCities(country.id);
  }

  void onCityChanged(LocationOption city) {
    if (!canChangeLocation.value) return;
    selectedCity.value = city;
  }

  void onGenderChanged(String value) => selectedGender.value = value;

  String? validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) return 'field_required'.tr;
    return null;
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;

    isSaving.value = true;
    try {
      final Map<String, dynamic> payload = {
        'username': usernameController.text.trim(),
        'last_name': nomController.text.trim(),
        'first_name': prenomController.text.trim(),
        'bio': bioController.text.trim(),
        if (selectedGender.value != null) 'gender': selectedGender.value,
        if (selectedBirthDate.value != null)
          'birth_date': _formatDate(selectedBirthDate.value!),
      };

      final countryChanged = selectedCountry.value != null &&
          selectedCountry.value!.nom.toLowerCase() != _profileController.country.value.toLowerCase();
      final cityChanged = selectedCity.value != null &&
          selectedCity.value!.nom.toLowerCase() != _profileController.city.value.toLowerCase();

      if (canChangeLocation.value && (countryChanged || cityChanged)) {
        if (selectedCountry.value != null) payload['country_id'] = selectedCountry.value!.id;
        if (selectedCity.value != null) payload['city_id'] = selectedCity.value!.id;
      }

      final success = await _profileController.updateProfile(payload);
      
      if (success) {
        // 1. Sauvegarde des intérêts en base
        await _interestService.saveUserInterests(
          _profileController.userId.value, 
          selectedInterestIds.toList()
        );
        
        // 2. On force le ProfileController à recharger ses intérêts
        await _profileController.refreshProfile();
        
        Get.back();
      }
    } finally {
      isSaving.value = false;
    }
  }

  @override
  void onClose() {
    nomController.dispose();
    prenomController.dispose();
    usernameController.dispose();
    bioController.dispose();
    super.onClose();
  }
}