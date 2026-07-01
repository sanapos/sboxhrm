using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PosProductCategoryConfiguration : IEntityTypeConfiguration<PosProductCategory>
{
    public void Configure(EntityTypeBuilder<PosProductCategory> builder)
    {
        builder.ToTable("PosProductCategories");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Name).IsRequired().HasMaxLength(200);
        builder.HasIndex(x => new { x.StoreId, x.Name });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Parent).WithMany(x => x.Children).HasForeignKey(x => x.ParentId).OnDelete(DeleteBehavior.Restrict);
    }
}

public class PosProductBrandConfiguration : IEntityTypeConfiguration<PosProductBrand>
{
    public void Configure(EntityTypeBuilder<PosProductBrand> builder)
    {
        builder.ToTable("PosProductBrands");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Name).IsRequired().HasMaxLength(200);
        builder.HasIndex(x => new { x.StoreId, x.Name });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosStorageLocationConfiguration : IEntityTypeConfiguration<PosStorageLocation>
{
    public void Configure(EntityTypeBuilder<PosStorageLocation> builder)
    {
        builder.ToTable("PosStorageLocations");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Name).IsRequired().HasMaxLength(200);
        builder.HasIndex(x => new { x.StoreId, x.Name });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosProductConfiguration : IEntityTypeConfiguration<PosProduct>
{
    public void Configure(EntityTypeBuilder<PosProduct> builder)
    {
        builder.ToTable("PosProducts");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.ProductCode).IsRequired().HasMaxLength(50);
        builder.Property(x => x.Barcode).HasMaxLength(50);
        builder.Property(x => x.Name).IsRequired().HasMaxLength(500);
        builder.Property(x => x.Description).HasMaxLength(2000);
        builder.Property(x => x.ImageUrl).HasMaxLength(500);
        builder.Property(x => x.WeightUnit).HasMaxLength(20);
        builder.Property(x => x.BaseUnitName).HasMaxLength(100);
        builder.Property(x => x.SaleQuickNotesJson).HasMaxLength(4000);
        builder.Property(x => x.CostPrice).HasPrecision(18, 2);
        builder.Property(x => x.BasePrice).HasPrecision(18, 2);
        builder.Property(x => x.OnHandQty).HasPrecision(18, 4);
        builder.Property(x => x.ReservedQty).HasPrecision(18, 4);
        builder.Property(x => x.MinStockQty).HasPrecision(18, 4);
        builder.Property(x => x.MaxStockQty).HasPrecision(18, 4);
        builder.Property(x => x.Weight).HasPrecision(18, 4);
        builder.HasIndex(x => new { x.StoreId, x.ProductCode }).IsUnique();
        builder.HasIndex(x => new { x.StoreId, x.Name });
        builder.HasIndex(x => new { x.StoreId, x.Barcode });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Category).WithMany(x => x.Products).HasForeignKey(x => x.CategoryId).OnDelete(DeleteBehavior.SetNull);
        builder.HasOne(x => x.Brand).WithMany(x => x.Products).HasForeignKey(x => x.BrandId).OnDelete(DeleteBehavior.SetNull);
        builder.HasOne(x => x.StorageLocation).WithMany(x => x.Products).HasForeignKey(x => x.StorageLocationId).OnDelete(DeleteBehavior.SetNull);
        builder.HasOne(x => x.Supplier).WithMany(x => x.Products).HasForeignKey(x => x.SupplierId).OnDelete(DeleteBehavior.SetNull);
    }
}

