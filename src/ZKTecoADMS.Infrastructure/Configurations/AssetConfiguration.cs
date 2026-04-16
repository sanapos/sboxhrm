using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class AssetCategoryConfiguration : IEntityTypeConfiguration<AssetCategory>
{
    public void Configure(EntityTypeBuilder<AssetCategory> builder)
    {
        builder.ToTable("AssetCategories");
        
        builder.HasKey(x => x.Id);
        
        builder.Property(x => x.CategoryCode)
            .IsRequired()
            .HasMaxLength(50);
        
        builder.Property(x => x.Name)
            .IsRequired()
            .HasMaxLength(200);
        
        builder.Property(x => x.Description)
            .HasMaxLength(500);
        
        builder.HasOne(x => x.ParentCategory)
            .WithMany(x => x.SubCategories)
            .HasForeignKey(x => x.ParentCategoryId)
            .OnDelete(DeleteBehavior.Restrict);
        
        builder.HasOne(x => x.Store)
            .WithMany()
            .HasForeignKey(x => x.StoreId)
            .OnDelete(DeleteBehavior.Cascade);
        
        builder.HasIndex(x => new { x.StoreId, x.CategoryCode }).IsUnique();
        builder.HasIndex(x => x.ParentCategoryId);
    }
}

public class AssetConfiguration : IEntityTypeConfiguration<Asset>
{
    public void Configure(EntityTypeBuilder<Asset> builder)
    {
        builder.ToTable("Assets");
        
        builder.HasKey(x => x.Id);
        
        builder.Property(x => x.AssetCode)
            .IsRequired()
            .HasMaxLength(50);
        
        builder.Property(x => x.Name)
            .IsRequired()
            .HasMaxLength(500);
        
        builder.Property(x => x.Description)
            .HasMaxLength(2000);
        
        builder.Property(x => x.SerialNumber)
            .HasMaxLength(200);
        
        builder.Property(x => x.Model)
            .HasMaxLength(200);
        
        builder.Property(x => x.Brand)
            .HasMaxLength(200);
        
        builder.Property(x => x.Unit)
            .HasMaxLength(50)
            .HasDefaultValue("Cái");
        
        builder.Property(x => x.PurchasePrice)
            .HasPrecision(18, 2);
        
        builder.Property(x => x.Currency)
            .HasMaxLength(10)
            .HasDefaultValue("VND");
        
        builder.Property(x => x.Supplier)
            .HasMaxLength(300);
        
        builder.Property(x => x.InvoiceNumber)
            .HasMaxLength(100);
        
        builder.Property(x => x.Location)
            .HasMaxLength(300);
        
        builder.Property(x => x.Notes)
            .HasMaxLength(2000);
        
        builder.Property(x => x.DepreciationRate)
            .HasPrecision(5, 2);
        
        builder.Property(x => x.CurrentValue)
            .HasPrecision(18, 2);
        
        builder.HasOne(x => x.Category)
            .WithMany(x => x.Assets)
            .HasForeignKey(x => x.CategoryId)
            .OnDelete(DeleteBehavior.SetNull);
        
        builder.HasOne(x => x.CurrentAssignee)
            .WithMany()
            .HasForeignKey(x => x.CurrentAssigneeId)
            .OnDelete(DeleteBehavior.SetNull);
        
        builder.HasOne(x => x.Store)
            .WithMany()
            .HasForeignKey(x => x.StoreId)
            .OnDelete(DeleteBehavior.Cascade);
        
        builder.HasIndex(x => new { x.StoreId, x.AssetCode }).IsUnique();
        builder.HasIndex(x => x.SerialNumber);
        builder.HasIndex(x => x.Status);
        builder.HasIndex(x => x.CategoryId);
        builder.HasIndex(x => x.CurrentAssigneeId);
        builder.HasIndex(x => x.AssetType);
        builder.HasIndex(x => x.WarrantyExpiry);
        
        builder.Ignore(x => x.CurrentAssigneeName);
        builder.Ignore(x => x.CategoryName);
        builder.Ignore(x => x.IsWarrantyExpired);
        builder.Ignore(x => x.DaysUntilWarrantyExpiry);
    }
}

public class AssetImageConfiguration : IEntityTypeConfiguration<AssetImage>
{
    public void Configure(EntityTypeBuilder<AssetImage> builder)
    {
        builder.ToTable("AssetImages");
        
        builder.HasKey(x => x.Id);
        
        builder.Property(x => x.ImageUrl)
            .IsRequired()
            .HasMaxLength(1000);
        
        builder.Property(x => x.FileName)
            .HasMaxLength(300);
        
        builder.Property(x => x.Description)
            .HasMaxLength(500);
        
        builder.HasOne(x => x.Asset)
            .WithMany(x => x.Images)
            .HasForeignKey(x => x.AssetId)
            .OnDelete(DeleteBehavior.Cascade);
        
        builder.HasIndex(x => x.AssetId);
        builder.HasIndex(x => new { x.AssetId, x.IsPrimary });
    }
}

