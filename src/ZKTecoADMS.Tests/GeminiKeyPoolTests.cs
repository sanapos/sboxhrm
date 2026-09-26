using Xunit;
using ZKTecoADMS.Api.Services;

namespace ZKTecoADMS.Tests;

public class GeminiKeyPoolTests
{
    const string A = "AIzaAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1";
    const string B = "AIzaBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB2";
    const string C = "AIzaCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC3";

    [Fact]
    public void Parses_one_key_per_line_comma_or_semicolon_and_drops_duplicates()
    {
        Assert.Equal([A, B, C], GeminiKeyPool.Parse($" {A}\r\n{B}, {C};{A}\n\nshort"));
    }

    [Fact]
    public void Merge_appends_replaces_removes_and_ignores_masked_input()
    {
        var existing = GeminiKeyPool.Join([A, B]);
        // Thêm vào danh sách.
        Assert.Equal(GeminiKeyPool.Join([A, B, C]), GeminiKeyPool.Merge(existing, C, append: true, null));
        // Thay toàn bộ.
        Assert.Equal(C, GeminiKeyPool.Merge(existing, C, append: false, null));
        // Xóa theo mặt nạ hiển thị.
        Assert.Equal(B, GeminiKeyPool.Merge(existing, null, append: true, [GeminiKeyPool.Mask(A)]));
        // Mặt nạ gửi lại / không đổi → null (giữ nguyên, không ghi đè khóa thật bằng dấu *).
        Assert.Null(GeminiKeyPool.Merge(existing, GeminiKeyPool.Mask(A), append: false, null));
        Assert.Null(GeminiKeyPool.Merge(existing, "", append: false, null));
    }

    [Fact]
    public void Exhausted_keys_are_tried_last()
    {
        var keys = new[] { "AIzaKEY1xxxxxxxxxxxxxxxxxxxxxxxxxxxx" + Guid.NewGuid().ToString("N")[..4],
                           "AIzaKEY2xxxxxxxxxxxxxxxxxxxxxxxxxxxx" + Guid.NewGuid().ToString("N")[..4],
                           "AIzaKEY3xxxxxxxxxxxxxxxxxxxxxxxxxxxx" + Guid.NewGuid().ToString("N")[..4] };
        GeminiKeyPool.MarkExhausted(keys[0], TimeSpan.FromMinutes(5));
        Assert.Equal([1, 2, 0], GeminiKeyPool.OrderForUse(keys));
        Assert.True(GeminiKeyPool.IsCoolingDown(keys[0]));
        Assert.False(GeminiKeyPool.IsCoolingDown(keys[1]));
    }
}
