namespace ZKTecoADMS.Application.Services;

/// <summary>
/// Phân tích lộ trình GPS trong ca: lọc điểm nhiễu, tính quãng đường, tìm điểm dừng,
/// khoảng mất tín hiệu, thời gian di chuyển / dừng.
/// </summary>
public static class RouteAnalyzer
{
    public sealed record GeoPoint(double Lat, double Lng, DateTime TimeUtc, double? Accuracy = null);

    public sealed record Stop(double Lat, double Lng, DateTime StartUtc, DateTime EndUtc, int Points)
    {
        public double Minutes => (EndUtc - StartUtc).TotalMinutes;
    }

    public sealed record Gap(DateTime FromUtc, DateTime ToUtc)
    {
        public double Minutes => (ToUtc - FromUtc).TotalMinutes;
    }

    public sealed record Summary(
        double DistanceKm, double MovingMinutes, double StoppedMinutes, double TrackedMinutes,
        DateTime? FirstUtc, DateTime? LastUtc, int RawPoints, int CleanPoints, int DroppedPoints,
        IReadOnlyList<Stop> Stops, IReadOnlyList<Gap> Gaps, double MaxSpeedKmh);

    /// <summary>Sai số lớn hơn mức này (m) coi là điểm kém (vẫn giữ nếu là điểm duy nhất).</summary>
    public const double MaxAccuracyMeters = 150;

    /// <summary>Tốc độ vô lý giữa 2 điểm (km/h) → điểm «nhảy» do GPS, bỏ.</summary>
    public const double MaxSpeedKmh = 160;

    /// <summary>Bán kính gom điểm dừng (m) và thời gian dừng tối thiểu (phút).</summary>
    public const double StopRadiusMeters = 80;
    public const double StopMinMinutes = 5;

    /// <summary>Không có điểm trong khoảng này (phút) → mất tín hiệu / tắt app.</summary>
    public const double GapMinutes = 15;

    /// <summary>Chỉ cộng quãng đường khi đã rời điểm neo ít nhất chừng này (m) — tránh GPS rung khi đứng yên.</summary>
    public const double JitterMeters = 25;

    public static double DistanceMeters(double lat1, double lng1, double lat2, double lng2)
    {
        const double r = 6371000;
        static double Rad(double d) => d * Math.PI / 180;
        var dLat = Rad(lat2 - lat1);
        var dLng = Rad(lng2 - lng1);
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(Rad(lat1)) * Math.Cos(Rad(lat2)) * Math.Sin(dLng / 2) * Math.Sin(dLng / 2);
        return 2 * r * Math.Asin(Math.Min(1, Math.Sqrt(a)));
    }

    public static double DistanceMeters(GeoPoint a, GeoPoint b) => DistanceMeters(a.Lat, a.Lng, b.Lat, b.Lng);

    /// <summary>Sắp theo thời gian, bỏ toạ độ 0/0, bỏ điểm sai số lớn, bỏ điểm «nhảy» (tốc độ vô lý).</summary>
    public static List<GeoPoint> Clean(IEnumerable<GeoPoint> raw)
    {
        var sorted = raw
            .Where(p => !(p.Lat == 0 && p.Lng == 0) && Math.Abs(p.Lat) <= 90 && Math.Abs(p.Lng) <= 180)
            .OrderBy(p => p.TimeUtc)
            .ToList();
        var accurate = sorted.Where(p => p.Accuracy is null or <= MaxAccuracyMeters).ToList();
        if (accurate.Count == 0 && sorted.Count > 0) accurate = [sorted[^1]];

        var result = new List<GeoPoint>(accurate.Count);
        foreach (var p in accurate)
        {
            if (result.Count == 0)
            {
                result.Add(p);
                continue;
            }
            var prev = result[^1];
            var hours = (p.TimeUtc - prev.TimeUtc).TotalHours;
            if (hours <= 0)
            {
                // Trùng thời điểm: giữ điểm chính xác hơn
                if ((p.Accuracy ?? 999) < (prev.Accuracy ?? 999)) result[^1] = p;
                continue;
            }
            var kmh = DistanceMeters(prev, p) / 1000 / hours;
            if (kmh > MaxSpeedKmh) continue;
            result.Add(p);
        }
        return result;
    }

    /// <summary>Quãng đường (km): cộng dồn khi rời điểm neo quá <see cref="JitterMeters"/>.</summary>
    public static double DistanceKm(IReadOnlyList<GeoPoint> pts)
    {
        if (pts.Count < 2) return 0;
        double total = 0;
        var anchor = pts[0];
        for (var i = 1; i < pts.Count; i++)
        {
            var d = DistanceMeters(anchor, pts[i]);
            if (d >= JitterMeters)
            {
                total += d;
                anchor = pts[i];
            }
        }
        return Math.Round(total / 1000, 2);
    }

