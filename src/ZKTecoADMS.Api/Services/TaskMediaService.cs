using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using Google.Apis.Auth.OAuth2;
using Google.Apis.Auth.OAuth2.Flows;
using Google.Apis.Auth.OAuth2.Responses;
using Google.Apis.Drive.v3;
using Google.Apis.Services;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Settings;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Ảnh / chữ ký / file báo cáo công việc: lưu trên máy chủ (mặc định) hoặc Google Drive của khách
/// (khách bấm «Kết nối Google Drive», cấp quyền drive.file — SBOX chỉ thấy file do SBOX tạo).
/// Drive lỗi → tự lưu máy chủ để không mất ảnh hiện trường.
/// Cấu hình máy chủ: GoogleDrive:ClientId, GoogleDrive:ClientSecret, App:PublicBaseUrl (vd https://sboxhrm.com).
/// </summary>
public sealed class TaskMediaService(
    ZKTecoDbContext db,
    IFileStorageService localStorage,
    IConfiguration config,
    ILogger<TaskMediaService> logger)
{
    public const string RootFolderName = "SBOX - Báo cáo công việc";
    static readonly ConcurrentDictionary<string, string> FolderCache = new();

    // ─── Bí mật: mã hoá refresh token + ký link ảnh ───────────────

    byte[] Key(string purpose)
    {
        var secret = config.GetSection("JwtSettings").Get<JwtSettings>()?.AccessTokenSecret ?? "sbox-dev-secret";
        return SHA256.HashData(Encoding.UTF8.GetBytes(secret + "|task-media|" + purpose));
    }

    public string Protect(string plain)
    {
        var nonce = RandomNumberGenerator.GetBytes(12);
        var data = Encoding.UTF8.GetBytes(plain);
        var cipher = new byte[data.Length];
        var tag = new byte[16];
        using var aes = new AesGcm(Key("enc"), 16);
        aes.Encrypt(nonce, data, cipher, tag);
        return Convert.ToBase64String(nonce.Concat(tag).Concat(cipher).ToArray());
    }

    public string? Unprotect(string? packed)
    {
        if (string.IsNullOrWhiteSpace(packed)) return null;
        try
        {
            var all = Convert.FromBase64String(packed);
            var nonce = all[..12];
            var tag = all[12..28];
            var cipher = all[28..];
            var plain = new byte[cipher.Length];
            using var aes = new AesGcm(Key("enc"), 16);
            aes.Decrypt(nonce, cipher, tag, plain);
            return Encoding.UTF8.GetString(plain);
        }
        catch (Exception ex) when (ex is CryptographicException or FormatException)
        {
            return null;
        }
    }

    public string Sign(string payload) =>
        Convert.ToHexString(HMACSHA256.HashData(Key("sig"), Encoding.UTF8.GetBytes(payload))).ToLowerInvariant()[..32];

    /// <summary>Link xem ảnh trên Drive qua máy chủ (không cần đăng nhập Google), hết hạn sau 30 ngày.</summary>
    public string SignedContentUrl(Guid attachmentId)
    {
        var exp = DateTimeOffset.UtcNow.AddDays(30).ToUnixTimeSeconds();
        return $"/api/tasks/media/{attachmentId}/content?exp={exp}&sig={Sign($"{attachmentId}|{exp}")}";
    }

    public bool VerifySignature(Guid attachmentId, long exp, string? sig) =>
        exp > DateTimeOffset.UtcNow.ToUnixTimeSeconds() &&
        !string.IsNullOrEmpty(sig) &&
        CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(sig), Encoding.ASCII.GetBytes(Sign($"{attachmentId}|{exp}")));

    public string Url(TaskAttachment a) =>
        a.StorageKind == "gdrive" ? SignedContentUrl(a.Id) : localStorage.GetFileUrl(a.FilePath);

    // ─── Google OAuth ─────────────────────────────────────────────

    string? ClientId => config["GoogleDrive:ClientId"];
    string? ClientSecret => config["GoogleDrive:ClientSecret"];
    public bool DriveConfigured => !string.IsNullOrWhiteSpace(ClientId) && !string.IsNullOrWhiteSpace(ClientSecret);

    public string RedirectUri(HttpRequest request)
    {
        var baseUrl = config["App:PublicBaseUrl"];
        if (string.IsNullOrWhiteSpace(baseUrl))
        {
            var proto = request.Headers["X-Forwarded-Proto"].FirstOrDefault() ?? request.Scheme;
            var host = request.Headers["X-Forwarded-Host"].FirstOrDefault() ?? request.Host.ToString();
            baseUrl = $"{proto}://{host}";
        }
        return baseUrl.TrimEnd('/') + "/api/tasks/drive/callback";
    }

    GoogleAuthorizationCodeFlow Flow() => new(new GoogleAuthorizationCodeFlow.Initializer
    {
        ClientSecrets = new ClientSecrets { ClientId = ClientId, ClientSecret = ClientSecret },
        Scopes = [DriveService.Scope.DriveFile],
    });

    /// <summary>state = storeId|userId|hết hạn|chữ ký — chống giả mạo khi Google gọi lại.</summary>
    public string BuildState(Guid storeId, Guid userId)
    {
        var exp = DateTimeOffset.UtcNow.AddMinutes(20).ToUnixTimeSeconds();
        var payload = $"{storeId:N}.{userId:N}.{exp}";
        return payload + "." + Sign(payload);
    }

    public (Guid StoreId, Guid UserId)? ReadState(string? state)
    {
        var parts = (state ?? "").Split('.');
        if (parts.Length != 4) return null;
        var payload = $"{parts[0]}.{parts[1]}.{parts[2]}";
        if (!CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(parts[3]), Encoding.ASCII.GetBytes(Sign(payload))))
            return null;
        if (!long.TryParse(parts[2], out var exp) || exp < DateTimeOffset.UtcNow.ToUnixTimeSeconds()) return null;
        return Guid.TryParse(parts[0], out var s) && Guid.TryParse(parts[1], out var u) ? (s, u) : null;
    }

    public string AuthUrl(HttpRequest request, string state) =>
        "https://accounts.google.com/o/oauth2/v2/auth" +
        $"?client_id={Uri.EscapeDataString(ClientId!)}" +
        $"&redirect_uri={Uri.EscapeDataString(RedirectUri(request))}" +
        "&response_type=code&access_type=offline&prompt=consent&include_granted_scopes=true" +
        $"&scope={Uri.EscapeDataString(DriveService.Scope.DriveFile)}" +
        $"&state={Uri.EscapeDataString(state)}";

    DriveService Service(string refreshToken) => new(new BaseClientService.Initializer
    {
        HttpClientInitializer = new UserCredential(Flow(), "store", new TokenResponse { RefreshToken = refreshToken }),
        ApplicationName = "SBOX",
    });

    /// <summary>Đổi mã Google → refresh token, tạo thư mục gốc, lưu vào thiết lập cửa hàng.</summary>
    public async Task<string?> CompleteConnectAsync(HttpRequest request, Guid storeId, string code, CancellationToken ct)
    {
        var token = await Flow().ExchangeCodeForTokenAsync("store", code, RedirectUri(request), ct);
        if (string.IsNullOrWhiteSpace(token.RefreshToken))
            return "Google không trả quyền truy cập lâu dài — vào myaccount.google.com/permissions gỡ SBOX rồi kết nối lại.";
        var drive = Service(token.RefreshToken);
        var about = drive.About.Get();
        about.Fields = "user(emailAddress)";
        var me = await about.ExecuteAsync(ct);
        var folder = await EnsureFolderAsync(drive, RootFolderName, null, ct);

        var s = await GetOrCreateSettingsAsync(storeId, ct);
        s.DriveRefreshTokenEnc = Protect(token.RefreshToken);
        s.DriveAccountEmail = me.User?.EmailAddress;
        s.DriveRootFolderId = folder;
        s.DriveConnectedAt = DateTime.UtcNow;
        s.DriveLastError = null;
        s.PhotoStorage = "gdrive";
        s.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        FolderCache.Clear();
        return null;
    }

    public async Task<TaskWorkspaceSetting> GetOrCreateSettingsAsync(Guid storeId, CancellationToken ct)
    {
        var s = await db.TaskWorkspaceSettings.AsTracking().FirstOrDefaultAsync(x => x.StoreId == storeId, ct);
        if (s != null) return s;
        s = new TaskWorkspaceSetting { Id = Guid.NewGuid(), StoreId = storeId, CreatedAt = DateTime.UtcNow };
        db.TaskWorkspaceSettings.Add(s);
        return s;
    }

    static async Task<string> EnsureFolderAsync(DriveService drive, string name, string? parentId, CancellationToken ct)
    {
        var key = (parentId ?? "root") + "/" + name;
        if (FolderCache.TryGetValue(key, out var cached)) return cached;
        var list = drive.Files.List();
        var safe = name.Replace("\\", "\\\\").Replace("'", "\\'");
        list.Q = $"mimeType='application/vnd.google-apps.folder' and name='{safe}' and trashed=false" +
                 (parentId == null ? "" : $" and '{parentId}' in parents");
        list.Fields = "files(id)";
        var found = await list.ExecuteAsync(ct);
        var id = found.Files?.FirstOrDefault()?.Id;
        if (id == null)
        {
            var create = drive.Files.Create(new Google.Apis.Drive.v3.Data.File
            {
                Name = name,
                MimeType = "application/vnd.google-apps.folder",
                Parents = parentId == null ? null : [parentId],
            });
            create.Fields = "id";
            id = (await create.ExecuteAsync(ct)).Id;
        }
        FolderCache[key] = id;
        return id;
    }

    // ─── Lưu / đọc / xoá ──────────────────────────────────────────

    public sealed record Stored(string FilePath, string StorageKind, string? Warning);

    /// <summary>
    /// Lưu file của việc. Cửa hàng chọn Google Drive → «SBOX - Báo cáo công việc / yyyy-MM / Mã việc - Tên việc».
    /// </summary>
    async Task<Stored> SaveAsync(WorkTask task, Stream content, string fileName, string contentType, CancellationToken ct)
    {
        var settings = await db.TaskWorkspaceSettings.AsNoTracking().FirstOrDefaultAsync(x => x.StoreId == task.StoreId, ct);
        string? warning = null;
        if (settings?.PhotoStorage == "gdrive" && DriveConfigured)
        {
            var refresh = Unprotect(settings.DriveRefreshTokenEnc);
            if (refresh != null)
            {
                try
                {
                    using var buffer = new MemoryStream();
                    await content.CopyToAsync(buffer, ct);
                    buffer.Position = 0;
                    var drive = Service(refresh);
                    var root = settings.DriveRootFolderId ?? await EnsureFolderAsync(drive, RootFolderName, null, ct);
                    var month = await EnsureFolderAsync(drive, DateTime.UtcNow.AddHours(7).ToString("yyyy-MM"), root, ct);
                    var title = task.Title.Length > 60 ? task.Title[..60] : task.Title;
                    var folder = await EnsureFolderAsync(drive, $"{task.TaskCode} - {title}".Replace("/", "-"), month, ct);
                    var upload = drive.Files.Create(new Google.Apis.Drive.v3.Data.File { Name = fileName, Parents = [folder] }, buffer, contentType);
                    upload.Fields = "id";
                    var progress = await upload.UploadAsync(ct);
                    if (progress.Exception != null) throw progress.Exception;
                    return new Stored("gdrive://" + upload.ResponseBody.Id, "gdrive", null);
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    logger.LogWarning(ex, "Upload Google Drive lỗi — lưu máy chủ (store {Store})", task.StoreId);
                    await MarkDriveErrorAsync(task.StoreId, ex.Message, ct);
                    // Luồng đã đọc hết — SaveBytesAsync lưu lại máy chủ bằng dữ liệu gốc.
                    throw new DriveFallbackException("Google Drive lỗi — ảnh đã lưu tạm trên máy chủ.", ex);
                }
            }
            warning = "Kết nối Google Drive đã hết hạn — ảnh lưu trên máy chủ. Vào Thiết lập Công việc để kết nối lại.";
        }
        var path = await localStorage.UploadAsync(content, fileName, $"uploads/tasks/{task.StoreId:N}/{DateTime.UtcNow:yyyyMM}");
        return new Stored(path, "server", warning);
    }

    /// <summary>Lưu từ mảng byte (để Drive lỗi thì lưu lại máy chủ cùng dữ liệu).</summary>
    public async Task<Stored> SaveBytesAsync(WorkTask task, byte[] bytes, string fileName, string contentType, CancellationToken ct)
    {
        try
        {
            return await SaveAsync(task, new MemoryStream(bytes), fileName, contentType, ct);
        }
        catch (DriveFallbackException fb)
        {
            var path = await localStorage.UploadAsync(new MemoryStream(bytes), fileName, $"uploads/tasks/{task.StoreId:N}/{DateTime.UtcNow:yyyyMM}");
            return new Stored(path, "server", fb.Message);
        }
    }

    async Task MarkDriveErrorAsync(Guid storeId, string message, CancellationToken ct)
    {
        var s = await db.TaskWorkspaceSettings.AsTracking().FirstOrDefaultAsync(x => x.StoreId == storeId, ct);
        if (s == null) return;
        s.DriveLastError = message.Length > 490 ? message[..490] : message;
        await db.SaveChangesAsync(ct);
    }

    public async Task<(Stream Stream, string ContentType)?> OpenAsync(TaskAttachment a, Guid storeId, CancellationToken ct)
    {
        if (a.StorageKind != "gdrive" || !a.FilePath.StartsWith("gdrive://", StringComparison.Ordinal)) return null;
        var settings = await db.TaskWorkspaceSettings.AsNoTracking().FirstOrDefaultAsync(x => x.StoreId == storeId, ct);
        var refresh = Unprotect(settings?.DriveRefreshTokenEnc);
        if (refresh == null || !DriveConfigured) return null;
        var ms = new MemoryStream();
        await Service(refresh).Files.Get(a.FilePath["gdrive://".Length..]).DownloadAsync(ms, ct);
        ms.Position = 0;
        return (ms, a.ContentType ?? "application/octet-stream");
    }

    public async Task DeleteAsync(TaskAttachment a, Guid storeId, CancellationToken ct)
    {
        try
        {
            if (a.StorageKind == "gdrive" && a.FilePath.StartsWith("gdrive://", StringComparison.Ordinal))
            {
                var settings = await db.TaskWorkspaceSettings.AsNoTracking().FirstOrDefaultAsync(x => x.StoreId == storeId, ct);
                var refresh = Unprotect(settings?.DriveRefreshTokenEnc);
                if (refresh != null && DriveConfigured)
                    await Service(refresh).Files.Delete(a.FilePath["gdrive://".Length..]).ExecuteAsync(ct);
            }
            else
            {
                await localStorage.DeleteAsync(a.FilePath);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Không xoá được file {Path}", a.FilePath);
        }
    }

    /// <summary>Kiểm tra kết nối Drive: tạo + xoá một file nhỏ.</summary>
    public async Task<string?> TestDriveAsync(Guid storeId, CancellationToken ct)
    {
        var settings = await db.TaskWorkspaceSettings.AsNoTracking().FirstOrDefaultAsync(x => x.StoreId == storeId, ct);
        var refresh = Unprotect(settings?.DriveRefreshTokenEnc);
        if (refresh == null) return "Chưa kết nối Google Drive";
        try
        {
            var drive = Service(refresh);
            var root = settings!.DriveRootFolderId ?? await EnsureFolderAsync(drive, RootFolderName, null, ct);
            var up = drive.Files.Create(new Google.Apis.Drive.v3.Data.File { Name = "sbox-test.txt", Parents = [root] },
                new MemoryStream(Encoding.UTF8.GetBytes("SBOX test")), "text/plain");
            up.Fields = "id";
            var p = await up.UploadAsync(ct);
            if (p.Exception != null) throw p.Exception;
            await drive.Files.Delete(up.ResponseBody.Id).ExecuteAsync(ct);
            return null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            await MarkDriveErrorAsync(storeId, ex.Message, ct);
            return "Google Drive báo lỗi: " + ex.Message;
        }
    }
}

public sealed class DriveFallbackException(string message, Exception inner) : Exception(message, inner);
