namespace ZKTecoADMS.Application.Settings;

public class EmailSettings
{
    public const string SectionName = "Email";
    
    public string SmtpHost { get; set; } = "smtp.gmail.com";
    public int SmtpPort { get; set; } = 587;
    public string SmtpUsername { get; set; } = string.Empty;
    public string SmtpPassword { get; set; } = string.Empty; // App password for Gmail
    public string FromEmail { get; set; } = string.Empty;
    public string FromName { get; set; } = "ZKTeco ADMS";
    public bool EnableSsl { get; set; } = true;
    
    /// <summary>
    /// Base URL for password reset link (e.g., http://localhost:3000)
    /// </summary>
    public string ResetPasswordBaseUrl { get; set; } = "http://localhost:3000";
}
