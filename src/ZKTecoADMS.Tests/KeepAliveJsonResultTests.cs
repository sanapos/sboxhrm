using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Abstractions;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Tests;

[Collection(nameof(KeepAliveJsonResultTests))]
public class KeepAliveJsonResultTests
{
    static (ActionContext ctx, MemoryStream body) NewContext()
    {
        var services = new ServiceCollection().AddLogging();
        services.AddControllers();
        var http = new DefaultHttpContext { RequestServices = services.BuildServiceProvider() };
        var body = new MemoryStream();
        http.Response.Body = body;
        return (new ActionContext(http, new RouteData(), new ActionDescriptor()), body);
    }

    [Fact]
    public async Task Slow_work_sends_spaces_then_parsable_json()
    {
        KeepAliveJsonResult.FirstByteAfter = TimeSpan.FromMilliseconds(40);
        KeepAliveJsonResult.Interval = TimeSpan.FromMilliseconds(20);
        try
        {
            var (ctx, body) = NewContext();
            var result = KeepAliveJsonResult.For<AppResponse<string>>(async () =>
            {
                await Task.Delay(250);
                return new OkObjectResult(AppResponse<string>.Fail("AI lỗi"));
            });
            await result.ExecuteResultAsync(ctx);

            var text = Encoding.UTF8.GetString(body.ToArray());
            Assert.Equal(200, ctx.HttpContext.Response.StatusCode);
            Assert.StartsWith(" ", text);
            Assert.True(text.TakeWhile(c => c == ' ').Count() >= 3);
            using var doc = JsonDocument.Parse(text);
            Assert.False(doc.RootElement.GetProperty("isSuccess").GetBoolean());
            Assert.Equal("AI lỗi", doc.RootElement.GetProperty("message").GetString());
        }
        finally
        {
            KeepAliveJsonResult.FirstByteAfter = TimeSpan.FromSeconds(15);
            KeepAliveJsonResult.Interval = TimeSpan.FromSeconds(10);
        }
    }

    [Fact]
    public async Task Fast_work_keeps_status_code_and_no_padding()
    {
        var (ctx, body) = NewContext();
        var result = KeepAliveJsonResult.For<AppResponse<string>>(() =>
            Task.FromResult<ActionResult<AppResponse<string>>>(new BadRequestObjectResult(AppResponse<string>.Fail("Chọn ảnh"))));
        await result.ExecuteResultAsync(ctx);

        Assert.Equal(400, ctx.HttpContext.Response.StatusCode);
        Assert.StartsWith("{", Encoding.UTF8.GetString(body.ToArray()));
    }
}