    /// <summary>Điểm dừng: chuỗi điểm liên tiếp nằm trong bán kính quanh điểm đầu cụm, kéo dài ≥ <see cref="StopMinMinutes"/>.</summary>
    public static List<Stop> DetectStops(IReadOnlyList<GeoPoint> pts,
        double radiusMeters = StopRadiusMeters, double minMinutes = StopMinMinutes)
    {
        var stops = new List<Stop>();
        var i = 0;
        while (i < pts.Count)
        {
            var j = i + 1;
            double sumLat = pts[i].Lat, sumLng = pts[i].Lng;
            while (j < pts.Count)
            {
                var cLat = sumLat / (j - i);
                var cLng = sumLng / (j - i);
                if (DistanceMeters(cLat, cLng, pts[j].Lat, pts[j].Lng) > radiusMeters) break;
                // Mất tín hiệu quá lâu giữa cụm thì vẫn coi là cùng điểm dừng (đứng yên, app ngủ)
                sumLat += pts[j].Lat;
                sumLng += pts[j].Lng;
                j++;
            }
            var count = j - i;
            var minutes = (pts[j - 1].TimeUtc - pts[i].TimeUtc).TotalMinutes;
            if (count >= 2 && minutes >= minMinutes)
            {
                stops.Add(new Stop(sumLat / count, sumLng / count, pts[i].TimeUtc, pts[j - 1].TimeUtc, count));
                i = j;
            }
            else
            {
                i++;
            }
        }
        return stops;
    }

    /// <summary>Khoảng không có tín hiệu dài hơn <see cref="GapMinutes"/> mà người không đứng yên tại chỗ.</summary>
    public static List<Gap> DetectGaps(IReadOnlyList<GeoPoint> pts, double gapMinutes = GapMinutes)
    {
        var gaps = new List<Gap>();
        for (var i = 1; i < pts.Count; i++)
        {
            var minutes = (pts[i].TimeUtc - pts[i - 1].TimeUtc).TotalMinutes;
            if (minutes >= gapMinutes && DistanceMeters(pts[i - 1], pts[i]) > StopRadiusMeters)
                gaps.Add(new Gap(pts[i - 1].TimeUtc, pts[i].TimeUtc));
        }
        return gaps;
    }

    public static Summary Analyze(IEnumerable<GeoPoint> raw)
    {
        var rawList = raw.ToList();
        var pts = Clean(rawList);
        var stops = DetectStops(pts);
        var gaps = DetectGaps(pts);
        var tracked = pts.Count >= 2 ? (pts[^1].TimeUtc - pts[0].TimeUtc).TotalMinutes : 0;
        var stopped = stops.Sum(s => s.Minutes);
        var gapMinutes = gaps.Sum(g => g.Minutes);
        double maxKmh = 0;
        for (var i = 1; i < pts.Count; i++)
        {
            var h = (pts[i].TimeUtc - pts[i - 1].TimeUtc).TotalHours;
            if (h > 0) maxKmh = Math.Max(maxKmh, DistanceMeters(pts[i - 1], pts[i]) / 1000 / h);
        }
        return new Summary(
            DistanceKm(pts),
            Math.Round(Math.Max(0, tracked - stopped - gapMinutes), 1),
            Math.Round(stopped, 1),
            Math.Round(tracked, 1),
            pts.Count > 0 ? pts[0].TimeUtc : null,
            pts.Count > 0 ? pts[^1].TimeUtc : null,
            rawList.Count, pts.Count, rawList.Count - pts.Count,
            stops, gaps, Math.Round(maxKmh, 1));
    }

    /// <summary>Giảm số điểm gửi về client (giữ điểm đầu/cuối và điểm cách nhau đủ xa / đủ lâu).</summary>
    public static List<GeoPoint> Downsample(IReadOnlyList<GeoPoint> pts, int max = 1500)
    {
        if (pts.Count <= max) return pts.ToList();
        var result = new List<GeoPoint> { pts[0] };
        var minMeters = 10.0;
        while (true)
        {
            result.Clear();
            result.Add(pts[0]);
            for (var i = 1; i < pts.Count - 1; i++)
            {
                var last = result[^1];
                if (DistanceMeters(last, pts[i]) >= minMeters || (pts[i].TimeUtc - last.TimeUtc).TotalMinutes >= 10)
                    result.Add(pts[i]);
            }
            result.Add(pts[^1]);
            if (result.Count <= max || minMeters > 2000) return result;
            minMeters *= 2;
        }
    }
}
