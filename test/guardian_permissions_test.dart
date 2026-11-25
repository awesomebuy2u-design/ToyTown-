import 'package:flutter_test/flutter_test.dart';
import '../lib/guardian_permissions.dart';

void main() {
  test('child mode permits only explicitly allowed activities', () {
    const allowed = {
      TownCapability.play, TownCapability.careForPet,
      TownCapability.decorateShop, TownCapability.draftListing,
    };
    for (final capability in TownCapability.values) {
      expect(canUseTownCapability(capability, guardianVerified: false),
        allowed.contains(capability), reason: capability.name);
      expect(canUseTownCapability(capability, guardianVerified: true), true);
    }
  });
}
