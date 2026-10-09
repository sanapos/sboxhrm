namespace ZKTecoADMS.Domain.Enums;

public enum PosSerialStatus
{
    InStock = 0,
    Sold = 1,
    /// <summary>Đã ra khỏi kho bán: hủy phiếu nhập, trả nhà cung cấp, thu hồi máy lỗi.</summary>
    Removed = 2,
    /// <summary>Kiểm kho không tìm thấy máy.</summary>
    Missing = 3,
}

public enum PosSerialCountStatus
{
    InProgress = 0,
    Completed = 1,
    Cancelled = 2,
}

public enum PosSerialScanResult
{
    /// <summary>Quét trúng máy đang trong kho thuộc phạm vi kiểm.</summary>
    Matched = 0,
    /// <summary>Mã không có trong sổ seri.</summary>
    Unknown = 1,
    /// <summary>Máy có trong sổ nhưng không ở trạng thái trong kho (đã bán / đã xuất).</summary>
    NotInStock = 2,
    /// <summary>Máy ngoài phạm vi phiếu kiểm (khác mặt hàng).</summary>
    OutOfScope = 3,
    /// <summary>Máy từng bị ghi nhận thiếu nay quét thấy lại.</summary>
    Recovered = 4,
}

public enum PosWarrantyClaimType
{
    Note = 0,
    Repair = 1,
    Replace = 2,
}

public enum PosWarrantyClaimStatus
{
    Received = 0,
    Processing = 1,
    Done = 2,
    Rejected = 3,
}

public enum PosWarrantyStatus
{
    Active = 0,
    Returned = 1,
    Voided = 2,
    Replaced = 3,
}
