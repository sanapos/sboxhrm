-- Upgrade TaskComments: add ImageUrls, LinkUrls, CommentType, ProgressSnapshot
ALTER TABLE "TaskComments" ADD COLUMN IF NOT EXISTS "CommentType" integer NOT NULL DEFAULT 0;
ALTER TABLE "TaskComments" ADD COLUMN IF NOT EXISTS "ImageUrls" text;
ALTER TABLE "TaskComments" ADD COLUMN IF NOT EXISTS "LinkUrls" text;
ALTER TABLE "TaskComments" ADD COLUMN IF NOT EXISTS "ProgressSnapshot" integer;

-- Index for quick lookup of progress updates
CREATE INDEX IF NOT EXISTS "IX_TaskComments_TaskId_CommentType" ON "TaskComments" ("TaskId", "CommentType");
