namespace ZKTecoADMS.Application.Constants;

public static class ClockResponses
{
    public const string Ok = "OK";

    public const string Fail = "FAIL";
}

/// <summary>
/// Represents the query response codes returned from ZKTeco device
/// </summary>
public enum ClockQueryResponses
{
    /// <summary>
    /// The query executed successfully without error
    /// </summary>
    Success = 0,

    /// <summary>
    /// Parameter error, Database Not initialized
    /// </summary>
    ParameterError = -1,

    /// <summary>
    /// Wrong operation
    /// </summary>
    WrongOperation = -2,

    /// <summary>
    /// Access error, Flash I/O Error
    /// </summary>
    AccessError = -3,

    /// <summary>
    /// No matched data found
    /// </summary>
    NoMatchedData = -4,

    /// <summary>
    /// No more space available
    /// </summary>
    NoMoreSpace = -5,

    /// <summary>
    /// Data is not valid
    /// </summary>
    InvalidData = -6,

    /// <summary>
    /// The size of the fingerprint template does not match the specified "Size"
    /// </summary>
    FingerprintTemplateSizeMismatch = -9,

    /// <summary>
    /// The user specified by "PIN" does not exist
    /// </summary>
    UserNotFound = -10,

    /// <summary>
    /// Invalid fingerprint template format
    /// </summary>
    InvalidFingerprintFormat = -11,

    /// <summary>
    /// Invalid fingerprint template
    /// </summary>
    InvalidFingerprintTemplate = -12,

    /// <summary>
    /// Unknown command
    /// </summary>
    UnknownCommand = -22
}

/// <summary>
/// Extension methods for ClockQueryResponses enum
/// </summary>
public static class ClockQueryResponsesExtensions
{
    /// <summary>
    /// Determines whether the query execution was successful
    /// </summary>
    /// <param name="response">The query response to check</param>
    /// <returns>True if the query was successful, false otherwise</returns>
    public static bool IsSuccess(this ClockQueryResponses response) => response == ClockQueryResponses.Success;

    /// <summary>
    /// Gets a human-readable description of the query response
    /// </summary>
    /// <param name="response">The query response</param>
    /// <returns>A string describing the response</returns>
    public static string GetDescription(this ClockQueryResponses response)
    {
        return response switch
        {
            ClockQueryResponses.Success => "Query executed successfully",
            ClockQueryResponses.ParameterError => "Parameter error: Database not initialized",
            ClockQueryResponses.WrongOperation => "Wrong operation",
            ClockQueryResponses.AccessError => "Access error: Flash I/O Error",
            ClockQueryResponses.NoMatchedData => "No matched data found",
            ClockQueryResponses.NoMoreSpace => "No more space available",
            ClockQueryResponses.InvalidData => "Data is not valid",
            ClockQueryResponses.FingerprintTemplateSizeMismatch => "Fingerprint template size does not match the specified Size",
            ClockQueryResponses.UserNotFound => "User specified by PIN does not exist",
            ClockQueryResponses.InvalidFingerprintFormat => "Invalid fingerprint template format",
            ClockQueryResponses.InvalidFingerprintTemplate => "Invalid fingerprint template",
            ClockQueryResponses.UnknownCommand => "Unknown command",
            _ => $"Unknown response code: {response}"
        };
    }
}

/// <summary>
/// Represents the result codes returned from ZKTeco device commands
/// </summary>
public enum ClockCommandResponses
{
    /// <summary>
    /// The command executed successfully without error
    /// </summary>
    Success = 0,

    /// <summary>
    /// Parameter error, Database Not initialized
    /// </summary>
    ParameterError = -1,

    /// <summary>
    /// Wrong operation
    /// </summary>
    WrongOperation = -2,

    /// <summary>
    /// Access error, Flash I/O Error
    /// </summary>
    AccessError = -3,

    /// <summary>
    /// No matched data found
    /// </summary>
    NoMatchedData = -4,

    /// <summary>
    /// No more space available
    /// </summary>
    NoMoreSpace = -5,

    /// <summary>
    /// Data is not valid
    /// </summary>
    InvalidData = -6,

    /// <summary>
    /// The size of the fingerprint template does not match the specified "Size"
    /// </summary>
    FingerprintTemplateSizeMismatch = -9,

    /// <summary>
    /// The user specified by "PIN" does not exist
    /// </summary>
    UserNotFound = -10,

    /// <summary>
    /// Invalid fingerprint template format
    /// </summary>
    InvalidFingerprintFormat = -11,

