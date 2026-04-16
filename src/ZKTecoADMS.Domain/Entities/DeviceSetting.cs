using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities
;
public class DeviceSetting : Entity<Guid>
{

    public Guid DeviceId { get; set; }

    [Required]
    [MaxLength(100)]
    public string SettingKey { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? SettingValue { get; set; }

    [MaxLength(200)]
    public string? Description { get; set; }


    // Navigation Properties
    public virtual Device Device { get; set; } = null!;
}