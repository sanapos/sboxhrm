CREATE TABLE IF NOT EXISTS "KeyActivationPromotions" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "Name" text NOT NULL DEFAULT '',
    "ServicePackageId" uuid NOT NULL,
    "StartDate" timestamp without time zone NOT NULL,
    "EndDate" timestamp without time zone NOT NULL,
    "Bonus1Key" integer NOT NULL DEFAULT 0,
    "Bonus2Keys" integer NOT NULL DEFAULT 0,
    "Bonus3Keys" integer NOT NULL DEFAULT 0,
    "Bonus4Keys" integer NOT NULL DEFAULT 0,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    CONSTRAINT "PK_KeyActivationPromotions" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_KeyActivationPromotions_ServicePackages" FOREIGN KEY ("ServicePackageId") REFERENCES "ServicePackages"("Id") ON DELETE CASCADE
);
