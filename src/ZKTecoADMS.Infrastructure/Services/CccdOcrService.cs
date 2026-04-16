using System.Globalization;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// OCR Service for Vietnamese CCCD (Citizen ID Card)
/// This implementation uses regex patterns to extract data from OCR text.
/// The actual OCR can be performed client-side (mobile) or via external API.
/// </summary>
public class CccdOcrService : IOcrService
{
    private readonly ILogger<CccdOcrService> _logger;

    public CccdOcrService(ILogger<CccdOcrService> logger)
    {
        _logger = logger;
    }

    public Task<CccdOcrResult> ExtractCccdDataAsync(Stream imageStream)
    {
        // This method is a placeholder for server-side OCR
        // For production, integrate with Google Vision API, Azure Computer Vision, or Tesseract
        // Currently, we recommend using client-side OCR (Flutter) and sending text to parse
        
        return Task.FromResult(new CccdOcrResult
        {
            IsSuccess = false,
            ErrorMessage = "Server-side OCR not implemented. Please use client-side OCR and call /api/upload/parse-cccd-text"
        });
    }

    /// <summary>
    /// Parse CCCD data from OCR text extracted by client (mobile OCR libraries like Google ML Kit)
    /// </summary>
    public CccdOcrResult ParseCccdText(string ocrText)
    {
        if (string.IsNullOrWhiteSpace(ocrText))
        {
            return new CccdOcrResult
            {
                IsSuccess = false,
                ErrorMessage = "OCR text is empty"
            };
        }

        try
        {
            var result = new CccdOcrResult
            {
                IsSuccess = true,
                RawText = ocrText
            };

            // Normalize text
            var text = ocrText.ToUpper();
            var lines = text.Split(new[] { '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries)
                           .Select(l => l.Trim())
                           .Where(l => !string.IsNullOrEmpty(l))
                           .ToList();

            // Extract ID Number (12 digits for new CCCD, 9 or 12 for old CMND)
            var idPattern = new Regex(@"\b(\d{12}|\d{9})\b");
            var idMatch = idPattern.Match(text);
            if (idMatch.Success)
            {
                result.IdNumber = idMatch.Groups[1].Value;
            }

            // Extract Full Name (look for "Họ và tên" or similar patterns)
            result.FullName = ExtractFieldValue(lines, new[] { "HỌ VÀ TÊN", "HO VA TEN", "FULL NAME", "HỌ TÊN" });

            // Extract Date of Birth
            var dobString = ExtractFieldValue(lines, new[] { "NGÀY SINH", "NGAY SINH", "DATE OF BIRTH", "SINH" });
            if (!string.IsNullOrEmpty(dobString))
            {
                result.DateOfBirth = ParseVietnameseDate(dobString);
            }

            // Extract Gender
            var genderText = ExtractFieldValue(lines, new[] { "GIỚI TÍNH", "GIOI TINH", "SEX" });
            if (!string.IsNullOrEmpty(genderText))
            {
                result.Gender = genderText.Contains("NAM") || genderText.Contains("MALE") ? "Nam" : "Nữ";
            }

            // Extract Nationality
            result.Nationality = ExtractFieldValue(lines, new[] { "QUỐC TỊCH", "QUOC TICH", "NATIONALITY" });
            if (string.IsNullOrEmpty(result.Nationality) && text.Contains("VIỆT NAM"))
            {
                result.Nationality = "Việt Nam";
            }

            // Extract Place of Origin
            result.PlaceOfOrigin = ExtractFieldValue(lines, new[] { "QUÊ QUÁN", "QUE QUAN", "PLACE OF ORIGIN" });

            // Extract Place of Residence
            result.PlaceOfResidence = ExtractFieldValue(lines, new[] { "NƠI THƯỜNG TRÚ", "NOI THUONG TRU", "PLACE OF RESIDENCE", "THƯỜNG TRÚ" });

            // Extract Issue Date
            var issueDateString = ExtractFieldValue(lines, new[] { "NGÀY CẤP", "NGAY CAP", "DATE OF ISSUE" });
            if (!string.IsNullOrEmpty(issueDateString))
            {
                result.IssueDate = ParseVietnameseDate(issueDateString);
            }

            // Extract Expiry Date
            var expiryDateString = ExtractFieldValue(lines, new[] { "CÓ GIÁ TRỊ ĐẾN", "CO GIA TRI DEN", "DATE OF EXPIRY", "HẾT HẠN" });
            if (!string.IsNullOrEmpty(expiryDateString))
            {
                result.ExpiryDate = ParseVietnameseDate(expiryDateString);
            }

            // Extract Issue Place
            result.IssuePlace = ExtractFieldValue(lines, new[] { "NƠI CẤP", "NOI CAP" });
            if (string.IsNullOrEmpty(result.IssuePlace))
            {
                // Default for new CCCD
                result.IssuePlace = "Cục Cảnh sát QLHC về TTXH";
            }

            _logger.LogInformation("CCCD OCR parsed successfully. ID: {IdNumber}, Name: {FullName}", 
                result.IdNumber, result.FullName);

            return result;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to parse CCCD text");
            return new CccdOcrResult
            {
                IsSuccess = false,
                ErrorMessage = $"Failed to parse CCCD: {ex.Message}",
                RawText = ocrText
            };
        }
    }

    private string? ExtractFieldValue(List<string> lines, string[] fieldNames)
    {
        foreach (var fieldName in fieldNames)
        {
            // Try to find line containing field name
            var matchingLine = lines.FirstOrDefault(l => l.Contains(fieldName, StringComparison.OrdinalIgnoreCase));
            if (matchingLine != null)
            {
                // Extract value after the field name or colon
                var colonIndex = matchingLine.IndexOf(':');
                if (colonIndex >= 0)
                {
                    var value = matchingLine.Substring(colonIndex + 1).Trim();
                    if (!string.IsNullOrEmpty(value))
                        return CleanText(value);
                }

                // Try to get the next line as the value
                var lineIndex = lines.IndexOf(matchingLine);
                if (lineIndex < lines.Count - 1)
                {
                    var nextLine = lines[lineIndex + 1];
                    // Make sure next line is not another field
                    if (!ContainsFieldName(nextLine))
                    {
                        return CleanText(nextLine);
                    }
                }

                // Try to extract from same line after field name
                var fieldIndex = matchingLine.IndexOf(fieldName, StringComparison.OrdinalIgnoreCase);
                if (fieldIndex >= 0)
                {
                    var afterField = matchingLine.Substring(fieldIndex + fieldName.Length).Trim();
                    if (afterField.StartsWith(":"))
                        afterField = afterField.Substring(1).Trim();
                    if (!string.IsNullOrEmpty(afterField))
                        return CleanText(afterField);
                }
            }
        }
        return null;
    }

    private bool ContainsFieldName(string text)
    {
        var fieldNames = new[] { "HỌ", "TÊN", "NGÀY", "GIỚI", "QUỐC", "QUÊ", "NƠI", "CẤP", "GIÁ TRỊ" };
        return fieldNames.Any(f => text.Contains(f, StringComparison.OrdinalIgnoreCase));
    }

    private string CleanText(string text)
    {
        // Remove common OCR artifacts and normalize
        text = text.Trim();
        text = Regex.Replace(text, @"[|]", "");
        text = Regex.Replace(text, @"\s+", " ");
        return text;
    }

    private DateTime? ParseVietnameseDate(string dateString)
    {
        if (string.IsNullOrWhiteSpace(dateString))
            return null;

        // Clean the date string
        dateString = Regex.Replace(dateString, @"[^0-9/\-.]", "");

        // Common Vietnamese date formats
        var formats = new[]
        {
            "dd/MM/yyyy",
            "d/M/yyyy",
            "dd-MM-yyyy",
            "d-M-yyyy",
            "dd.MM.yyyy",
            "ddMMyyyy"
        };

        foreach (var format in formats)
        {
            if (DateTime.TryParseExact(dateString, format, 
                CultureInfo.InvariantCulture, DateTimeStyles.None, out var date))
            {
                return date;
            }
        }

        // Try to extract and parse individual components
        var match = Regex.Match(dateString, @"(\d{1,2})[/\-.]?(\d{1,2})[/\-.]?(\d{4})");
        if (match.Success)
        {
            if (int.TryParse(match.Groups[1].Value, out var day) &&
                int.TryParse(match.Groups[2].Value, out var month) &&
                int.TryParse(match.Groups[3].Value, out var year))
            {
                try
                {
                    return new DateTime(year, month, day);
                }
                catch { }
            }
        }

        return null;
    }
}
