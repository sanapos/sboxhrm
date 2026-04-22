using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Silent (passive) face anti-spoofing using ONNX.
/// Model: hairymax/Face-AntiSpoofing AntiSpoofing_bin_1.5_128 — a binary
/// classifier trained to distinguish real faces from photo/video/screen replays.
///
/// Input: NCHW float32 [1,3,128,128], normalized (px - 127.5) / 127.5.
/// Output: [1,2] logits (spoof, live). We take softmax(live) as confidence.
///
/// Called after face detection crops the face region. If model missing,
/// IsReady returns false and callers skip the check.
/// </summary>
public class FaceAntiSpoofService : IDisposable
{
    private const int InputSize = 128;
    private readonly ILogger<FaceAntiSpoofService> _logger;
    private readonly IWebHostEnvironment _env;
    private readonly object _lock = new();
    private InferenceSession? _session;
    private string? _inputName;
    private string? _outputName;
    private bool _initAttempted;
    private string? _lastInitError;

    public FaceAntiSpoofService(ILogger<FaceAntiSpoofService> logger, IWebHostEnvironment env)
    {
        _logger = logger;
        _env = env;
    }

    public bool IsReady
    {
        get
        {
            EnsureInitialized();
            return _session != null;
        }
    }

    public string? LastInitError => _lastInitError;

    private void EnsureInitialized()
    {
        if (_initAttempted) return;
        lock (_lock)
        {
            if (_initAttempted) return;
            _initAttempted = true;
            try
            {
                var modelPath = Path.Combine(_env.ContentRootPath, "wwwroot", "models", "antispoof.onnx");
                if (!File.Exists(modelPath))
                {
                    _lastInitError = $"Anti-spoof model not found at {modelPath}";
                    _logger.LogWarning("FaceAntiSpoofService: {Error} — skipping passive anti-spoof", _lastInitError);
                    return;
                }

                var options = new Microsoft.ML.OnnxRuntime.SessionOptions
                {
                    GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL,
                    InterOpNumThreads = 1,
                    IntraOpNumThreads = 2,
                };
                _session = new InferenceSession(modelPath, options);
                _inputName = _session.InputMetadata.Keys.First();
                _outputName = _session.OutputMetadata.Keys.First();
                _logger.LogWarning(
                    "FaceAntiSpoofService loaded: input={In}, output={Out}",
                    _inputName, _outputName);
            }
            catch (Exception ex)
            {
                _lastInitError = ex.ToString();
                _logger.LogError(ex, "Failed to load anti-spoof model");
                _session = null;
            }
        }
    }

    /// <summary>
    /// Returns the live probability (0..1) for a face image file.
    /// If the model isn't loaded, returns 1.0 (pass-through — don't block punches
    /// when anti-spoof is unavailable, liveness is still handled by the client blink).
    /// </summary>
    public async Task<double> GetLiveProbabilityAsync(string imageFullPath)
    {
        EnsureInitialized();
        if (_session == null) return 1.0;
        try
        {
            using var image = await Image.LoadAsync<Rgb24>(imageFullPath);
            return RunInference(image);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Anti-spoof inference failed for {Path}", imageFullPath);
            return 1.0;
        }
    }

    public Task<double> GetLiveProbabilityFromRelativeAsync(string relativePath)
    {
        if (relativePath.StartsWith("http://") || relativePath.StartsWith("https://"))
        {
            try { relativePath = new Uri(relativePath).AbsolutePath; } catch { }
        }
        var cleanPath = relativePath.TrimStart('/');
        var fullPath = Path.Combine(_env.ContentRootPath, "wwwroot", cleanPath.Replace('/', Path.DirectorySeparatorChar));
        if (!File.Exists(fullPath)) return Task.FromResult(1.0);
        return GetLiveProbabilityAsync(fullPath);
    }

    private double RunInference(Image<Rgb24> image)
    {
        // Center-crop to square then resize — caller should ideally pass a
        // face crop already. The anti-spoof model is not super sensitive to
        // exact framing as long as the face occupies most of the image.
        var minDim = Math.Min(image.Width, image.Height);
        var offX = (image.Width - minDim) / 2;
        var offY = (image.Height - minDim) / 2;
        image.Mutate(x => x
            .Crop(new Rectangle(offX, offY, minDim, minDim))
            .Resize(InputSize, InputSize));

        var tensor = new DenseTensor<float>(new[] { 1, 3, InputSize, InputSize });
        image.ProcessPixelRows(accessor =>
        {
            for (var y = 0; y < accessor.Height; y++)
            {
                var row = accessor.GetRowSpan(y);
                for (var x = 0; x < row.Length; x++)
                {
                    var p = row[x];
                    tensor[0, 0, y, x] = (p.R - 127.5f) / 127.5f;
                    tensor[0, 1, y, x] = (p.G - 127.5f) / 127.5f;
                    tensor[0, 2, y, x] = (p.B - 127.5f) / 127.5f;
                }
            }
        });

        var inputs = new List<NamedOnnxValue>
        {
            NamedOnnxValue.CreateFromTensor(_inputName!, tensor),
        };
        using var outputs = _session!.Run(inputs);
        var logits = outputs.First(o => o.Name == _outputName).AsEnumerable<float>().ToArray();

        // Softmax over 2 classes [spoof, live]
        if (logits.Length < 2) return 1.0;
        var m = Math.Max(logits[0], logits[1]);
        var e0 = Math.Exp(logits[0] - m);
        var e1 = Math.Exp(logits[1] - m);
        return e1 / (e0 + e1);
    }

    public void Dispose()
    {
        _session?.Dispose();
        _session = null;
        GC.SuppressFinalize(this);
    }
}
