-- Update Permissions table to match 42 modules (aligned with menu structure)
-- This script uses UPSERT (INSERT ... ON CONFLICT) to add new modules
-- and update existing ones to match the current menu structure.

-- First, update existing modules with new DisplayOrder and DisplayName
-- Then insert new modules that don't exist yet

INSERT INTO "Permissions" ("Id", "Module", "ModuleDisplayName", "Description", "DisplayOrder", "CreatedAt")
VALUES 
    -- ══════════ TỔNG QUAN ══════════
    ('11111111-1111-1111-1111-111111111001', 'Home', 'Trang chủ', 'Màn hình tổng quan menu', 1, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111002', 'Notification', 'Thông báo', 'Hệ thống thông báo', 2, CURRENT_TIMESTAMP),

    -- ══════════ HỒ SƠ NHÂN SỰ ══════════
    ('11111111-1111-1111-1111-111111111003', 'Dashboard', 'Bảng điều khiển', 'Bảng điều khiển tổng quan', 3, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111004', 'Employee', 'Hồ sơ nhân sự', 'Thông tin nhân viên, chức vụ', 4, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111005', 'DeviceUser', 'Nhân sự chấm công', 'Nhân sự trên máy chấm công', 5, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111006', 'Department', 'Phòng ban', 'Quản lý phòng ban', 6, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111007', 'Leave', 'Nghỉ phép', 'Quản lý nghỉ phép', 7, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111008', 'SalarySettings', 'Thiết lập lương', 'Cấu hình bảng lương', 8, CURRENT_TIMESTAMP),

    -- ══════════ CHẤM CÔNG ══════════
    ('11111111-1111-1111-1111-111111111009', 'Attendance', 'Chấm công', 'Dữ liệu chấm công', 9, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111010', 'WorkSchedule', 'Lịch làm việc', 'Phân lịch làm việc', 10, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111011', 'AttendanceSummary', 'Tổng hợp chấm công', 'Bảng tổng hợp chấm công', 11, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111012', 'AttendanceByShift', 'Tổng hợp theo ca', 'Chấm công theo ca làm việc', 12, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111013', 'AttendanceApproval', 'Duyệt chấm công', 'Duyệt điều chỉnh chấm công', 13, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111014', 'ScheduleApproval', 'Duyệt lịch làm việc', 'Duyệt lịch làm việc đăng ký', 14, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111015', 'Payroll', 'Tổng hợp lương', 'Bảng lương nhân viên', 15, CURRENT_TIMESTAMP),

    -- ══════════ TÀI CHÍNH ══════════
    ('11111111-1111-1111-1111-111111111016', 'BonusPenalty', 'Thưởng / Phạt', 'Quản lý thưởng phạt', 16, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111027', 'PenaltyTickets', 'Phiếu phạt', 'Phiếu phạt tự động từ chấm công', 27, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111017', 'AdvanceRequests', 'Ứng lương', 'Quản lý ứng lương', 17, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111018', 'CashTransaction', 'Thu chi', 'Quản lý thu chi', 18, CURRENT_TIMESTAMP),

    -- ══════════ QUẢN LÝ VẬN HÀNH ══════════
    ('11111111-1111-1111-1111-111111111019', 'Asset', 'Tài sản', 'Quản lý tài sản', 19, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111020', 'Task', 'Công việc', 'Quản lý công việc', 20, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111021', 'Communication', 'Truyền thông', 'Truyền thông nội bộ', 21, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111022', 'KPI', 'KPI', 'Đánh giá KPI', 22, CURRENT_TIMESTAMP),

    -- ══════════ BÁO CÁO ══════════
    ('11111111-1111-1111-1111-111111111023', 'HrReport', 'Báo cáo nhân sự', 'Thống kê nhân sự, phòng ban', 23, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111024', 'AttendanceReport', 'Báo cáo chấm công', 'Ngày, tháng, đi muộn, phòng ban', 24, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111025', 'PayrollReport', 'Báo cáo lương', 'Chi phí lương, phân bổ', 25, CURRENT_TIMESTAMP),

    -- ══════════ CÀI ĐẶT ══════════
    ('11111111-1111-1111-1111-111111111026', 'SettingsHub', 'Thiết lập HRM', 'Trung tâm cài đặt HRM', 26, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111027', 'ShiftSetup', 'Thiết lập ca', 'Ca làm việc, vào sớm, đi trễ, về sớm, tăng ca', 27, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111028', 'MobileAttendance', 'Chấm công mobile', 'Face ID, GPS, vùng chấm công', 28, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111029', 'Holiday', 'Ngày lễ', 'Ngày nghỉ lễ, hệ số công', 29, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111030', 'Device', 'Máy chấm công', 'Kết nối, quản lý, điều khiển máy chấm công', 30, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111031', 'Allowance', 'Phụ cấp', 'Phụ cấp cố định, phụ cấp ngày công', 31, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111032', 'PenaltySetup', 'Phạt', 'Đi trễ, về sớm, tái phạm, kỷ luật', 32, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111033', 'Insurance', 'Bảo hiểm', 'BHXH, BHYT, BHTN, lương cơ sở', 33, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111034', 'Tax', 'Thuế TNCN', 'Bậc thuế, giảm trừ gia cảnh', 34, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111035', 'UserManagement', 'Tài khoản', 'Người dùng, kích hoạt, vai trò', 35, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111036', 'Role', 'Phân quyền', 'Ma trận quyền, vai trò, module', 36, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111037', 'DepartmentPermission', 'PQ Phòng ban', 'Phân quyền theo sơ đồ cây phòng ban', 37, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111038', 'SystemSettings', 'Hệ thống', 'Giờ kết thúc ngày, tham số vận hành', 38, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111039', 'NotificationSettings', 'Thiết lập thông báo', 'Nhóm thông báo, bật/tắt nhận thông báo', 39, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111040', 'GoogleDrive', 'Google Drive', 'Lưu trữ ảnh, service account', 40, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111041', 'AIGemini', 'AI Gemini', 'API key, model, tham số AI', 41, CURRENT_TIMESTAMP),
    ('11111111-1111-1111-1111-111111111042', 'Settings', 'Cài đặt chung', 'Cài đặt hệ thống', 42, CURRENT_TIMESTAMP)
ON CONFLICT ("Id") DO UPDATE SET
    "Module" = EXCLUDED."Module",
    "ModuleDisplayName" = EXCLUDED."ModuleDisplayName",
    "Description" = EXCLUDED."Description",
    "DisplayOrder" = EXCLUDED."DisplayOrder";

-- Also handle conflict on Module name (in case old modules exist with different IDs)
-- Delete old modules that are no longer in the menu structure
DELETE FROM "Permissions" 
WHERE "Module" IN (
    'Salary', 'Payslip', 'Account', 'Store', 'Advance', 
    'Overtime', 'AttendanceCorrection', 'ShiftSwap', 'ShiftTemplate', 
    'ShiftSalaryLevel', 'Benefit', 'Transaction', 'BankAccount', 
    'HrDocument', 'Geofence', 'OrgChart', 'Branch', 'Shift', 'Report'
)
AND "Module" NOT IN (
    'Home', 'Notification', 'Dashboard', 'Employee', 'DeviceUser', 'Department', 'Leave', 'SalarySettings',
    'Attendance', 'WorkSchedule', 'AttendanceSummary', 'AttendanceByShift', 'AttendanceApproval', 'ScheduleApproval', 'Payroll',
    'BonusPenalty', 'PenaltyTickets', 'AdvanceRequests', 'CashTransaction',
    'Asset', 'Task', 'Communication', 'KPI',
    'HrReport', 'AttendanceReport', 'PayrollReport',
    'SettingsHub', 'ShiftSetup', 'MobileAttendance', 'Holiday', 'Device', 'Allowance', 'PenaltySetup', 'Insurance', 'Tax',
    'UserManagement', 'Role', 'DepartmentPermission', 'SystemSettings', 'NotificationSettings', 'GoogleDrive', 'AIGemini', 'Settings'
);

-- Clean up orphaned RolePermissions that reference deleted Permissions
-- (This will be handled automatically by FK CASCADE if configured,
-- but just in case, remove any that reference non-existent Permission IDs)
DELETE FROM "RolePermissions" 
WHERE "PermissionId" NOT IN (SELECT "Id" FROM "Permissions");
