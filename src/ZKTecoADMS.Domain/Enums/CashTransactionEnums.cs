namespace ZKTecoADMS.Domain.Enums;

/// <summary>
/// Loại giao dịch thu chi
/// </summary>
public enum CashTransactionType
{
    /// <summary>
    /// Thu (nhận tiền vào)
    /// </summary>
    Income = 1,
    
    /// <summary>
    /// Chi (chi tiền ra)
    /// </summary>
    Expense = 2
}

/// <summary>
/// Trạng thái giao dịch
/// </summary>
public enum CashTransactionStatus
{
    /// <summary>
    /// Chờ xử lý
    /// </summary>
    Pending = 1,
    
    /// <summary>
    /// Đã hoàn thành
    /// </summary>
    Completed = 2,
    
    /// <summary>
    /// Đã hủy
    /// </summary>
    Cancelled = 3,
    
    /// <summary>
    /// Chờ thanh toán (dùng cho VietQR)
    /// </summary>
    WaitingPayment = 4
}

/// <summary>
/// Phương thức thanh toán
/// </summary>
public enum PaymentMethodType
{
    /// <summary>
    /// Tiền mặt
    /// </summary>
    Cash = 1,
    
    /// <summary>
    /// Chuyển khoản ngân hàng
    /// </summary>
    BankTransfer = 2,
    
    /// <summary>
    /// VietQR
    /// </summary>
    VietQR = 3,
    
    /// <summary>
    /// Thẻ tín dụng/ghi nợ
    /// </summary>
    Card = 4,
    
    /// <summary>
    /// Ví điện tử (Momo, ZaloPay...)
    /// </summary>
    EWallet = 5,
    
    /// <summary>
    /// Khác
    /// </summary>
    Other = 99
}
