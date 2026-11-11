using Microsoft.EntityFrameworkCore;

using ZKTecoADMS.Application.Constants;

using ZKTecoADMS.Application.Interfaces;

using ZKTecoADMS.Domain.Entities;

using ZKTecoADMS.Domain.Enums;



namespace ZKTecoADMS.Infrastructure.Services;



/// <summary>

/// Thông báo phiếu thưởng/phạt (PaymentTransaction) — NV + chủ cửa hàng / QL / người có quyền.

/// </summary>

public static class PaymentTransactionNotificationHelper

{

    private const string EntityType = "BonusPenalty";

    private const string ModuleCode = "BonusPenalty";



    /// <summary>Phiếu phạt vào nhóm «Phiếu phạt» (cùng phiếu phạt chấm công); thưởng / khấu trừ… giữ «Thu chi».</summary>
    public static string CategoryFor(string? type) =>
        string.Equals(type, "Penalty", StringComparison.OrdinalIgnoreCase) ? "penalty" : "transaction";

    public static string TypeLabel(string? type) => type switch

    {

        "Bonus" => "thưởng",

        "Penalty" => "phạt",

        "Deduction" => "khấu trừ",

        "AdvancePayment" => "ứng lương",

        "SalaryPayment" => "chi lương",

        "Allowance" => "phụ cấp",

        _ => "thu chi"

    };



    /// <summary>Tiền kiểu Việt «200.000đ».</summary>

    private static string Vnd(decimal v) => CashTransactionLinkageHelper.Vnd(v);

    /// <summary>Ghép ý bằng « · », bỏ ý trống; mô tả dài cắt 60 ký tự.</summary>

    private static string JoinDot(params string?[] parts) =>

        string.Join(" · ", parts.Where(p => !string.IsNullOrWhiteSpace(p))

            .Select(p => p!.Trim().Length > 60 ? p.Trim()[..60].TrimEnd() + "…" : p.Trim()));

    public static async Task NotifyCreatedAsync(

        ZKTecoDbContext? context,

        IModulePermissionService? permissionService,

        ISystemNotificationService notificationService,

        PaymentTransaction tx,

        Guid actorUserId,

        Guid? storeId)

    {

        var label = TypeLabel(tx.Type);

        var amount = Math.Abs(tx.Amount);



        if (TryGetEmployeeUserId(tx, actorUserId, out var empUserId))

        {

            await notificationService.CreateAndSendAsync(

                empUserId,

                NotificationType.Info,

                $"Phiếu {label} mới",

                JoinDot(Vnd(amount), tx.Description),

                relatedEntityType: EntityType,

                relatedEntityId: tx.Id,

                fromUserId: actorUserId,

                categoryCode: CategoryFor(tx.Type),

                storeId: storeId);

        }



        if (context == null || permissionService == null || !storeId.HasValue)

            return;



        var adminTargets = await ResolveAdminNotifyTargetsAsync(

            context, permissionService, actorUserId, storeId.Value, tx.EmployeeUserId);

        if (adminTargets.Count == 0) return;



        // Người tạo = fromUserId → formatter tự thêm tên (trước đây message ghi tên + formatter lặp lại).

        var empName = await ResolveEmployeeNameAsync(context, tx);



        await notificationService.CreateAndSendToUsersAsync(

            adminTargets,

            NotificationType.Info,

            $"Phiếu {label} cho {empName}",

            JoinDot(Vnd(amount), tx.Description),

            relatedEntityType: EntityType,

            relatedEntityId: tx.Id,

            fromUserId: actorUserId,

            categoryCode: CategoryFor(tx.Type),

            storeId: storeId);

    }



    public static async Task NotifyStatusChangedAsync(

        ISystemNotificationService notificationService,

        PaymentTransaction tx,

        string newStatus,

        Guid actorUserId,

        Guid? storeId)

    {

        if (!TryGetEmployeeUserId(tx, actorUserId, out var userId)) return;



        var label = TypeLabel(tx.Type);

        var (notifType, statusText) = newStatus switch

        {

            "Completed" => (NotificationType.Success, "đã duyệt"),

            "Cancelled" => (NotificationType.Warning, "đã hủy"),

            "Pending" => (NotificationType.Info, "chờ duyệt"),

            "Rejected" => (NotificationType.Warning, "bị từ chối"),

            "Paid" => (NotificationType.Success, "đã thanh toán"),

            _ => (NotificationType.Info, "đã cập nhật")

        };



        await notificationService.CreateAndSendAsync(

            userId,

            notifType,

            $"Phiếu {label} {statusText}",

            JoinDot(Vnd(Math.Abs(tx.Amount)), tx.Description),

            relatedEntityType: EntityType,

            relatedEntityId: tx.Id,

            fromUserId: actorUserId,

            categoryCode: CategoryFor(tx.Type),

            storeId: storeId);

    }



