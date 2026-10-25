-- AppPages: Terms / Privacy / Help content
CREATE TABLE IF NOT EXISTS "AppPages" (
    "Id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "Type" VARCHAR(30) NOT NULL,
    "Title" VARCHAR(200) NOT NULL DEFAULT '',
    "Content" TEXT NULL,
    "IsPublished" BOOLEAN NOT NULL DEFAULT TRUE,
    "UpdatedByName" VARCHAR(200) NULL,
    "CreatedAt" TIMESTAMP NOT NULL DEFAULT NOW(),
    "UpdatedAt" TIMESTAMP NULL,
    "CreatedBy" VARCHAR(200) NULL,
    "UpdatedBy" VARCHAR(200) NULL,
    CONSTRAINT "PK_AppPages" PRIMARY KEY ("Id")
);
CREATE INDEX IF NOT EXISTS "IX_AppPages_Type" ON "AppPages" ("Type");

-- AppBugReports: Bug reports / feedback from app settings
CREATE TABLE IF NOT EXISTS "AppBugReports" (
    "Id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "UserId" VARCHAR(100) NULL,
    "UserName" VARCHAR(200) NULL,
    "UserEmail" VARCHAR(100) NULL,
    "StoreName" VARCHAR(200) NULL,
    "Type" VARCHAR(30) NOT NULL DEFAULT 'Bug',
    "Title" VARCHAR(300) NOT NULL DEFAULT '',
    "Content" VARCHAR(5000) NOT NULL DEFAULT '',
    "AppVersion" VARCHAR(50) NULL,
    "DeviceInfo" VARCHAR(200) NULL,
    "Status" VARCHAR(30) NOT NULL DEFAULT 'New',
    "AdminNote" VARCHAR(2000) NULL,
    "ResolvedAt" TIMESTAMP NULL,
    "CreatedAt" TIMESTAMP NOT NULL DEFAULT NOW(),
    "UpdatedAt" TIMESTAMP NULL,
    "CreatedBy" VARCHAR(200) NULL,
    "UpdatedBy" VARCHAR(200) NULL,
    CONSTRAINT "PK_AppBugReports" PRIMARY KEY ("Id")
);
CREATE INDEX IF NOT EXISTS "IX_AppBugReports_Status" ON "AppBugReports" ("Status");
CREATE INDEX IF NOT EXISTS "IX_AppBugReports_CreatedAt" ON "AppBugReports" ("CreatedAt" DESC);

-- Seed default pages
INSERT INTO "AppPages" ("Id", "Type", "Title", "Content", "IsPublished", "CreatedAt")
VALUES
  (gen_random_uuid(), 'terms', 'Điều khoản sử dụng',
   E'# Điều khoản sử dụng\n\nVui lòng đọc kỹ các điều khoản sử dụng dưới đây trước khi sử dụng ứng dụng.\n\n## 1. Chấp nhận điều khoản\n\nBằng cách sử dụng ứng dụng, bạn đồng ý với các điều khoản này.\n\n## 2. Quyền sử dụng\n\nỨng dụng được cấp phép sử dụng cho mục đích quản lý nhân sự nội bộ.\n\n## 3. Bảo mật tài khoản\n\nBạn có trách nhiệm bảo mật thông tin tài khoản của mình.',
   TRUE, NOW()),
  (gen_random_uuid(), 'privacy', 'Chính sách bảo mật',
   E'# Chính sách bảo mật\n\n## 1. Thu thập thông tin\n\nChúng tôi thu thập thông tin cần thiết để vận hành ứng dụng quản lý nhân sự.\n\n## 2. Sử dụng thông tin\n\nThông tin chỉ được sử dụng trong phạm vi quản lý nội bộ doanh nghiệp.\n\n## 3. Bảo vệ dữ liệu\n\nDữ liệu được mã hóa và lưu trữ an toàn trên máy chủ.',
   TRUE, NOW()),
  (gen_random_uuid(), 'help', 'Trợ giúp',
   E'# Trợ giúp & Hướng dẫn\n\n## Chấm công\n- Chấm công bằng Face ID: Vào mục Chấm công → Bấm Chấm công\n- Chấm công GPS: Đảm bảo bật vị trí trên điện thoại\n\n## Nghỉ phép\n- Đăng ký nghỉ: Vào Nghỉ phép → Tạo đơn\n- Theo dõi trạng thái trong tab Chờ duyệt\n\n## Liên hệ hỗ trợ\nEmail: support@sana.vn',
   TRUE, NOW())
ON CONFLICT DO NOTHING;
