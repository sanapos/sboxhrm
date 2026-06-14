using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PermissionConfiguration : IEntityTypeConfiguration<Permission>
{
    public void Configure(EntityTypeBuilder<Permission> builder)
    {
        builder.HasKey(e => e.Id);
        
        builder.Property(e => e.Module)
            .IsRequired()
            .HasMaxLength(50);
        
        builder.Property(e => e.ModuleDisplayName)
            .IsRequired()
            .HasMaxLength(100);
        
        builder.Property(e => e.Description)
            .HasMaxLength(255);
        
        // Index unique cho Module
        builder.HasIndex(e => e.Module)
            .IsUnique();
        
        // Seed data cho các module mặc định
        builder.HasData(
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111001"), Module = "Dashboard", ModuleDisplayName = "Tổng quan", Description = "Xem tổng quan hệ thống", DisplayOrder = 1 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111002"), Module = "Employee", ModuleDisplayName = "Hồ sơ nhân sự", Description = "Thông tin nhân viên, chức vụ", DisplayOrder = 2 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111003"), Module = "Attendance", ModuleDisplayName = "Chấm công thô", Description = "Dữ liệu chấm công thô", DisplayOrder = 3 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111004"), Module = "Leave", ModuleDisplayName = "Nghỉ phép", Description = "Quản lý đơn nghỉ phép", DisplayOrder = 4 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111005"), Module = "Shift", ModuleDisplayName = "Ca làm việc", Description = "Quản lý ca làm việc", DisplayOrder = 5 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111006"), Module = "Salary", ModuleDisplayName = "Lương", Description = "Quản lý bảng lương", DisplayOrder = 6 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111007"), Module = "Payslip", ModuleDisplayName = "Phiếu lương", Description = "Quản lý phiếu lương", DisplayOrder = 7 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111008"), Module = "Device", ModuleDisplayName = "Máy chấm công", Description = "Kết nối, quản lý, điều khiển máy chấm công", DisplayOrder = 8 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111009"), Module = "Report", ModuleDisplayName = "Báo cáo", Description = "Xem và xuất báo cáo", DisplayOrder = 9 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111010"), Module = "Settings", ModuleDisplayName = "Cài đặt", Description = "Giao diện, ngôn ngữ, kết nối", DisplayOrder = 10 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111011"), Module = "Account", ModuleDisplayName = "Tài khoản", Description = "Quản lý tài khoản người dùng", DisplayOrder = 11 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111012"), Module = "Role", ModuleDisplayName = "Phân quyền", Description = "Quản lý phân quyền", DisplayOrder = 12 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111013"), Module = "Store", ModuleDisplayName = "Cửa hàng", Description = "Quản lý cửa hàng", DisplayOrder = 13 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111014"), Module = "Allowance", ModuleDisplayName = "Phụ cấp", Description = "Quản lý phụ cấp", DisplayOrder = 14 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111015"), Module = "Holiday", ModuleDisplayName = "Ngày lễ", Description = "Quản lý ngày lễ", DisplayOrder = 15 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111016"), Module = "Insurance", ModuleDisplayName = "Bảo hiểm", Description = "Quản lý bảo hiểm", DisplayOrder = 16 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111017"), Module = "Tax", ModuleDisplayName = "Thuế TNCN", Description = "Quản lý thuế thu nhập", DisplayOrder = 17 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111018"), Module = "Advance", ModuleDisplayName = "Tạm ứng", Description = "Quản lý tạm ứng lương", DisplayOrder = 18 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111019"), Module = "Notification", ModuleDisplayName = "Thông báo", Description = "Quản lý thông báo", DisplayOrder = 19 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111020"), Module = "Department", ModuleDisplayName = "Phòng ban", Description = "Quản lý phòng ban", DisplayOrder = 20 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111021"), Module = "Overtime", ModuleDisplayName = "Tăng ca", Description = "Quản lý tăng ca", DisplayOrder = 21 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111022"), Module = "AttendanceCorrection", ModuleDisplayName = "Chỉnh sửa chấm công", Description = "Yêu cầu chỉnh sửa log chấm công", DisplayOrder = 22 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111023"), Module = "WorkSchedule", ModuleDisplayName = "Lịch làm việc", Description = "Quản lý lịch làm việc", DisplayOrder = 23 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111024"), Module = "ShiftSwap", ModuleDisplayName = "Đổi ca", Description = "Quản lý đổi ca", DisplayOrder = 24 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111025"), Module = "ShiftTemplate", ModuleDisplayName = "Mẫu ca", Description = "Quản lý mẫu ca làm việc", DisplayOrder = 25 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111026"), Module = "ShiftSalaryLevel", ModuleDisplayName = "Bậc lương ca", Description = "Quản lý bậc lương theo ca", DisplayOrder = 26 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111027"), Module = "Benefit", ModuleDisplayName = "Phúc lợi", Description = "Quản lý phúc lợi", DisplayOrder = 27 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111028"), Module = "Transaction", ModuleDisplayName = "Giao dịch", Description = "Quản lý giao dịch", DisplayOrder = 28 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111029"), Module = "CashTransaction", ModuleDisplayName = "Thu chi", Description = "Sổ thu chi, quỹ tiền mặt", DisplayOrder = 29 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111030"), Module = "BankAccount", ModuleDisplayName = "Tài khoản ngân hàng", Description = "Tài khoản ngân hàng thu chi", DisplayOrder = 30 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111031"), Module = "HrDocument", ModuleDisplayName = "Tài liệu HR", Description = "Quản lý tài liệu nhân sự", DisplayOrder = 31 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111032"), Module = "Task", ModuleDisplayName = "Công việc", Description = "Quản lý công việc", DisplayOrder = 32 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111033"), Module = "KPI", ModuleDisplayName = "Đánh giá KPI", Description = "Quản lý KPI", DisplayOrder = 33 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111034"), Module = "Asset", ModuleDisplayName = "Tài sản", Description = "Quản lý tài sản", DisplayOrder = 34 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111035"), Module = "Geofence", ModuleDisplayName = "Vùng chấm công", Description = "Geofence chấm công mobile", DisplayOrder = 35 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111036"), Module = "OrgChart", ModuleDisplayName = "Sơ đồ tổ chức", Description = "Quản lý sơ đồ tổ chức", DisplayOrder = 36 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111037"), Module = "Branch", ModuleDisplayName = "Chi nhánh", Description = "Quản lý chi nhánh", DisplayOrder = 37 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111038"), Module = "Communication", ModuleDisplayName = "Truyền thông", Description = "Quản lý truyền thông nội bộ", DisplayOrder = 38 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111039"), Module = "DeviceUser", ModuleDisplayName = "Nhân sự chấm công", Description = "Nhân sự trên máy chấm công", DisplayOrder = 39 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111040"), Module = "UserManagement", ModuleDisplayName = "Tài khoản", Description = "Người dùng, kích hoạt, vai trò", DisplayOrder = 40 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111041"), Module = "DepartmentPermission", ModuleDisplayName = "PQ Phòng ban", Description = "Phân quyền theo phòng ban", DisplayOrder = 41 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111042"), Module = "FieldCheckIn", ModuleDisplayName = "Bản đồ nhân sự", Description = "Vị trí trực tuyến NV chấm ngoài CT trên bản đồ", DisplayOrder = 42 },
            // ══════════ MODULES BỔ SUNG (đồng bộ DbInitializer) ══════════
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111043"), Module = "Home", ModuleDisplayName = "Trang chủ", Description = "Màn hình tổng quan menu", DisplayOrder = 1 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111044"), Module = "SalarySettings", ModuleDisplayName = "Thiết lập lương", Description = "Cấu hình bảng lương", DisplayOrder = 8 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111045"), Module = "AttendanceSummary", ModuleDisplayName = "Tổng hợp chấm công", Description = "Bảng tổng hợp công theo tháng", DisplayOrder = 11 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111046"), Module = "AttendanceByShift", ModuleDisplayName = "Tổng hợp chấm công theo ca", Description = "Thống kê giờ công theo ca làm", DisplayOrder = 12 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111047"), Module = "AttendanceApproval", ModuleDisplayName = "Duyệt chấm công", Description = "Duyệt điều chỉnh chấm công", DisplayOrder = 13 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111048"), Module = "ScheduleApproval", ModuleDisplayName = "Duyệt lịch làm việc", Description = "Duyệt lịch làm việc đăng ký", DisplayOrder = 14 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111049"), Module = "Payroll", ModuleDisplayName = "Tổng hợp lương", Description = "Bảng lương nhân viên", DisplayOrder = 15 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111050"), Module = "BonusPenalty", ModuleDisplayName = "Phiếu thưởng", Description = "Quản lý phiếu thưởng nhân viên", DisplayOrder = 16 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111051"), Module = "PenaltyTickets", ModuleDisplayName = "Phiếu phạt", Description = "Phiếu phạt tự động từ chấm công", DisplayOrder = 27 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111052"), Module = "AdvanceRequests", ModuleDisplayName = "Ứng lương", Description = "Quản lý ứng lương", DisplayOrder = 17 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111053"), Module = "Production", ModuleDisplayName = "Sản lượng", Description = "Nhập sản lượng, tính lương sản phẩm", DisplayOrder = 43 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111054"), Module = "MobileDeviceRegistration", ModuleDisplayName = "Đăng ký chấm công Mobile", Description = "Đăng ký thiết bị & khuôn mặt", DisplayOrder = 46 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111055"), Module = "MobileAttendanceApproval", ModuleDisplayName = "Duyệt chấm công Mobile", Description = "Duyệt yêu cầu chấm công mobile", DisplayOrder = 47 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111056"), Module = "Meal", ModuleDisplayName = "Chấm cơm", Description = "Quản lý suất ăn ca", DisplayOrder = 48 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111058"), Module = "AttendanceReport", ModuleDisplayName = "Báo cáo chấm công", Description = "Ngày, tháng, đi muộn, phòng ban", DisplayOrder = 24 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111060"), Module = "SettingsHub", ModuleDisplayName = "Thiết lập HRM", Description = "Trung tâm cài đặt HRM", DisplayOrder = 26 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111061"), Module = "ShiftSetup", ModuleDisplayName = "Thiết lập ca", Description = "Ca làm việc, vào sớm, đi trễ, về sớm, tăng ca", DisplayOrder = 27 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111062"), Module = "MobileAttendance", ModuleDisplayName = "Chấm công Mobile", Description = "Chấm công bằng điện thoại", DisplayOrder = 28 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111063"), Module = "PenaltySetup", ModuleDisplayName = "Phạt", Description = "Đi trễ, về sớm, tái phạm, kỷ luật", DisplayOrder = 32 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111064"), Module = "SystemSettings", ModuleDisplayName = "Hệ thống", Description = "Giờ kết thúc ngày, tham số vận hành", DisplayOrder = 38 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111065"), Module = "NotificationSettings", ModuleDisplayName = "Thiết lập thông báo", Description = "Nhóm thông báo, bật/tắt nhận thông báo", DisplayOrder = 39 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111066"), Module = "GoogleDrive", ModuleDisplayName = "Google Drive", Description = "Lưu trữ ảnh, service account", DisplayOrder = 40 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111067"), Module = "AIGemini", ModuleDisplayName = "Thiết lập AI", Description = "API key, model, tham số AI", DisplayOrder = 41 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111068"), Module = "ProductSalary", ModuleDisplayName = "Lương sản phẩm", Description = "Nhóm sản phẩm, sản phẩm, đơn giá theo bậc", DisplayOrder = 44 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111069"), Module = "Feedback", ModuleDisplayName = "Phản ánh / Ý kiến", Description = "Phản ánh, góp ý ẩn danh hoặc công khai", DisplayOrder = 45 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111070"), Module = "PenaltyReport", ModuleDisplayName = "Báo cáo phạt", Description = "Thống kê phiếu phạt, kỷ luật", DisplayOrder = 50 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111071"), Module = "AdvanceReport", ModuleDisplayName = "Báo cáo ứng lương", Description = "Thống kê ứng lương, tạm ứng", DisplayOrder = 51 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111072"), Module = "LeaveReport", ModuleDisplayName = "Báo cáo nghỉ phép", Description = "Thống kê nghỉ phép, ngày nghỉ", DisplayOrder = 52 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111073"), Module = "CashReport", ModuleDisplayName = "Báo cáo thu chi", Description = "Thống kê thu chi tiền mặt", DisplayOrder = 53 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111074"), Module = "AssetReport", ModuleDisplayName = "Báo cáo tài sản", Description = "Danh mục, cấp phát, lịch sử chuyển giao", DisplayOrder = 55 },
            // Widgets on Dashboard (granular permissions)
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111075"), Module = "DashboardAttendanceOverview", ModuleDisplayName = "Tổng quan chấm công", Description = "KPI chấm công, donut, lọc ngày trên Dashboard", DisplayOrder = 4 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111076"), Module = "DashboardHrInsights", ModuleDisplayName = "Chỉ số nhân sự & vận hành", Description = "Các chip chỉ số HR trên Dashboard", DisplayOrder = 5 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111077"), Module = "DashboardTodaySchedule", ModuleDisplayName = "Lịch làm việc hôm nay", Description = "Khối lịch ca hôm nay trên Dashboard", DisplayOrder = 6 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111078"), Module = "DashboardRealtimeAttendance", ModuleDisplayName = "Chấm công thời gian thực", Description = "Danh sách chấm công realtime", DisplayOrder = 7 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111079"), Module = "DashboardAbsent", ModuleDisplayName = "Nhân viên vắng mặt", Description = "Khối vắng mặt trên Dashboard", DisplayOrder = 8 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111080"), Module = "DashboardLateEarly", ModuleDisplayName = "Đi trễ / về sớm", Description = "Khối trễ sớm theo ca trên Dashboard", DisplayOrder = 9 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111081"), Module = "DashboardKpiPanel", ModuleDisplayName = "KPI (Dashboard)", Description = "Khối KPI trên Dashboard", DisplayOrder = 10 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111082"), Module = "DashboardInternalNews", ModuleDisplayName = "Bản tin nội bộ", Description = "Tin truyền thông trên Dashboard", DisplayOrder = 11 }
        );
    }
}
