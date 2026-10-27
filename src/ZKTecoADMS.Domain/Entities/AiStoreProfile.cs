using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// «Hồ sơ cửa hàng cho Trợ lý ảo» — chủ cửa hàng tự viết: giờ mở cửa, chính sách đổi trả, nội quy / mức phạt,
/// tên gọi tắt món / hàng, cách xưng hô… Được nạp vào hướng dẫn của AI để trả lời đúng kiểu của cửa hàng.
/// Mỗi cửa hàng một dòng.
/// </summary>
public class AiStoreProfile : Entity<Guid>
{
    public Guid StoreId { get; set; }

    public string Content { get; set; } = string.Empty;
}
