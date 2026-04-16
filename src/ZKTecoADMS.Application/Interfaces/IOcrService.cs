namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Interface for OCR (Optical Character Recognition) service
/// </summary>
public interface IOcrService
{
    /// <summary>
    /// Extract text and data from Vietnamese CCCD (Citizen ID Card) image
    /// </summary>
    Task<CccdOcrResult> ExtractCccdDataAsync(Stream imageStream);
}

/// <summary>
/// Result from CCCD OCR extraction
/// </summary>
public class CccdOcrResult
{
    public bool IsSuccess { get; set; }
    public string? ErrorMessage { get; set; }
    
    // Basic Info
    public string? IdNumber { get; set; }          // Số CCCD
    public string? FullName { get; set; }          // Họ và tên
    public DateTime? DateOfBirth { get; set; }     // Ngày sinh
    public string? Gender { get; set; }            // Giới tính
    public string? Nationality { get; set; }       // Quốc tịch
    public string? PlaceOfOrigin { get; set; }     // Quê quán
    public string? PlaceOfResidence { get; set; }  // Nơi thường trú
    
    // Issue Info
    public DateTime? IssueDate { get; set; }       // Ngày cấp
    public DateTime? ExpiryDate { get; set; }      // Ngày hết hạn
    public string? IssuePlace { get; set; }        // Nơi cấp
    
    // Raw extracted text for debugging
    public string? RawText { get; set; }
}
