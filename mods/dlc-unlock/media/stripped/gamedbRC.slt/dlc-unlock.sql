-- dlc-unlock: lets DLC and bonus cars be bought in the Autoshow without the Xbox Live license check.
-- Reproduces the community gamedbrc-dlc-mod.slt exactly (verified with sqldiff against it).

-- ContentId 99 marks a car as license-gated (97 DLC cars + 46 bonus/edition cars).
UPDATE Data_Car SET ContentId = 0 WHERE ContentId = 99;

-- Drop the per-car and car-pack store offers so nothing links these cars to a DLC purchase.
-- Expansion (Storm Island, Porsche), VIP, token and treasure map offers are kept.
DELETE FROM ContentOffersMapping WHERE OfferId IN (SELECT Id FROM ContentOffers WHERE Style IN ('Car', 'CarPack', 'CarPass'));
DELETE FROM ContentOffers WHERE Style IN ('Car', 'CarPack', 'CarPass');
