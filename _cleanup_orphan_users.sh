docker exec -i zkteco_postgres psql -U postgres -d ZKTecoADMS <<'SQL'
BEGIN;

-- Các user cần dọn: StoreId IS NULL, và KHÔNG phải superadmin
CREATE TEMP TABLE orphan_users AS
SELECT u."Id"
FROM "AspNetUsers" u
LEFT JOIN "Stores" s ON s."Id" = u."StoreId"
WHERE (u."StoreId" IS NULL OR s."Id" IS NULL)
  AND u."UserName" <> 'superadmin'
  AND u."Email" <> 'sanapos.vn@gmail.com';

SELECT COUNT(*) AS to_delete FROM orphan_users;

-- Null-out mọi FK nullable tham chiếu AspNetUsers (phát hiện qua constraint thật)
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT tc.table_name, kcu.column_name, col.is_nullable
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
        JOIN information_schema.constraint_column_usage ccu
          ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.table_schema
        JOIN information_schema.columns col
          ON col.table_schema = kcu.table_schema AND col.table_name = kcu.table_name AND col.column_name = kcu.column_name
        WHERE tc.constraint_type = 'FOREIGN KEY'
          AND tc.table_schema = 'public'
          AND ccu.table_name = 'AspNetUsers'
          AND ccu.column_name = 'Id'
          AND tc.table_name NOT LIKE 'AspNet%'
          AND tc.table_name <> 'UserRefreshTokens'
    LOOP
        IF r.is_nullable = 'YES' THEN
            BEGIN
                EXECUTE format('UPDATE %I SET %I = NULL WHERE %I IN (SELECT "Id" FROM orphan_users)', r.table_name, r.column_name, r.column_name);
            EXCEPTION WHEN others THEN RAISE NOTICE 'Skip null %.%: %', r.table_name, r.column_name, SQLERRM; END;
        ELSE
            BEGIN
                EXECUTE format('DELETE FROM %I WHERE %I IN (SELECT "Id" FROM orphan_users)', r.table_name, r.column_name);
            EXCEPTION WHEN others THEN RAISE NOTICE 'Skip delete %.%: %', r.table_name, r.column_name, SQLERRM; END;
        END IF;
    END LOOP;
END$$;

-- Xóa Employees tham chiếu user (nếu cột UserId tồn tại)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='Employees' AND column_name='UserId') THEN
        EXECUTE 'DELETE FROM "Employees" WHERE "UserId" IN (SELECT "Id" FROM orphan_users)';
    END IF;
END$$;

-- Xóa các bảng phụ thuộc Identity
DELETE FROM "UserRefreshTokens" WHERE "ApplicationUserId" IN (SELECT "Id" FROM orphan_users);
DELETE FROM "AspNetUserRoles"   WHERE "UserId" IN (SELECT "Id" FROM orphan_users);
DELETE FROM "AspNetUserClaims"  WHERE "UserId" IN (SELECT "Id" FROM orphan_users);
DELETE FROM "AspNetUserLogins"  WHERE "UserId" IN (SELECT "Id" FROM orphan_users);
DELETE FROM "AspNetUserTokens"  WHERE "UserId" IN (SELECT "Id" FROM orphan_users);

-- Cuối cùng xóa user
DELETE FROM "AspNetUsers" WHERE "Id" IN (SELECT "Id" FROM orphan_users);

SELECT COUNT(*) AS remaining_users FROM "AspNetUsers";
SELECT u."UserName", u."Email", s."Name" AS store
FROM "AspNetUsers" u LEFT JOIN "Stores" s ON s."Id"=u."StoreId";

COMMIT;
SQL
