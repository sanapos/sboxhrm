using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Authorization;

/// <summary>
/// Ai được gán vai trò nào / quản lý tài khoản nào trong một cửa hàng.
/// <list type="bullet">
/// <item>SuperAdmin, Agent là vai trò nền tảng — không gán được qua màn tài khoản cửa hàng.</item>
/// <item>Chủ cửa hàng gán được mọi vai trò cửa hàng; chỉ chủ mới gán được Admin.</item>
/// <item>Người khác chỉ gán / quản lý tài khoản có cấp thấp hơn mình.</item>
/// <item>Tài khoản chủ cửa hàng chỉ chủ (qua hồ sơ của mình) hoặc SuperAdmin sửa được.</item>
/// </list>
/// </summary>
public static class AccountRolePolicy
{
    static readonly Dictionary<string, int> Rank = new(StringComparer.OrdinalIgnoreCase)
    {
        [nameof(Roles.SuperAdmin)] = 100,
        [nameof(Roles.Agent)] = 90,
        [nameof(Roles.Admin)] = 80,
        [nameof(Roles.Director)] = 70,
        [nameof(Roles.Manager)] = 60,
        [nameof(Roles.DepartmentHead)] = 50,
        [nameof(Roles.Accountant)] = 50,
        [nameof(Roles.Cashier)] = 30,
        [nameof(Roles.Employee)] = 20,
        [nameof(Roles.Waiter)] = 20,
        [nameof(Roles.User)] = 10,
    };

    public static int RankOf(string? role) => role != null && Rank.TryGetValue(role, out var r) ? r : 0;

    public static bool IsPlatformRole(string? role) =>
        string.Equals(role, nameof(Roles.SuperAdmin), StringComparison.OrdinalIgnoreCase)
        || string.Equals(role, nameof(Roles.Agent), StringComparison.OrdinalIgnoreCase);

    static bool IsSuper(string? role) => string.Equals(role, nameof(Roles.SuperAdmin), StringComparison.OrdinalIgnoreCase);

    /// <summary>Vai trò cửa hàng mà người này được gán cho người khác.</summary>
    public static IReadOnlyList<string> AssignableRoles(string actorRole, bool actorIsOwner) =>
        Enum.GetNames<Roles>().Where(r => CanAssign(actorRole, actorIsOwner, r) == null).ToList();

    /// <summary>null = được gán; ngược lại là lý do từ chối.</summary>
    public static string? CanAssign(string actorRole, bool actorIsOwner, string? newRole)
    {
        if (string.IsNullOrWhiteSpace(newRole) || !Enum.TryParse<Roles>(newRole, ignoreCase: true, out _))
            return $"Vai trò '{newRole}' không hợp lệ.";
        if (IsPlatformRole(newRole))
            return IsSuper(actorRole) ? null : "Không thể gán vai trò quản trị nền tảng.";
        if (IsSuper(actorRole) || actorIsOwner) return null;
        if (string.Equals(newRole, nameof(Roles.Admin), StringComparison.OrdinalIgnoreCase))
            return "Chỉ chủ cửa hàng mới gán được vai trò Admin.";
        return RankOf(newRole) < RankOf(actorRole)
            ? null
            : "Chỉ gán được vai trò thấp hơn vai trò của bạn.";
    }

    /// <summary>
    /// null = được sửa bảng quyền của vai trò <paramref name="roleName"/>.
    /// Không ai tự nâng quyền vai trò của mình hoặc vai trò cao hơn (vd Giám đốc sửa quyền Giám đốc).
    /// Chức danh tự đặt (ngoài danh sách vai trò hệ thống) không gán được cho tài khoản nên không giới hạn.
    /// </summary>
    public static string? CanEditRole(string actorRole, bool actorIsOwner, string? roleName)
    {
        if (string.IsNullOrWhiteSpace(roleName)) return "Thiếu vai trò.";
        if (IsSuper(actorRole)) return null;
        if (IsPlatformRole(roleName)) return "Không thể sửa quyền vai trò quản trị nền tảng.";
        if (string.Equals(roleName, nameof(Roles.Admin), StringComparison.OrdinalIgnoreCase))
            return "Admin (chủ cửa hàng) luôn toàn quyền.";
        if (actorIsOwner) return null;
        var rank = RankOf(roleName);
        return rank == 0 || rank < RankOf(actorRole)
            ? null
            : "Chỉ sửa được quyền của vai trò thấp hơn vai trò của bạn.";
    }

    /// <summary>null = được sửa / khóa / đặt lại mật khẩu / xóa tài khoản đích.</summary>
    public static string? CanManage(string actorRole, bool actorIsOwner, string? targetRole, bool targetIsOwner)
    {
        if (IsSuper(actorRole)) return null;
        if (targetIsOwner) return "Không thể thay đổi tài khoản chủ cửa hàng.";
        if (IsPlatformRole(targetRole)) return "Không thể thay đổi tài khoản quản trị nền tảng.";
        if (actorIsOwner) return null;
        return RankOf(targetRole) < RankOf(actorRole)
            ? null
            : "Chỉ quản lý được tài khoản có vai trò thấp hơn vai trò của bạn.";
    }
}