public class PosProductUnitConfiguration : IEntityTypeConfiguration<PosProductUnit>
{
    public void Configure(EntityTypeBuilder<PosProductUnit> builder)
    {
        builder.ToTable("PosProductUnits");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.UnitName).IsRequired().HasMaxLength(100);
        builder.Property(x => x.ConversionRate).HasPrecision(18, 4);
        builder.Property(x => x.BasePrice).HasPrecision(18, 2);
        builder.HasIndex(x => new { x.ProductId, x.UnitName });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Product).WithMany(x => x.Units).HasForeignKey(x => x.ProductId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosSupplierConfiguration : IEntityTypeConfiguration<PosSupplier>
{
    public void Configure(EntityTypeBuilder<PosSupplier> builder)
    {
        builder.ToTable("PosSuppliers");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.SupplierCode).IsRequired().HasMaxLength(30);
        builder.Property(x => x.Name).IsRequired().HasMaxLength(200);
        builder.Property(x => x.Phone).HasMaxLength(50);
        builder.Property(x => x.Email).HasMaxLength(200);
        builder.Property(x => x.Address).HasMaxLength(500);
        builder.Property(x => x.Province).HasMaxLength(100);
        builder.Property(x => x.Ward).HasMaxLength(100);
        builder.Property(x => x.CompanyName).HasMaxLength(200);
        builder.Property(x => x.TaxCode).HasMaxLength(50);
        builder.Property(x => x.IdentityNo).HasMaxLength(50);
        builder.Property(x => x.Note).HasMaxLength(1000);
        builder.Property(x => x.TotalPurchase).HasPrecision(18, 2);
        builder.Property(x => x.CurrentDebt).HasPrecision(18, 2);
        builder.HasIndex(x => new { x.StoreId, x.SupplierCode }).IsUnique();
        builder.HasIndex(x => new { x.StoreId, x.Name });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Group).WithMany(x => x.Suppliers).HasForeignKey(x => x.GroupId).OnDelete(DeleteBehavior.SetNull);
    }
}

