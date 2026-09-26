using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Middlewares;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Interceptors;

namespace ZKTecoADMS.Api.Controllers.Filters;

/// <summary>
/// Lịch sử thao tác của cửa hàng: mỗi request thêm / sửa / xóa thành công (có thay đổi dữ liệu thật)
/// → một dòng AuditLog: ai, lúc nào, chức năng nào, bản ghi nào, trường nào đổi (cũ → mới), IP / thiết bị.
/// Máy chấm công / webhook (không có người dùng) không ghi. Giữ 30 ngày (ActivityLogCleanupService).
/// </summary>
public sealed class ActivityAuditFilter(
    ActivityAuditCollector collector,
    IServiceScopeFactory scopes,
    ILogger<ActivityAuditFilter> logger) : IAsyncActionFilter
{
    public const string Source = "StoreActivity";

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var executed = await next();
        try
        {
            var http = context.HttpContext;
            var method = http.Request.Method.ToUpperInvariant();
            if (method is not ("POST" or "PUT" or "PATCH" or "DELETE")) return;
            if (collector.Changes.Count == 0) return;
            if (executed.Exception != null && !executed.ExceptionHandled) return;
            var user = http.User;
            if (user.Identity?.IsAuthenticated != true) return;
            if (!Guid.TryParse(user.FindFirst(ClaimTypeNames.StoreId)?.Value, out var storeId)) return;

            var changes = collector.Changes.ToList();
            collector.Changes.Clear();
            var path = http.Request.Path.Value ?? "";
            var module = StorePackageModuleMiddleware.ResolveModule(path) ?? GuessModule(changes);
            var action = changes.Any(c => c.Op == "Delete") && (method == "DELETE" || changes.All(c => c.Op == "Delete"))
                ? "Delete"
                : changes.Any(c => c.Op == "Create") && method == "POST" ? "Create" : "Update";
            var main = changes.FirstOrDefault(c => c.Op == action) ?? changes[0];
            var userId = Guid.TryParse(user.FindFirst("id")?.Value ?? user.FindFirst(ClaimTypes.NameIdentifier)?.Value, out var uid)
                ? uid : (Guid?)null;
            var details = JsonSerializer.Serialize(new
            {
                source = Source,
                endpoint = $"{method} {RouteTemplate(context) ?? path}",
                changes = changes.Select(c => new
                {
                    type = c.Type,
                    typeName = EntityLabel(c.Type),
                    id = c.Id,
                    op = c.Op,
                    label = c.Label,
                    fields = c.Fields.Select(f => new { f.Field, f.Old, f.New }),
                }),
            }, new JsonSerializerOptions(JsonSerializerDefaults.Web));

            var log = new AuditLog
            {
                Id = Guid.NewGuid(),
                Action = action,
                EntityType = module ?? EntityLabel(main.Type),
                EntityId = main.Id,
                EntityName = Summary(main, changes.Count),
                Details = details,
                UserId = userId,
                UserEmail = user.FindFirst(ClaimTypes.Email)?.Value,
                UserName = user.FindFirst(ClaimTypeNames.UserName)?.Value ?? user.Identity?.Name,
                UserRole = user.FindFirst(ClaimTypes.Role)?.Value,
                StoreId = storeId,
                StoreName = user.FindFirst(ClaimTypeNames.StoreName)?.Value,
                IpAddress = http.Connection.RemoteIpAddress?.ToString(),
                UserAgent = Trim(http.Request.Headers.UserAgent.ToString(), 500),
                Timestamp = DateTime.UtcNow,
                Status = "Success",
            };

            using var scope = scopes.CreateScope();
            scope.ServiceProvider.GetRequiredService<ActivityAuditCollector>().Suspended = true;
            var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
            if (userId is Guid id)
            {
                var u = await db.Users.IgnoreQueryFilters().AsNoTracking()
                    .Where(x => x.Id == id).Select(x => new { x.FirstName, x.LastName, x.Email })
                    .FirstOrDefaultAsync();
                var full = $"{u?.LastName} {u?.FirstName}".Trim();
                if (full.Length > 0) log.UserName = full;
                log.UserEmail ??= u?.Email;
            }
            db.AuditLogs.Add(log);
            await db.SaveChangesAsync();
        }
        catch (Exception ex)
        {
            // Không để nhật ký làm hỏng thao tác của người dùng.
            logger.LogWarning(ex, "Activity audit write failed");
        }
    }

    static string? RouteTemplate(ActionExecutingContext c) =>
        c.ActionDescriptor.AttributeRouteInfo?.Template is { } t ? "/" + t : null;

    static string Trim(string s, int max) => s.Length > max ? s[..max] : s;

    static string Summary(ActivityEntityChange main, int count)
    {
        var name = EntityLabel(main.Type);
        var label = string.IsNullOrWhiteSpace(main.Label) ? "" : $" «{Trim(main.Label!, 120)}»";
        var more = count > 1 ? $" (+{count - 1} bản ghi liên quan)" : "";
        return Trim($"{name}{label}{more}", 480);
    }

    static string? GuessModule(List<ActivityEntityChange> changes) => null;

    /// <summary>Tên dễ hiểu của loại dữ liệu (không có → tên kỹ thuật).</summary>
    public static string EntityLabel(string type) => type switch
    {
        "PosSaleOrder" => "Hóa đơn / đơn hàng",
        "PosSaleOrderLine" => "Dòng hàng trên hóa đơn",
        "PosSalePayment" or "PosPayment" => "Thanh toán",
        "PosSaleReturn" => "Phiếu trả hàng",
        "PosProduct" => "Hàng hóa",
        "PosProductVariant" => "Biến thể hàng hóa",
        "PosCategory" or "PosProductCategory" => "Nhóm hàng",
        "PosCustomer" => "Khách hàng",
        "PosSupplier" => "Nhà cung cấp",
        "PosPurchaseReceipt" => "Phiếu nhập hàng",
        "PosPurchaseReturn" => "Phiếu trả hàng nhập",
        "PosStockCount" => "Phiếu kiểm kho",
        "PosStockTransfer" => "Phiếu chuyển kho",
        "PosInventoryTransaction" or "PosStockMovement" => "Biến động kho",
        "PosQuote" => "Báo giá",
        "PosQuoteDocument" => "Hợp đồng / biên bản",
        "PosPrintTemplate" => "Mẫu in",
        "PosVoucher" or "PosPromotion" => "Khuyến mãi",
        "PosCashierShift" => "Ca thu ngân",
        "PosResourceSession" => "Phiên bàn / phòng",
        "PosServiceResource" => "Bàn / phòng",
        "PosCustomerSessionBalance" => "Gói buổi / thẻ tập",
        "PosGymVisit" => "Lượt tập",
        "PosStoreSellSettings" => "Thiết lập bán hàng",
        "CashTransaction" => "Phiếu thu / chi",
        "Employee" => "Nhân viên",
        "Department" => "Phòng ban",
        "Attendance" => "Chấm công",
        "Leave" => "Đơn nghỉ phép",
        "WorkSchedule" => "Lịch làm việc",
        "Shift" or "ShiftTemplate" => "Ca làm việc",
        "Payslip" or "Payroll" or "SalaryRecord" => "Bảng lương",
        "BonusPenalty" => "Thưởng / phạt",
        "PenaltyTicket" => "Phiếu phạt",
        "AdvanceRequest" => "Tạm ứng",
        "Asset" => "Tài sản",
        "TaskItem" or "WorkTask" => "Công việc",
        "AppSettings" => "Cài đặt",
        "ApplicationUser" => "Tài khoản",
        "RolePermission" or "DepartmentPermission" => "Phân quyền",
        "Device" => "Máy chấm công",
        "DeviceUser" => "Người dùng máy chấm công",
        _ => type,
    };

    /// <summary>Tên chức năng theo mã module (Lịch sử thao tác hiển thị).</summary>
    public static string ModuleLabel(string? code)
    {
        if (string.IsNullOrWhiteSpace(code)) return "Khác";
        var m = FeatureModuleCatalog.All.FirstOrDefault(x => x.Code == code);
        return m == null ? EntityLabel(code) : FeatureModuleCatalog.PublicDisplayName(m);
    }
}
