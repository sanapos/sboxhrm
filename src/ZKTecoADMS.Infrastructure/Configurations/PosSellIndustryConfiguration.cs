using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PosStoreSellSettingsConfiguration : IEntityTypeConfiguration<PosStoreSellSettings>
{
    public void Configure(EntityTypeBuilder<PosStoreSellSettings> builder)
    {
        builder.ToTable("PosStoreSellSettings");
        builder.HasKey(x => x.Id);
        builder.HasIndex(x => x.StoreId).IsUnique();
        builder.Property(x => x.DefaultSellMode).HasMaxLength(20);
        builder.Property(x => x.ExtraJson).HasMaxLength(4000);
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosServiceAreaConfiguration : IEntityTypeConfiguration<PosServiceArea>
{
    public void Configure(EntityTypeBuilder<PosServiceArea> builder)
    {
        builder.ToTable("PosServiceAreas");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Name).HasMaxLength(100).IsRequired();
        builder.Property(x => x.Code).HasMaxLength(50);
        builder.Property(x => x.AreaType).HasMaxLength(50);
        builder.HasIndex(x => new { x.StoreId, x.Name });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosServiceAreaAssignmentConfiguration : IEntityTypeConfiguration<PosServiceAreaAssignment>
{
    public void Configure(EntityTypeBuilder<PosServiceAreaAssignment> builder)
    {
        builder.ToTable("PosServiceAreaAssignments");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.GrantedBy).HasMaxLength(100);
        builder.Property(x => x.Note).HasMaxLength(500);
        builder.HasIndex(x => new { x.StoreId, x.UserId, x.AreaId }).IsUnique();
        builder.HasIndex(x => new { x.StoreId, x.UserId });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.User).WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Area).WithMany().HasForeignKey(x => x.AreaId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosServiceResourceConfiguration : IEntityTypeConfiguration<PosServiceResource>
{
    public void Configure(EntityTypeBuilder<PosServiceResource> builder)
    {
        builder.ToTable("PosServiceResources");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Code).HasMaxLength(50).IsRequired();
        builder.Property(x => x.Name).HasMaxLength(100).IsRequired();
        builder.Property(x => x.DefaultHourlyRate).HasPrecision(18, 2);
        builder.HasIndex(x => new { x.StoreId, x.Code }).IsUnique();
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Area).WithMany(a => a.Resources).HasForeignKey(x => x.AreaId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosResourceSessionConfiguration : IEntityTypeConfiguration<PosResourceSession>
{
    public void Configure(EntityTypeBuilder<PosResourceSession> builder)
    {
        builder.ToTable("PosResourceSessions");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Note).HasMaxLength(500);
        builder.HasIndex(x => new { x.StoreId, x.ResourceId, x.Status });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Resource).WithMany(r => r.Sessions).HasForeignKey(x => x.ResourceId)
            .OnDelete(DeleteBehavior.Restrict);
        builder.HasOne(x => x.SaleOrder).WithMany().HasForeignKey(x => x.SaleOrderId)
            .OnDelete(DeleteBehavior.SetNull);
        builder.HasOne(x => x.Customer).WithMany().HasForeignKey(x => x.CustomerId)
            .OnDelete(DeleteBehavior.SetNull);
    }
}

public class PosResourceReservationConfiguration : IEntityTypeConfiguration<PosResourceReservation>
{
    public void Configure(EntityTypeBuilder<PosResourceReservation> builder)
    {
        builder.ToTable("PosResourceReservations");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.CustomerName).HasMaxLength(200);
        builder.Property(x => x.Phone).HasMaxLength(30);
        builder.Property(x => x.Note).HasMaxLength(500);
        builder.Property(x => x.Occasion).HasMaxLength(40);
        builder.Property(x => x.SpecialRequest).HasMaxLength(500);
        builder.Property(x => x.PreOrderJson).HasColumnType("text");
        builder.Property(x => x.DepositAmount).HasPrecision(18, 2);
        builder.Property(x => x.DepositPaid).HasPrecision(18, 2);
        builder.Property(x => x.DepositPaymentMethod).HasMaxLength(50);
        builder.HasIndex(x => new { x.StoreId, x.ResourceId, x.Status });
        builder.HasIndex(x => new { x.StoreId, x.Status, x.ReservedUntil });
        builder.HasIndex(x => new { x.StoreId, x.AssignedEmployeeId, x.Status, x.ReservedAt });
        builder.HasOne(x => x.ServiceProduct).WithMany().HasForeignKey(x => x.ServiceProductId)
            .OnDelete(DeleteBehavior.SetNull);
        builder.HasOne(x => x.AssignedEmployee).WithMany().HasForeignKey(x => x.AssignedEmployeeId)
            .OnDelete(DeleteBehavior.SetNull);
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Resource).WithMany().HasForeignKey(x => x.ResourceId)
            .OnDelete(DeleteBehavior.Restrict);
        builder.HasOne(x => x.Customer).WithMany().HasForeignKey(x => x.CustomerId)
            .OnDelete(DeleteBehavior.SetNull);
    }
}

