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
    /// <summary>Chỉ hiện tên dễ hiểu — Code dùng nội bộ khi gọi API.</summary>
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
