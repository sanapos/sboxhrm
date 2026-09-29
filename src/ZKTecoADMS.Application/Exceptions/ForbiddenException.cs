namespace ZKTecoADMS.Application.Exceptions;

/// <summary>Không đủ quyền (vd ghi chứng từ ở chi nhánh ngoài phạm vi) → 403.</summary>
public class ForbiddenException : Exception
{
    public ForbiddenException(string message) : base(message)
    {
    }
}
