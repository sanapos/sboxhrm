using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Khách (hội viên gym) được đăng ký lên máy chấm công với PIN riêng — tách biệt nhân viên.
/// Lượt quét của PIN này ghi vào <see cref="PosGymVisit"/>, không vào chấm công.
/// </summary>
public class PosGymMemberDevice : AuditableEntity<Guid>
{
    /// <summary>PIN hội viên trên máy: dải 8 chữ số bắt đầu bằng 9 (90000001…) để không đụng PIN nhân viên.</summary>
    public const long PinRangeStart = 90_000_001L;
    public const long PinRangeEnd = 99_999_999L;

    public static bool IsMemberPin(string? pin) =>
        long.TryParse(pin, out var n) && n >= PinRangeStart && n <= PinRangeEnd;

    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public Guid CustomerId { get; set; }
    public virtual PosCustomer? Customer { get; set; }

    public Guid DeviceId { get; set; }
    public virtual Device? Device { get; set; }

    /// <summary>Bản ghi người dùng trên máy (DeviceUsers) — để xóa / lấy vân tay, khuôn mặt.</summary>
    public Guid? DeviceUserId { get; set; }

    public string Pin { get; set; } = string.Empty;
    public string? CardNumber { get; set; }

    /// <summary>Đã đẩy thông báo «hết hạn» lên máy cho PIN này (máy ở cửa, chế độ máy chủ mở cửa).</summary>
    public bool AccessBlocked { get; set; }
    public DateTime? AccessSyncedAt { get; set; }
}

/// <summary>Một lượt tập: vào (quét lần đầu) → ra (quét lần sau). Trừ buổi tối đa 1 lần / ngày.</summary>
public class PosGymVisit : AuditableEntity<Guid>
{
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public Guid CustomerId { get; set; }
    public virtual PosCustomer? Customer { get; set; }

    public Guid? DeviceId { get; set; }
    public string? Pin { get; set; }

    /// <summary>UTC.</summary>
    public DateTime CheckInAt { get; set; }
    /// <summary>UTC.</summary>
    public DateTime? CheckOutAt { get; set; }
    public int? DurationMinutes { get; set; }

    /// <summary>Thẻ / gói dùng cho lượt này (null nếu khách không còn gói hợp lệ).</summary>
    public Guid? BalanceId { get; set; }
    public string? PackageName { get; set; }
    /// <summary>Đã trừ 1 buổi ở lượt này.</summary>
    public bool SessionDeducted { get; set; }
    /// <summary>Ok / NoPackage / Expired / OutOfSessions.</summary>
    public string Status { get; set; } = "Ok";
    /// <summary>Device / Manual.</summary>
    public string Source { get; set; } = "Device";
    public string? Note { get; set; }
}

/// <summary>Phiếu đánh giá thể trạng hội viên do PT ghi (cân nặng, mỡ, cơ, vòng eo, nhận xét / mục tiêu).</summary>
public class PosGymAssessment : AuditableEntity<Guid>
{
    public Guid StoreId { get; set; }
    public Guid CustomerId { get; set; }
    public virtual PosCustomer? Customer { get; set; }

    public Guid? TrainerEmployeeId { get; set; }
    public string? TrainerName { get; set; }

    /// <summary>UTC.</summary>
    public DateTime AssessedAt { get; set; }
    public decimal? WeightKg { get; set; }
    public decimal? HeightCm { get; set; }
    public decimal? BodyFatPercent { get; set; }
    public decimal? MuscleKg { get; set; }
    public decimal? WaistCm { get; set; }
    public decimal? ChestCm { get; set; }
    public decimal? HipCm { get; set; }
    public decimal? ArmCm { get; set; }
    public decimal? ThighCm { get; set; }
    /// <summary>0 = đo thể trạng định kỳ; 1 = đánh giá sau buổi tập.</summary>
    public int Kind { get; set; }
    /// <summary>Điểm buổi tập 1–5 (phiếu sau buổi).</summary>
    public int? Rating { get; set; }
    /// <summary>Lượt tập được đánh giá (phiếu sau buổi).</summary>
    public Guid? VisitId { get; set; }
    /// <summary>Tình trạng / chấn thương / nhận xét của PT.</summary>
    public string? Condition { get; set; }
    /// <summary>Mục tiêu tập (giảm mỡ, tăng cơ…).</summary>
    public string? Goal { get; set; }
}

/// <summary>Phác đồ / giáo án tập PT giao cho hội viên (hiện trên link chia sẻ của hội viên).</summary>
public class PosGymWorkoutPlan : AuditableEntity<Guid>
{
    public Guid StoreId { get; set; }
    public Guid CustomerId { get; set; }
    public virtual PosCustomer? Customer { get; set; }

    public Guid? TrainerEmployeeId { get; set; }
    public string? TrainerName { get; set; }

    public string Title { get; set; } = string.Empty;
    /// <summary>Nội dung phác đồ: bài tập, số hiệp × lần, lịch tuần, dinh dưỡng…</summary>
    public string? Content { get; set; }
    /// <summary>Ngày bắt đầu áp dụng (UTC, chỉ dùng phần ngày).</summary>
    public DateTime? StartDate { get; set; }
}