public class PosSupplierGroupConfiguration : IEntityTypeConfiguration<PosSupplierGroup>
{
    public void Configure(EntityTypeBuilder<PosSupplierGroup> builder)
    {
        builder.ToTable("PosSupplierGroups");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Name).IsRequired().HasMaxLength(100);
        builder.HasIndex(x => new { x.StoreId, x.Name });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosCustomerConfiguration : IEntityTypeConfiguration<PosCustomer>
{
    public void Configure(EntityTypeBuilder<PosCustomer> builder)
    {
        builder.ToTable("PosCustomers");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.CustomerCode).IsRequired().HasMaxLength(30);
        builder.Property(x => x.Name).IsRequired().HasMaxLength(200);
        builder.Property(x => x.Phone).HasMaxLength(50);
        builder.Property(x => x.Email).HasMaxLength(200);
        builder.Property(x => x.Address).HasMaxLength(500);
        builder.Property(x => x.Province).HasMaxLength(100);
        builder.Property(x => x.Ward).HasMaxLength(100);
        builder.Property(x => x.CompanyName).HasMaxLength(200);
        builder.Property(x => x.TaxCode).HasMaxLength(50);
        builder.Property(x => x.Note).HasMaxLength(1000);
        builder.Property(x => x.TotalPurchase).HasPrecision(18, 2);
        builder.Property(x => x.CurrentDebt).HasPrecision(18, 2);
        builder.HasIndex(x => new { x.StoreId, x.CustomerCode }).IsUnique();
        builder.HasIndex(x => new { x.StoreId, x.Name });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosProductAttributeConfiguration : IEntityTypeConfiguration<PosProductAttribute>
{
    public void Configure(EntityTypeBuilder<PosProductAttribute> builder)
    {
        builder.ToTable("PosProductAttributes");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Name).IsRequired().HasMaxLength(100);
        builder.HasIndex(x => new { x.StoreId, x.Name });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosProductAttributeValueConfiguration : IEntityTypeConfiguration<PosProductAttributeValue>
{
    public void Configure(EntityTypeBuilder<PosProductAttributeValue> builder)
    {
        builder.ToTable("PosProductAttributeValues");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Value).IsRequired().HasMaxLength(500);
        builder.HasIndex(x => new { x.ProductId, x.AttributeId }).IsUnique();
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Product).WithMany(x => x.AttributeValues).HasForeignKey(x => x.ProductId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Attribute).WithMany(x => x.Values).HasForeignKey(x => x.AttributeId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosStockTransactionConfiguration : IEntityTypeConfiguration<PosStockTransaction>
{
    public void Configure(EntityTypeBuilder<PosStockTransaction> builder)
    {
        builder.ToTable("PosStockTransactions");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.QtyChange).HasPrecision(18, 4);
        builder.Property(x => x.QtyAfter).HasPrecision(18, 4);
        builder.Property(x => x.UnitCost).HasPrecision(18, 4);
        builder.Property(x => x.LineAmount).HasPrecision(18, 2);
        builder.Property(x => x.ReferenceNo).HasMaxLength(50);
        builder.Property(x => x.Note).HasMaxLength(500);
        builder.HasIndex(x => new { x.StoreId, x.ProductId, x.CreatedAt });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Product).WithMany(x => x.StockTransactions).HasForeignKey(x => x.ProductId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Variant).WithMany().HasForeignKey(x => x.VariantId).OnDelete(DeleteBehavior.SetNull);
        builder.HasOne(x => x.SaleOrder).WithMany().HasForeignKey(x => x.SaleOrderId).OnDelete(DeleteBehavior.SetNull);
        builder.HasOne(x => x.StockReceipt).WithMany().HasForeignKey(x => x.StockReceiptId).OnDelete(DeleteBehavior.SetNull);
        builder.HasOne(x => x.StockIssue).WithMany().HasForeignKey(x => x.StockIssueId).OnDelete(DeleteBehavior.SetNull);
        builder.HasOne(x => x.StockCount).WithMany().HasForeignKey(x => x.StockCountId).OnDelete(DeleteBehavior.SetNull);
        builder.HasOne(x => x.PurchaseReturn).WithMany().HasForeignKey(x => x.PurchaseReturnId).OnDelete(DeleteBehavior.SetNull);
    }
}

public class PosSaleOrderConfiguration : IEntityTypeConfiguration<PosSaleOrder>
{
    public void Configure(EntityTypeBuilder<PosSaleOrder> builder)
    {
        builder.ToTable("PosSaleOrders");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.OrderNo).IsRequired().HasMaxLength(30);
        builder.Property(x => x.SubTotal).HasPrecision(18, 2);
        builder.Property(x => x.Discount).HasPrecision(18, 2);
        builder.Property(x => x.Total).HasPrecision(18, 2);
        builder.Property(x => x.PaidAmount).HasPrecision(18, 2);
        builder.Property(x => x.PaymentMethod).HasMaxLength(50);
        builder.Property(x => x.CustomerName).HasMaxLength(200);
        builder.Property(x => x.DeliveryAddress).HasMaxLength(500);
        builder.Property(x => x.DeliveryPhone).HasMaxLength(50);
        builder.Property(x => x.DeliveryPartner).HasMaxLength(100);
        builder.Property(x => x.DeliveryStatus).HasMaxLength(50);
        builder.Property(x => x.Note).HasMaxLength(500);
        builder.Property(x => x.SoldBy).HasMaxLength(200);
        builder.Property(x => x.SalesChannel).HasMaxLength(100);
        builder.HasIndex(x => new { x.StoreId, x.SoldByEmployeeId });
        builder.Property(x => x.PriceListName).HasMaxLength(100);
        builder.HasIndex(x => new { x.StoreId, x.OrderNo }).IsUnique();
        builder.HasIndex(x => new { x.StoreId, x.Status, x.CreatedAt });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Customer).WithMany(x => x.SaleOrders).HasForeignKey(x => x.CustomerId).OnDelete(DeleteBehavior.SetNull);
    }
}

