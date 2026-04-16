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
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111002"), Module = "Employee", ModuleDisplayName = "Nhân viên", Description = "Quản lý thông tin nhân viên", DisplayOrder = 2 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111003"), Module = "Attendance", ModuleDisplayName = "Chấm công", Description = "Quản lý chấm công", DisplayOrder = 3 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111004"), Module = "Leave", ModuleDisplayName = "Nghỉ phép", Description = "Quản lý đơn nghỉ phép", DisplayOrder = 4 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111005"), Module = "Shift", ModuleDisplayName = "Ca làm việc", Description = "Quản lý ca làm việc", DisplayOrder = 5 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111006"), Module = "Salary", ModuleDisplayName = "Lương", Description = "Quản lý bảng lương", DisplayOrder = 6 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111007"), Module = "Payslip", ModuleDisplayName = "Phiếu lương", Description = "Quản lý phiếu lương", DisplayOrder = 7 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111008"), Module = "Device", ModuleDisplayName = "Thiết bị", Description = "Quản lý thiết bị chấm công", DisplayOrder = 8 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111009"), Module = "Report", ModuleDisplayName = "Báo cáo", Description = "Xem và xuất báo cáo", DisplayOrder = 9 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111010"), Module = "Settings", ModuleDisplayName = "Thiết lập", Description = "Cấu hình hệ thống", DisplayOrder = 10 },
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
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111022"), Module = "AttendanceCorrection", ModuleDisplayName = "Điều chỉnh CC", Description = "Quản lý điều chỉnh chấm công", DisplayOrder = 22 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111023"), Module = "WorkSchedule", ModuleDisplayName = "Lịch làm việc", Description = "Quản lý lịch làm việc", DisplayOrder = 23 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111024"), Module = "ShiftSwap", ModuleDisplayName = "Đổi ca", Description = "Quản lý đổi ca", DisplayOrder = 24 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111025"), Module = "ShiftTemplate", ModuleDisplayName = "Mẫu ca", Description = "Quản lý mẫu ca làm việc", DisplayOrder = 25 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111026"), Module = "ShiftSalaryLevel", ModuleDisplayName = "Bậc lương ca", Description = "Quản lý bậc lương theo ca", DisplayOrder = 26 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111027"), Module = "Benefit", ModuleDisplayName = "Phúc lợi", Description = "Quản lý phúc lợi", DisplayOrder = 27 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111028"), Module = "Transaction", ModuleDisplayName = "Giao dịch", Description = "Quản lý giao dịch", DisplayOrder = 28 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111029"), Module = "CashTransaction", ModuleDisplayName = "Thu chi tiền mặt", Description = "Quản lý thu chi tiền mặt", DisplayOrder = 29 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111030"), Module = "BankAccount", ModuleDisplayName = "Tài khoản NH", Description = "Quản lý tài khoản ngân hàng", DisplayOrder = 30 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111031"), Module = "HrDocument", ModuleDisplayName = "Hồ sơ nhân sự", Description = "Quản lý hồ sơ nhân sự", DisplayOrder = 31 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111032"), Module = "Task", ModuleDisplayName = "Công việc", Description = "Quản lý công việc", DisplayOrder = 32 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111033"), Module = "KPI", ModuleDisplayName = "Đánh giá KPI", Description = "Quản lý KPI", DisplayOrder = 33 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111034"), Module = "Asset", ModuleDisplayName = "Tài sản", Description = "Quản lý tài sản", DisplayOrder = 34 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111035"), Module = "Geofence", ModuleDisplayName = "Vùng địa lý", Description = "Quản lý vùng địa lý", DisplayOrder = 35 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111036"), Module = "OrgChart", ModuleDisplayName = "Sơ đồ tổ chức", Description = "Quản lý sơ đồ tổ chức", DisplayOrder = 36 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111037"), Module = "Branch", ModuleDisplayName = "Chi nhánh", Description = "Quản lý chi nhánh", DisplayOrder = 37 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111038"), Module = "Communication", ModuleDisplayName = "Truyền thông", Description = "Quản lý truyền thông nội bộ", DisplayOrder = 38 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111039"), Module = "DeviceUser", ModuleDisplayName = "User máy CC", Description = "Quản lý user trên máy chấm công", DisplayOrder = 39 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111040"), Module = "UserManagement", ModuleDisplayName = "Quản lý user", Description = "Quản lý tài khoản hệ thống", DisplayOrder = 40 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111041"), Module = "DepartmentPermission", ModuleDisplayName = "PQ Phòng ban", Description = "Phân quyền theo phòng ban", DisplayOrder = 41 },
            new Permission { Id = Guid.Parse("11111111-1111-1111-1111-111111111042"), Module = "FieldCheckIn", ModuleDisplayName = "Check-in điểm bán", Description = "Quản lý check-in điểm bán, giao điểm, báo cáo tại điểm", DisplayOrder = 42 }
        );
    }
}
