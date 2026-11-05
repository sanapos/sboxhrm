using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Accounts;

/// <summary>Điều kiện gắn hồ sơ nhân viên vào tài khoản đăng nhập (dùng chung khi tạo và khi sửa tài khoản).</summary>
public static class EmployeeAccountLink
{
    /// <summary>Lý do không gắn được; null = gắn được. <paramref name="userId"/> = null khi tài khoản chưa tạo.</summary>
    public static string? Deny(Employee? employee, Guid? storeId, Guid? userId = null)
    {
        if (employee == null || employee.Deleted != null || employee.StoreId != storeId)
            return "Không tìm thấy hồ sơ nhân viên.";
        if (employee.WorkStatus == EmployeeWorkStatus.Resigned)
            return "Nhân viên này đã nghỉ việc.";
        if (employee.ApplicationUserId.HasValue && employee.ApplicationUserId != userId)
            return "Hồ sơ này đã gắn với tài khoản khác.";
        return null;
    }
}
