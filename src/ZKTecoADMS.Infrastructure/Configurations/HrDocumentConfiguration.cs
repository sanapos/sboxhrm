using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class HrDocumentConfiguration : IEntityTypeConfiguration<HrDocument>
{
    public void Configure(EntityTypeBuilder<HrDocument> builder)
    {
        builder.ToTable("HrDocuments");

        builder.HasKey(e => e.Id);

        builder.Property(e => e.Name)
            .IsRequired()
            .HasMaxLength(255);

        builder.Property(e => e.Description)
            .HasMaxLength(1000);

        builder.Property(e => e.FilePath)
            .IsRequired()
            .HasMaxLength(500);

        builder.Property(e => e.FileName)
            .IsRequired()
            .HasMaxLength(255);

        builder.Property(e => e.ContentType)
            .HasMaxLength(100);

        builder.Property(e => e.DocumentNumber)
            .HasMaxLength(100);

        builder.Property(e => e.IssuedBy)
            .HasMaxLength(255);

        builder.Property(e => e.Notes)
            .HasMaxLength(1000);

        // Indexes
        builder.HasIndex(e => e.EmployeeUserId)
            .HasDatabaseName("IX_HrDocuments_EmployeeUserId");

        builder.HasIndex(e => new { e.StoreId, e.DocumentType })
            .HasDatabaseName("IX_HrDocuments_Store_DocType");

        builder.HasIndex(e => e.ExpiryDate)
            .HasDatabaseName("IX_HrDocuments_ExpiryDate");

        // Relationships
        builder.HasOne(e => e.EmployeeUser)
            .WithMany()
            .HasForeignKey(e => e.EmployeeUserId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(e => e.UploadedByUser)
            .WithMany()
            .HasForeignKey(e => e.UploadedByUserId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasOne(e => e.Store)
            .WithMany()
            .HasForeignKey(e => e.StoreId)
            .OnDelete(DeleteBehavior.SetNull);
    }
}
