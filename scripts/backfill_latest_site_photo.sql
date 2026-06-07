-- Khôi phục ảnh CT cho bản ghi vừa upload (file đã có trên disk)
UPDATE "MobileAttendanceRecords"
SET "SitePhotoUrl" = '/stores/truongphat/uploads/mobile-site-photos/1a7d23f9-5888-43eb-92be-55dc0898e6ec.jpg',
    "UpdatedAt" = NOW()
WHERE "Id" = '9ed89df5-5b1a-447a-a785-8dda09882354'
  AND ("SitePhotoUrl" IS NULL OR trim("SitePhotoUrl") = '');
