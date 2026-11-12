using System.Text.Json;
using Xunit;
using ZKTecoADMS.Api.Services;

namespace ZKTecoADMS.Tests;

public class GeminiAnswerTextTests
{
    static string Answer(string partsJson)
    {
        using var doc = JsonDocument.Parse(partsJson);
        return GeminiAiService.AnswerText(doc.RootElement);
    }

    [Fact]
    public void Joins_answer_split_across_parts_and_skips_thoughts()
    {
        var text = Answer("""
            [{"text":"nghĩ…","thought":true},
             {"text":"{\"items\":[{\"name\":\"Cà phê\"},"},
             {"text":"{\"name\":\"Trà đào\"}]}"},
             {"text":"","thoughtSignature":"abc"}]
            """);
        Assert.Equal("""{"items":[{"name":"Cà phê"},{"name":"Trà đào"}]}""", text);
        using var _ = JsonDocument.Parse(text);
    }

    [Fact]
    public void Single_part_and_non_text_parts()
    {
        Assert.Equal("ok", Answer("""[{"text":"ok"}]"""));
        Assert.Equal("", Answer("""[{"functionCall":{"name":"x"}}]"""));
        Assert.Equal("", Answer("{}"));
    }
}