public class PosSaleOrderLineConfiguration : IEntityTypeConfiguration<PosSaleOrderLine>
{
    public void Configure(EntityTypeBuilder<PosSaleOrderLine> builder)
    {
        builder.ToTable("PosSaleOrderLines");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.ProductName).IsRequired().HasMaxLength(500);
        builder.Property(x => x.UnitName).HasMaxLength(100);
        builder.Property(x => x.Qty).HasPrecision(18, 4);
        builder.Property(x => x.UnitPrice).HasPrecision(18, 2);
        builder.Property(x => x.LineTotal).HasPrecision(18, 2);
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.SaleOrder).WithMany(x => x.Lines).HasForeignKey(x => x.SaleOrderId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Product).WithMany().HasForeignKey(x => x.ProductId).OnDelete(DeleteBehavior.Restrict);
        builder.HasOne(x => x.Variant).WithMany().HasForeignKey(x => x.VariantId).OnDelete(DeleteBehavior.SetNull);
    }
}

public class PosProductComboLineConfiguration : IEntityTypeConfiguration<PosProductComboLine>
{
    public void Configure(EntityTypeBuilder<PosProductComboLine> builder)
    {
        builder.ToTable("PosProductComboLines");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Qty).HasPrecision(18, 4);
        builder.HasIndex(x => new { x.ComboProductId, x.ComponentProductId }).IsUnique();
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.ComboProduct).WithMany(x => x.ComboLines).HasForeignKey(x => x.ComboProductId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.ComponentProduct).WithMany().HasForeignKey(x => x.ComponentProductId).OnDelete(DeleteBehavior.Restrict);
    }
}

public class PosProductVariantConfiguration : IEntityTypeConfiguration<PosProductVariant>
{
    public void Configure(EntityTypeBuilder<PosProductVariant> builder)
    {
        builder.ToTable("PosProductVariants");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.SkuCode).IsRequired().HasMaxLength(50);
        builder.Property(x => x.Barcode).HasMaxLength(50);
        builder.Property(x => x.Name).IsRequired().HasMaxLength(500);
        builder.Property(x => x.AttributeJson).HasMaxLength(2000);
        builder.Property(x => x.CostPrice).HasPrecision(18, 2);
        builder.Property(x => x.BasePrice).HasPrecision(18, 2);
        builder.Property(x => x.OnHandQty).HasPrecision(18, 4);
        builder.HasIndex(x => new { x.ProductId, x.SkuCode }).IsUnique();
        builder.HasIndex(x => new { x.StoreId, x.Barcode });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Product).WithMany(x => x.Variants).HasForeignKey(x => x.ProductId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosStockReceiptConfiguration : IEntityTypeConfiguration<PosStockReceipt>
{
    public void Configure(EntityTypeBuilder<PosStockReceipt> builder)
    {
        builder.ToTable("PosStockReceipts");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.ReceiptNo).IsRequired().HasMaxLength(30);
        builder.Property(x => x.Note).HasMaxLength(500);
        builder.Property(x => x.TotalQty).HasPrecision(18, 4);
        builder.Property(x => x.TotalCost).HasPrecision(18, 2);
        builder.Property(x => x.DiscountAmount).HasPrecision(18, 2);
        builder.Property(x => x.PaidAmount).HasPrecision(18, 2);
        builder.Property(x => x.DiscountInput).HasPrecision(18, 2);
        builder.Property(x => x.TotalVat).HasPrecision(18, 2);
        builder.Property(x => x.ImportedBy).HasMaxLength(200);
        builder.Property(x => x.InputInvoiceNo).HasMaxLength(50);
        builder.Property(x => x.PurchaseOrderNo).HasMaxLength(50);
        builder.HasIndex(x => new { x.StoreId, x.ReceiptNo }).IsUnique();
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Supplier).WithMany(x => x.Receipts).HasForeignKey(x => x.SupplierId).OnDelete(DeleteBehavior.SetNull);
    }
}

