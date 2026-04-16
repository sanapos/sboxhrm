using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Face comparison service using structural + gradient similarity.
/// Compares check-in face photos against registered face photos.
/// </summary>
public class FaceComparisonService
{
    private const int CompareSize = 128;
    private readonly ILogger<FaceComparisonService> _logger;
    private readonly IWebHostEnvironment _env;

    public FaceComparisonService(ILogger<FaceComparisonService> logger, IWebHostEnvironment env)
    {
        _logger = logger;
        _env = env;
    }

    /// <summary>
    /// Compare a check-in face image against multiple registered face images.
    /// Returns best match score (0-100). Higher = more similar.
    /// </summary>
    public async Task<(double Score, string Details)> CompareAsync(
        string checkInImageRelativePath,
        List<string> registeredImageRelativePaths)
    {
        if (registeredImageRelativePaths.Count == 0)
            return (0.0, "Không có ảnh đăng ký");

        try
        {
            var checkInFullPath = ResolveFullPath(checkInImageRelativePath);
            if (!File.Exists(checkInFullPath))
                return (0.0, "Ảnh chấm công không tìm thấy");

            // Load and preprocess check-in image
            using var checkInImage = await LoadAndPreprocessAsync(checkInFullPath);
            if (checkInImage == null)
                return (0.0, "Không xử lý được ảnh chấm công");

            var checkInGradient = ComputeGradient(checkInImage);
            var checkInHistogram = ComputeHistogram(checkInImage);

            double bestScore = 0;
            int compared = 0;

            foreach (var regPath in registeredImageRelativePaths)
            {
                try
                {
                    var regFullPath = ResolveFullPath(regPath);
                    if (!File.Exists(regFullPath)) continue;

                    using var regImage = await LoadAndPreprocessAsync(regFullPath);
                    if (regImage == null) continue;

                    var regGradient = ComputeGradient(regImage);
                    var regHistogram = ComputeHistogram(regImage);

                    // Multi-factor comparison:
                    // 1. Gradient (edge structure) similarity - captures face shape (50%)
                    var gradientSim = CosineSimilarity(checkInGradient, regGradient);
                    // 2. Histogram similarity - captures overall brightness distribution (20%)
                    var histSim = HistogramSimilarity(checkInHistogram, regHistogram);
                    // 3. Pixel correlation - direct pixel comparison (30%)
                    var pixelSim = PixelCorrelation(checkInImage, regImage);

                    var score = (gradientSim * 0.50 + histSim * 0.20 + pixelSim * 0.30) * 100.0;
                    compared++;

                    _logger.LogDebug(
                        "Face compare: grad={Grad:F2} hist={Hist:F2} pixel={Pixel:F2} total={Total:F1}",
                        gradientSim, histSim, pixelSim, score);

                    if (score > bestScore)
                        bestScore = score;
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Error comparing with registered image {Path}", regPath);
                }
            }

            if (compared == 0)
                return (0.0, "Không so sánh được ảnh đăng ký nào");

            return (Math.Round(bestScore, 1), $"So sánh {compared} ảnh, điểm cao nhất: {bestScore:F1}");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Face comparison failed");
            return (0.0, $"Lỗi so sánh: {ex.Message}");
        }
    }

    private string ResolveFullPath(string relativePath)
    {
        // Handle absolute URLs stored in legacy data
        if (relativePath.StartsWith("http://") || relativePath.StartsWith("https://"))
        {
            var uri = new Uri(relativePath);
            relativePath = uri.AbsolutePath;
        }

        // Remove leading slash
        var cleanPath = relativePath.TrimStart('/');
        return Path.Combine(_env.ContentRootPath, "wwwroot", cleanPath.Replace('/', Path.DirectorySeparatorChar));
    }

