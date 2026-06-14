using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Services;

/// <summary>
/// Tìm phòng ban theo tên; nếu chưa có thì tạo mới (dùng khi import Excel nhân sự).
/// </summary>
public static class DepartmentImportHelper
{
    public static async Task<Department?> ResolveOrCreateAsync(
        IRepository<Department> departmentRepository,
        Guid storeId,
        string? departmentName,
        CancellationToken cancellationToken = default)
    {
        var name = departmentName?.Trim();
        if (string.IsNullOrWhiteSpace(name)) return null;

        var existing = await departmentRepository.GetSingleAsync(
            d => d.StoreId == storeId && d.Name == name,
            cancellationToken: cancellationToken);
        if (existing != null) return existing;

        var allInStore = await departmentRepository.GetAllAsync(
            d => d.StoreId == storeId,
            cancellationToken: cancellationToken);
        existing = allInStore.FirstOrDefault(d =>
            string.Equals(d.Name, name, StringComparison.OrdinalIgnoreCase));
        if (existing != null) return existing;

        var code = await GenerateUniqueCodeAsync(
            departmentRepository, storeId, name, cancellationToken);

        var department = new Department
        {
            Id = Guid.NewGuid(),
            Code = code,
            Name = name,
            StoreId = storeId,
            Level = 0,
            HierarchyPath = "/",
            IsActive = true,
            DirectEmployeeCount = 0,
            TotalEmployeeCount = 0,
            SortOrder = 0,
        };

        await departmentRepository.AddAsync(department, cancellationToken);
        return department;
    }

    static async Task<string> GenerateUniqueCodeAsync(
        IRepository<Department> departmentRepository,
        Guid storeId,
        string name,
        CancellationToken cancellationToken)
    {
        var baseCode = ToDepartmentCode(name);
        var code = baseCode;
        var suffix = 1;

        while (await departmentRepository.ExistsAsync(
                   d => d.StoreId == storeId && d.Code == code,
                   cancellationToken))
        {
            var suffixText = suffix.ToString(CultureInfo.InvariantCulture);
            var maxBaseLen = Math.Max(2, 20 - suffixText.Length);
            var trimmedBase = baseCode.Length > maxBaseLen
                ? baseCode[..maxBaseLen]
                : baseCode;
            code = $"{trimmedBase}{suffixText}";
            suffix++;
        }

        return code;
    }

    static string ToDepartmentCode(string name)
    {
        var ascii = RemoveDiacritics(name).ToUpperInvariant();
        var slug = Regex.Replace(ascii, @"[^A-Z0-9]", "");
        if (slug.Length >= 2)
            return slug.Length <= 20 ? slug : slug[..20];

        var words = name.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (words.Length >= 2)
        {
            var initials = string.Concat(words.Take(4).Select(w =>
            {
                var c = RemoveDiacritics(w)
                    .Trim()
                    .FirstOrDefault(ch => char.IsLetterOrDigit(ch));
                return char.ToUpperInvariant(c);
            }));
            if (initials.Length >= 2)
                return initials.Length <= 20 ? initials : initials[..20];
        }

        var hash = Math.Abs(name.GetHashCode(StringComparison.Ordinal)) % 100000;
        return $"PB{hash:D5}";
    }

    static string RemoveDiacritics(string text)
    {
        var normalized = text.Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder(normalized.Length);
        foreach (var ch in normalized)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(ch) != UnicodeCategory.NonSpacingMark)
                builder.Append(ch);
        }

        return builder
            .ToString()
            .Normalize(NormalizationForm.FormC)
            .Replace('đ', 'd')
            .Replace('Đ', 'D');
    }
}
