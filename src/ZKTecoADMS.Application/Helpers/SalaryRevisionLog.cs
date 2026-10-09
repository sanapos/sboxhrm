using System.Text.Json;
using ZKTecoADMS.Application.DTOs.Benefits;

namespace ZKTecoADMS.Application.Helpers;

/// <summary>Chụp hồ sơ lương (BenefitDto JSON) để ghi lịch sử trước khi sửa / thay.</summary>
public static class SalaryRevisionLog
{
    static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    /// <summary>Trường không phải nội dung lương — bỏ khi so sánh.</summary>
    static readonly string[] Noise = ["updatedAt", "createdAt", "updatedBy", "createdBy", "lastModified", "lastModifiedBy", "employeeCount"];

    public static string Snapshot(Benefit b) => JsonSerializer.Serialize(b.Adapt<BenefitDto>(), Json);

    /// <summary>Hai bản chụp có cùng nội dung lương (bỏ dấu thời gian / người sửa)?</summary>
    public static bool SameContent(string a, string b)
    {
        static string Norm(string s)
        {
            using var doc = JsonDocument.Parse(s);
            var parts = doc.RootElement.EnumerateObject()
                .Where(p => !Noise.Contains(p.Name, StringComparer.OrdinalIgnoreCase))
                .OrderBy(p => p.Name, StringComparer.Ordinal)
                .Select(p => p.Name + "=" + p.Value.GetRawText());
            return string.Join("|", parts);
        }
        return Norm(a) == Norm(b);
    }

    public static SalaryProfileRevision New(
        Guid? storeId, Guid? employeeId, Guid benefitId, EmployeeBenefit? version,
        string kind, string before, string? after, string? by) => new()
    {
        Id = Guid.NewGuid(),
        StoreId = storeId ?? Guid.Empty,
        EmployeeId = employeeId,
        BenefitId = benefitId,
        EmployeeBenefitId = version?.Id,
        Kind = kind,
        BeforeJson = before,
        AfterJson = after,
        EffectiveDate = version?.EffectiveDate,
        EndDate = version?.EndDate,
        CreatedAt = DateTime.UtcNow,
        CreatedBy = by,
        IsActive = true,
    };
}
