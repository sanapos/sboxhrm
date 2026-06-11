-- Snapshot chấm công độc lập gắn phiếu lương (chốt từ tổng hợp lương)
CREATE TABLE IF NOT EXISTS "PayslipAttendanceSnapshots" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "PayslipId" uuid NOT NULL,
    "StoreId" uuid NULL,
    "PeriodStart" timestamp without time zone NOT NULL,
    "PeriodEnd" timestamp without time zone NOT NULL,
    "SnapshotJson" text NOT NULL,
    "CapturedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "CapturedByUserId" uuid NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS "IX_PayslipAttendanceSnapshots_PayslipId"
    ON "PayslipAttendanceSnapshots" ("PayslipId");

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'FK_PayslipAttendanceSnapshots_Payslips_PayslipId'
    ) THEN
        ALTER TABLE "PayslipAttendanceSnapshots"
            ADD CONSTRAINT "FK_PayslipAttendanceSnapshots_Payslips_PayslipId"
            FOREIGN KEY ("PayslipId") REFERENCES "Payslips" ("Id") ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'FK_PayslipAttendanceSnapshots_Stores_StoreId'
    ) THEN
        ALTER TABLE "PayslipAttendanceSnapshots"
            ADD CONSTRAINT "FK_PayslipAttendanceSnapshots_Stores_StoreId"
            FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE RESTRICT;
    END IF;
END $$;
