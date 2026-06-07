namespace ZKTecoADMS.Application.DTOs.Leaves;

public class ApproveLeaveRequest
{
    /// <summary>Phép đã duyệt nhưng vẫn tính công (chỉ áp dụng khi duyệt xong).</summary>
    public bool? CountAsWork { get; set; }
}
