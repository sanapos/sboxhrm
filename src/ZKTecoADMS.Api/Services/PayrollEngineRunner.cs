using System.Diagnostics;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;

namespace ZKTecoADMS.Api.Services;

/// <summary>Cấu hình chương trình tính lương (src/payroll_engine — biên dịch trong Docker).</summary>
public sealed class PayrollEngineOptions
{
    public const string Section = "PayrollEngine";

    /// <summary>Đường dẫn file thực thi. Docker: /app/engine/payroll_engine.</summary>
    public string Path { get; set; } = "/app/engine/payroll_engine";

    /// <summary>Địa chỉ API nội bộ mà chương trình gọi lại (cùng container).</summary>
    public string BaseUrl { get; set; } = "http://127.0.0.1:7070";

    public int TimeoutSeconds { get; set; } = 180;

    /// <summary>Số bảng lương tính cùng lúc (bảo vệ máy chủ khi nhiều cửa hàng cùng mở).</summary>
    public int MaxConcurrent { get; set; } = 3;

    /// <summary>Múi giờ khi tính (ngày vắng, «hôm nay»…) — giống app người dùng.</summary>
    public string TimeZone { get; set; } = "Asia/Ho_Chi_Minh";
}

/// <summary>Đầu vào chương trình tính lương (stdin JSON — token không lên dòng lệnh).</summary>
public sealed record PayrollEngineInput(
    string Token,
    DateTime From,
    DateTime To,
    bool EmployeeRole = false,
    string? BranchId = null,
    string? HeadquarterId = null,
    string? BranchHeader = null,
    bool WithSnapshots = false,
    bool Finalize = false,
    IReadOnlyCollection<string>? EmployeeIds = null);

public sealed class PayrollEngineException(string message) : Exception(message);

/// <summary>
/// Tính bảng lương trên máy chủ bằng CÙNG công thức với app: chạy chương trình Dart payroll_engine,
/// chương trình tự nạp dữ liệu qua chính các API của hệ thống (bằng quyền người đang xem) rồi trả JSON.
/// </summary>
public sealed class PayrollEngineRunner(IOptions<PayrollEngineOptions> options, ILogger<PayrollEngineRunner> logger)
{
    readonly PayrollEngineOptions _opt = options.Value;
    static SemaphoreSlim? _gate;

    SemaphoreSlim Gate => LazyInitializer.EnsureInitialized(ref _gate, () => new SemaphoreSlim(Math.Max(1, _opt.MaxConcurrent)))!;

    public bool IsAvailable => File.Exists(_opt.Path);

