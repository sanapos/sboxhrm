-- Migration: Add feedback chat-style replies and image support
-- Date: 2025-01-XX

-- 1. Add ImageUrls column to Feedbacks table
ALTER TABLE "Feedbacks" ADD COLUMN IF NOT EXISTS "ImageUrls" character varying(2000);

-- 2. Create FeedbackReplies table
CREATE TABLE IF NOT EXISTS "FeedbackReplies" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "FeedbackId" uuid NOT NULL,
    "SenderEmployeeId" uuid,
    "Content" character varying(5000) NOT NULL,
    "ImageUrls" character varying(2000),
    "IsFromSender" boolean NOT NULL DEFAULT false,
    "StoreId" uuid,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    CONSTRAINT "PK_FeedbackReplies" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_FeedbackReplies_Feedbacks_FeedbackId" FOREIGN KEY ("FeedbackId") REFERENCES "Feedbacks" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_FeedbackReplies_Employees_SenderEmployeeId" FOREIGN KEY ("SenderEmployeeId") REFERENCES "Employees" ("Id") ON DELETE SET NULL
);

-- 3. Create indexes
CREATE INDEX IF NOT EXISTS "IX_FeedbackReplies_FeedbackId" ON "FeedbackReplies" ("FeedbackId");
CREATE INDEX IF NOT EXISTS "IX_FeedbackReplies_SenderEmployeeId" ON "FeedbackReplies" ("SenderEmployeeId");
