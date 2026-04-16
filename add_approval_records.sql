-- Migration: Add multi-level approval for attendance corrections
-- 1. Add columns to AttendanceCorrectionRequests
ALTER TABLE "AttendanceCorrectionRequests" 
ADD COLUMN IF NOT EXISTS "TotalApprovalLevels" INTEGER NOT NULL DEFAULT 1;

ALTER TABLE "AttendanceCorrectionRequests" 
ADD COLUMN IF NOT EXISTS "CurrentApprovalStep" INTEGER NOT NULL DEFAULT 0;

-- Set existing approved records to have step = total
UPDATE "AttendanceCorrectionRequests" 
SET "CurrentApprovalStep" = 1 
WHERE "Status" = 1; -- Approved

-- 2. Create ApprovalRecords table
CREATE TABLE IF NOT EXISTS "ApprovalRecords" (
    "Id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "CorrectionRequestId" UUID NOT NULL REFERENCES "AttendanceCorrectionRequests"("Id") ON DELETE CASCADE,
    "StepOrder" INTEGER NOT NULL DEFAULT 1,
    "StepName" VARCHAR(200),
    "AssignedUserId" UUID REFERENCES "AspNetUsers"("Id"),
    "AssignedUserName" VARCHAR(200),
    "ActualUserId" UUID REFERENCES "AspNetUsers"("Id"),
    "ActualUserName" VARCHAR(200),
    "Status" INTEGER NOT NULL DEFAULT 0,
    "Note" VARCHAR(1000),
    "ActionDate" TIMESTAMP,
    "StoreId" UUID
);

-- Create index for fast lookup
CREATE INDEX IF NOT EXISTS "IX_ApprovalRecords_CorrectionRequestId" 
ON "ApprovalRecords" ("CorrectionRequestId");

CREATE INDEX IF NOT EXISTS "IX_ApprovalRecords_AssignedUserId" 
ON "ApprovalRecords" ("AssignedUserId");

-- 3. Backfill existing approved records with a single approval record
INSERT INTO "ApprovalRecords" ("Id", "CorrectionRequestId", "StepOrder", "StepName", 
    "AssignedUserId", "ActualUserId", "ActualUserName", "Status", "Note", "ActionDate", "StoreId")
SELECT gen_random_uuid(), c."Id", 1, 'Phê duyệt',
    c."ApprovedById", c."ApprovedById", 
    COALESCE(u."FullName", u."Email"),
    CASE WHEN c."Status" = 1 THEN 1 WHEN c."Status" = 2 THEN 2 ELSE 0 END,
    c."ApproverNote", c."ApprovedDate", c."StoreId"
FROM "AttendanceCorrectionRequests" c
LEFT JOIN "AspNetUsers" u ON u."Id" = c."ApprovedById"
WHERE c."ApprovedById" IS NOT NULL
AND NOT EXISTS (SELECT 1 FROM "ApprovalRecords" ar WHERE ar."CorrectionRequestId" = c."Id");
