using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Gán loại chứng từ → máy in.</summary>
public class PosPrinterDocumentRoute : AuditableEntity<Guid>
{
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public Guid PrinterId { get; set; }
    public virtual PosStorePrinter? Printer { get; set; }

    public PosPrintDocumentType DocumentType { get; set; }

    public int DefaultCopies { get; set; } = 1;
}
