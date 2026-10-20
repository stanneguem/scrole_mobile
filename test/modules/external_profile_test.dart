import 'package:flutter_test/flutter_test.dart';
import 'package:scrole/modules/module_decouverte/externe/repositories/external_profile_repository.dart';

void main() {
  group('ExternalProfileResult Status Tests', () {
    test('ExternalProfileResult correctly stores status and profile', () {
      const deletedRes = ExternalProfileResult(status: ProfileResultStatus.deleted);
      expect(deletedRes.status, equals(ProfileResultStatus.deleted));
      expect(deletedRes.profile, isNull);

      const notFoundRes = ExternalProfileResult(status: ProfileResultStatus.notFound);
      expect(notFoundRes.status, equals(ProfileResultStatus.notFound));
      expect(notFoundRes.profile, isNull);

      const suspendedRes = ExternalProfileResult(status: ProfileResultStatus.suspended);
      expect(suspendedRes.status, equals(ProfileResultStatus.suspended));

      const bannedRes = ExternalProfileResult(status: ProfileResultStatus.banned);
      expect(bannedRes.status, equals(ProfileResultStatus.banned));

      const errorRes = ExternalProfileResult(status: ProfileResultStatus.error, errorMessage: 'Erreur réseau');
      expect(errorRes.status, equals(ProfileResultStatus.error));
      expect(errorRes.errorMessage, equals('Erreur réseau'));
    });
  });
}
