import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:scrole/app/utils/supabase_error_mapper.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/scrole_bottom_sheet.dart';
import '../../../module_discussion_direct/externe/repositories/social_repository.dart';
import '../controllers/profile_controller.dart';

class UserQrIdentityScreen extends StatefulWidget {
  const UserQrIdentityScreen({super.key});

  @override
  State<UserQrIdentityScreen> createState() => _UserQrIdentityScreenState();
}

class _UserQrIdentityScreenState extends State<UserQrIdentityScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final MobileScannerController _scannerController = MobileScannerController();
  final SocialRepository _socialRepo = SocialRepository();

  Map<String, dynamic>? _activeQrCode;
  bool _isLoadingQr = true;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadQrCode();
  }

  Future<void> _loadQrCode() async {
    setState(() => _isLoadingQr = true);
    try {
      final qr = await _socialRepo.getOrGenerateUserQrCode();
      if (mounted) {
        setState(() {
          _activeQrCode = qr;
          _isLoadingQr = false;
        });
      }
    } catch (e) {
      debugPrint('[UserQrIdentityScreen] Error loading QR: $e');
      if (mounted) setState(() => _isLoadingQr = false);
    }
  }

  Future<void> _forceRegenerateQrCode() async {
    setState(() => _isLoadingQr = true);
    try {
      final newUuid = _socialRepo.generateLocalUuid();
      final userId = _socialRepo.currentUserId ?? '';
      final localQr = {
        'id': newUuid,
        'user_id': userId,
        'uses_remaining': 3,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'sync_status': 'pending_push',
      };
      await _socialRepo.dao.saveUserQrCodes([localQr]);
      await _socialRepo.dao.enqueueOutbox(
        userId: userId,
        operation: 'generate_user_qr_code',
        payload: {'id': newUuid},
      );
      if (mounted) {
        setState(() {
          _activeQrCode = localQr;
          _isLoadingQr = false;
        });
      }
    } catch (e) {
      Get.snackbar('Erreur', e.toString());
      if (mounted) setState(() => _isLoadingQr = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetectBarcode(BarcodeCapture capture) {
    if (_isScanning) return;

    final barcode = capture.barcodes.firstOrNull;
    final String? rawValue = barcode?.rawValue;

    if (rawValue == null || rawValue.isEmpty) return;

    setState(() => _isScanning = true);

    if (rawValue.startsWith('scrole_user:')) {
      final userId = rawValue.replaceFirst('scrole_user:', '');
      Get.toNamed(AppPages.externalProfilePath(userId));
      setState(() => _isScanning = false);
      return;
    }

    String qrId = rawValue;
    if (rawValue.startsWith('scrole_qr:')) {
      qrId = rawValue.replaceFirst('scrole_qr:', '');
    }

    _showModeSelectionSheet(qrId);
  }

  void _showModeSelectionSheet(String qrId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ScroleBottomSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Option d\'ajout d\'ami', style: AppTextStyles.h4),
            const SizedBox(height: 8),
            Text(
              'Choisissez comment vous souhaitez ajouter cet utilisateur via son QR Code.',
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: 20),
            ScroleBottomSheetGroup(
              children: [
                ScroleBottomSheetAction(
                  icon: Icons.person_add_rounded,
                  label: 'Envoyer une demande d\'ami',
                  subtitle: 'Le destinataire devra accepter votre demande.',
                  color: AppColors.primary,
                  onTap: () {
                    Get.back();
                    _performScan(qrId, 'demande');
                  },
                ),
                const ScroleBottomSheetDivider(),
                ScroleBottomSheetAction(
                  icon: Icons.flash_on_rounded,
                  label: 'Confirmation directe (Amitié immédiate)',
                  subtitle: 'Crée l\'amitié immédiatement sans attente (consomme 1 usage du QR).',
                  color: Colors.amber[800],
                  onTap: () {
                    Get.back();
                    _confirmDirectScan(qrId);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                Get.back();
                setState(() => _isScanning = false);
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                backgroundColor: AppColors.surfaceDark,
              ),
              child: const Text('Annuler'),
            ),
          ],
        ),
      ),
    ).then((_) {
      if (mounted) setState(() => _isScanning = false);
    });
  }

  void _confirmDirectScan(String qrId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmation Directe'),
        content: const Text(
          'Attention : Confirmation directe crée l\'amitié immédiatement sans validation du propriétaire du QR code. Souhaitez-vous continuer ?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() => _isScanning = false);
            },
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _performScan(qrId, 'confirmation_directe');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[800]),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  Future<void> _performScan(String qrId, String mode) async {
    try {
      final res = await _socialRepo.scanQrCode(qrId, mode);
      final friendId = res != null ? (res['friend_id'] ?? res['user_id'] ?? res['receiver_id'])?.toString() : null;

      if (mode == 'confirmation_directe') {
        Get.snackbar('Succès', 'Nouvel ami confirmé directement !', backgroundColor: Colors.green, colorText: Colors.white);
        if (friendId != null && friendId.isNotEmpty) {
          Get.toNamed(AppPages.externalProfilePath(friendId));
        }
      } else {
        Get.snackbar('Succès', 'Demande d\'ami envoyée !', backgroundColor: AppColors.primary, colorText: Colors.white);
      }
    } catch (e) {
      showAppErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileController = Get.find<ProfileController>();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        centerTitle: true,
        title: _buildPillTabs(context),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMyQrCodeTab(profileController),
          _buildScannerTab(context),
        ],
      ),
    );
  }

  Widget _buildPillTabs(BuildContext context) {
    final activeIndex = _tabController.index;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTabChip(
            index: 0,
            label: 'Mon QR Code',
            icon: Icons.qr_code_rounded,
            isActive: activeIndex == 0,
          ),
          const SizedBox(width: 4),
          _buildTabChip(
            index: 1,
            label: 'Scanner',
            icon: Icons.qr_code_scanner_rounded,
            isActive: activeIndex == 1,
          ),
        ],
      ),
    );
  }

  Widget _buildTabChip({
    required int index,
    required String label,
    required IconData icon,
    required bool isActive,
  }) {
    return GestureDetector(
      onTap: () {
        _tabController.animateTo(index);
        setState(() {});
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? Colors.white : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive ? Colors.white : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyQrCodeTab(ProfileController controller) {
    if (_isLoadingQr) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    final qrData = _activeQrCode;
    final qrId = qrData != null ? (qrData['id'] ?? '').toString() : '';
    final usesRemaining = qrData != null ? (qrData['uses_remaining'] as num?)?.toInt() ?? 0 : 0;
    final syncStatus = qrData != null ? (qrData['sync_status'] ?? 'synced').toString() : 'synced';
    final isSynced = syncStatus == 'synced';

    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.topCenter,
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 300,
                  margin: const EdgeInsets.only(top: 40),
                  padding: const EdgeInsets.fromLTRB(30, 80, 30, 30),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isSynced)
                        Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.amber[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'En attente de connexion réseau pour activation du QR code...',
                            style: TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (qrId.isEmpty)
                        ElevatedButton.icon(
                          onPressed: _forceRegenerateQrCode,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Générer mon QR Code'),
                        )
                      else
                        QrImageView(
                          data: 'scrole_qr:$qrId',
                          version: QrVersions.auto,
                          size: 200.0,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Colors.black,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Colors.black,
                          ),
                        ),
                      const SizedBox(height: 20),
                      Obx(() => Text(
                        '@${controller.username.value}',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      )),
                      const SizedBox(height: 12),
                      if (qrId.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: usesRemaining > 0 ? AppColors.primary.withValues(alpha: 0.15) : AppColors.error.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            usesRemaining > 0 ? '$usesRemaining utilisation(s) restante(s)' : '0 utilisation restante (Expiré)',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: usesRemaining > 0 ? AppColors.primary : AppColors.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (usesRemaining <= 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: OutlinedButton.icon(
                            onPressed: _forceRegenerateQrCode,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Régénérer un QR Code'),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  top: -10,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF121212),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(45),
                        child: Obx(() => controller.profileImageUrl.value.isNotEmpty
                            ? AppCachedImage(imageUrl: controller.profileImageUrl.value, fit: BoxFit.cover)
                            : Center(
                                child: Text(
                                  controller.initials,
                                  style: AppTextStyles.h3.copyWith(color: Colors.white),
                                ),
                              )),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            Text(
              'SCROLE IDENTITY QR CODE',
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white54,
                letterSpacing: 2,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerTab(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: _onDetectBarcode,
        ),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 3),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        Positioned(
          bottom: 60,
          left: 20,
          right: 20,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white24),
              ),
              child: const Text(
                'Placez le code QR d\'un ami dans le cadre pour le scanner',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
