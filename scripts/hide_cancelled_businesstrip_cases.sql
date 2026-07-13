-- Ẩn toàn bộ phiếu công tác phí đã hủy khỏi danh sách / báo cáo (soft-delete).
-- Status Cancelled = 9
UPDATE "BusinessTripCases"
SET
  "IsActive" = false,
  "Deleted" = COALESCE("Deleted", NOW() AT TIME ZONE 'UTC'),
  "DeletedBy" = COALESCE("DeletedBy", 'system-hide-cancelled'),
  "UpdatedAt" = NOW() AT TIME ZONE 'UTC'
WHERE "Status" = 9
  AND "Deleted" IS NULL;
