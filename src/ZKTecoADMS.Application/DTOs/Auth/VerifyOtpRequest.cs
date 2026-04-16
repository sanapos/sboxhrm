namespace ZKTecoADMS.Application.DTOs.Auth;

public record VerifyOtpRequest(string StoreCode, string Email, string Otp, string NewPassword, string ConfirmPassword);
