enum TownCapability {
  play, careForPet, decorateShop, draftListing,
  publishListing, deleteListing, messageBuyer, manageAgreement,
  partnerPurchase, manageFamily,
}

/// UI capability matrix only. Server policies must independently enforce
/// ownership, guardian identity and elevated authorization.
bool canUseTownCapability(TownCapability capability, {
  required bool guardianVerified,
}) {
  switch (capability) {
    case TownCapability.play:
    case TownCapability.careForPet:
    case TownCapability.decorateShop:
    case TownCapability.draftListing:
      return true;
    case TownCapability.publishListing:
    case TownCapability.deleteListing:
    case TownCapability.messageBuyer:
    case TownCapability.manageAgreement:
    case TownCapability.partnerPurchase:
    case TownCapability.manageFamily:
      return guardianVerified;
  }
}
