namespace SboxPrintAgent;

public static class AppIcon
{
    public static Icon? LoadIcon()
    {
        try
        {
            using var s = typeof(AppIcon).Assembly.GetManifestResourceStream("SboxPrintAgent.Assets.app.ico");
            if (s != null) return new Icon(s);
        }
        catch { /* ignore */ }
        try
        {
            var path = Path.Combine(AppContext.BaseDirectory, "Assets", "app.ico");
            if (File.Exists(path)) return new Icon(path);
        }
        catch { /* ignore */ }
        return null;
    }

    public static Image? LoadLogoImage(int size = 40)
    {
        try
        {
            using var s = typeof(AppIcon).Assembly.GetManifestResourceStream("SboxPrintAgent.Assets.logo.png");
            if (s != null)
            {
                using var img = Image.FromStream(s);
                return new Bitmap(img, new Size(size, size));
            }
        }
        catch { /* ignore */ }
        try
        {
            var path = Path.Combine(AppContext.BaseDirectory, "Assets", "logo.png");
            if (File.Exists(path))
            {
                using var img = Image.FromFile(path);
                return new Bitmap(img, new Size(size, size));
            }
        }
        catch { /* ignore */ }
        return null;
    }
}