public class AssetTransferConfiguration : IEntityTypeConfiguration<AssetTransfer>
{
    public void Configure(EntityTypeBuilder<AssetTransfer> builder)
    {
        builder.ToTable("AssetTransfers");
        
        builder.HasKey(x => x.Id);
        
        builder.Property(x => x.Reason)
            .HasMaxLength(500);
        
        builder.Property(x => x.Notes)
            .HasMaxLength(1000);
        
        builder.HasOne(x => x.Asset)
            .WithMany(x => x.Transfers)
            .HasForeignKey(x => x.AssetId)
            .OnDelete(DeleteBehavior.Cascade);
        
        builder.HasOne(x => x.FromUser)
            .WithMany()
            .HasForeignKey(x => x.FromUserId)
            .OnDelete(DeleteBehavior.SetNull);
        
        builder.HasOne(x => x.ToUser)
            .WithMany()
            .HasForeignKey(x => x.ToUserId)
            .OnDelete(DeleteBehavior.SetNull);
        
        builder.HasOne(x => x.PerformedBy)
            .WithMany()
            .HasForeignKey(x => x.PerformedById)
            .OnDelete(DeleteBehavior.SetNull);
        
        builder.HasIndex(x => x.AssetId);
        builder.HasIndex(x => x.FromUserId);
        builder.HasIndex(x => x.ToUserId);
        builder.HasIndex(x => x.TransferDate);
        builder.HasIndex(x => x.TransferType);
        
        builder.Ignore(x => x.FromUserName);
        builder.Ignore(x => x.ToUserName);
        builder.Ignore(x => x.PerformedByName);
        builder.Ignore(x => x.AssetName);
        builder.Ignore(x => x.AssetCode);
    }
}

public class AssetInventoryConfiguration : IEntityTypeConfiguration<AssetInventory>
{
    public void Configure(EntityTypeBuilder<AssetInventory> builder)
    {
        builder.ToTable("AssetInventories");
        
        builder.HasKey(x => x.Id);
        
        builder.Property(x => x.InventoryCode)
            .IsRequired()
            .HasMaxLength(50);
        
        builder.Property(x => x.Name)
            .IsRequired()
            .HasMaxLength(300);
        
        builder.Property(x => x.Description)
            .HasMaxLength(1000);
        
        builder.Property(x => x.Notes)
            .HasMaxLength(2000);
        
        builder.HasOne(x => x.ResponsibleUser)
            .WithMany()
            .HasForeignKey(x => x.ResponsibleUserId)
            .OnDelete(DeleteBehavior.SetNull);
        
        builder.HasOne(x => x.Store)
            .WithMany()
            .HasForeignKey(x => x.StoreId)
            .OnDelete(DeleteBehavior.Cascade);
        
        builder.HasIndex(x => new { x.StoreId, x.InventoryCode }).IsUnique();
        builder.HasIndex(x => x.Status);
        builder.HasIndex(x => x.StartDate);
        
        builder.Ignore(x => x.TotalAssets);
        builder.Ignore(x => x.CheckedCount);
        builder.Ignore(x => x.IssueCount);
    }
}

public class AssetInventoryItemConfiguration : IEntityTypeConfiguration<AssetInventoryItem>
{
    public void Configure(EntityTypeBuilder<AssetInventoryItem> builder)
    {
        builder.ToTable("AssetInventoryItems");
        
        builder.HasKey(x => x.Id);
        
        builder.Property(x => x.ActualLocation)
            .HasMaxLength(300);
        
        builder.Property(x => x.IssueDescription)
            .HasMaxLength(1000);
        
        builder.Property(x => x.Notes)
            .HasMaxLength(1000);
        
        builder.HasOne(x => x.Inventory)
            .WithMany(x => x.Items)
            .HasForeignKey(x => x.InventoryId)
            .OnDelete(DeleteBehavior.Cascade);
        
        builder.HasOne(x => x.Asset)
            .WithMany(x => x.InventoryItems)
            .HasForeignKey(x => x.AssetId)
            .OnDelete(DeleteBehavior.Cascade);
        
        builder.HasOne(x => x.CheckedBy)
            .WithMany()
            .HasForeignKey(x => x.CheckedById)
            .OnDelete(DeleteBehavior.SetNull);
        
        builder.HasIndex(x => x.InventoryId);
        builder.HasIndex(x => x.AssetId);
        builder.HasIndex(x => new { x.InventoryId, x.AssetId }).IsUnique();
        builder.HasIndex(x => x.IsChecked);
        
        builder.Ignore(x => x.AssetCode);
        builder.Ignore(x => x.AssetName);
        builder.Ignore(x => x.ExpectedQuantity);
        builder.Ignore(x => x.QuantityMismatch);
    }
}
