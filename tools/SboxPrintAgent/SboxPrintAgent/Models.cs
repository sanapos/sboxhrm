namespace SboxPrintAgent;

public sealed record PrinterItem(
    Guid Id,
    string Name,
    string? LanHost,
    int LanPort,
    string ConnectionType,
    string PaperSize,
    bool IsDefault,
    bool IsActive,
    bool RequiresAgent,
    bool IsDeviceLocal,
    string? OwnerDeviceId,
    string HealthStatus,
    List<string> DocumentTypes,
    int DefaultCopies,
    int FeedBeforeCut,
    bool PartialCut,
    string? PrinterBrand,
    string? TextMode,
    string? UsbDeviceName);

public sealed record RouteItem(string DocumentType, Guid PrinterId, int Copies = 1);

public static class ConnLabel
{
    public static string Vi(string? type) => type?.ToLowerInvariant() switch
    {
        "lan" => "Mạng",
        "usb" => "USB",
        "bluetooth" => "Bluetooth",
        "sunmi" => "Sunmi",
        _ => type ?? "—",
    };

    public static bool IsLan(PrinterItem p) =>
        p.ConnectionType.Equals("Lan", StringComparison.OrdinalIgnoreCase);

    public static bool IsUsb(PrinterItem p) =>
        p.ConnectionType.Equals("Usb", StringComparison.OrdinalIgnoreCase);

    public static bool CanPrintOnWindows(PrinterItem p) =>
        (IsLan(p) && !string.IsNullOrWhiteSpace(p.LanHost)) ||
        (IsUsb(p) && !string.IsNullOrWhiteSpace(p.UsbDeviceName));

    /// <summary>Máy cloud Agent — bỏ bản ghi local từ A6/A7.</summary>
    public static bool IsCloudAgentPrinter(PrinterItem p) =>
        p.IsActive &&
        !p.IsDeviceLocal &&
        CanPrintOnWindows(p);

    public static string AddressKey(PrinterItem p)
    {
        if (IsUsb(p))
            return "usb:" + (p.UsbDeviceName ?? "").Trim().ToLowerInvariant();
        var host = (p.LanHost ?? "").Trim().ToLowerInvariant();
        var port = p.LanPort > 0 ? p.LanPort : 9100;
        return $"lan:{host}:{port}";
    }
}

/// <summary>Gộp máy trùng cùng IP/USB — ưu tiên RequiresAgent.</summary>
public static class PrinterListNormalize
{
    public static List<PrinterItem> ForWindowsAgent(IEnumerable<PrinterItem> raw)
    {
        return raw
            .Where(ConnLabel.IsCloudAgentPrinter)
            .GroupBy(ConnLabel.AddressKey, StringComparer.OrdinalIgnoreCase)
            .Select(g => g
                .OrderByDescending(p => p.RequiresAgent)
                .ThenByDescending(p => p.IsDefault)
                .ThenBy(p => p.Name.Length)
                .ThenBy(p => p.Name, StringComparer.CurrentCultureIgnoreCase)
                .First())
            .OrderBy(p => p.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToList();
    }
}

public sealed record ClaimJob(
    Guid JobId,
    Guid PrinterId,
    string DocumentType,
    string PayloadFormat,
    string? Payload,
    int Copies,
    string? ReferenceNo);

public sealed record AgentInfo(
    Guid AgentId,
    string DeviceId,
    string? DeviceName,
    string? EmployeeName,
    string? AccountLabel,
    List<Guid> PrinterIds,
    List<string> PrinterNames,
    bool IsOnline,
    DateTime? LastHeartbeatAt,
    string? AppVersion);

public sealed record AgentsSnapshot(
    int OnlineCount,
    bool MultiAgent,
    bool HasPrinterConflict,
    List<Guid> ConflictPrinterIds,
    List<AgentInfo> Agents);

public static class DocTypes
{
    public static readonly (string Code, string Label)[] All =
    [
        ("SaleInvoice", "Hóa đơn"),
        ("SaleOrder", "Đơn hàng"),
        ("StockIssue", "Phiếu báo bếp"),
        ("KitchenSlip", "Phiếu chế biến"),
        ("KitchenVoid", "Phiếu hủy bếp"),
        ("KitchenLabel", "Tem dán ly"),
        ("BarcodeLabel", "Tem mã vạch"),
        ("EndOfDayReport", "Báo cáo cuối ngày"),
        ("Delivery", "Phiếu giao hàng"),
        ("SaleReturn", "Phiếu trả hàng"),
    ];

    public static string LabelOf(string? code)
    {
        if (string.IsNullOrWhiteSpace(code)) return "—";
        var hit = All.FirstOrDefault(x => x.Code.Equals(code, StringComparison.OrdinalIgnoreCase));
        return string.IsNullOrEmpty(hit.Label) ? code : hit.Label;
    }
}

/// <summary>"192.168.1.230" → "192.168.1"</summary>
public static class SubnetNormalize
{
    public static string Clean(string? input)
    {
        var s = (input ?? "").Trim().TrimEnd('.');
        if (string.IsNullOrWhiteSpace(s)) return "";
        var parts = s.Split('.', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length >= 3 &&
            parts.Take(3).All(p => int.TryParse(p, out var n) && n is >= 0 and <= 255))
            return $"{parts[0]}.{parts[1]}.{parts[2]}";
        return s;
    }
}
