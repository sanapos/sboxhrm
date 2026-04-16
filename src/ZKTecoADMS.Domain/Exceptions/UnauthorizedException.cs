namespace ZKTecoADMS.Domain.Exceptions;

public class UnauthorizedException : Exception
{
    public UnauthorizedException() : base("Unauthorized access.")
    {
    }

    public UnauthorizedException(string message) : base(message)
    {
    }
} 