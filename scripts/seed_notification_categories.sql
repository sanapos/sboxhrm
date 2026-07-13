-- Seed thêm nhóm thông báo (Thu chi / Phạt / Suất ăn / Công tác / POS / Ca)
-- Idempotent: bỏ qua nếu Code đã tồn tại (StoreId IS NULL = hệ thống chung)

INSERT INTO "NotificationCategories" (
  "Id", "Code", "DisplayName", "Description", "Icon",
  "DisplayOrder", "IsSystem", "DefaultEnabled", "StoreId", "CreatedAt"
)
SELECT v."Id", v."Code", v."DisplayName", v."Description", v."Icon",
       v."DisplayOrder", TRUE, TRUE, NULL, NOW() AT TIME ZONE 'UTC'
FROM (VALUES
  ('a0000001-0000-0000-0000-000000000013'::uuid, 'transaction',   'Thu chi',              'Phiếu thu, phiếu chi, thanh toán',           'account_balance_wallet', 13),
  ('a0000001-0000-0000-0000-000000000014'::uuid, 'penalty',       'Phiếu phạt',           'Phiếu phạt chấm công, duyệt/thu phạt',      'gavel',                 14),
  ('a0000001-0000-0000-0000-000000000015'::uuid, 'meal',          'Suất ăn',              'Buổi ăn, thực đơn, chấm cơm',               'restaurant',            15),
  ('a0000001-0000-0000-0000-000000000016'::uuid, 'business_trip', 'Công tác',             'Ứng công tác, hoạch toán, chi bù',          'flight_takeoff',        16),
  ('a0000001-0000-0000-0000-000000000017'::uuid, 'pos',           'POS',                  'Bán hàng, nhập hàng, tồn kho',              'point_of_sale',         17),
  ('a0000001-0000-0000-0000-000000000018'::uuid, 'shift',         'Ca làm việc',          'Ca làm việc, đổi ca',                       'schedule',              18)
) AS v("Id", "Code", "DisplayName", "Description", "Icon", "DisplayOrder")
WHERE NOT EXISTS (
  SELECT 1 FROM "NotificationCategories" c
  WHERE c."Code" = v."Code" AND c."StoreId" IS NULL
);
