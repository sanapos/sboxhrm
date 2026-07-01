-- Khách hàng POS + giao hàng trên đơn bán
CREATE TABLE IF NOT EXISTS "PosCustomers" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "CustomerCode" character varying(30) NOT NULL,
    "Name" character varying(200) NOT NULL,
    "Phone" character varying(50),
    "Email" character varying(200),
    "Address" character varying(500),
    "Province" character varying(100),
    "Ward" character varying(100),
    "CompanyName" character varying(200),
    "TaxCode" character varying(50),
    "Note" character varying(1000),
    "TotalPurchase" numeric(18,2) NOT NULL DEFAULT 0,
    "CurrentDebt" numeric(18,2) NOT NULL DEFAULT 0,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "CreatedBy" character varying(200),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" character varying(200),
    "Deleted" timestamp without time zone,
    "DeletedBy" character varying(200),
    "LastModified" timestamp without time zone,
    "LastModifiedBy" character varying(200),
    CONSTRAINT "FK_PosCustomers_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id") ON DELETE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosCustomers_StoreId_CustomerCode" ON "PosCustomers"("StoreId", "CustomerCode");

ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "CustomerId" uuid NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "IsDelivery" boolean NOT NULL DEFAULT false;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryAddress" character varying(500);
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryPhone" character varying(50);
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryPartner" character varying(100);
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryStatus" character varying(50);
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryDate" timestamp without time zone;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FK_PosSaleOrders_Customer') THEN
        ALTER TABLE "PosSaleOrders"
            ADD CONSTRAINT "FK_PosSaleOrders_Customer"
            FOREIGN KEY ("CustomerId") REFERENCES "PosCustomers"("Id") ON DELETE SET NULL;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS "IX_PosSaleOrders_StoreId_CustomerId" ON "PosSaleOrders"("StoreId", "CustomerId");
CREATE INDEX IF NOT EXISTS "IX_PosSaleOrders_StoreId_IsDelivery" ON "PosSaleOrders"("StoreId", "IsDelivery");
