using System.Text.Json;

namespace SboxPrintAgent;

public sealed class AppSettings
{
    public const string DefaultApiBaseUrl = "https://sboxhrm.com";

    public string ApiBaseUrl { get; set; } = DefaultApiBaseUrl;
    public string StoreCode { get; set; } = "";
    public string Username { get; set; } = "";
    public string Password { get; set; } = "";
    public Guid StoreId { get; set; }
    public Guid AgentId { get; set; }
    public string DeviceId { get; set; } = "";
    public string AgentName { get; set; } = Environment.MachineName;
    public string SubnetPrefix { get; set; } = "";
    public bool AutoStartAgent { get; set; }
    /// <summary>Tự mở app khi khởi động Windows.</summary>
    public bool RunAtWindowsStartup { get; set; }
    public bool RememberPassword { get; set; } = true;
    public List<string> AssignedPrinterIds { get; set; } = new();
    public List<string> SettledJobIds { get; set; } = new();

    static string Path =>
        System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "SboxPrintAgent",
            "settings.json");

    public string EnsureDeviceId()
    {
        if (string.IsNullOrWhiteSpace(DeviceId))
        {
            DeviceId = "win-" + Guid.NewGuid().ToString("N")[..16];
            Save();
        }
        return DeviceId;
    }

    public List<Guid> AssignedGuids()
    {
        var list = new List<Guid>();
        foreach (var s in AssignedPrinterIds)
            if (Guid.TryParse(s, out var g)) list.Add(g);
        return list;
    }

    public static AppSettings Load()
    {
        try
        {
            var p = Path;
            if (!File.Exists(p)) return new AppSettings();
            var json = File.ReadAllText(p);
            var s = JsonSerializer.Deserialize<AppSettings>(json) ?? new AppSettings();
            // Migrate URL cũ → sboxhrm.com
            if (string.IsNullOrWhiteSpace(s.ApiBaseUrl) ||
                s.ApiBaseUrl.Contains("api.sbox.vn", StringComparison.OrdinalIgnoreCase) ||
                s.ApiBaseUrl.Equals("https://api.sboxhrm.com", StringComparison.OrdinalIgnoreCase))
            {
                s.ApiBaseUrl = DefaultApiBaseUrl;
            }
            return s;
        }
        catch
        {
            return new AppSettings();
        }
    }

    public void Save()
    {
        var dir = System.IO.Path.GetDirectoryName(Path)!;
        Directory.CreateDirectory(dir);
        File.WriteAllText(Path, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
    }
}
