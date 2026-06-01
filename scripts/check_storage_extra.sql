SELECT "Code", "Name" FROM "Stores" ORDER BY "Code";

SELECT "Status", COUNT(*) 
FROM "MobileAttendanceRecords" 
WHERE "FaceImageUrl" IS NOT NULL AND TRIM("FaceImageUrl") <> ''
GROUP BY "Status";

SELECT COUNT(*) AS pending_with_face
FROM "MobileAttendanceRecords"
WHERE "Status" = 'pending' AND "FaceImageUrl" IS NOT NULL AND TRIM("FaceImageUrl") <> '';
