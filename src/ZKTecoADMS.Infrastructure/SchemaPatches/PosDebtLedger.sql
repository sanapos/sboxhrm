-- Sổ công nợ khách hàng / nhà cung cấp (đối chiếu đầu kỳ / phát sinh / cuối kỳ).
CREATE TABLE IF NOT EXISTS "PosDebtLedgerEntries" (
  "Id" uuid NOT NULL PRIMARY KEY,
  "StoreId" uuid NOT NULL,
  "PartyType" character varying(20) NOT NULL,
  "PartyId" uuid NOT NULL,
  "At" timestamp without time zone NOT NULL,
  "DocType" character varying(30) NOT NULL,
  "DocId" uuid NULL,
  "DocNo" character varying(60) NULL,
  "Delta" numeric(18,2) NOT NULL,
  "BalanceAfter" numeric(18,2) NOT NULL,
  "Note" character varying(300) NULL,
  "CreatedAt" timestamp without time zone NOT NULL DEFAULT now(),
  "UpdatedAt" timestamp without time zone NULL,
  "UpdatedBy" text NULL,
  "CreatedBy" text NULL
);
CREATE INDEX IF NOT EXISTS "IX_PosDebtLedgerEntries_Party" ON "PosDebtLedgerEntries" ("StoreId", "PartyType", "PartyId", "At");

CREATE TABLE IF NOT EXISTS "__SchemaPatches" (
  "Name" character varying(200) NOT NULL PRIMARY KEY,
  "AppliedAt" timestamp with time zone NOT NULL DEFAULT now()
);

-- Một lần: số dư hiện tại của khách / NCC thành dòng «Số dư đầu» (trước khi có sổ).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__SchemaPatches" WHERE "Name" = 'PosDebtLedgerOpening') THEN
    INSERT INTO "PosDebtLedgerEntries" ("Id", "StoreId", "PartyType", "PartyId", "At", "DocType", "Delta", "BalanceAfter", "Note", "CreatedAt", "CreatedBy")
    SELECT gen_random_uuid(), "StoreId", 'customer', "Id", now() AT TIME ZONE 'UTC', 'Opening', "CurrentDebt", "CurrentDebt",
           'Số dư khi bắt đầu sổ công nợ', now() AT TIME ZONE 'UTC', 'System'
    FROM "PosCustomers" WHERE "Deleted" IS NULL AND "CurrentDebt" <> 0;
    INSERT INTO "PosDebtLedgerEntries" ("Id", "StoreId", "PartyType", "PartyId", "At", "DocType", "Delta", "BalanceAfter", "Note", "CreatedAt", "CreatedBy")
    SELECT gen_random_uuid(), "StoreId", 'supplier', "Id", now() AT TIME ZONE 'UTC', 'Opening', "CurrentDebt", "CurrentDebt",
           'Số dư khi bắt đầu sổ công nợ', now() AT TIME ZONE 'UTC', 'System'
    FROM "PosSuppliers" WHERE "Deleted" IS NULL AND "CurrentDebt" <> 0;
    INSERT INTO "__SchemaPatches" ("Name", "AppliedAt") VALUES ('PosDebtLedgerOpening', NOW());
  END IF;
END $$;
