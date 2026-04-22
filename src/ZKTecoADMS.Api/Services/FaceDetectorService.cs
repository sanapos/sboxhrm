using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Face detector using UltraFace RFB-320 ONNX.
/// Input: NCHW float32 [1,3,240,320], pixels normalized (p - 127) / 128, RGB order.
/// Outputs:
///   scores : [1, N, 2]   (bg, face)
///   boxes  : [1, N, 4]   normalized (x1,y1,x2,y2) in [0,1]
///
/// Used before feeding MobileFaceNet so the embedding focuses on the face,
/// not the background. If model is missing or no face detected, callers
/// should fall back to a centered square crop.
/// </summary>
public class FaceDetectorService : IDisposable
{
    private const int InputW = 320;
    private const int InputH = 240;
    private const float ScoreThreshold = 0.7f;

    private readonly ILogger<FaceDetectorService> _logger;
    private readonly IWebHostEnvironment _env;
    private readonly object _lock = new();
    private InferenceSession? _session;
    private string? _inputName;
    private string? _scoresName;
    private string? _boxesName;
    private bool _initAttempted;
    private string? _lastInitError;

    public FaceDetectorService(ILogger<FaceDetectorService> logger, IWebHostEnvironment env)
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
                var modelPath = Path.Combine(_env.ContentRootPath, "wwwroot", "models", "ultraface-RFB-320.onnx");
                if (!File.Exists(modelPath))
                {
                    _lastInitError = $"UltraFace model not found at {modelPath}";
                    _logger.LogWarning("FaceDetectorService: {Error} — will fall back to center crop", _lastInitError);
                    return;
                }

                var options = new SessionOptions
                {
                    GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL,
                    InterOpNumThreads = 1,
                    IntraOpNumThreads = 2,
                };
                _session = new InferenceSession(modelPath, options);
                _inputName = _session.InputMetadata.Keys.First();

                // Identify scores/boxes by output shape (scores has last dim=2, boxes has last dim=4)
                foreach (var kv in _session.OutputMetadata)
                {
                    var last = kv.Value.Dimensions.LastOrDefault();
                    if (last == 2) _scoresName = kv.Key;
                    else if (last == 4) _boxesName = kv.Key;
                }
                _scoresName ??= _session.OutputMetadata.Keys.First();
                _boxesName ??= _session.OutputMetadata.Keys.Last();

                _logger.LogWarning(
                    "FaceDetectorService loaded: input={In}, scores={S}, boxes={B}",
                    _inputName, _scoresName, _boxesName);
            }
            catch (Exception ex)
            {
                _lastInitError = ex.ToString();
                _logger.LogError(ex, "Failed to load UltraFace model");
                _session = null;
            }
        }
    }

    /// <summary>
    /// Detect the largest / highest-confidence face and return its bounding box
    /// in original image pixel coordinates, expanded by <paramref name="expandRatio"/>.
    /// Returns null if model unavailable or no face found.
    /// </summary>
    public Rectangle? DetectBestFace(Image<Rgb24> image, float expandRatio = 0.25f)
    {
        EnsureInitialized();
        if (_session == null) return null;

        try
        {
            // Resize to 320x240 for inference (keep aspect via pad-letterbox-free: UltraFace
            // is trained with direct resize, not letterbox — matches reference impl)
            using var resized = image.Clone(ctx => ctx.Resize(InputW, InputH));

            var tensor = new DenseTensor<float>(new[] { 1, 3, InputH, InputW });
            resized.ProcessPixelRows(accessor =>
            {
                for (var y = 0; y < accessor.Height; y++)
                {
                    var row = accessor.GetRowSpan(y);
                    for (var x = 0; x < row.Length; x++)
                    {
                        var p = row[x];
                        tensor[0, 0, y, x] = (p.R - 127f) / 128f;
                        tensor[0, 1, y, x] = (p.G - 127f) / 128f;
                        tensor[0, 2, y, x] = (p.B - 127f) / 128f;
                    }
                }
            });

            var inputs = new List<NamedOnnxValue>
            {
                NamedOnnxValue.CreateFromTensor(_inputName!, tensor),
            };

            using var outputs = _session.Run(inputs);
            var scoresTensor = outputs.First(o => o.Name == _scoresName).AsEnumerable<float>().ToArray();
            var boxesTensor = outputs.First(o => o.Name == _boxesName).AsEnumerable<float>().ToArray();

            // scores layout: [N, 2]  boxes: [N, 4]
            var n = scoresTensor.Length / 2;
            int bestIdx = -1;
            float bestScore = ScoreThreshold;
            for (var i = 0; i < n; i++)
            {
                var face = scoresTensor[i * 2 + 1];
                if (face > bestScore)
                {
                    bestScore = face;
                    bestIdx = i;
                }
            }
            if (bestIdx < 0) return null;

            var x1 = boxesTensor[bestIdx * 4 + 0];
            var y1 = boxesTensor[bestIdx * 4 + 1];
            var x2 = boxesTensor[bestIdx * 4 + 2];
            var y2 = boxesTensor[bestIdx * 4 + 3];

            // Map normalized coords back to original image
            var px1 = x1 * image.Width;
            var py1 = y1 * image.Height;
            var px2 = x2 * image.Width;
            var py2 = y2 * image.Height;

            // Expand box for more context (MobileFaceNet trained with ~20-30% margin)
            var w = px2 - px1;
            var h = py2 - py1;
            var cx = (px1 + px2) * 0.5f;
            var cy = (py1 + py2) * 0.5f;
            var side = Math.Max(w, h) * (1f + expandRatio);
            var half = side * 0.5f;

            var rx = (int)Math.Max(0, Math.Floor(cx - half));
            var ry = (int)Math.Max(0, Math.Floor(cy - half));
            var rx2 = (int)Math.Min(image.Width, Math.Ceiling(cx + half));
            var ry2 = (int)Math.Min(image.Height, Math.Ceiling(cy + half));
            var rw = rx2 - rx;
            var rh = ry2 - ry;
            if (rw <= 8 || rh <= 8) return null;

            return new Rectangle(rx, ry, rw, rh);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "UltraFace detection failed");
            return null;
        }
    }

    public void Dispose()
    {
        _session?.Dispose();
        _session = null;
        GC.SuppressFinalize(this);
    }
}