    /// <summary>
    /// Invalid fingerprint template
    /// </summary>
    InvalidFingerprintTemplate = -12,

    /// <summary>
    /// Unknown command
    /// </summary>
    UnknownCommand = -22,

    /// <summary>
    /// Enrollment timeout - user not at device camera/sensor within time limit
    /// </summary>
    EnrollmentTimeout = -1003
}


/// <summary>
/// Extension methods for ClockCommandResponses enum
/// </summary>
public static class ClockCommandResponsesExtensions
{
    /// <summary>
    /// Determines whether the command execution was successful
    /// </summary>
    /// <param name="result">The command result to check</param>
    /// <returns>True if the command was successful, false otherwise</returns>
    public static bool IsSuccess(this ClockCommandResponses result) => result == ClockCommandResponses.Success;

    /// <summary>
    /// Gets a human-readable description of the command result
    /// </summary>
    /// <param name="result">The command result</param>
    /// <returns>A string describing the result</returns>
    public static string GetDescription(this ClockCommandResponses result)
    {
        return result switch
        {
            ClockCommandResponses.Success => "Command executed successfully",
            ClockCommandResponses.ParameterError => "Parameter error: Database not initialized",
            ClockCommandResponses.WrongOperation => "Wrong operation",
            ClockCommandResponses.AccessError => "Access error: Flash I/O Error",
            ClockCommandResponses.NoMatchedData => "No matched data found",
            ClockCommandResponses.NoMoreSpace => "No more space available",
            ClockCommandResponses.InvalidData => "Data is not valid",
            ClockCommandResponses.FingerprintTemplateSizeMismatch => "Fingerprint template size mismatch",
            ClockCommandResponses.UserNotFound => "User not found",
            ClockCommandResponses.InvalidFingerprintFormat => "Invalid fingerprint template format",
            ClockCommandResponses.InvalidFingerprintTemplate => "Invalid fingerprint template",
            ClockCommandResponses.UnknownCommand => "Unknown command",
            ClockCommandResponses.EnrollmentTimeout => "Hết thời gian đăng ký - vui lòng đứng trước camera/máy chấm công và thử lại",
            _ => $"Unknown result code: {(int)result}"
        };
    }

    /// <summary>
    /// Gets a description from a numeric return code without requiring enum conversion
    /// </summary>
    public static string GetDescriptionByCode(int returnCode)
    {
        return returnCode switch
        {
            0 => "Command executed successfully",
            // Positive return codes from device enrollment
            2 => "Vân tay/khuôn mặt đã tồn tại trên máy - cần xóa trước khi đăng ký lại",
            5 => "Đăng ký thất bại - máy đang bận hoặc có lỗi, vui lòng thử lại",
            // Negative return codes
            -1 => "Parameter error: Database not initialized",
            -2 => "Wrong operation",
            -3 => "Access error: Flash I/O Error",
            -4 => "No matched data found",
            -5 => "No more space available",
            -6 => "Data is not valid",
            -9 => "Fingerprint template size mismatch",
            -10 => "User not found",
            -11 => "Invalid fingerprint template format",
            -12 => "Invalid fingerprint template",
            -22 => "Unknown command",
            -1003 => "Hết thời gian đăng ký - vui lòng đứng trước camera/máy chấm công và thử lại",
            _ => $"Device error code: {returnCode}"
        };
    }

    /// <summary>
    /// Creates a ClockCommandResponses from the numeric value returned by the device
    /// </summary>
    /// <param name="value">The numeric result code</param>
    /// <returns>The corresponding ClockCommandResponses enum value</returns>
    public static ClockCommandResponses FromValue(int value)
    {
        return value switch
        {
            0 => ClockCommandResponses.Success,
            -1 => ClockCommandResponses.ParameterError,
            -2 => ClockCommandResponses.WrongOperation,
            -3 => ClockCommandResponses.AccessError,
            -4 => ClockCommandResponses.NoMatchedData,
            -5 => ClockCommandResponses.NoMoreSpace,
            -6 => ClockCommandResponses.InvalidData,
            -9 => ClockCommandResponses.FingerprintTemplateSizeMismatch,
            -10 => ClockCommandResponses.UserNotFound,
            -11 => ClockCommandResponses.InvalidFingerprintFormat,
            -12 => ClockCommandResponses.InvalidFingerprintTemplate,
            -22 => ClockCommandResponses.UnknownCommand,
            -1003 => ClockCommandResponses.EnrollmentTimeout,
            _ => throw new ArgumentException($"Unknown command result code: {value}", nameof(value))
        };
    }
}
