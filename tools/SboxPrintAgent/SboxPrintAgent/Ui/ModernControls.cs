using System.ComponentModel;
using System.Drawing.Drawing2D;

namespace SboxPrintAgent.Ui;

/// <summary>Ô nhập có viền bo góc, padding, focus accent.</summary>
public sealed class ModernTextBox : Panel
{
    readonly TextBox _inner = new()
    {
        BorderStyle = BorderStyle.None,
        Font = Theme.FontUi(10.5f),
        ForeColor = Theme.Text,
        BackColor = Theme.Card,
    };
    readonly Label _hint = new()
    {
        AutoSize = false,
        ForeColor = Theme.TextMuted,
        Font = Theme.FontUi(10.5f),
        BackColor = Theme.Card,
        TextAlign = ContentAlignment.MiddleLeft,
        Cursor = Cursors.IBeam,
    };
    readonly LinkLabel _reveal = new()
    {
        Text = "Hiện",
        AutoSize = true,
        LinkColor = Theme.Accent,
        ActiveLinkColor = Theme.AccentDark,
        VisitedLinkColor = Theme.Accent,
        Font = Theme.FontUi(9f, FontStyle.Bold),
        Visible = false,
        Cursor = Cursors.Hand,
        BackColor = Theme.Card,
    };
    bool _focused;
    bool _showReveal;

    public ModernTextBox()
    {
        Height = 44;
        BackColor = Theme.Card;
        Padding = new Padding(12, 10, 12, 10);
        DoubleBuffered = true;
        Controls.Add(_inner);
        Controls.Add(_hint);
        Controls.Add(_reveal);
        _hint.Click += (_, _) => _inner.Focus();
        _reveal.LinkClicked += (_, _) =>
        {
            UseSystemPasswordChar = !UseSystemPasswordChar;
            _reveal.Text = UseSystemPasswordChar ? "Hiện" : "Ẩn";
            _inner.Focus();
        };
        _inner.GotFocus += (_, _) => { _focused = true; SyncHint(); Invalidate(); };
        _inner.LostFocus += (_, _) => { _focused = false; SyncHint(); Invalidate(); };
        _inner.TextChanged += (_, _) =>
        {
            SyncHint();
            TextChanged?.Invoke(this, EventArgs.Empty);
        };
        Resize += (_, _) => LayoutInner();
        LayoutInner();
        SyncHint();
    }

    [Browsable(true)]
    public override string Text
    {
        get => _inner.Text;
        set { _inner.Text = value ?? ""; SyncHint(); }
    }

    [Browsable(true)]
    public string Placeholder
    {
        get => _hint.Text;
        set { _hint.Text = value; SyncHint(); }
    }

    [Browsable(true)]
    public bool UseSystemPasswordChar
    {
        get => _inner.UseSystemPasswordChar;
        set => _inner.UseSystemPasswordChar = value;
    }

    [Browsable(true)]
    public bool ShowPasswordToggle
    {
        get => _showReveal;
        set
        {
            _showReveal = value;
            _reveal.Visible = value;
            if (value)
            {
                UseSystemPasswordChar = true;
                _reveal.Text = "Hiện";
            }
            LayoutInner();
        }
    }

    [Browsable(true)]
    public bool ReadOnly
    {
        get => _inner.ReadOnly;
        set => _inner.ReadOnly = value;
    }

    public new event EventHandler? TextChanged;

    void LayoutInner()
    {
        var r = ClientRectangle;
        r.Inflate(-12, -10);
        if (r.Width < 1 || r.Height < 1) return;
        var revealW = _showReveal ? 44 : 0;
        _reveal.Location = new Point(r.Right - revealW + 4, r.Top + (r.Height - _reveal.Height) / 2);
        var textR = new Rectangle(r.X, r.Y, Math.Max(1, r.Width - revealW), r.Height);
        _inner.Bounds = textR;
        _hint.Bounds = textR;
        if (_showReveal) _reveal.BringToFront();
    }