public class PosStockReceiptLineConfiguration : IEntityTypeConfiguration<PosStockReceiptLine>
{
    public void Configure(EntityTypeBuilder<PosStockReceiptLine> builder)
    {
        builder.ToTable("PosStockReceiptLines");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.ProductName).IsRequired().HasMaxLength(500);
        builder.Property(x => x.ProductCode).HasMaxLength(50);
        builder.Property(x => x.Qty).HasPrecision(18, 4);
        builder.Property(x => x.CostPrice).HasPrecision(18, 2);
        builder.Property(x => x.DiscountAmount).HasPrecision(18, 2);
        builder.Property(x => x.LineTotal).HasPrecision(18, 2);
        builder.Property(x => x.VatRate).HasPrecision(5, 2);
        builder.Property(x => x.VatAmount).HasPrecision(18, 2);
        builder.Property(x => x.UnitName).HasMaxLength(100);
        builder.Property(x => x.LineNote).HasMaxLength(500);
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Receipt).WithMany(x => x.Lines).HasForeignKey(x => x.ReceiptId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Product).WithMany().HasForeignKey(x => x.ProductId).OnDelete(DeleteBehavior.Restrict);
        builder.HasOne(x => x.Variant).WithMany().HasForeignKey(x => x.VariantId).OnDelete(DeleteBehavior.SetNull);
    }
}

public class PosStockIssueConfiguration : IEntityTypeConfiguration<PosStockIssue>
{
    public void Configure(EntityTypeBuilder<PosStockIssue> builder)
    {
        builder.ToTable("PosStockIssues");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.IssueNo).IsRequired().HasMaxLength(30);
        builder.Property(x => x.Reason).HasMaxLength(200);
        builder.Property(x => x.Note).HasMaxLength(500);
        builder.Property(x => x.TotalQty).HasPrecision(18, 4);
        builder.Property(x => x.TotalValue).HasPrecision(18, 4);
        builder.Property(x => x.CategoryName).HasMaxLength(100);
        builder.Property(x => x.RecipientName).HasMaxLength(200);
        builder.Property(x => x.IssuedBy).HasMaxLength(200);
        builder.HasIndex(x => new { x.StoreId, x.IssueNo }).IsUnique();
        builder.HasIndex(x => new { x.StoreId, x.Kind, x.Status });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosStockIssueLineConfiguration : IEntityTypeConfiguration<PosStockIssueLine>
{
    public void Configure(EntityTypeBuilder<PosStockIssueLine> builder)
    {
        builder.ToTable("PosStockIssueLines");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.ProductName).IsRequired().HasMaxLength(500);
        builder.Property(x => x.ProductCode).HasMaxLength(50);
        builder.Property(x => x.Qty).HasPrecision(18, 4);
        builder.Property(x => x.CostPrice).HasPrecision(18, 4);
        builder.Property(x => x.UnitName).HasMaxLength(50);
        builder.Property(x => x.LineNote).HasMaxLength(500);
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Issue).WithMany(x => x.Lines).HasForeignKey(x => x.IssueId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Product).WithMany().HasForeignKey(x => x.ProductId).OnDelete(DeleteBehavior.Restrict);
        builder.HasOne(x => x.Variant).WithMany().HasForeignKey(x => x.VariantId).OnDelete(DeleteBehavior.SetNull);
    }
}

public class PosStockCountConfiguration : IEntityTypeConfiguration<PosStockCount>
{
    public void Configure(EntityTypeBuilder<PosStockCount> builder)
    {
        builder.ToTable("PosStockCounts");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.CountNo).IsRequired().HasMaxLength(30);
        builder.Property(x => x.Name).IsRequired().HasMaxLength(200);
        builder.Property(x => x.Note).HasMaxLength(500);
        builder.HasIndex(x => new { x.StoreId, x.CountNo }).IsUnique();
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosStockCountLineConfiguration : IEntityTypeConfiguration<PosStockCountLine>
{
    public void Configure(EntityTypeBuilder<PosStockCountLine> builder)
    {
        builder.ToTable("PosStockCountLines");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.ProductName).HasMaxLength(500);
        builder.Property(x => x.ProductCode).HasMaxLength(50);
        builder.Property(x => x.SystemQty).HasPrecision(18, 4);
        builder.Property(x => x.CountedQty).HasPrecision(18, 4);
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Count).WithMany(x => x.Lines).HasForeignKey(x => x.CountId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Product).WithMany().HasForeignKey(x => x.ProductId).OnDelete(DeleteBehavior.Restrict);
        builder.HasOne(x => x.Variant).WithMany().HasForeignKey(x => x.VariantId).OnDelete(DeleteBehavior.SetNull);
    }
}

