namespace SboxPrintAgent.Ui;

public static class Theme
{
    public static readonly Color Sidebar = Color.FromArgb(15, 23, 42);
    public static readonly Color SidebarHover = Color.FromArgb(30, 41, 59);
    public static readonly Color SidebarActive = Color.FromArgb(13, 148, 136);
    public static readonly Color Accent = Color.FromArgb(13, 148, 136);
    public static readonly Color AccentDark = Color.FromArgb(15, 118, 110);
    public static readonly Color Bg = Color.FromArgb(241, 245, 249);
    public static readonly Color Card = Color.White;
    public static readonly Color Border = Color.FromArgb(226, 232, 240);
    public static readonly Color BorderFocus = Color.FromArgb(13, 148, 136);
    public static readonly Color Text = Color.FromArgb(15, 23, 42);
    public static readonly Color TextMuted = Color.FromArgb(100, 116, 139);
    public static readonly Color Danger = Color.FromArgb(220, 38, 38);
    public static readonly Color Success = Color.FromArgb(22, 163, 74);
    public static readonly Color Warning = Color.FromArgb(217, 119, 6);

    public static Font FontUi(float size = 10f, FontStyle style = FontStyle.Regular)
        => new("Segoe UI", size, style, GraphicsUnit.Point);

    public static Font FontTitle => FontUi(18f, FontStyle.Bold);
    public static Font FontSection => FontUi(12.5f, FontStyle.Bold);
    public static Font FontMono
    {
        get
        {
            try { return new Font("Cascadia Mono", 9f, FontStyle.Regular, GraphicsUnit.Point); }
            catch { return new Font("Consolas", 9f, FontStyle.Regular, GraphicsUnit.Point); }
        }
    }
}
