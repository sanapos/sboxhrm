-- Add DepartmentPermissions table
CREATE TABLE IF NOT EXISTS "DepartmentPermissions" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "UserId" uuid NOT NULL,
    "DepartmentId" uuid,
    "PermissionId" uuid NOT NULL,
    "IncludeChildren" boolean NOT NULL DEFAULT true,
    "StoreId" uuid,
    "CanView" boolean NOT NULL DEFAULT false,
    "CanCreate" boolean NOT NULL DEFAULT false,
    "CanEdit" boolean NOT NULL DEFAULT false,
    "CanDelete" boolean NOT NULL DEFAULT false,
    "CanExport" boolean NOT NULL DEFAULT false,
    "CanApprove" boolean NOT NULL DEFAULT false,
    "IsActive" boolean NOT NULL DEFAULT true,
    "GrantedBy" text,
    "Note" text,
    "CreatedAt" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "UpdatedAt" timestamp with time zone,
    "CreatedBy" text,
    "UpdatedBy" text,
    CONSTRAINT "PK_DepartmentPermissions" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_DepartmentPermissions_AspNetUsers_UserId" FOREIGN KEY ("UserId") REFERENCES "AspNetUsers" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_DepartmentPermissions_Departments_DepartmentId" FOREIGN KEY ("DepartmentId") REFERENCES "Departments" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_DepartmentPermissions_Permissions_PermissionId" FOREIGN KEY ("PermissionId") REFERENCES "Permissions" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_DepartmentPermissions_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE CASCADE
);

-- Indexes
CREATE INDEX IF NOT EXISTS "IX_DepartmentPermissions_UserId" ON "DepartmentPermissions" ("UserId");
CREATE INDEX IF NOT EXISTS "IX_DepartmentPermissions_DepartmentId" ON "DepartmentPermissions" ("DepartmentId");
CREATE INDEX IF NOT EXISTS "IX_DepartmentPermissions_PermissionId" ON "DepartmentPermissions" ("PermissionId");
CREATE INDEX IF NOT EXISTS "IX_DepartmentPermissions_StoreId" ON "DepartmentPermissions" ("StoreId");
CREATE UNIQUE INDEX IF NOT EXISTS "IX_DepartmentPermissions_User_Dept_Perm_Store" 
    ON "DepartmentPermissions" ("UserId", "DepartmentId", "PermissionId", "StoreId");

-- Add missing Permission modules (seed data)
INSERT INTO "Permissions" ("Id", "Module", "ModuleDisplayName", "Description", "DisplayOrder", "CreatedAt")
VALUES 
    ('11111111-1111-1111-1111-111111111020', 'Department', 'Phòng ban', 'Quản lý phòng ban', 20, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111021', 'Overtime', 'Tăng ca', 'Quản lý tăng ca', 21, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111022', 'AttendanceCorrection', 'Điều chỉnh CC', 'Quản lý điều chỉnh chấm công', 22, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111023', 'WorkSchedule', 'Lịch làm việc', 'Quản lý lịch làm việc', 23, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111024', 'ShiftSwap', 'Đổi ca', 'Quản lý đổi ca', 24, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111025', 'ShiftTemplate', 'Mẫu ca', 'Quản lý mẫu ca làm việc', 25, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111026', 'ShiftSalaryLevel', 'Bậc lương ca', 'Quản lý bậc lương theo ca', 26, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111027', 'Benefit', 'Phúc lợi', 'Quản lý phúc lợi', 27, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111028', 'Transaction', 'Giao dịch', 'Quản lý giao dịch', 28, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111029', 'CashTransaction', 'Thu chi tiền mặt', 'Quản lý thu chi tiền mặt', 29, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111030', 'BankAccount', 'Tài khoản NH', 'Quản lý tài khoản ngân hàng', 30, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111031', 'HrDocument', 'Hồ sơ nhân sự', 'Quản lý hồ sơ nhân sự', 31, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111032', 'Task', 'Công việc', 'Quản lý công việc', 32, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111033', 'KPI', 'Đánh giá KPI', 'Quản lý KPI', 33, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111034', 'Asset', 'Tài sản', 'Quản lý tài sản', 34, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111035', 'Geofence', 'Vùng địa lý', 'Quản lý vùng địa lý', 35, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111036', 'OrgChart', 'Sơ đồ tổ chức', 'Quản lý sơ đồ tổ chức', 36, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111037', 'Branch', 'Chi nhánh', 'Quản lý chi nhánh', 37, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111038', 'Communication', 'Truyền thông', 'Quản lý truyền thông nội bộ', 38, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111039', 'DeviceUser', 'User máy CC', 'Quản lý user trên máy chấm công', 39, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111040', 'UserManagement', 'Quản lý user', 'Quản lý tài khoản hệ thống', 40, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111041', 'DepartmentPermission', 'PQ Phòng ban', 'Phân quyền theo phòng ban', 41, CURRENT_TIMESTAMP)
ON CONFLICT ("Id") DO NOTHING;
