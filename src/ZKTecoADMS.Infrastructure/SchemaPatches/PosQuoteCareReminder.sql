-- Nhắc lịch hẹn chăm sóc khách (báo giá)
ALTER TABLE "PosQuoteActivities" ADD COLUMN IF NOT EXISTS "ReminderSentAt" timestamp without time zone NULL;
CREATE INDEX IF NOT EXISTS "IX_PosQuoteActivities_FollowUp"
    ON "PosQuoteActivities" ("NextFollowUpAt") WHERE "NextFollowUpAt" IS NOT NULL AND "ReminderSentAt" IS NULL AND "Deleted" IS NULL;
