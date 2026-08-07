namespace ZKTecoADMS.Domain.Enums;

/// <summary>Hồ sơ ngành — điều khiển UI bán hàng và tính năng phòng/bàn/ghế.</summary>
public enum PosSellProfile
{
    /// <summary>Bán lẻ / siêu thị (mặc định).</summary>
    Retail = 0,
    /// <summary>Salon / nail — ghế + dịch vụ.</summary>
    Salon = 1,
    /// <summary>Bi-a / karaoke — phòng/bàn tính giờ.</summary>
    RoomHourly = 2,
    /// <summary>F&amp;B — khu vực + bàn.</summary>
    Restaurant = 3,
    /// <summary>Gym — gói buổi / membership.</summary>
    Gym = 4,
}

/// <summary>Cách tính tiền dịch vụ.</summary>
public enum PosServiceBillingMode
{
    /// <summary>Giá cố định theo dòng (qty × giá).</summary>
    Flat = 0,
    /// <summary>Theo giờ (làm tròn theo BillRoundMinutes).</summary>
    PerHour = 1,
    /// <summary>Theo phút.</summary>
    PerMinute = 2,
    /// <summary>Theo buổi / session (gym, lớp).</summary>
    PerSession = 3,
}

/// <summary>Loại tài nguyên phục vụ (ghế / bàn / phòng).</summary>
public enum PosResourceKind
{
    Chair = 0,
    Table = 1,
    Room = 2,
    Other = 3,
}

/// <summary>Trạng thái phiên sử dụng tài nguyên.</summary>
public enum PosResourceSessionStatus
{
    Open = 0,
    Paused = 1,
    Closed = 2,
}

/// <summary>Đặt bàn trước — khách chưa đến.</summary>
public enum PosResourceReservationStatus
{
    Booked = 0,
    Seated = 1,
    Cancelled = 2,
    NoShow = 3,
}

/// <summary>Trạng thái cọc giữ chỗ khi đặt bàn/phòng.</summary>
public enum PosReservationDepositStatus
{
    None = 0,
    /// <summary>Đã thu, đang giữ.</summary>
    Held = 1,
    /// <summary>Đã trừ vào đơn khi nhận bàn.</summary>
    Applied = 2,
    /// <summary>Đã hoàn cọc.</summary>
    Refunded = 3,
    /// <summary>Mất cọc (hủy / NoShow).</summary>
    Forfeited = 4,
}

/// <summary>Loại giao dịch sổ buổi gym.</summary>
public enum PosSessionTxnType
{
    Purchase = 0,
    Redeem = 1,
    Adjust = 2,
    Expire = 3,
}
