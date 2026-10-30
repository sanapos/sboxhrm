using System.Text.Json.Nodes;
using Xunit;
using ZKTecoADMS.Api.Controllers;

namespace ZKTecoADMS.Tests.Pos;

public class PosPromotionValidateTests
{
    [Theory]
    [InlineData("""{"percent":150}""", true)]
    [InlineData("""{"percent":-5}""", true)]
    [InlineData("""{"billPercent":101}""", true)]
    [InlineData("""{"tiers":[{"minQty":2,"percent":10},{"minQty":5,"percent":120}]}""", true)]
    [InlineData("""{"percent":100}""", false)]
    [InlineData("""{"percent":10,"target":{"scope":"all"}}""", false)]
    [InlineData("""{"salePrice":15000}""", false)]
    public void Percent_must_be_0_to_100(string json, bool bad) =>
        Assert.Equal(bad, PosPromotionsController.PercentOutOfRange((JsonObject)JsonNode.Parse(json)!));
}
