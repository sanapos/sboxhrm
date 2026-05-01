using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities
{
    public class ShiftTemplate : Entity<Guid>
    {
        public Guid ManagerId { get; set; }
        public ApplicationUser Manager { get; set; } = null!;
        
        [Required]
        public string Name { get; set; } = null!;
        
        public string? Code { get; set; }
        
        public TimeSpan StartTime { get; set; }
        public TimeSpan EndTime { get; set; }
        
        [Required]
        public int MaximumAllowedLateMinutes { get; set; } = 30;
        
        [Required]
        public int MaximumAllowedEarlyLeaveMinutes { get; set; } = 30;

        [Required]
        public int BreakTimeMinutes { get; set; } = 0;
        
        public int EarlyCheckInMinutes { get; set; } = 30;
        
        public int LateGraceMinutes { get; set; } = 5;
        
        public int EarlyLeaveGraceMinutes { get; set; } = 5;
        
        public int OvertimeMinutesThreshold { get; set; } = 30;
        
        /// <summary>
        /// Loại ca: HanhChinh, TangCa, QuaDem
        /// </summary>
        public string? ShiftType { get; set; }

        /// <summary>
        /// Giờ qua đêm: mốc thời gian kết thúc ca đêm (phải > EndTime)
        /// Ví dụ: Ca đêm 22:00-06:00, OvernightCutoffTime = 07:30
        /// </summary>
        public TimeSpan? OvernightCutoffTime { get; set; }
        
        public string? Description { get; set; }
        
        public bool IsActive { get; set; }
        
        /// <summary>
        /// Cửa hàng mà mẫu ca thuộc về
        /// </summary>
        public Guid? StoreId { get; set; }
        public virtual Store? Store { get; set; }
    }
}