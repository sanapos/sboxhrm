using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;
// ZKTecoADMS.Domain/Entities/SystemConfiguration.cs
public class SystemConfiguration : Entity<Guid>
{
    [Required]
    [MaxLength(100)]
    public string ConfigKey { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? ConfigValue { get; set; }

    [MaxLength(200)]
    public string? Description { get; set; }

    /// <summary>
    /// Cửa hàng sở hữu cấu hình
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}