namespace ZKTecoADMS.Domain.Enums;

public enum AttendanceStates
{
    CheckIn,
    CheckOut,
    MealIn,
    MealOut,
    BreakIn,
    BreakOut,
    /// <summary>Mobile: Bắt đầu đi (không tính vào giờ ca).</summary>
    TravelStart,
    /// <summary>Mobile: Đến điểm làm (không tính vào giờ ca).</summary>
    TravelArrive,
}