    void SyncHint()
    {
        _hint.Visible = string.IsNullOrEmpty(_inner.Text) && !_focused;
        if (_hint.Visible) _hint.BringToFront();
        else _inner.BringToFront();
        if (_showReveal) _reveal.BringToFront();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var path = RoundRect(ClientRectangle, 8);
        using var brush = new SolidBrush(Theme.Card);
        e.Graphics.FillPath(brush, path);
        var border = _focused ? Theme.BorderFocus : Theme.Border;
        using var pen = new Pen(border, _focused ? 2f : 1.2f);
        e.Graphics.DrawPath(pen, path);
    }

    static GraphicsPath RoundRect(Rectangle r, int radius)
    {
        var path = new GraphicsPath();
        var d = radius * 2;
        var rect = new Rectangle(r.X + 1, r.Y + 1, r.Width - 3, r.Height - 3);
        path.AddArc(rect.X, rect.Y, d, d, 180, 90);
        path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
        path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
        path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}

public sealed class ModernButton : Button
{
    public enum StyleKind { Primary, Secondary, Danger, Ghost }

    StyleKind _kind = StyleKind.Primary;
    bool _hover;

    public ModernButton()
    {
        // Không tự vẽ OnPaint — tránh chữ dính đáy / bị cắt (bug DPI + TextRenderer).
        FlatStyle = FlatStyle.Flat;
        FlatAppearance.BorderSize = 0;
        FlatAppearance.MouseOverBackColor = Theme.AccentDark;
        FlatAppearance.MouseDownBackColor = Theme.AccentDark;
        Cursor = Cursors.Hand;
        Font = Theme.FontUi(10f, FontStyle.Bold);
        TextAlign = ContentAlignment.MiddleCenter;
        UseCompatibleTextRendering = false;
        AutoSize = false;
        MinimumSize = new Size(96, 44);
        Size = new Size(160, 44);
        Margin = new Padding(0, 4, 10, 4);
        Padding = new Padding(14, 8, 14, 8);
        ApplyStyle();
        MouseEnter += (_, _) => { _hover = true; ApplyStyle(); };
        MouseLeave += (_, _) => { _hover = false; ApplyStyle(); };
    }

    [Browsable(true)]
    public StyleKind Kind
    {
        get => _kind;
        set { _kind = value; ApplyStyle(); }
    }

    void ApplyStyle()
    {
        switch (_kind)
        {
            case StyleKind.Primary:
                BackColor = _hover ? Theme.AccentDark : Theme.Accent;
                ForeColor = Color.White;
                FlatAppearance.BorderSize = 0;
                FlatAppearance.MouseOverBackColor = Theme.AccentDark;
                FlatAppearance.MouseDownBackColor = Color.FromArgb(13, 100, 94);
                break;
            case StyleKind.Secondary:
                BackColor = _hover ? Color.FromArgb(226, 232, 240) : Color.FromArgb(248, 250, 252);
                ForeColor = Theme.Text;
                FlatAppearance.BorderSize = 1;
                FlatAppearance.BorderColor = Theme.Border;
                FlatAppearance.MouseOverBackColor = Color.FromArgb(226, 232, 240);
                FlatAppearance.MouseDownBackColor = Color.FromArgb(203, 213, 225);
                break;
            case StyleKind.Danger:
                BackColor = _hover ? Color.FromArgb(185, 28, 28) : Theme.Danger;
                ForeColor = Color.White;
                FlatAppearance.BorderSize = 0;
                FlatAppearance.MouseOverBackColor = Color.FromArgb(185, 28, 28);
                FlatAppearance.MouseDownBackColor = Color.FromArgb(153, 27, 27);
                break;
            case StyleKind.Ghost:
                BackColor = _hover ? Theme.SidebarHover : Color.Transparent;
                ForeColor = Color.White;
                FlatAppearance.BorderSize = 0;
                break;
        }
        Invalidate();
    }
}

/// <summary>Thanh nút cố định đáy card — không bị che bởi panel Fill.</summary>
public static class ButtonBar
{
    public static Panel Create(params Control[] buttons)
    {
        var host = new Panel
        {
            Dock = DockStyle.Bottom,
            Height = 56,
            MinimumSize = new Size(0, 56),
            MaximumSize = new Size(0, 56),
            BackColor = Theme.Card,
            Padding = new Padding(0, 6, 0, 2),
        };
        var flow = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            AutoSize = false,
            BackColor = Theme.Card,
            Padding = new Padding(0),
            Margin = new Padding(0),
        };
        foreach (var b in buttons)
        {
            if (b is ModernButton mb)
            {
                mb.Height = 40;
                mb.MinimumSize = new Size(Math.Max(88, mb.Width), 40);
                mb.Margin = new Padding(0, 2, 8, 2);
            }
            else
            {
                b.Height = 40;
                b.Margin = new Padding(0, 2, 8, 2);
            }
            flow.Controls.Add(b);
        }
        host.Controls.Add(flow);
        return host;
    }
}

