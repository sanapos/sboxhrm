using Microsoft.EntityFrameworkCore;

namespace ZKTecoADMS.Application.Helpers;

public static class DbExceptionMessageHelper
{
    public static string ToUserMessage(Exception ex)
    {
        var inner = Unwrap(ex);
        var text = inner.ToLowerInvariant();

        if (text.Contains("foreign key") || text.Contains("violates foreign key constraint")
            || text.Contains("23503"))
        {
            return "Không thể xóa chấm công: còn dữ liệu liên kết trên server. "
                   + "Đã cập nhật bản sửa — thử lại sau khi mở lại app.";
        }

        if (text.Contains("saving the entity changes"))
        {
            return "Lỗi lưu cơ sở dữ liệu khi xử lý chấm công. Thử lại sau vài giây hoặc tải lại dữ liệu.";
        }

        return string.IsNullOrWhiteSpace(ex.Message)
            ? "Lỗi xử lý dữ liệu. Vui lòng thử lại."
            : ex.Message;
    }

    private static string Unwrap(Exception ex)
    {
        while (ex.InnerException != null)
            ex = ex.InnerException;
        return ex is DbUpdateException ? ex.InnerException?.Message ?? ex.Message : ex.Message;
    }
}
