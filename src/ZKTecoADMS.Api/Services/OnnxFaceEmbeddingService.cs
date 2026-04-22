using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Face embedding service using a MobileFaceNet ONNX model.
/// Produces a 192-dim identity vector from a face image and computes
/// cosine similarity against registered faces.
///
/// This is the same technology used by Android TFLite client side,
/// so scores are directly comparable and share the same threshold.
///
/// The ONNX model is expected at:
///   {ContentRoot}/wwwroot/models/mobilefacenet.onnx
/// If absent, IsReady will be false and callers should fall back to
/// the feature-based <see cref="FaceComparisonService"/>.
/// </summary>
public class OnnxFaceEmbeddingService : IDisposable
{
    private const int InputSize = 112; // MobileFaceNet: 112x112 RGB
    private readonly ILogger<OnnxFaceEmbeddingService> _logger;
    private readonly IWebHostEnvironment _env;
    private readonly object _lock = new();
    private InferenceSession? _session;
    private string? _inputName;
    private string? _outputName;
    private int _embeddingSize;
    private bool _initAttempted;
    private string? _lastInitError;

    public OnnxFaceEmbeddingService(
        ILogger<OnnxFaceEmbeddingService> logger,
        IWebHostEnvironment env)
    {
        _logger = logger;
        _env = env;
    }

    public bool IsReady => _session != null;
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
                var modelPath = Path.Combine(_env.ContentRootPath, "wwwroot", "models", "mobilefacenet.onnx");
                if (!File.Exists(modelPath))
                {
                    _lastInitError = $"ONNX model not found at {modelPath}";
                    _logger.LogWarning("OnnxFaceEmbeddingService: {Error} — falling back to feature-based comparator", _lastInitError);
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
                var outShape = _session.OutputMetadata[_outputName].Dimensions;
                _embeddingSize = outShape.Last() > 0 ? outShape.Last() : 192;
                _logger.LogInformation(
                    "OnnxFaceEmbeddingService loaded: input={In}, output={Out}, embeddingSize={Size}",
                    _inputName, _outputName, _embeddingSize);
            }
            catch (Exception ex)
            {
                _lastInitError = ex.ToString();
                _logger.LogError(ex, "Failed to load ONNX face model");
                _session = null;
            }
        }
    }

    /// <summary>
    /// Extracts a normalized 192-dim embedding from a face image file.
    /// The image will be auto-cropped to a centered square and resized to 112x112.
    /// Returns null if the model is not loaded or extraction fails.
    /// </summary>
    public async Task<float[]?> GetEmbeddingAsync(string imageFullPath)
    {
        EnsureInitialized();
        if (_session == null) return null;

        try
        {
            using var image = await Image.LoadAsync<Rgb24>(imageFullPath);
            return RunInference(image);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "ONNX embedding extraction failed for {Path}", imageFullPath);
            return null;
        }
    }

    /// <summary>
    /// Same as <see cref="GetEmbeddingAsync(string)"/> but resolves a wwwroot-relative
    /// path (e.g. "/uploads/face-verifications/foo.jpg") to an absolute one.
    /// </summary>
    public Task<float[]?> GetEmbeddingFromRelativeAsync(string relativePath)
    {
        if (relativePath.StartsWith("http://") || relativePath.StartsWith("https://"))
        {
            try { relativePath = new Uri(relativePath).AbsolutePath; } catch { }
        }
        var cleanPath = relativePath.TrimStart('/');
        var fullPath = Path.Combine(_env.ContentRootPath, "wwwroot", cleanPath.Replace('/', Path.DirectorySeparatorChar));
        if (!File.Exists(fullPath))
        {
            _logger.LogWarning("ONNX embedding: file not found {Path}", fullPath);
            return Task.FromResult<float[]?>(null);
        }
        return GetEmbeddingAsync(fullPath);
    }

    /// <summary>
    /// Compare a check-in embedding against a list of registered embeddings.
    /// Returns the best cosine-similarity score scaled to 0-100.
    /// </summary>
    public static double BestCosineScore(float[] checkInEmbedding, IEnumerable<float[]> registered)
    {
        double best = 0.0;
        foreach (var reg in registered)
        {
            var sim = CosineSimilarity(checkInEmbedding, reg);
            // MobileFaceNet raw cosine is typically 0.3..0.8 for different people,
            // 0.5..0.9 for the same person. Scale linearly to 0-100 clamped:
            //   cos=0.3 → 30, cos=0.8 → 95, cos>=0.85 → 100.
            var score = Math.Max(0.0, Math.Min(100.0, sim * 100.0));
            if (score > best) best = score;
        }
        return Math.Round(best, 1);
    }

    private float[] RunInference(Image<Rgb24> image)
    {
        // Center-crop to square, then resize to 112x112
        var minDim = Math.Min(image.Width, image.Height);
        var offX = (image.Width - minDim) / 2;
        var offY = (image.Height - minDim) / 2;
        image.Mutate(x => x
            .Crop(new Rectangle(offX, offY, minDim, minDim))
            .Resize(InputSize, InputSize));

        // NHWC float32 tensor, normalized to [-1, 1] per MobileFaceNet convention
        var tensor = new DenseTensor<float>(new[] { 1, InputSize, InputSize, 3 });
        image.ProcessPixelRows(accessor =>
        {
            for (var y = 0; y < accessor.Height; y++)
            {
                var row = accessor.GetRowSpan(y);
                for (var x = 0; x < row.Length; x++)
                {
                    var p = row[x];
                    tensor[0, y, x, 0] = (p.R - 127.5f) / 128.0f;
                    tensor[0, y, x, 1] = (p.G - 127.5f) / 128.0f;
                    tensor[0, y, x, 2] = (p.B - 127.5f) / 128.0f;
                }
            }
        });

        var inputs = new List<NamedOnnxValue>
        {
            NamedOnnxValue.CreateFromTensor(_inputName!, tensor)
        };
        using var outputs = _session!.Run(inputs);
        var raw = outputs.First(v => v.Name == _outputName).AsEnumerable<float>().ToArray();

        // L2-normalize so cosine similarity == dot product
        var norm = 0.0;
        for (var i = 0; i < raw.Length; i++) norm += raw[i] * raw[i];
        norm = Math.Sqrt(norm);
        if (norm > 1e-9)
        {
            for (var i = 0; i < raw.Length; i++) raw[i] = (float)(raw[i] / norm);
        }
        return raw;
    }

    private static double CosineSimilarity(float[] a, float[] b)
    {
        if (a.Length != b.Length) return 0.0;
        double dot = 0.0;
        for (var i = 0; i < a.Length; i++) dot += a[i] * b[i];
        // Embeddings are already L2-normalized → cosine == dot
        return Math.Max(0.0, dot);
    }

    public void Dispose()
    {
        _session?.Dispose();
        _session = null;
        GC.SuppressFinalize(this);
    }
}
