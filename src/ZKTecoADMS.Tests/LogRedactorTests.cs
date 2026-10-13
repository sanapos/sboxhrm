using Xunit;
using ZKTecoADMS.Application.Behaviours;
using ZKTecoADMS.Application.Commands.Auth.Login;

namespace ZKTecoADMS.Tests;

public class LogRedactorTests
{
    [Fact]
    public void LoginCommand_password_and_device_key_are_masked()
    {
        var json = LogRedactor.Serialize(new LoginCommand("demopos", "demo@x.vn", "Secr3t!pw", "android", "dev-key-123", "C20Lite"));
        Assert.DoesNotContain("Secr3t!pw", json);
        Assert.DoesNotContain("dev-key-123", json);
        Assert.Contains("\"password\":\"***\"", json);
        // Trường thường vẫn còn để tra log.
        Assert.Contains("demopos", json);
        Assert.Contains("C20Lite", json);
    }

    record Nested(string Name, Inner Inner, List<Inner> Items);
    record Inner(string RefreshToken, string NewPassword, string Pin, string Note);

    [Fact]
    public void Nested_objects_and_arrays_are_masked()
    {
        var req = new Nested("x", new Inner("rt-1", "np-1", "1234", "keep"),
            [new Inner("rt-2", "np-2", "5678", "keep2")]);
        var json = LogRedactor.Serialize(req);
        foreach (var secret in new[] { "rt-1", "np-1", "1234", "rt-2", "np-2", "5678" })
            Assert.DoesNotContain(secret, json);
        Assert.Contains("keep2", json);
    }

    record Big(string Data);

    [Fact]
    public void Long_payload_is_truncated()
    {
        var json = LogRedactor.Serialize(new Big(new string('a', 20000)));
        Assert.True(json.Length < LogRedactor.MaxLength + 50);
    }

    [Theory]
    [InlineData("password", true)]
    [InlineData("Password", true)]
    [InlineData("confirm_password", true)]
    [InlineData("accessToken", true)]
    [InlineData("apiKey", true)]
    [InlineData("deviceKey", true)]
    [InlineData("pin", true)]
    [InlineData("otpCode", true)]
    [InlineData("userName", false)]
    [InlineData("storeCode", false)]
    [InlineData("pinned", false)]
    public void Sensitive_key_detection(string key, bool expected) =>
        Assert.Equal(expected, LogRedactor.IsSensitiveKey(key));
}
