namespace ZKTecoADMS.Domain.Enums;

public enum ShiftProblem
{
    None = 0,
    MissingCheckIn = 1 << 0,
    MissingCheckOut = 1 << 1,
    LateCheckIn = 1 << 2,
    EarlyCheckOut = 1 << 3
}