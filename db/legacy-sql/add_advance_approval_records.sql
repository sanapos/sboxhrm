-- Migration: Add multi-level approval for Advance Requests
-- AdvanceApprovalRecords table + new columns on AdvanceRequests

-- Step 1: Add columns to AdvanceRequests
ALTER TABLE "AdvanceRequests" ADD COLUMN IF NOT EXISTS "TotalApprovalLevels" integer NOT NULL DEFAULT 1;
ALTER TABLE "AdvanceRequests" ADD COLUMN IF NOT EXISTS "CurrentApprovalStep" integer NOT NULL DEFAULT 0;

-- Step 2: Create AdvanceApprovalRecords table
CREATE TABLE IF NOT EXISTS "AdvanceApprovalRecords" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "AdvanceRequestId" uuid NOT NULL,
    "StepOrder" integer NOT NULL DEFAULT 0,
    "StepName" character varying(200),
    "AssignedUserId" uuid,
    "AssignedUserName" character varying(200),
    "ActualUserId" uuid,
    "ActualUserName" character varying(200),
    "Status" integer NOT NULL DEFAULT 0,
    "Note" character varying(1000),
    "ActionDate" timestamp with time zone,
    "StoreId" uuid,
    "CreatedAt" timestamp with time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp with time zone,
    "CreatedBy" character varying(450),
    "UpdatedBy" character varying(450),
    CONSTRAINT "PK_AdvanceApprovalRecords" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_AdvanceApprovalRecords_AdvanceRequests_AdvanceRequestId" FOREIGN KEY ("AdvanceRequestId") REFERENCES "AdvanceRequests" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_AdvanceApprovalRecords_AspNetUsers_AssignedUserId" FOREIGN KEY ("AssignedUserId") REFERENCES "AspNetUsers" ("Id"),
    CONSTRAINT "FK_AdvanceApprovalRecords_AspNetUsers_ActualUserId" FOREIGN KEY ("ActualUserId") REFERENCES "AspNetUsers" ("Id")
);

-- Step 3: Create indexes
CREATE INDEX IF NOT EXISTS "IX_AdvanceApprovalRecords_AdvanceRequestId" ON "AdvanceApprovalRecords" ("AdvanceRequestId");
CREATE INDEX IF NOT EXISTS "IX_AdvanceApprovalRecords_AssignedUserId" ON "AdvanceApprovalRecords" ("AssignedUserId");
CREATE INDEX IF NOT EXISTS "IX_AdvanceApprovalRecords_ActualUserId" ON "AdvanceApprovalRecords" ("ActualUserId");
CREATE INDEX IF NOT EXISTS "IX_AdvanceApprovalRecords_StoreId" ON "AdvanceApprovalRecords" ("StoreId");

-- Step 4: Backfill existing approved/rejected records with single-step approval records
INSERT INTO "AdvanceApprovalRecords" ("Id", "AdvanceRequestId", "StepOrder", "StepName", "AssignedUserId", "AssignedUserName", "ActualUserId", "ActualUserName", "Status", "ActionDate", "StoreId", "CreatedAt")
SELECT 
    gen_random_uuid(),
    ar."Id",
    1,
    'Quản lý',
    ar."ApprovedById",
    u."FullName",
    ar."ApprovedById",
    u."FullName",
    CASE 
        WHEN ar."Status" = 1 THEN 1  -- Approved
        WHEN ar."Status" = 2 THEN 2  -- Rejected
        ELSE 0  -- Pending
    END,
    ar."ApprovedDate",
    ar."StoreId",
    now()
FROM "AdvanceRequests" ar
LEFT JOIN "AspNetUsers" u ON ar."ApprovedById" = u."Id"
WHERE ar."Status" IN (1, 2) AND ar."ApprovedById" IS NOT NULL
AND NOT EXISTS (SELECT 1 FROM "AdvanceApprovalRecords" aar WHERE aar."AdvanceRequestId" = ar."Id");

-- Step 5: Update TotalApprovalLevels and CurrentApprovalStep for existing records
UPDATE "AdvanceRequests" SET "TotalApprovalLevels" = 1, "CurrentApprovalStep" = 1
WHERE "Status" IN (1, 2) AND "ApprovedById" IS NOT NULL;
