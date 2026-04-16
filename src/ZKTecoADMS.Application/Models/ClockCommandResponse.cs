using System.Text.Json.Serialization;
using ZKTecoADMS.Application.Constants;

namespace ZKTecoADMS.Application.Models;

public class ClockCommandResponse
{

    public long CommandId { get; set; }
    public int Return { get; set; }
    public string CMD { get; set; }
    
    [JsonIgnore]
    public string Message => ClockCommandResponsesExtensions.GetDescriptionByCode(Return);
    
    [JsonIgnore]
    public bool IsSuccess => Return == 0;
}