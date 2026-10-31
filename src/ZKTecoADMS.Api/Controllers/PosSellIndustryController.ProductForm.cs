using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosSellIndustryController
{
    /// <param name="Preset">Ngành chi tiết của form (grocery, pharmacy, electronics, fashion, food…).</param>
    /// <param name="Sections">Các mục bật trên form thêm/sửa hàng.</param>
    public record ProductFormLayoutDto(string? Preset, List<string>? Sections);

    /// <summary>
    /// Bộ mục form hàng hóa của CẢ cửa hàng (ExtraJson.productForm). Trước lưu riêng từng máy:
    /// chủ quán chỉnh trên máy tính, nhân viên mở trên điện thoại vẫn thấy form khác.
    /// Người được sửa hàng hóa là chỉnh được — không cần quyền thiết lập cửa hàng.
    /// </summary>
    [HttpPut("product-form-layout")]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "PosProducts", "SettingsHub")]
    public async Task<ActionResult<AppResponse<ProductFormLayoutDto>>> SaveProductFormLayout(
        [FromBody] ProductFormLayoutDto dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<ProductFormLayoutDto>.Fail("Thiếu cửa hàng"));

        var s = await db.PosStoreSellSettings.AsTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null);
        if (s == null)
        {
            s = PosServiceBillingHelper.CreateDefault(storeId, CurrentUserEmail);
            db.PosStoreSellSettings.Add(s);
        }

        var preset = (dto.Preset ?? "").Trim();
        var sections = (dto.Sections ?? [])
            .Select(x => x.Trim())
            .Where(x => x.Length is > 0 and <= 40)
            .Distinct(StringComparer.Ordinal)
            .Take(40)
            .ToList();
        s.ExtraJson = MergeProductFormLayout(s.ExtraJson, preset.Length > 40 ? preset[..40] : preset, sections);
        s.UpdatedAt = DateTime.UtcNow;
        s.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        return Ok(AppResponse<ProductFormLayoutDto>.Success(new ProductFormLayoutDto(preset, sections)));
    }

    internal static string MergeProductFormLayout(string? extraJson, string preset, List<string> sections)
    {
        JsonObject root;
        try
        {
            root = string.IsNullOrWhiteSpace(extraJson)
                ? new JsonObject()
                : JsonNode.Parse(extraJson) as JsonObject ?? new JsonObject();
        }
        catch (System.Text.Json.JsonException)
        {
            root = new JsonObject();
        }
        root.Remove("ProductForm");
        var arr = new JsonArray();
        foreach (var x in sections) arr.Add(x);
        root["productForm"] = new JsonObject { ["preset"] = preset, ["sections"] = arr };
        return root.ToJsonString();
    }
}
