ALTER TABLE "LeaveApprovalRecords" ADD COLUMN IF NOT EXISTS "CreatedBy" text;
ALTER TABLE "LeaveApprovalRecords" ADD COLUMN IF NOT EXISTS "UpdatedBy" text;
ALTER TABLE "ApprovalRecords" ADD COLUMN IF NOT EXISTS "CreatedBy" text;
ALTER TABLE "ApprovalRecords" ADD COLUMN IF NOT EXISTS "UpdatedBy" text;
ALTER TABLE "AdvanceApprovalRecords" ADD COLUMN IF NOT EXISTS "CreatedBy" text;
ALTER TABLE "AdvanceApprovalRecords" ADD COLUMN IF NOT EXISTS "UpdatedBy" text;
SELECT 'Done' as result;
