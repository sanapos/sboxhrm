-- 1. Check leave_approval_levels setting
SELECT "Key", "Value", "StoreId"
FROM "AppSettings"
WHERE "Key" = 'leave_approval_levels';

-- 2. Check the latest leave from Nguyễn Đức Mỹ and its approval chain
SELECT l."Id", CONCAT(e."LastName", ' ', e."FirstName") as employee,
       l."TotalApprovalLevels", l."CurrentApprovalStep", l."Status",
       l."CreatedAt"
FROM "Leaves" l
JOIN "Employees" e ON e."ApplicationUserId" = l."EmployeeUserId"
WHERE CONCAT(e."LastName", ' ', e."FirstName") LIKE '%Mỹ%'
ORDER BY l."CreatedAt" DESC LIMIT 3;

-- 3. Check approval records for that leave
SELECT lar."StepOrder", lar."StepName", lar."AssignedUserName",
       lar."Status", lar."ActionDate"
FROM "LeaveApprovalRecords" lar
JOIN "Leaves" l ON l."Id" = lar."LeaveId"
JOIN "Employees" e ON e."ApplicationUserId" = l."EmployeeUserId"
WHERE CONCAT(e."LastName", ' ', e."FirstName") LIKE '%Mỹ%'
ORDER BY l."CreatedAt" DESC, lar."StepOrder" ASC
LIMIT 10;

-- 4. Check DirectManager chain for Nguyễn Đức Mỹ
SELECT e."Id", CONCAT(e."LastName", ' ', e."FirstName") as name,
       e."DirectManagerEmployeeId",
       CONCAT(dm."LastName", ' ', dm."FirstName") as direct_manager
FROM "Employees" e
LEFT JOIN "Employees" dm ON dm."Id" = e."DirectManagerEmployeeId"
WHERE CONCAT(e."LastName", ' ', e."FirstName") LIKE '%Mỹ%'
   OR CONCAT(e."LastName", ' ', e."FirstName") LIKE '%Quốc%'
   OR CONCAT(e."LastName", ' ', e."FirstName") LIKE '%Linh%'
ORDER BY e."LastName";

-- 5. Check notifications sent for the latest leave
SELECT n."Title", n."Message", n."Timestamp",
       CONCAT(tu."UserName") as target_user,
       CONCAT(fu."UserName") as from_user
FROM "Notifications" n
LEFT JOIN "AspNetUsers" tu ON tu."Id" = n."TargetUserId"
LEFT JOIN "AspNetUsers" fu ON fu."Id" = n."FromUserId"
WHERE n."RelatedEntityType" = 'Leave'
ORDER BY n."Timestamp" DESC LIMIT 10;
