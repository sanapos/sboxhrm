using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Infrastructure;
using Microsoft.Extensions.Options;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Api.Controllers.Base;

/// <summary>
/// Kết quả JSON cho lời gọi chờ AI lâu (đọc menu / hóa đơn / mẫu Word, tới 150 giây).
/// nginx production cắt <c>/api/</c> khi 60 giây không nhận byte nào từ API → app nhận trang 504 HTML,
/// không đọc được («Lỗi xử lý dữ liệu (504)»). Xong trong <see cref="FirstByteAfter"/> → trả như thường (giữ mã lỗi 400…);
/// lâu hơn → gửi 200 + một dấu cách mỗi <see cref="Interval"/> (JSON cho phép khoảng trắng đầu), xong mới ghi nội dung.
/// Lỗi phát sinh sau khi đã gửi đầu trả về dạng <c>{"isSuccess":false,…}</c> như các lỗi khác của AI.
/// </summary>
public sealed class KeepAliveJsonResult(Func<Task<IActionResult>> work) : ActionResult
{
    public static TimeSpan FirstByteAfter { get; set; } = TimeSpan.FromSeconds(15);
    public static TimeSpan Interval { get; set; } = TimeSpan.FromSeconds(10);

    static readonly byte[] Space = " "u8.ToArray();

    public static KeepAliveJsonResult For<T>(Func<Task<ActionResult<T>>> work) =>
        new(async () => ((IConvertToActionResult)await work()).Convert());

    public override async Task ExecuteResultAsync(ActionContext context)
    {
        var http = context.HttpContext;
        var aborted = http.RequestAborted;
        var task = work();
        if (await Task.WhenAny(task, Task.Delay(FirstByteAfter, aborted)) == task || aborted.IsCancellationRequested)
        {
            await (await task).ExecuteResultAsync(context);
            return;
        }

        var res = http.Response;
        res.StatusCode = StatusCodes.Status200OK;
        res.ContentType = "application/json; charset=utf-8";
        res.Headers.CacheControl = "no-cache";
        res.Headers["X-Accel-Buffering"] = "no";
        try
        {
            do
            {
                await res.Body.WriteAsync(Space, aborted);
                await res.Body.FlushAsync(aborted);
            } while (await Task.WhenAny(task, Task.Delay(Interval, aborted)) != task);
        }
        catch (Exception ex) when (ex is OperationCanceledException or IOException)
        {
            return; // máy khách đã đóng kết nối
        }

        object? value;
        try
        {
            value = await task switch
            {
                ObjectResult o => o.Value,
                var r => AppResponse<object>.Fail(r is IStatusCodeActionResult { StatusCode: int c } ? $"Lỗi máy chủ (mã {c})" : "Lỗi máy chủ"),
            };
        }
        catch (Exception ex)
        {
            http.RequestServices.GetRequiredService<ILogger<KeepAliveJsonResult>>()
                .LogError(ex, "Long AI request failed after keep-alive started: {Path}", http.Request.Path);
            value = AppResponse<object>.Fail("Lỗi máy chủ khi đọc bằng AI — vui lòng thử lại.");
        }

        var options = http.RequestServices.GetRequiredService<IOptions<JsonOptions>>().Value.JsonSerializerOptions;
        try
        {
            await JsonSerializer.SerializeAsync(res.Body, value, value?.GetType() ?? typeof(object), options, aborted);
        }
        catch (Exception ex) when (ex is OperationCanceledException or IOException)
        {
        }
    }
}
