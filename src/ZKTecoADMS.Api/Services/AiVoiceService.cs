using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Giọng nói của Trợ lý ảo bằng Gemini (cùng khóa AI của cửa hàng):
///  • Nghe: ghi âm → Gemini chép lời tiếng Việt, kèm từ vựng của chính cửa hàng (tên nhân viên, hàng hóa, khách,
///    phòng ban) để viết đúng tên riêng — nhận dạng của trình duyệt / điện thoại hay ra chữ lộn xộn, lặp từ.
///  • Đọc: Gemini TTS giọng người thật, có ngữ điệu (thay giọng máy của thiết bị).
/// </summary>
public sealed class AiVoiceService(
    ZKTecoDbContext db,
    IGeminiAiService gemini,
    IMemoryCache cache,
    ILogger<AiVoiceService> logger)
{
    /// <summary>Model TTS — thử lần lượt (Google đổi tên bản preview / chính thức theo thời gian).</summary>
    static readonly string[] TtsModels = ["gemini-2.5-flash-preview-tts", "gemini-2.5-flash-tts", "gemini-2.5-pro-preview-tts"];

    /// <summary>Giọng Gemini TTS đọc tiếng Việt tự nhiên (đa ngôn ngữ).</summary>
    public static readonly IReadOnlyDictionary<string, string> Voices = new Dictionary<string, string>
    {
        ["Kore"] = "Nữ — rõ ràng, chắc",
        ["Aoede"] = "Nữ — nhẹ nhàng, tự nhiên",
        ["Leda"] = "Nữ — trẻ trung",
        ["Sulafat"] = "Nữ — ấm áp",
        ["Puck"] = "Nam — vui vẻ",
        ["Charon"] = "Nam — trầm, điềm đạm",
        ["Orus"] = "Nam — chắc chắn",
        ["Iapetus"] = "Nam — rõ ràng",
    };

    public const string DefaultVoice = "Aoede";

    // ─── Nghe ───────────────────────────────────────────────────────

    public async Task<string> TranscribeAsync(byte[] audio, string mimeType, Guid storeId, CancellationToken ct)
    {
        var vocab = await VocabularyAsync(storeId, ct);
        var prompt = new StringBuilder("""
            Chép lại CHÍNH XÁC lời người dùng nói trong đoạn ghi âm (tiếng Việt, đang ra lệnh cho trợ lý phần mềm
            quản lý bán hàng / nhân sự). Quy tắc:
            - Chỉ trả về câu nói đã chép — không giải thích, không thêm dấu ngoặc, không trả lời câu hỏi.
            - Viết tiếng Việt có dấu đúng chính tả; bỏ tiếng ậm ừ ("ờ", "à", "ừm"), từ lặp do ngập ngừng, câu nói lại.
            - Số tiền viết bằng số có dấu chấm ngăn cách nghìn: "năm trăm nghìn" → 500.000; "một triệu rưỡi" → 1.500.000;
              "hai trăm k" → 200.000. Giờ viết HH:mm (17:30), ngày viết dd/MM nếu người nói đọc ngày cụ thể.
            - Tên người / hàng / khách nghe gần giống danh sách dưới đây thì viết ĐÚNG như trong danh sách.
            - Không nghe rõ hoặc không có lời nói → trả về chuỗi rỗng.
            """);
        if (vocab.Length > 0) prompt.AppendLine().AppendLine("TỪ VỰNG CỦA CỬA HÀNG:").AppendLine(vocab);

        var body = new
        {
            contents = new object[]
            {
                new
                {
                    role = "user",
                    parts = new object[]
                    {
                        new { text = prompt.ToString() },
                        new { inlineData = new { mimeType = NormalizeMime(mimeType), data = Convert.ToBase64String(audio) } },
                    },
                },
            },
            generationConfig = new { temperature = 0.0, maxOutputTokens = 512 },
        };
        JsonElement content;
        try
        {
            content = await gemini.GenerateContentRawAsync(body, ct, GeminiModels.Flash);
        }
        catch (AiApiException ex) when (ex.IsQuotaError || ex.StatusCode == 503)
        {
            // Hết lượt / quá tải model Flash — Flash Lite có hạn mức riêng, vẫn chép lời tốt.
            content = await gemini.GenerateContentRawAsync(body, ct, GeminiModels.FlashLite);
        }
        var text = TextOf(content).Trim().Trim('"', '“', '”').Trim();
        logger.LogInformation("AI transcribe {Bytes}B {Mime} → {Chars} chars", audio.Length, mimeType, text.Length);
        return text;
    }

    static string NormalizeMime(string? m)
    {
        var s = (m ?? "").Split(';')[0].Trim().ToLowerInvariant();
        return s switch
        {
            "audio/x-m4a" or "audio/m4a" or "audio/aac" or "audio/mp4a-latm" => "audio/mp4",
            "audio/x-wav" or "audio/wave" => "audio/wav",
            "" => "audio/webm",
            _ => s,
        };
    }

    /// <summary>Tên nhân viên, phòng ban, hàng hóa, khách thường gặp — gợi ý chính tả tên riêng (cache 10 phút).</summary>
    async Task<string> VocabularyAsync(Guid storeId, CancellationToken ct)
    {
        var key = "ai-vocab:" + storeId;
        if (cache.TryGetValue(key, out string? hit) && hit != null) return hit;
        var emps = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.Deleted == null && e.WorkStatus != Domain.Enums.EmployeeWorkStatus.Resigned)
            .Select(e => e.FirstName + " " + e.LastName).Take(250).ToListAsync(ct);
        var depts = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.Department != null)
            .Select(e => e.Department!).Distinct().Take(40).ToListAsync(ct);
        var products = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive)
            .OrderByDescending(p => p.UpdatedAt ?? p.CreatedAt)
            .Select(p => p.Name).Take(250).ToListAsync(ct);
        var customers = await db.PosCustomers.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null)
            .OrderByDescending(c => c.UpdatedAt ?? c.CreatedAt)
            .Select(c => c.Name).Take(120).ToListAsync(ct);
        var sb = new StringBuilder();
        void Add(string label, IEnumerable<string> items)
        {
            var list = items.Select(x => x.Trim()).Where(x => x.Length > 1).Distinct().ToList();
            if (list.Count > 0) sb.Append(label).Append(": ").AppendLine(string.Join("; ", list));
        }
        Add("Nhân viên", emps);
        Add("Phòng ban", depts);
        Add("Hàng hóa", products);
        Add("Khách hàng", customers);
        var v = sb.ToString();
        cache.Set(key, v, new MemoryCacheEntryOptions { AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(10), Size = 1 });
        return v;
    }

    // ─── Đọc ────────────────────────────────────────────────────────

    /// <summary>Đọc câu trả lời → WAV (PCM 24 kHz mono). Câu giống nhau dùng lại bản đã đọc (cache 30 phút).</summary>
    public async Task<byte[]> SpeakAsync(string text, string? voice, CancellationToken ct)
    {
        var v = voice != null && Voices.ContainsKey(voice) ? voice : DefaultVoice;
        var clean = text.Trim();
        if (clean.Length > 1500) clean = clean[..1500];
        var key = "ai-tts:" + v + ":" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(clean)))[..32];
        if (cache.TryGetValue(key, out byte[]? hit) && hit != null) return hit;

        var body = new
        {
            contents = new[]
            {
                new
                {
                    role = "user",
                    parts = new[]
                    {
                        // Chỉ dẫn phong cách đọc (model TTS hiểu lời dặn trước đoạn văn).
                        new { text = "Đọc bằng tiếng Việt, giọng nhân viên chăm sóc khách hàng thân thiện, tự nhiên, "
                                     + "nhịp vừa phải, ngắt nghỉ đúng dấu câu:\n" + clean },
                    },
                },
            },
            generationConfig = new
            {
                responseModalities = new[] { "AUDIO" },
                speechConfig = new { voiceConfig = new { prebuiltVoiceConfig = new { voiceName = v } } },
            },
        };

        AiApiException? last = null;
        foreach (var model in TtsModels)
        {
            JsonElement content;
            try
            {
                content = await gemini.GenerateContentRawAsync(body, ct, model);
            }
            catch (AiApiException ex) when (ex.StatusCode is 404 or 400)
            {
                // Model chưa / không còn — thử tên kế tiếp.
                last = ex;
                continue;
            }
            var (pcm, rate) = AudioOf(content);
            if (pcm == null || pcm.Length == 0) continue;
            var wav = Wav(pcm, rate);
            cache.Set(key, wav, new MemoryCacheEntryOptions { AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(30), Size = 1 });
            logger.LogInformation("AI TTS {Model} {Voice}: {Chars} chars → {Bytes}B", model, v, clean.Length, wav.Length);
            return wav;
        }
        throw last ?? new AiApiException("Máy chủ AI không trả âm thanh.", 502);
    }

    static string TextOf(JsonElement content) =>
        content.TryGetProperty("parts", out var ps) && ps.ValueKind == JsonValueKind.Array
            ? string.Concat(ps.EnumerateArray()
                .Where(p => !(p.TryGetProperty("thought", out var t) && t.ValueKind == JsonValueKind.True))
                .Where(p => p.TryGetProperty("text", out _))
                .Select(p => p.GetProperty("text").GetString()))
            : "";

    static (byte[]? Pcm, int Rate) AudioOf(JsonElement content)
    {
        if (!content.TryGetProperty("parts", out var ps) || ps.ValueKind != JsonValueKind.Array) return (null, 0);
        foreach (var p in ps.EnumerateArray())
        {
            if (!p.TryGetProperty("inlineData", out var d) || !d.TryGetProperty("data", out var data)) continue;
            var mime = d.TryGetProperty("mimeType", out var m) ? m.GetString() ?? "" : "";
            var rate = 24000;
            var i = mime.IndexOf("rate=", StringComparison.OrdinalIgnoreCase);
            if (i >= 0 && int.TryParse(new string(mime[(i + 5)..].TakeWhile(char.IsDigit).ToArray()), out var r)) rate = r;
            return (Convert.FromBase64String(data.GetString() ?? ""), rate);
        }
        return (null, 0);
    }

    /// <summary>PCM 16-bit mono → WAV (trình duyệt / điện thoại phát được).</summary>
    public static byte[] Wav(byte[] pcm, int sampleRate)
    {
        var wav = new byte[44 + pcm.Length];
        var s = wav.AsSpan();
        Encoding.ASCII.GetBytes("RIFF").CopyTo(s);
        BinaryPrimitives.WriteInt32LittleEndian(s[4..], 36 + pcm.Length);
        Encoding.ASCII.GetBytes("WAVEfmt ").CopyTo(s[8..]);
        BinaryPrimitives.WriteInt32LittleEndian(s[16..], 16);
        BinaryPrimitives.WriteInt16LittleEndian(s[20..], 1);
        BinaryPrimitives.WriteInt16LittleEndian(s[22..], 1);
        BinaryPrimitives.WriteInt32LittleEndian(s[24..], sampleRate);
        BinaryPrimitives.WriteInt32LittleEndian(s[28..], sampleRate * 2);
        BinaryPrimitives.WriteInt16LittleEndian(s[32..], 2);
        BinaryPrimitives.WriteInt16LittleEndian(s[34..], 16);
        Encoding.ASCII.GetBytes("data").CopyTo(s[36..]);
        BinaryPrimitives.WriteInt32LittleEndian(s[40..], pcm.Length);
        pcm.CopyTo(s[44..]);
        return wav;
    }
}