    public static async Task NotifyDeletedAsync(

        ISystemNotificationService notificationService,

        Guid? employeeUserId,

        string type,

        decimal amount,

        Guid actorUserId,

        Guid? storeId)

    {

        if (!employeeUserId.HasValue || employeeUserId.Value == Guid.Empty

            || employeeUserId.Value == actorUserId)

            return;



        var label = TypeLabel(type);

        await notificationService.CreateAndSendAsync(

            employeeUserId.Value,

            NotificationType.Warning,

            $"Phiếu {label} đã xóa",

            Vnd(Math.Abs(amount)),

            relatedEntityType: EntityType,

            fromUserId: actorUserId,

            categoryCode: CategoryFor(type),

            storeId: storeId);

    }



    public static async Task NotifyPaidAsync(

        ISystemNotificationService notificationService,

        PaymentTransaction tx,

        Guid actorUserId,

        Guid? storeId)

    {

        if (!TryGetEmployeeUserId(tx, actorUserId, out var userId)) return;



        var label = TypeLabel(tx.Type);

        var action = tx.Type == "Penalty" ? "đã thu" : "đã thanh toán";

        await notificationService.CreateAndSendAsync(

            userId,

            NotificationType.Success,

            $"Phiếu {label} {action}",

            JoinDot(Vnd(Math.Abs(tx.Amount)), tx.Description),

            relatedEntityType: EntityType,

            relatedEntityId: tx.Id,

            fromUserId: actorUserId,

            categoryCode: CategoryFor(tx.Type),

            storeId: storeId);

    }



    private static async Task<HashSet<Guid>> ResolveAdminNotifyTargetsAsync(

        ZKTecoDbContext context,

        IModulePermissionService permissionService,

        Guid actorUserId,

        Guid storeId,

        Guid? employeeUserId)

    {

        var targets = new HashSet<Guid>();



        var ownerId = await context.Stores.AsNoTracking()

            .Where(s => s.Id == storeId)

            .Select(s => s.OwnerId)

            .FirstOrDefaultAsync();

        if (ownerId.HasValue && ownerId.Value != Guid.Empty && ownerId.Value != actorUserId)

            targets.Add(ownerId.Value);



        if (employeeUserId.HasValue && employeeUserId.Value != Guid.Empty)

        {

            var directManagerUserId = await (

                from emp in context.Employees.AsNoTracking()

                join mgr in context.Employees.AsNoTracking()

                    on emp.DirectManagerEmployeeId equals mgr.Id

                where emp.ApplicationUserId == employeeUserId.Value

                      && emp.StoreId == storeId

                      && emp.Deleted == null

                      && mgr.ApplicationUserId != null

                select mgr.ApplicationUserId!.Value

            ).FirstOrDefaultAsync();

            if (directManagerUserId != Guid.Empty && directManagerUserId != actorUserId)

                targets.Add(directManagerUserId);

        }



        var storeUsers = await context.Users.AsNoTracking()

            .Where(u => u.IsActive && u.StoreId == storeId && u.Id != actorUserId)

            .Select(u => new { u.Id, u.Role })

            .ToListAsync();



        foreach (var user in storeUsers)

        {

            if (await permissionService.HasPermissionAsync(

                    user.Id,

                    user.Role ?? string.Empty,

                    storeId,

                    ModuleCode,

                    ModulePermissionAction.Create))

            {

                targets.Add(user.Id);

            }



            if (await permissionService.HasPermissionAsync(

                    user.Id,

                    user.Role ?? string.Empty,

                    storeId,

                    "Transaction",

                    ModulePermissionAction.Create))

            {

                targets.Add(user.Id);

            }

        }



        return targets;

    }



    private static async Task<string> ResolveEmployeeNameAsync(ZKTecoDbContext context, PaymentTransaction tx)

    {

        if (tx.EmployeeId.HasValue)

        {

            var emp = await context.Employees.AsNoTracking()

                .Where(e => e.Id == tx.EmployeeId.Value)

                .Select(e => new { e.LastName, e.FirstName })

                .FirstOrDefaultAsync();

            if (emp != null)

                return $"{emp.LastName} {emp.FirstName}".Trim();

        }



        if (tx.EmployeeUserId.HasValue)

        {

            var user = await context.Users.AsNoTracking()

                .Where(u => u.Id == tx.EmployeeUserId.Value)

                .Select(u => new { u.LastName, u.FirstName })

                .FirstOrDefaultAsync();

            if (user != null)

                return $"{user.LastName} {user.FirstName}".Trim();

        }



        return "nhân viên";

    }



    private static bool TryGetEmployeeUserId(

        PaymentTransaction tx, Guid actorUserId, out Guid userId)

    {

        userId = Guid.Empty;

        if (!tx.EmployeeUserId.HasValue || tx.EmployeeUserId.Value == Guid.Empty)

            return false;

        if (tx.EmployeeUserId.Value == actorUserId)

            return false;

        userId = tx.EmployeeUserId.Value;

        return true;

    }

}