public class PosCustomerSessionBalanceConfiguration : IEntityTypeConfiguration<PosCustomerSessionBalance>
{
    public void Configure(EntityTypeBuilder<PosCustomerSessionBalance> builder)
    {
        builder.ToTable("PosCustomerSessionBalances");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.PackageName).HasMaxLength(200);
        builder.HasIndex(x => new { x.StoreId, x.CustomerId });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Customer).WithMany().HasForeignKey(x => x.CustomerId)
            .OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Product).WithMany().HasForeignKey(x => x.ProductId)
            .OnDelete(DeleteBehavior.SetNull);
    }
}

public class PosCustomerSessionTransactionConfiguration : IEntityTypeConfiguration<PosCustomerSessionTransaction>
{
    public void Configure(EntityTypeBuilder<PosCustomerSessionTransaction> builder)
    {
        builder.ToTable("PosCustomerSessionTransactions");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Note).HasMaxLength(500);
        builder.HasIndex(x => new { x.StoreId, x.BalanceId });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Balance).WithMany(b => b.Transactions).HasForeignKey(x => x.BalanceId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosKitchenVoidSlipConfiguration : IEntityTypeConfiguration<PosKitchenVoidSlip>
{
    public void Configure(EntityTypeBuilder<PosKitchenVoidSlip> builder)
    {
        builder.ToTable("PosKitchenVoidSlips");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.ProductName).HasMaxLength(200).IsRequired();
        builder.Property(x => x.OrderNo).HasMaxLength(40);
        builder.Property(x => x.ResourceName).HasMaxLength(120);
        builder.Property(x => x.UnitName).HasMaxLength(40);
        builder.Property(x => x.LineNote).HasMaxLength(300);
        builder.Property(x => x.Reason).HasMaxLength(80);
        builder.Property(x => x.DetailNote).HasMaxLength(500);
        builder.Property(x => x.VoidedBy).HasMaxLength(200);
        builder.Property(x => x.DeviceName).HasMaxLength(120);
        builder.Property(x => x.Qty).HasPrecision(18, 3);
        builder.HasIndex(x => new { x.StoreId, x.VoidedAt });
        builder.HasIndex(x => new { x.StoreId, x.AfterBillRequested, x.VoidedAt });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosCancelReturnAuditConfiguration : IEntityTypeConfiguration<PosCancelReturnAudit>
{
    public void Configure(EntityTypeBuilder<PosCancelReturnAudit> builder)
    {
        builder.ToTable("PosCancelReturnAudits");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.ActionType).HasMaxLength(40).IsRequired();
        builder.Property(x => x.Reason).HasMaxLength(80);
        builder.Property(x => x.DetailNote).HasMaxLength(500);
        builder.Property(x => x.OrderNo).HasMaxLength(40);
        builder.Property(x => x.ResourceName).HasMaxLength(120);
        builder.Property(x => x.ProductName).HasMaxLength(200);
        builder.Property(x => x.UnitName).HasMaxLength(40);
        builder.Property(x => x.Actor).HasMaxLength(200);
        builder.Property(x => x.DeviceName).HasMaxLength(120);
        builder.Property(x => x.Qty).HasPrecision(18, 3);
        builder.Property(x => x.Amount).HasPrecision(18, 2);
        builder.HasIndex(x => new { x.StoreId, x.OccurredAt });
        builder.HasIndex(x => new { x.StoreId, x.ActionType, x.OccurredAt });
        builder.HasIndex(x => new { x.StoreId, x.AfterProvisionalBill, x.OccurredAt });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
    }
}
