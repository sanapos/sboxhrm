SELECT NOW() AT TIME ZONE 'Asia/Ho_Chi_Minh' AS now_vn,
       l."UpdatedAt" AT TIME ZONE 'Asia/Ho_Chi_Minh' AS gps_vn,
       l."Latitude", l."Longitude", l."Accuracy",
       EXTRACT(EPOCH FROM (NOW()-l."UpdatedAt"))/60 AS age_min
FROM "EmployeeLiveLocations" l
WHERE l."EmployeeId"='53c1bcbd-f8c2-47da-bca3-684b80a08c04';
