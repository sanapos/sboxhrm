-- Migration: Add multi-level approval support for Leave
-- 1. Add columns to Leaves table
-- 2. Create LeaveApprovalRecords table
-- 3. Backfill existing approved/rejected leaves with single-step records

-- Step 1: Add new columns to Leaves table
ALTER TABLE "Leaves" ADD COLUMN IF NOT EXISTS "TotalApprovalLevels" INTEGER NOT NULL DEFAULT 1;
ALTER TABLE "Leaves" ADD COLUMN IF NOT EXISTS "CurrentApprovalStep" INTEGER NOT NULL DEFAULT 0;

-- Step 2: Create LeaveApprovalRecords table
CREATE TABLE IF NOT EXISTS "LeaveApprovalRecords" (
    "Id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "LeaveId" UUID NOT NULL REFERENCES "Leaves"("Id") ON DELETE CASCADE,
    "StepOrder" INTEGER NOT NULL DEFAULT 1,
    "StepName" TEXT,
    "AssignedUserId" UUID REFERENCES "AspNetUsers"("Id"),
    "AssignedUserName" TEXT,
    "ActualUserId" UUID REFERENCES "AspNetUsers"("Id"),
    "ActualUserName" TEXT,
    "Status" INTEGER NOT NULL DEFAULT 0,
    "Note" TEXT,
    "ActionDate" TIMESTAMP,
    "StoreId" UUID NOT NULL,
    "CreatedAt" TIMESTAMP NOT NULL DEFAULT NOW(),
    "UpdatedAt" TIMESTAMP
);

CREATE INDEX IF NOT EXISTS "IX_LeaveApprovalRecords_LeaveId" ON "LeaveApprovalRecords" ("LeaveId");
CREATE INDEX IF NOT EXISTS "IX_LeaveApprovalRecords_StoreId" ON "LeaveApprovalRecords" ("StoreId");
CREATE INDEX IF NOT EXISTS "IX_LeaveApprovalRecords_AssignedUserId" ON "LeaveApprovalRecords" ("AssignedUserId");

-- Step 3: Backfill existing leaves with approval records
-- For Approved leaves: create a single step record marked as Approved
INSERT INTO "LeaveApprovalRecords" ("LeaveId", "StepOrder", "StepName", "AssignedUserId", "Status", "ActionDate", "StoreId", "CreatedAt")
SELECT l."Id", 1, 'Quản lý trực tiếp', l."ManagerId", 1, l."UpdatedAt", l."StoreId", NOW()
FROM "Leaves" l
WHERE l."Status" = 1
AND NOT EXISTS (SELECT 1 FROM "LeaveApprovalRecords" r WHERE r."LeaveId" = l."Id");

-- For Rejected leaves: create a single step record marked as Rejected
INSERT INTO "LeaveApprovalRecords" ("LeaveId", "StepOrder", "StepName", "AssignedUserId", "Status", "Note", "ActionDate", "StoreId", "CreatedAt")
SELECT l."Id", 1, 'Quản lý trực tiếp', l."ManagerId", 2, l."RejectionReason", l."UpdatedAt", l."StoreId", NOW()
FROM "Leaves" l
WHERE l."Status" = 2
AND NOT EXISTS (SELECT 1 FROM "LeaveApprovalRecords" r WHERE r."LeaveId" = l."Id");

-- For Pending leaves: create a single step record marked as Pending
INSERT INTO "LeaveApprovalRecords" ("LeaveId", "StepOrder", "StepName", "AssignedUserId", "Status", "StoreId", "CreatedAt")
SELECT l."Id", 1, 'Quản lý trực tiếp', l."ManagerId", 0, l."StoreId", NOW()
FROM "Leaves" l
WHERE l."Status" = 0
AND NOT EXISTS (SELECT 1 FROM "LeaveApprovalRecords" r WHERE r."LeaveId" = l."Id");

-- Update CurrentApprovalStep for already approved leaves
UPDATE "Leaves" SET "CurrentApprovalStep" = 1 WHERE "Status" = 1;
