using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Trang nội dung ứng dụng: Điều khoản sử dụng, Chính sách bảo mật, Trợ giúp.
/// Type: "terms" | "privacy" | "help"
/// </summary>
public class AppPage : Entity<Guid>
{
    [Required]
    [MaxLength(30)]
    public string Type { get; set; } = string.Empty;   // terms | privacy | help

    [Required]
    [MaxLength(200)]
    public string Title { get; set; } = string.Empty;

    [MaxLength(100000)]
    public string? Content { get; set; }               // Markdown / plain text

    public bool IsPublished { get; set; } = true;

    [MaxLength(200)]
    public string? UpdatedByName { get; set; }
}