public sealed class CardPanel : Panel
{
    public CardPanel()
    {
        BackColor = Theme.Card;
        Padding = new Padding(16, 16, 16, 12);
        DoubleBuffered = true;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var path = new GraphicsPath();
        var r = ClientRectangle;
        var d = 16;
        var rect = new Rectangle(r.X + 1, r.Y + 1, r.Width - 3, r.Height - 3);
        path.AddArc(rect.X, rect.Y, d, d, 180, 90);
        path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
        path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
        path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        using var brush = new SolidBrush(Theme.Card);
        e.Graphics.FillPath(brush, path);
        using var pen = new Pen(Theme.Border);
        e.Graphics.DrawPath(pen, path);
    }
}

public static class UiMsg
{
    public static void Info(string message, string title = "Thông báo")
        => MessageBox.Show(message, title, MessageBoxButtons.OK, MessageBoxIcon.Information);

    public static void Warn(string message, string title = "Cảnh báo")
        => MessageBox.Show(message, title, MessageBoxButtons.OK, MessageBoxIcon.Warning);

    public static void Error(string message, string title = "Lỗi")
        => MessageBox.Show(ToVi(message), title, MessageBoxButtons.OK, MessageBoxIcon.Error);

    public static bool Confirm(string message, string title = "Xác nhận")
        => MessageBox.Show(message, title, MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes;

    public static string ToVi(string? msg)
    {
        if (string.IsNullOrWhiteSpace(msg)) return "Đã xảy ra lỗi không xác định.";
        if (msg.Contains("same key has already been added", StringComparison.OrdinalIgnoreCase))
            return "Trùng loại chứng từ khi gắn route. Đã xử lý — hãy thử lại (cập nhật phiên bản mới).";
        if (msg.Contains("Unauthorized", StringComparison.OrdinalIgnoreCase) ||
            msg.Contains("401"))
            return "Phiên đăng nhập hết hạn hoặc sai tài khoản. Vui lòng đăng nhập lại.";
        if (msg.Contains("403") || msg.Contains("Forbidden", StringComparison.OrdinalIgnoreCase))
            return "Tài khoản không có quyền thao tác máy in / Print Agent.";
        if (msg.Contains("timed out", StringComparison.OrdinalIgnoreCase) ||
            msg.Contains("Timeout", StringComparison.OrdinalIgnoreCase))
            return "Hết thời gian chờ máy chủ. Kiểm tra mạng hoặc địa chỉ server.";
        if (msg.Contains("actively refused", StringComparison.OrdinalIgnoreCase) ||
            msg.Contains("No such host", StringComparison.OrdinalIgnoreCase) ||
            msg.Contains("không thể kết nối", StringComparison.OrdinalIgnoreCase))
            return "Không kết nối được máy chủ. Kiểm tra địa chỉ (mặc định https://sboxhrm.com) và mạng.";
        if (msg.Contains("SSL", StringComparison.OrdinalIgnoreCase) ||
            msg.Contains("certificate", StringComparison.OrdinalIgnoreCase))
            return "Lỗi chứng chỉ HTTPS. Kiểm tra địa chỉ server.";
        return msg;
    }
}