    public async Task<JsonDocument> RunAsync(PayrollEngineInput input, CancellationToken ct)
    {
        if (!IsAvailable)
            throw new PayrollEngineException("Máy chủ chưa cài chương trình tính lương");

        if (!await Gate.WaitAsync(TimeSpan.FromSeconds(60), ct))
            throw new PayrollEngineException("Máy chủ đang tính nhiều bảng lương — vui lòng thử lại sau ít phút");
        try
        {
            var payload = JsonSerializer.Serialize(new
            {
                baseUrl = _opt.BaseUrl,
                token = input.Token,
                from = input.From.ToString("yyyy-MM-dd"),
                to = input.To.ToString("yyyy-MM-dd"),
                employeeRole = input.EmployeeRole,
                branchId = input.BranchId,
                headquarterId = input.HeadquarterId,
                branchHeader = input.BranchHeader,
                withSnapshots = input.WithSnapshots,
                finalize = input.Finalize,
                employeeIds = input.EmployeeIds,
            });

            var psi = new ProcessStartInfo(_opt.Path)
            {
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                StandardOutputEncoding = Encoding.UTF8,
                StandardInputEncoding = new UTF8Encoding(false),
            };
            psi.Environment["TZ"] = _opt.TimeZone;

            var sw = Stopwatch.StartNew();
            using var proc = Process.Start(psi) ?? throw new PayrollEngineException("Không chạy được chương trình tính lương");
            await proc.StandardInput.WriteAsync(payload);
            proc.StandardInput.Close();

            var stdoutTask = proc.StandardOutput.ReadToEndAsync(ct);
            var stderrTask = proc.StandardError.ReadToEndAsync(ct);
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeout.CancelAfter(TimeSpan.FromSeconds(_opt.TimeoutSeconds));
            try
            {
                await proc.WaitForExitAsync(timeout.Token);
            }
            catch (OperationCanceledException)
            {
                try { proc.Kill(entireProcessTree: true); } catch { /* đã thoát */ }
                throw new PayrollEngineException(ct.IsCancellationRequested
                    ? "Đã hủy tính lương"
                    : "Tính lương quá thời gian — thử lại hoặc chọn kỳ / chi nhánh nhỏ hơn");
            }

            var stdout = await stdoutTask;
            var stderr = await stderrTask;
            JsonDocument doc;
            try
            {
                doc = JsonDocument.Parse(stdout);
            }
            catch (JsonException)
            {
                logger.LogError("Payroll engine bad output (exit {Code}): {Err}", proc.ExitCode, Trim(stderr));
                throw new PayrollEngineException("Chương trình tính lương trả kết quả không hợp lệ");
            }

            if (!doc.RootElement.TryGetProperty("ok", out var ok) || ok.ValueKind != JsonValueKind.True)
            {
                var err = doc.RootElement.TryGetProperty("error", out var e) ? e.GetString() : null;
                logger.LogError("Payroll engine failed: {Err} {Stack}", err,
                    doc.RootElement.TryGetProperty("stack", out var s) ? s.GetString() : null);
                doc.Dispose();
                throw new PayrollEngineException("Tính lương thất bại: " + (err ?? "lỗi không rõ"));
            }

            logger.LogInformation("Payroll engine {From:yyyy-MM-dd}..{To:yyyy-MM-dd} done in {Ms} ms ({Req} API calls)",
                input.From, input.To, sw.ElapsedMilliseconds,
                doc.RootElement.TryGetProperty("requests", out var r) ? r.GetInt32() : 0);
            return doc;
        }
        finally
        {
            Gate.Release();
        }
    }

    static string Trim(string s) => s.Length > 2000 ? s[..2000] : s;

    static readonly JsonSerializerOptions Web = new(JsonSerializerDefaults.Web);

    /// <summary>Đầu vào theo request hiện tại: token + chi nhánh đang thao tác của người xem.</summary>
    public static PayrollEngineInput InputFor(
        HttpContext http, bool isEmployee, DateTime from, DateTime to, string? branchId = null, string? headquarterId = null)
    {
        var h = http.Request.Headers.Authorization.ToString();
        var token = h.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) ? h["Bearer ".Length..].Trim() : null;
        if (string.IsNullOrEmpty(token)) throw new PayrollEngineException("Thiếu phiên đăng nhập");
        return new PayrollEngineInput(
            Token: token,
            From: from.Date,
            To: to.Date,
            EmployeeRole: isEmployee,
            BranchId: string.IsNullOrWhiteSpace(branchId) ? null : branchId.Trim(),
            HeadquarterId: string.IsNullOrWhiteSpace(headquarterId) ? null : headquarterId.Trim(),
            BranchHeader: http.Request.Headers[ZKTecoADMS.Api.Middlewares.BranchContextMiddleware.HeaderName].FirstOrDefault());
    }

    /// <summary>Tính bảng lương và dựng yêu cầu chốt lương (số do máy chủ tính).</summary>
    public async Task<(ZKTecoADMS.Application.DTOs.Payslips.FinalizePayrollRequest Request, List<string> Skipped)> ComputeFinalizeAsync(
        PayrollEngineInput input, CancellationToken ct)
    {
        using var doc = await RunAsync(input with { Finalize = true }, ct);
        var fin = doc.RootElement.GetProperty("finalize");
        var request = fin.GetProperty("request").Deserialize<ZKTecoADMS.Application.DTOs.Payslips.FinalizePayrollRequest>(Web)
                      ?? throw new PayrollEngineException("Không dựng được yêu cầu chốt lương");
        var skipped = fin.GetProperty("skipped").Deserialize<List<string>>(Web) ?? [];
        return (request, skipped);
    }
}