    private static async Task<Image<L8>?> LoadAndPreprocessAsync(string path)
    {
        try
        {
            var image = await Image.LoadAsync<L8>(path);
            // Auto-rotate per EXIF orientation, then crop+resize
            var minDim = Math.Min(image.Width, image.Height);
            var cropX = (image.Width - minDim) / 2;
            var cropY = (image.Height - minDim) / 2;

            // Face-focused crop: take center 50% after square crop
            // Removes background noise (walls, ceiling) that dilutes face similarity
            var faceDim = (int)(minDim * 0.50);
            var faceOffset = (minDim - faceDim) / 2;

            image.Mutate(x => x
                .AutoOrient()
                .Crop(new Rectangle(cropX + faceOffset, cropY + faceOffset, faceDim, faceDim))
                .Resize(CompareSize, CompareSize)
                .HistogramEqualization());

            return image;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Compute gradient magnitude map (Sobel-like edge detection).
    /// Captures face structure (edges around eyes, nose, mouth).
    /// </summary>
    private static double[] ComputeGradient(Image<L8> image)
    {
        var width = image.Width;
        var height = image.Height;
        var gradient = new double[(width - 2) * (height - 2)];
        int idx = 0;

        for (int y = 1; y < height - 1; y++)
        {
            for (int x = 1; x < width - 1; x++)
            {
                // Sobel X
                var gx = -image[x - 1, y - 1].PackedValue - 2.0 * image[x - 1, y].PackedValue - image[x - 1, y + 1].PackedValue
                       + image[x + 1, y - 1].PackedValue + 2.0 * image[x + 1, y].PackedValue + image[x + 1, y + 1].PackedValue;
                // Sobel Y
                var gy = -image[x - 1, y - 1].PackedValue - 2.0 * image[x, y - 1].PackedValue - image[x + 1, y - 1].PackedValue
                       + image[x - 1, y + 1].PackedValue + 2.0 * image[x, y + 1].PackedValue + image[x + 1, y + 1].PackedValue;

                gradient[idx++] = Math.Sqrt(gx * gx + gy * gy);
            }
        }

        return gradient;
    }

    /// <summary>
    /// Compute 32-bin grayscale histogram (normalized).
    /// </summary>
    private static double[] ComputeHistogram(Image<L8> image)
    {
        var histogram = new double[32];

        for (int y = 0; y < image.Height; y++)
        {
            for (int x = 0; x < image.Width; x++)
            {
                var bin = image[x, y].PackedValue / 8; // 256 / 32 = 8
                if (bin >= 32) bin = 31;
                histogram[bin]++;
            }
        }

        // Normalize
        var total = image.Width * image.Height;
        for (int i = 0; i < 32; i++)
            histogram[i] /= total;

        return histogram;
    }

    /// <summary>
    /// Cosine similarity between two vectors. Returns 0-1.
    /// </summary>
    private static double CosineSimilarity(double[] a, double[] b)
    {
        if (a.Length != b.Length || a.Length == 0) return 0;

        double dot = 0, magA = 0, magB = 0;
        for (int i = 0; i < a.Length; i++)
        {
            dot += a[i] * b[i];
            magA += a[i] * a[i];
            magB += b[i] * b[i];
        }

        if (magA == 0 || magB == 0) return 0;
        return Math.Max(0, dot / (Math.Sqrt(magA) * Math.Sqrt(magB)));
    }

    /// <summary>
    /// Histogram intersection similarity (Bhattacharyya-like). Returns 0-1.
    /// </summary>
    private static double HistogramSimilarity(double[] a, double[] b)
    {
        if (a.Length != b.Length) return 0;
        double sum = 0;
        for (int i = 0; i < a.Length; i++)
            sum += Math.Sqrt(a[i] * b[i]);
        return sum;
    }

    /// <summary>
    /// Normalized cross-correlation of pixel values. Returns 0-1.
    /// Handles brightness and contrast differences.
    /// </summary>
    private static double PixelCorrelation(Image<L8> a, Image<L8> b)
    {
        var n = a.Width * a.Height;
        double sumA = 0, sumB = 0;

        // Compute means
        for (int y = 0; y < a.Height; y++)
        {
            for (int x = 0; x < a.Width; x++)
            {
                sumA += a[x, y].PackedValue;
                sumB += b[x, y].PackedValue;
            }
        }

        var meanA = sumA / n;
        var meanB = sumB / n;

        // Compute NCC
        double num = 0, denA = 0, denB = 0;
        for (int y = 0; y < a.Height; y++)
        {
            for (int x = 0; x < a.Width; x++)
            {
                var da = a[x, y].PackedValue - meanA;
                var db = b[x, y].PackedValue - meanB;
                num += da * db;
                denA += da * da;
                denB += db * db;
            }
        }

        if (denA == 0 || denB == 0) return 0;
        return Math.Max(0, num / (Math.Sqrt(denA) * Math.Sqrt(denB)));
    }
}
