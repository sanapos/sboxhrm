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
    private const int InputSize = 112; // MobileFaceNet / ArcFace: 112x112 RGB
    private readonly ILogger<OnnxFaceEmbeddingService> _logger;
    private readonly IWebHostEnvironment _env;
    private readonly FaceDetectorService _faceDetector;
    private readonly object _lock = new();
    private InferenceSession? _session;
    private string? _inputName;
    private string? _outputName;
    private int _embeddingSize;
    private bool _isNchw; // true: [1,3,H,W]  false: [1,H,W,3]
    private bool _initAttempted;
    private string? _lastInitError;

    public OnnxFaceEmbeddingService(
        ILogger<OnnxFaceEmbeddingService> logger,
        IWebHostEnvironment env,
        FaceDetectorService faceDetector)
    {
        _logger = logger;
        _env = env;
        _faceDetector = faceDetector;
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
                // Prefer w600k_mbf (InsightFace ArcFace, trained on WebFace600K,
                // 512-dim embedding — significantly better discrimination than the
                // generic mobilefacenet.onnx). Fall back to mobilefacenet if absent.
                var modelsDir = Path.Combine(_env.ContentRootPath, "wwwroot", "models");
                var candidates = new[] { "w600k_mbf.onnx", "mobilefacenet.onnx" };
                string? modelPath = candidates
                    .Select(n => Path.Combine(modelsDir, n))
                    .FirstOrDefault(File.Exists);
                if (modelPath == null)
                {
                    _lastInitError = $"No ONNX face model found in {modelsDir}";
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
                var inShape = _session.InputMetadata[_inputName].Dimensions;
                // InsightFace w600k_mbf is NCHW [1,3,112,112]; tflite-converted MFN is NHWC.
                _isNchw = inShape.Length == 4 && inShape[1] == 3;
                var outShape = _session.OutputMetadata[_outputName].Dimensions;
                _embeddingSize = outShape.Last() > 0 ? outShape.Last() : 512;
                _logger.LogWarning(
                    "OnnxFaceEmbeddingService loaded: model={Model}, input={In}, output={Out}, layout={Layout}, embeddingSize={Size}",
                    Path.GetFileName(modelPath), _inputName, _outputName, _isNchw ? "NCHW" : "NHWC", _embeddingSize);
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
    /// Returns the average of the top-2 cosine similarities (scaled 0-100).
    /// Using top-2 instead of top-1 suppresses single-outlier matches where a
    /// different person happens to look similar to one of the reference photos
    /// (e.g. a bad reference with heavy background contamination).
    /// </summary>
    public static double BestCosineScore(float[] checkInEmbedding, IEnumerable<float[]> registered)
    {
        var scores = new List<double>();
        foreach (var reg in registered)
        {
            var sim = CosineSimilarity(checkInEmbedding, reg);
            var score = Math.Max(0.0, Math.Min(100.0, sim * 100.0));
            scores.Add(score);
        }
        if (scores.Count == 0) return 0.0;
        scores.Sort((a, b) => b.CompareTo(a));
        // Average of top-2 (or top-1 if only one reference)
        var top = scores.Count >= 2 ? (scores[0] + scores[1]) * 0.5 : scores[0];
        return Math.Round(top, 1);
    }

    private float[] RunInference(Image<Rgb24> image)
    {
        // 1) Try UltraFace to crop to the actual face bbox.
        //    Tight crop (5% expansion) keeps the embedding focused on identity
        //    features and suppresses background contamination, which was causing
        //    false accepts between different people.
        var faceBox = _faceDetector.DetectBestFace(image, expandRatio: 0.05f);
        if (faceBox is { } box)
        {
            image.Mutate(x => x.Crop(box).Resize(InputSize, InputSize));
        }
        else
        {
            // Fallback: center-crop to square then resize
            var minDim = Math.Min(image.Width, image.Height);
            var offX = (image.Width - minDim) / 2;
            var offY = (image.Height - minDim) / 2;
            image.Mutate(x => x
                .Crop(new Rectangle(offX, offY, minDim, minDim))
                .Resize(InputSize, InputSize));
        }

        // Build tensor. InsightFace ArcFace uses (px - 127.5) / 127.5 in RGB order.
        // Layout depends on model (NCHW for w600k_mbf, NHWC for tflite-converted MFN).
        DenseTensor<float> tensor;
        if (_isNchw)
        {
            tensor = new DenseTensor<float>(new[] { 1, 3, InputSize, InputSize });
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
        }
        else
        {
            tensor = new DenseTensor<float>(new[] { 1, InputSize, InputSize, 3 });
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
        }

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
