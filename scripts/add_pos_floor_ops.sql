-- Floor map enhancements: layout, guests, kitchen send, cleaning
BEGIN;

ALTER TABLE "PosServiceResources" ADD COLUMN IF NOT EXISTS "LayoutX" double precision NULL;
ALTER TABLE "PosServiceResources" ADD COLUMN IF NOT EXISTS "LayoutY" double precision NULL;
ALTER TABLE "PosServiceResources" ADD COLUMN IF NOT EXISTS "LayoutW" double precision NOT NULL DEFAULT 120;
ALTER TABLE "PosServiceResources" ADD COLUMN IF NOT EXISTS "LayoutH" double precision NOT NULL DEFAULT 100;
ALTER TABLE "PosServiceResources" ADD COLUMN IF NOT EXISTS "NeedsCleaning" boolean NOT NULL DEFAULT false;

ALTER TABLE "PosResourceSessions" ADD COLUMN IF NOT EXISTS "AccumulatedPauseMinutes" integer NOT NULL DEFAULT 0;
ALTER TABLE "PosResourceSessions" ADD COLUMN IF NOT EXISTS "GuestCount" integer NOT NULL DEFAULT 1;
ALTER TABLE "PosResourceSessions" ADD COLUMN IF NOT EXISTS "BillRequested" boolean NOT NULL DEFAULT false;

ALTER TABLE "PosSaleOrderLines" ADD COLUMN IF NOT EXISTS "KitchenSentQty" numeric(18,3) NOT NULL DEFAULT 0;
ALTER TABLE "PosSaleOrderLines" ADD COLUMN IF NOT EXISTS "KitchenSentAt" timestamp without time zone NULL;

COMMIT;