public class PosPurchaseReturnConfiguration : IEntityTypeConfiguration<PosPurchaseReturn>
{
    public void Configure(EntityTypeBuilder<PosPurchaseReturn> builder)
    {
        builder.ToTable("PosPurchaseReturns");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.ReturnNo).IsRequired().HasMaxLength(30);
        builder.Property(x => x.Note).HasMaxLength(500);
        builder.Property(x => x.TotalQty).HasPrecision(18, 4);
        builder.Property(x => x.TotalAmount).HasPrecision(18, 2);
        builder.Property(x => x.DiscountAmount).HasPrecision(18, 2);
        builder.Property(x => x.RefundDue).HasPrecision(18, 2);
        builder.Property(x => x.RefundReceived).HasPrecision(18, 2);
        builder.Property(x => x.ReturnedBy).HasMaxLength(200);
        builder.HasIndex(x => new { x.StoreId, x.ReturnNo }).IsUnique();
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Supplier).WithMany(x => x.Returns).HasForeignKey(x => x.SupplierId).OnDelete(DeleteBehavior.SetNull);
        builder.HasOne(x => x.SourceReceipt).WithMany().HasForeignKey(x => x.SourceReceiptId).OnDelete(DeleteBehavior.SetNull);
    }
}

public class PosPurchaseReturnLineConfiguration : IEntityTypeConfiguration<PosPurchaseReturnLine>
{
    public void Configure(EntityTypeBuilder<PosPurchaseReturnLine> builder)
    {
        builder.ToTable("PosPurchaseReturnLines");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.ProductName).IsRequired().HasMaxLength(500);
        builder.Property(x => x.ProductCode).HasMaxLength(50);
        builder.Property(x => x.UnitName).HasMaxLength(100);
        builder.Property(x => x.Qty).HasPrecision(18, 4);
        builder.Property(x => x.CostPrice).HasPrecision(18, 2);
        builder.Property(x => x.DiscountAmount).HasPrecision(18, 2);
        builder.Property(x => x.LineTotal).HasPrecision(18, 2);
        builder.Property(x => x.LineNote).HasMaxLength(500);
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Return).WithMany(x => x.Lines).HasForeignKey(x => x.ReturnId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Product).WithMany().HasForeignKey(x => x.ProductId).OnDelete(DeleteBehavior.Restrict);
        builder.HasOne(x => x.Variant).WithMany().HasForeignKey(x => x.VariantId).OnDelete(DeleteBehavior.SetNull);
    }
}

public class PosSupplierPaymentConfiguration : IEntityTypeConfiguration<PosSupplierPayment>
{
    public void Configure(EntityTypeBuilder<PosSupplierPayment> builder)
    {
        builder.ToTable("PosSupplierPayments");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.PaymentNo).IsRequired().HasMaxLength(30);
        builder.Property(x => x.Amount).HasPrecision(18, 2);
        builder.Property(x => x.PaymentMethod).HasMaxLength(50);
        builder.Property(x => x.Note).HasMaxLength(500);
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Supplier).WithMany(x => x.Payments).HasForeignKey(x => x.SupplierId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.StockReceipt).WithMany(x => x.Payments).HasForeignKey(x => x.StockReceiptId).OnDelete(DeleteBehavior.SetNull);
    }
}

public class PosPrintTemplateConfiguration : IEntityTypeConfiguration<PosPrintTemplate>
{
    public void Configure(EntityTypeBuilder<PosPrintTemplate> builder)
    {
        builder.ToTable("PosPrintTemplates");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Name).IsRequired().HasMaxLength(120);
        builder.Property(x => x.HtmlContent).IsRequired();
        builder.HasIndex(x => new { x.StoreId, x.DocumentType, x.IsDefault });
        builder.HasIndex(x => new { x.StoreId, x.DocumentType, x.PaperSize, x.Name });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
    }
}
