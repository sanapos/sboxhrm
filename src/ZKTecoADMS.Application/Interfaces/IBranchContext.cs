namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Ngữ cảnh chi nhánh của request hiện tại (middleware điền, đã kiểm quyền).
/// Ngoài HTTP (job nền) mọi giá trị null → interceptor dùng chi nhánh trụ sở.
/// </summary>
public interface IBranchContext
{
    /// <summary>Cửa hàng đã tạo chi nhánh (false → mọi tính năng chi nhánh tắt, BranchId để null).</summary>
    bool StoreUsesBranches { get; set; }

    /// <summary>Chi nhánh đang thao tác (header X-Branch-Id / chi nhánh của NV / trụ sở).</summary>
    Guid? CurrentBranchId { get; set; }

    /// <summary>Chi nhánh trụ sở — tồn kho trụ sở tính ngầm.</summary>
    Guid? HeadquarterBranchId { get; set; }

    /// <summary>Chi nhánh được phép xem. Null = tất cả (chủ / quản trị / kế toán).</summary>
    IReadOnlyCollection<Guid>? AllowedBranchIds { get; set; }

    /// <summary>Lọc báo cáo / danh sách theo 1 chi nhánh (query ?branchId=), đã kiểm quyền.</summary>
    Guid? FilterBranchId { get; set; }

    /// <summary>Người dùng của request (null = job nền / webhook → không kiểm quyền chi nhánh khi ghi).</summary>
    Guid? UserId { get; set; }

    /// <summary>Không phải chủ / giám đốc / quản trị / kế toán → kiểm phạm vi + quyền Thêm/Sửa/Xóa theo chi nhánh khi ghi.</summary>
    bool RestrictWrites { get; set; }

    /// <summary>Người dùng xem được chi nhánh này không.</summary>
    bool CanAccess(Guid? branchId) =>
        !StoreUsesBranches || AllowedBranchIds == null || (branchId.HasValue && AllowedBranchIds.Contains(branchId.Value));
}

/// <summary>Cài đặt mặc định (scoped) — middleware ghi đè.</summary>
public sealed class BranchContext : IBranchContext
{
    public bool StoreUsesBranches { get; set; }
    public Guid? CurrentBranchId { get; set; }
    public Guid? HeadquarterBranchId { get; set; }
    public IReadOnlyCollection<Guid>? AllowedBranchIds { get; set; }
    public Guid? FilterBranchId { get; set; }
    public Guid? UserId { get; set; }
    public bool RestrictWrites { get; set; }
}
