namespace ZKTecoADMS.Application.Models;


public class AppResponse<T>
{
    public bool IsSuccess { get; set; }

    public List<string> Errors { get; set; } = [];

    public string Message => Errors.Any() ? string.Join("; ", Errors) : string.Empty;

    public T? Data { get; set; }

    public static AppResponse<T> Create(bool isSuccess, T? data = default, List<string> errors = null)
    {
        return new AppResponse<T>
        {
            IsSuccess = isSuccess,
            Data = data,
            Errors = errors ?? []
        };
    }

    public static AppResponse<T> Success(T? data = default)
    {
        return new AppResponse<T>
        {
            IsSuccess = true,
            Data = data
        };
    }

    public static AppResponse<T> Fail(string errorMsg)
    {
        return new AppResponse<T>
        {
            IsSuccess = false,
            Errors = new List<string> { errorMsg },
        };
    }

    public static AppResponse<T> Error(string errorMsg)
    {
        return new AppResponse<T>
        {
            IsSuccess = false,
            Errors = new List<string> { errorMsg },
        };
    }

    public static AppResponse<T> Error(IEnumerable<string> errorMsgs)
    {
        return new AppResponse<T>
        {
            IsSuccess = false,
            Errors = errorMsgs.ToList(),
        };
    }   
}