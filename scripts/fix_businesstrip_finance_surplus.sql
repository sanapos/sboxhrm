-- Fix BusinessTrip finance: link surplus to AdvanceRequest
ALTER TABLE "BusinessTripSettlementClaims"
    ADD COLUMN IF NOT EXISTS "SurplusAdvanceRequestId" uuid NULL;

CREATE INDEX IF NOT EXISTS "IX_BusinessTripSettlementClaims_SurplusAdvanceRequestId"
    ON "BusinessTripSettlementClaims" ("SurplusAdvanceRequestId");
