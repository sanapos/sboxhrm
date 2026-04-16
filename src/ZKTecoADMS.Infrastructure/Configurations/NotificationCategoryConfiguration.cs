using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class NotificationCategoryConfiguration : IEntityTypeConfiguration<NotificationCategory>
{
    public void Configure(EntityTypeBuilder<NotificationCategory> builder)
    {
        builder.HasKey(e => e.Id);

        builder.Property(e => e.Code)
            .IsRequired()
            .HasMaxLength(50);

        builder.Property(e => e.DisplayName)
            .IsRequired()
            .HasMaxLength(100);

        builder.Property(e => e.Description)
            .HasMaxLength(255);

        builder.Property(e => e.Icon)
            .HasMaxLength(50);

        builder.HasIndex(e => e.Code)
            .IsUnique()
            .HasDatabaseName("IX_NotificationCategories_Code");

        builder.HasIndex(e => e.StoreId)
            .HasDatabaseName("IX_NotificationCategories_StoreId");

        // Seed data
        builder.HasData(
            new NotificationCategory
            {
                Id = Guid.Parse("a0000001-0000-0000-0000-000000000001"),
                Code = "attendance",
                DisplayName = "Chấm công",
                Description = "Thông báo chấm công vào/ra, trễ giờ, vắng mặt",
                Icon = "fingerprint",
                DisplayOrder = 1,
                IsSystem = true,
                DefaultEnabled = true
            },
            new NotificationCategory
            {
                Id = Guid.Parse("a0000001-0000-0000-0000-000000000002"),
                Code = "leave",
                DisplayName = "Nghỉ phép",
                Description = "Đơn nghỉ phép, duyệt/từ chối phép",
                Icon = "event_busy",
                DisplayOrder = 2,
                IsSystem = true,
                DefaultEnabled = true
            },
            new NotificationCategory
            {
                Id = Guid.Parse("a0000001-0000-0000-0000-000000000003"),
                Code = "overtime",
                DisplayName = "Tăng ca",
                Description = "Đăng ký tăng ca, duyệt/từ chối tăng ca",
                Icon = "more_time",
                DisplayOrder = 3,
                IsSystem = true,
                DefaultEnabled = true
            },
            new NotificationCategory
            {
                Id = Guid.Parse("a0000001-0000-0000-0000-000000000004"),
                Code = "payroll",
                DisplayName = "Lương & Phiếu lương",
                Description = "Phiếu lương, thay đổi lương, thanh toán",
                Icon = "payments",
                DisplayOrder = 4,
                IsSystem = true,
                DefaultEnabled = true
            },
            new NotificationCategory
            {
                Id = Guid.Parse("a0000001-0000-0000-0000-000000000005"),
                Code = "task",
                DisplayName = "Công việc",
                Description = "Giao việc, cập nhật tiến độ, deadline",
                Icon = "task_alt",
                DisplayOrder = 5,
                IsSystem = true,
                DefaultEnabled = true
            },
            new NotificationCategory
            {
                Id = Guid.Parse("a0000001-0000-0000-0000-000000000006"),
                Code = "approval",
                DisplayName = "Phê duyệt",
                Description = "Yêu cầu phê duyệt, kết quả phê duyệt",
                Icon = "approval",
                DisplayOrder = 6,
                IsSystem = true,
                DefaultEnabled = true
            },
            new NotificationCategory
            {
                Id = Guid.Parse("a0000001-0000-0000-0000-000000000007"),
                Code = "device",
                DisplayName = "Thiết bị",
                Description = "Trạng thái máy chấm công online/offline",
                Icon = "router",
                DisplayOrder = 7,
                IsSystem = true,
                DefaultEnabled = true
            },
            new NotificationCategory
            {
                Id = Guid.Parse("a0000001-0000-0000-0000-000000000008"),
                Code = "hr",
                DisplayName = "Nhân sự",
                Description = "Hợp đồng, bổ nhiệm, thuyên chuyển",
                Icon = "people",
                DisplayOrder = 8,
                IsSystem = true,
                DefaultEnabled = true
            },
            new NotificationCategory
            {
                Id = Guid.Parse("a0000001-0000-0000-0000-000000000009"),
                Code = "system",
                DisplayName = "Hệ thống",
                Description = "Cập nhật hệ thống, bảo trì, thông báo chung",
                Icon = "settings",
                DisplayOrder = 9,
                IsSystem = true,
                DefaultEnabled = true
            }
        );
    }
}
