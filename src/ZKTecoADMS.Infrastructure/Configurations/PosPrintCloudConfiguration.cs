using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PosStorePrinterConfiguration : IEntityTypeConfiguration<PosStorePrinter>
{
    public void Configure(EntityTypeBuilder<PosStorePrinter> builder)
    {
        builder.ToTable("PosStorePrinters");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Name).IsRequired().HasMaxLength(120);
        builder.Property(x => x.PrinterBrand).HasMaxLength(32);
        builder.Property(x => x.PaperSize).HasMaxLength(16);
        builder.Property(x => x.TextMode).HasMaxLength(32);
        builder.Property(x => x.BluetoothAddress).HasMaxLength(64);
        builder.Property(x => x.BluetoothName).HasMaxLength(120);
        builder.Property(x => x.LanHost).HasMaxLength(64);
        builder.Property(x => x.UsbDeviceName).HasMaxLength(120);
        builder.Property(x => x.LastErrorMessage).HasMaxLength(500);
        builder.HasIndex(x => new { x.StoreId, x.IsDefault });
        builder.HasIndex(x => new { x.StoreId, x.Name });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosPrinterDocumentRouteConfiguration : IEntityTypeConfiguration<PosPrinterDocumentRoute>
{
    public void Configure(EntityTypeBuilder<PosPrinterDocumentRoute> builder)
    {
        builder.ToTable("PosPrinterDocumentRoutes");
        builder.HasKey(x => x.Id);
        builder.HasIndex(x => new { x.StoreId, x.DocumentType, x.PrinterId }).IsUnique();
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Printer).WithMany(p => p.DocumentRoutes).HasForeignKey(x => x.PrinterId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosPrintAgentConfiguration : IEntityTypeConfiguration<PosPrintAgent>
{
    public void Configure(EntityTypeBuilder<PosPrintAgent> builder)
    {
        builder.ToTable("PosPrintAgents");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.DeviceId).IsRequired().HasMaxLength(128);
        builder.Property(x => x.DeviceName).HasMaxLength(200);
        builder.Property(x => x.EmployeeName).HasMaxLength(200);
        builder.Property(x => x.UserId).HasMaxLength(450);
        builder.Property(x => x.AppVersion).HasMaxLength(32);
        builder.HasIndex(x => new { x.StoreId, x.DeviceId }).IsUnique();
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosPrintJobConfiguration : IEntityTypeConfiguration<PosPrintJob>
{
    public void Configure(EntityTypeBuilder<PosPrintJob> builder)
    {
        builder.ToTable("PosPrintJobs");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.ReferenceNo).HasMaxLength(64);
        builder.Property(x => x.RequestedByUserId).HasMaxLength(450);
        builder.Property(x => x.RequestedByName).HasMaxLength(200);
        builder.Property(x => x.ErrorCode).HasMaxLength(64);
        builder.Property(x => x.ErrorMessage).HasMaxLength(500);
        builder.HasIndex(x => new { x.StoreId, x.Status, x.CreatedAt });
        builder.HasIndex(x => new { x.PrinterId, x.Status });
        // Vòng claim của Agent lọc StoreId + Status + PrinterId + ExpiresAt và
        // chạy 3s/lần trên mọi thiết bị. Thiếu PrinterId trong index thì mỗi lượt
        // phải quét toàn bộ job Queued của cửa hàng.
        builder.HasIndex(x => new { x.StoreId, x.Status, x.PrinterId, x.ExpiresAt });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Printer).WithMany().HasForeignKey(x => x.PrinterId).OnDelete(DeleteBehavior.Restrict);
        builder.HasOne(x => x.Agent).WithMany().HasForeignKey(x => x.AgentId).OnDelete(DeleteBehavior.SetNull);
    }
}
