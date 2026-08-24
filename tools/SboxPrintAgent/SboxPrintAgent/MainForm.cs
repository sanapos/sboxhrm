using System.Net.Sockets;
using SboxPrintAgent.Ui;

namespace SboxPrintAgent;

/// <summary>
/// UI tối giản: đăng nhập cửa hàng → thêm máy LAN/USB → đặt tên → xem online/offline.
/// Nhận lệnh in chạy nền (server đẩy job).
/// </summary>
public sealed class MainForm : Form
{
    readonly AppSettings _settings = AppSettings.Load();
    SboxApiClient? _api;
    AgentService? _agent;
    List<PrinterItem> _printers = new();
    readonly Dictionary<Guid, bool> _online = new();
    readonly List<LanScanner.Hit> _hits = new();
    Guid[] _agentServingIds = Array.Empty<Guid>();
    System.Windows.Forms.Timer? _healthTimer;

    // —— Login ——
    readonly Panel _loginPanel = new() { Dock = DockStyle.Fill, BackColor = Theme.Bg };
    readonly ModernTextBox _storeCode = new() { Placeholder = "Mã cửa hàng", Dock = DockStyle.Top };
    readonly ModernTextBox _user = new() { Placeholder = "Email / tên đăng nhập", Dock = DockStyle.Top };
    readonly ModernTextBox _pass = new() { Placeholder = "Mật khẩu", ShowPasswordToggle = true, Dock = DockStyle.Top };
    readonly CheckBox _remember = new() { Text = "Lưu mật khẩu", AutoSize = true, ForeColor = Theme.Text, Font = Theme.FontUi() };
    readonly CheckBox _runAtBoot = new() { Text = "Tự chạy khi mở Windows", AutoSize = true, ForeColor = Theme.Text, Font = Theme.FontUi() };
    readonly ModernButton _btnLogin = new() { Text = "Đăng nhập cửa hàng", Kind = ModernButton.StyleKind.Primary, Width = 220, Height = 44 };
    readonly Label _loginHint = new() { AutoSize = true, ForeColor = Theme.TextMuted, Font = Theme.FontUi(9.5f), MaximumSize = new Size(420, 0) };

    // —— Main ——
    readonly Panel _mainPanel = new() { Dock = DockStyle.Fill, BackColor = Theme.Bg, Visible = false };
    readonly Label _storeTitle = new() { AutoSize = true, Font = Theme.FontTitle, ForeColor = Theme.Text };
    readonly Label _agentBadge = new() { AutoSize = true, Font = Theme.FontUi(10f, FontStyle.Bold), ForeColor = Theme.Success };
    readonly Label _storeSub = new() { AutoSize = true, ForeColor = Theme.TextMuted, Font = Theme.FontUi(9.5f) };
    readonly ModernButton _btnLogout = new() { Text = "Đăng xuất", Kind = ModernButton.StyleKind.Secondary, Width = 120, Height = 36 };
    readonly ModernButton _btnRefresh = new() { Text = "Làm mới", Kind = ModernButton.StyleKind.Secondary, Width = 110, Height = 36 };

    readonly ListView _printerView = new()
    {
        Dock = DockStyle.Fill,
        View = View.Details,
        FullRowSelect = true,
        MultiSelect = false,
        HideSelection = false,
        BorderStyle = BorderStyle.None,
        Font = Theme.FontUi(10f),
        HeaderStyle = ColumnHeaderStyle.Nonclickable,
    };

    readonly ModernTextBox _nameBox = new() { Placeholder = "Tên máy in (vd: Máy quầy, Máy bếp)", Dock = DockStyle.Top };
    readonly ModernTextBox _subnet = new() { Placeholder = "Subnet quét (vd: 192.168.1)", Dock = DockStyle.Top };
    readonly ModernTextBox _lanIp = new() { Placeholder = "IP máy in (vd: 192.168.1.50)", Dock = DockStyle.Top };
    readonly ModernTextBox _lanPort = new() { Placeholder = "Cổng (mặc định 9100)", Dock = DockStyle.Top };
    readonly ListBox _hitList = new() { Dock = DockStyle.Fill, Font = Theme.FontUi(10f), BorderStyle = BorderStyle.None, IntegralHeight = false };
    readonly ListBox _usbList = new() { Dock = DockStyle.Fill, Font = Theme.FontUi(10f), BorderStyle = BorderStyle.None, IntegralHeight = false };

    readonly ModernButton _btnScan = new() { Text = "Quét mạng", Kind = ModernButton.StyleKind.Secondary, Width = 110, Height = 40 };
    readonly ModernButton _btnTestIp = new() { Text = "In thử IP", Kind = ModernButton.StyleKind.Secondary, Width = 110, Height = 40 };
    readonly ModernButton _btnAddLan = new() { Text = "Thêm máy LAN", Kind = ModernButton.StyleKind.Primary, Width = 130, Height = 40 };
    readonly ModernButton _btnCheckOnline = new() { Text = "Kiểm tra online", Kind = ModernButton.StyleKind.Secondary, Width = 140, Height = 40 };
    readonly ModernButton _btnUsbRefresh = new() { Text = "Tải lại USB", Kind = ModernButton.StyleKind.Secondary, Width = 120, Height = 40 };
    readonly ModernButton _btnAddUsb = new() { Text = "Thêm máy USB", Kind = ModernButton.StyleKind.Primary, Width = 130, Height = 40 };
    readonly ModernButton _btnUsbTest = new() { Text = "In thử USB", Kind = ModernButton.StyleKind.Secondary, Width = 110, Height = 40 };
    readonly ModernButton _btnRename = new() { Text = "Đổi tên", Kind = ModernButton.StyleKind.Secondary, Width = 100, Height = 40 };
    readonly ModernButton _btnTest = new() { Text = "In thử máy này", Kind = ModernButton.StyleKind.Primary, Width = 140, Height = 40 };
    readonly ModernButton _btnDelete = new() { Text = "Gỡ khỏi PC", Kind = ModernButton.StyleKind.Danger, Width = 120, Height = 40 };

    readonly TextBox _logBox = new()
    {
        Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill,
        BorderStyle = BorderStyle.None, Font = Theme.FontMono,
        BackColor = Color.FromArgb(15, 23, 42), ForeColor = Color.FromArgb(226, 232, 240),
    };

    readonly NotifyIcon _tray = new();
    readonly Label _footer = new()
    {
        Dock = DockStyle.Bottom, Height = 26, ForeColor = Theme.TextMuted,
        Font = Theme.FontUi(8.5f), Padding = new Padding(12, 4, 12, 0), BackColor = Theme.Bg,
    };

    public MainForm()
    {
        Text = "SBOX — Máy in cửa hàng";
        Width = 1080;
        Height = 800;
        MinimumSize = new Size(980, 720);
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Theme.Bg;
        Font = Theme.FontUi();
        DoubleBuffered = true;

        var icon = AppIcon.LoadIcon();
        if (icon != null) Icon = icon;

        _storeCode.Text = _settings.StoreCode;
        _user.Text = _settings.Username;
        _pass.Text = _settings.RememberPassword ? _settings.Password : "";
        _subnet.Text = SubnetNormalize.Clean(_settings.SubnetPrefix);
        if (_subnet.Text != (_settings.SubnetPrefix ?? "").Trim())
        {
            _settings.SubnetPrefix = _subnet.Text;
            _settings.Save();
        }
        _remember.Checked = _settings.RememberPassword;
        _runAtBoot.Checked = _settings.RunAtWindowsStartup || WindowsStartup.IsEnabled();
        _settings.AutoStartAgent = true;

        _printerView.Columns.Add("Trạng thái", 110);
        _printerView.Columns.Add("Tên máy in", 220);
        _printerView.Columns.Add("Kết nối", 90);
        _printerView.Columns.Add("Địa chỉ / USB", 280);
        _printerView.Columns.Add("Sức khỏe server", 120);
        _printerView.OwnerDraw = true;
        _printerView.DrawColumnHeader += PrinterView_DrawColumnHeader;
        _printerView.DrawItem += (_, e) => e.DrawDefault = true;
        _printerView.DrawSubItem += PrinterView_DrawSubItem;

        BuildLogin();
        BuildMain();
        Controls.Add(_mainPanel);
        Controls.Add(_loginPanel);
        Controls.Add(_footer);
        SetupTray();
        WireEvents();

        Shown += async (_, _) =>
        {
            if (!string.IsNullOrWhiteSpace(_settings.StoreCode) &&
                !string.IsNullOrWhiteSpace(_settings.Username) &&
                !string.IsNullOrWhiteSpace(_settings.Password))
            {
                try { await LoginAsync(silent: true); }
                catch (Exception ex) { Log("Tự đăng nhập: " + UiMsg.ToVi(ex.Message)); }
            }
        };

        FormClosing += async (_, e) =>
        {
            if (_agent?.IsRunning == true)
            {
                e.Cancel = true;
                Hide();
                _tray.ShowBalloonTip(2200, "SBOX máy in",
                    "Đang chạy nền — nhận lệnh in từ server.", ToolTipIcon.Info);
            }
            else
            {
                StopHealthTimer();
                if (_agent != null) await _agent.DisposeAsync();
                _tray.Visible = false;
            }
        };
    }

    void BuildLogin()
    {
        var card = new CardPanel { Width = 480, Height = 460 };
        var stack = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 10,
            Padding = new Padding(8),
        };
        for (var i = 0; i < 10; i++)
            stack.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        var logo = AppIcon.LoadLogoImage(48);
        if (logo != null)
        {
            stack.Controls.Add(new PictureBox
            {
                Image = logo, SizeMode = PictureBoxSizeMode.Zoom,
                Size = new Size(48, 48), Margin = new Padding(0, 0, 0, 8),
            }, 0, 0);
        }
        stack.Controls.Add(new Label
        {
            Text = "Kết nối máy in cửa hàng",
            Font = Theme.FontUi(16f, FontStyle.Bold), ForeColor = Theme.Text, AutoSize = true,
            Margin = new Padding(0, 0, 0, 4),
        }, 0, 1);
        stack.Controls.Add(new Label
        {
            Text = "Đăng nhập → thêm máy LAN/USB → server tự đẩy lệnh in.",
            ForeColor = Theme.TextMuted, Font = Theme.FontUi(9.5f), AutoSize = true,
            MaximumSize = new Size(400, 0), Margin = new Padding(0, 0, 0, 16),
        }, 0, 2);

        stack.Controls.Add(new Label { Text = "Mã cửa hàng", AutoSize = true, ForeColor = Theme.TextMuted, Font = Theme.FontUi(9f), Margin = new Padding(0, 4, 0, 2) }, 0, 3);
        stack.Controls.Add(_storeCode, 0, 4);
        stack.Controls.Add(new Label { Text = "Tài khoản", AutoSize = true, ForeColor = Theme.TextMuted, Font = Theme.FontUi(9f), Margin = new Padding(0, 8, 0, 2) }, 0, 5);
        stack.Controls.Add(_user, 0, 6);
        stack.Controls.Add(new Label { Text = "Mật khẩu", AutoSize = true, ForeColor = Theme.TextMuted, Font = Theme.FontUi(9f), Margin = new Padding(0, 8, 0, 2) }, 0, 7);
        stack.Controls.Add(_pass, 0, 8);

        var opts = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0, 12, 0, 8) };
        opts.Controls.Add(_remember);
        opts.Controls.Add(_runAtBoot);
        stack.Controls.Add(opts, 0, 9);

        var bottom = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 70, Padding = new Padding(24, 8, 24, 12) };
        bottom.Controls.Add(_btnLogin);
        _loginHint.Text = "Máy chủ: " + AppSettings.DefaultApiBaseUrl;
        bottom.Controls.Add(_loginHint);

        card.Controls.Add(stack);
        card.Controls.Add(bottom);

        _loginPanel.Resize += (_, _) =>
        {
            card.Left = Math.Max(20, (_loginPanel.Width - card.Width) / 2);
            card.Top = Math.Max(20, (_loginPanel.Height - card.Height) / 2 - 10);
        };
        _loginPanel.Controls.Add(card);
    }

    void BuildMain()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 4,
            Padding = new Padding(14, 10, 14, 6),
        };
        // Danh sách máy chiếm nhiều chỗ nhất — không bị che
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 78));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 48));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 38));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 14));

        // —— Header ——
        var header = new TableLayoutPanel
        {
            Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 1, Margin = new Padding(0),
        };
        header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        header.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 250));
        var leftInfo = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 3, Margin = new Padding(0) };
        leftInfo.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        leftInfo.RowStyles.Add(new RowStyle(SizeType.Absolute, 22));
        leftInfo.RowStyles.Add(new RowStyle(SizeType.Absolute, 20));
        _storeTitle.Dock = DockStyle.Fill;
        _storeTitle.AutoEllipsis = true;
        _agentBadge.Dock = DockStyle.Fill;
        _agentBadge.AutoEllipsis = true;
        _storeSub.Dock = DockStyle.Fill;
        _storeSub.AutoEllipsis = true;
        _storeSub.ForeColor = Theme.Text;
        leftInfo.Controls.Add(_storeTitle, 0, 0);
        leftInfo.Controls.Add(_agentBadge, 0, 1);
        leftInfo.Controls.Add(_storeSub, 0, 2);
        var rightBtns = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill, FlowDirection = FlowDirection.RightToLeft,
            WrapContents = false, Padding = new Padding(0, 6, 0, 0),
        };
        rightBtns.Controls.Add(_btnLogout);
        rightBtns.Controls.Add(_btnRefresh);
        header.Controls.Add(leftInfo, 0, 0);
        header.Controls.Add(rightBtns, 1, 0);
        root.Controls.Add(header, 0, 0);

        // —— Danh sách máy (TableLayout: title + list + nút — không Dock chồng) ——
        var listCard = new CardPanel { Dock = DockStyle.Fill, Padding = new Padding(12, 10, 12, 8) };
        var listGrid = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 3, Margin = new Padding(0) };
        listGrid.RowStyles.Add(new RowStyle(SizeType.Absolute, 26));
        listGrid.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        listGrid.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
        listGrid.Controls.Add(new Label
        {
            Text = "Máy in trên máy này (đã kết nối tại PC)",
            Font = Theme.FontSection, ForeColor = Theme.Text, AutoSize = true, Dock = DockStyle.Left,
        }, 0, 0);
        listGrid.Controls.Add(_printerView, 0, 1);
        listGrid.Controls.Add(MakeButtonRow(_btnTest, _btnCheckOnline, _btnRename, _btnDelete), 0, 2);
        listCard.Controls.Add(listGrid);
        root.Controls.Add(listCard, 0, 1);

        // —— Thêm LAN + USB ——
        var addRow = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 1, Margin = new Padding(0) };
        addRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 58));
        addRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 42));

        var lanCard = new CardPanel { Dock = DockStyle.Fill, Margin = new Padding(0, 8, 8, 0), Padding = new Padding(12, 10, 12, 8) };
        var lanGrid = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 7, Margin = new Padding(0) };
        lanGrid.RowStyles.Add(new RowStyle(SizeType.Absolute, 22));
        lanGrid.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
        lanGrid.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
        lanGrid.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
        lanGrid.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
        lanGrid.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        lanGrid.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
        lanGrid.Controls.Add(new Label
        {
            Text = "Thêm máy in mạng (LAN)",
            Font = Theme.FontSection, ForeColor = Theme.Text, AutoSize = true,
        }, 0, 0);
        lanGrid.Controls.Add(_nameBox, 0, 1);
        lanGrid.Controls.Add(_lanIp, 0, 2);
        lanGrid.Controls.Add(_lanPort, 0, 3);
        lanGrid.Controls.Add(_subnet, 0, 4);
        lanGrid.Controls.Add(_hitList, 0, 5);
        lanGrid.Controls.Add(MakeButtonRow(_btnScan, _btnTestIp, _btnAddLan), 0, 6);
        lanCard.Controls.Add(lanGrid);
        addRow.Controls.Add(lanCard, 0, 0);

        var usbCard = new CardPanel { Dock = DockStyle.Fill, Margin = new Padding(8, 8, 0, 0), Padding = new Padding(12, 10, 12, 8) };
        var usbGrid = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 3, Margin = new Padding(0) };
        usbGrid.RowStyles.Add(new RowStyle(SizeType.Absolute, 22));
        usbGrid.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        usbGrid.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
        usbGrid.Controls.Add(new Label
        {
            Text = "Thêm máy in USB (Windows)",
            Font = Theme.FontSection, ForeColor = Theme.Text, AutoSize = true,
        }, 0, 0);
        usbGrid.Controls.Add(_usbList, 0, 1);
        usbGrid.Controls.Add(MakeButtonRow(_btnUsbRefresh, _btnUsbTest, _btnAddUsb), 0, 2);
        usbCard.Controls.Add(usbGrid);
        addRow.Controls.Add(usbCard, 1, 0);
        root.Controls.Add(addRow, 0, 2);

        var logCard = new CardPanel { Dock = DockStyle.Fill, Margin = new Padding(0, 8, 0, 0), Padding = new Padding(10, 8, 10, 8) };
        var logGrid = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 2, ColumnCount = 1 };
        logGrid.RowStyles.Add(new RowStyle(SizeType.Absolute, 20));
        logGrid.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        logGrid.Controls.Add(new Label
        {
            Text = "Nhật ký", Font = Theme.FontUi(9f, FontStyle.Bold),
            ForeColor = Theme.TextMuted, AutoSize = true,
        }, 0, 0);
        logGrid.Controls.Add(_logBox, 0, 1);
        logCard.Controls.Add(logGrid);
        root.Controls.Add(logCard, 0, 3);

        _mainPanel.Controls.Add(root);
    }

    static Panel MakeButtonRow(params Control[] buttons)
    {
        var flow = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            Padding = new Padding(0, 4, 0, 0),
            Margin = new Padding(0),
        };
        foreach (var b in buttons)
        {
            b.Margin = new Padding(0, 0, 8, 0);
            flow.Controls.Add(b);
        }
        return flow;
    }

    void WireEvents()
    {
        _btnLogin.Click += async (_, _) => await LoginAsync(silent: false);
        _btnLogout.Click += async (_, _) => await LogoutAsync();
        _btnRefresh.Click += async (_, _) => await FullRefreshAsync();
        _btnScan.Click += async (_, _) => await ScanLanAsync();
        _btnTestIp.Click += async (_, _) => await TestLanIpAsync();
        _btnAddLan.Click += async (_, _) => await AddLanAsync();
        _btnCheckOnline.Click += async (_, _) =>
        {
            Log("Đang kiểm tra online…");
            await ProbeHealthAsync();
        };
        _btnUsbRefresh.Click += (_, _) => RefreshUsbList();
        _btnUsbTest.Click += (_, _) => TestUsbSelected();
        _btnAddUsb.Click += async (_, _) => await AddUsbAsync();
        _btnRename.Click += async (_, _) => await RenameSelectedAsync();
        _btnTest.Click += async (_, _) => await TestSelectedAsync();
        _btnDelete.Click += async (_, _) => await DeleteSelectedAsync();
        _runAtBoot.CheckedChanged += (_, _) => ApplyBoot(_runAtBoot.Checked, quiet: true);
        _printerView.SelectedIndexChanged += (_, _) =>
        {
            var p = SelectedPrinter();
            if (p == null) return;
            _nameBox.Text = p.Name;
            if (ConnLabel.IsLan(p))
            {
                _lanIp.Text = p.LanHost ?? "";
                _lanPort.Text = (p.LanPort > 0 ? p.LanPort : 9100).ToString();
            }
            // Làm nổi nút in thử khi máy Online
            var on = _online.TryGetValue(p.Id, out var ok) && ok;
            _btnTest.Kind = on ? ModernButton.StyleKind.Primary : ModernButton.StyleKind.Secondary;
        };
        _hitList.DoubleClick += async (_, _) => await AddLanAsync();
        _hitList.SelectedIndexChanged += (_, _) =>
        {
            if (_hitList.SelectedIndex < 0 || _hitList.SelectedIndex >= _hits.Count) return;
            var h = _hits[_hitList.SelectedIndex];
            _lanIp.Text = h.Host;
            _lanPort.Text = h.Port.ToString();
            if (string.IsNullOrWhiteSpace(_nameBox.Text) || _nameBox.Text.StartsWith("Máy in ", StringComparison.OrdinalIgnoreCase))
                _nameBox.Text = "Máy in " + h.Host;
        };
        _usbList.SelectedIndexChanged += (_, _) =>
        {
            if (_usbList.SelectedItem is string n)
                _nameBox.Text = n;
        };
    }

    void SetupTray()
    {
        _tray.Icon = Icon ?? SystemIcons.Application;
        _tray.Text = "SBOX máy in";
        _tray.Visible = true;
        _tray.DoubleClick += (_, _) => { Show(); WindowState = FormWindowState.Normal; Activate(); };
        var menu = new ContextMenuStrip();
        menu.Items.Add("Mở cửa sổ", null, (_, _) => { Show(); WindowState = FormWindowState.Normal; Activate(); });
        menu.Items.Add("Thoát hẳn", null, async (_, _) =>
        {
            if (_agent != null) await _agent.DisposeAsync();
            _agent = null;
            _tray.Visible = false;
            Application.Exit();
        });
        _tray.ContextMenuStrip = menu;
    }

    void ShowMain(bool loggedIn)
    {
        _loginPanel.Visible = !loggedIn;
        _mainPanel.Visible = loggedIn;
        if (loggedIn) StartHealthTimer();
        else StopHealthTimer();
    }

    void ApplyBoot(bool enabled, bool quiet)
    {
        try
        {
            WindowsStartup.SetEnabled(enabled);
            _settings.RunAtWindowsStartup = enabled;
            _settings.Save();
            if (!quiet)
                Log(enabled ? "Đã bật tự chạy khi mở Windows." : "Đã tắt tự chạy Windows.");
        }
        catch (Exception ex)
        {
            _runAtBoot.Checked = WindowsStartup.IsEnabled();
            if (!quiet) UiMsg.Error(ex.Message, "Không đặt được tự chạy");
        }
    }

    void Log(string msg)
    {
        var line = $"[{DateTime.Now:HH:mm:ss}] {msg}";
        try
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "SboxPrintAgent");
            Directory.CreateDirectory(dir);
            var logPath = Path.Combine(dir, "agent.log");
            try
            {
                var fi = new FileInfo(logPath);
                if (fi.Exists && fi.Length > 2_000_000)
                {
                    var bak = Path.Combine(dir, "agent.prev.log");
                    if (File.Exists(bak)) File.Delete(bak);
                    File.Move(logPath, bak);
                }
            }
            catch { /* ignore */ }
            File.AppendAllText(logPath, line + Environment.NewLine);
        }
        catch { /* ignore */ }

        void Append()
        {
            _logBox.AppendText(line + Environment.NewLine);
            _footer.Text = msg.Length > 110 ? msg[..110] + "…" : msg;
        }
        if (InvokeRequired) BeginInvoke(Append);
        else Append();
    }

    async Task LoginAsync(bool silent)
    {
        try
        {
            _btnLogin.Enabled = false;
            var baseUrl = string.IsNullOrWhiteSpace(_settings.ApiBaseUrl)
                ? AppSettings.DefaultApiBaseUrl
                : _settings.ApiBaseUrl.Trim().TrimEnd('/');
            if (!baseUrl.StartsWith("http", StringComparison.OrdinalIgnoreCase))
                baseUrl = "https://" + baseUrl;

            if (string.IsNullOrWhiteSpace(_storeCode.Text))
                throw new InvalidOperationException("Nhập mã cửa hàng.");
            if (string.IsNullOrWhiteSpace(_user.Text))
                throw new InvalidOperationException("Nhập tài khoản.");

            if (_api == null || !string.Equals(_api.BaseUrl, baseUrl, StringComparison.OrdinalIgnoreCase))
                _api = new SboxApiClient(baseUrl);

            await _api.LoginAsync(_storeCode.Text.Trim(), _user.Text.Trim(), _pass.Text, CancellationToken.None);

            _settings.ApiBaseUrl = baseUrl;
            _settings.StoreCode = _storeCode.Text.Trim();
            _settings.Username = _user.Text.Trim();
            _settings.RememberPassword = _remember.Checked;
            _settings.Password = _remember.Checked ? _pass.Text : "";
            _settings.AutoStartAgent = true;
            if (_api.StoreId.HasValue) _settings.StoreId = _api.StoreId.Value;
            _settings.Save();
            ApplyBoot(_runAtBoot.Checked, quiet: true);

            _storeTitle.Text = "Cửa hàng " + _settings.StoreCode;
            _storeSub.Text = "Tài khoản: " + (_api.DisplayName ?? _settings.Username)
                + "   ·   " + AgentService.AppVersion;
            ShowMain(true);
            RefreshUsbList();
            await RefreshPrintersAsync();
            await SyncAgentIfNeededAsync();
            await ProbeHealthAsync();
            Log($"Đăng nhập OK · {_settings.StoreCode}");
            if (!silent)
                UiMsg.Info("Đã đăng nhập.\nThêm máy in LAN/USB nếu chưa có — lệnh in do server đẩy xuống.", "SBOX");
        }
        catch (Exception ex)
        {
            Log("Đăng nhập lỗi: " + UiMsg.ToVi(ex.Message));
            if (!silent) UiMsg.Error(ex.Message, "Đăng nhập thất bại");
        }
        finally { _btnLogin.Enabled = true; }
    }

    async Task LogoutAsync()
    {
        try
        {
            if (_agent != null)
            {
                await _agent.StopAsync(markOffline: true);
                await _agent.DisposeAsync();
                _agent = null;
            }
        }
        catch { /* ignore */ }
        _api = null;
        _printers.Clear();
        _online.Clear();
        _agentServingIds = Array.Empty<Guid>();
        _printerView.Items.Clear();
        UpdateAgentBadge();
        ShowMain(false);
        Log("Đã đăng xuất.");
    }

    async Task FullRefreshAsync()
    {
        if (_api == null) return;
        try
        {
            _btnRefresh.Enabled = false;
            Log("Đang làm mới danh sách máy in…");
            RefreshUsbList();
            await RefreshPrintersAsync();
            await SyncAgentIfNeededAsync();
            await ProbeHealthAsync();
            Log($"Làm mới xong · {_printers.Count} máy cloud · {_usbList.Items.Count} USB Windows.");
        }
        finally { _btnRefresh.Enabled = true; }
    }

    async Task RefreshPrintersAsync()
    {
        if (_api == null) return;
        try
        {
            var raw = await _api.ListPrintersAsync(CancellationToken.None);
            var candidates = PrinterListNormalize.ForWindowsAgent(raw);
            var localIds = _settings.LocalPrinterGuidSet();
            var detached = _settings.DetachedPrinterGuidSet();
            var winQueues = WindowsSpooler.ListInstalledPrinters();

            // Chỉ máy gắn với PC này — không hiện toàn bộ máy trên server.
            // Máy đã «Gỡ khỏi PC» nằm trong Detached → bỏ qua dù USB/LAN vẫn thấy.
            var local = new List<PrinterItem>();
            foreach (var p in candidates)
            {
                if (detached.Contains(p.Id))
                    continue;

                if (ConnLabel.IsUsb(p))
                {
                    var want = (p.UsbDeviceName ?? "").Trim();
                    if (want.Length == 0) continue;
                    var resolved = WindowsSpooler.ResolvePrinterName(want);
                    var onThisPc = winQueues.Any(n =>
                        string.Equals(n, resolved, StringComparison.OrdinalIgnoreCase) ||
                        string.Equals(n, want, StringComparison.OrdinalIgnoreCase));
                    // USB: chỉ hiện khi đã gắn (Local) hoặc lần đầu chưa có Local nào.
                    var allowUsb = localIds.Contains(p.Id) || _settings.LocalPrinterIds.Count == 0;
                    if (onThisPc && allowUsb)
                    {
                        local.Add(p);
                        localIds.Add(p.Id);
                    }
                }
                else if (ConnLabel.IsLan(p))
                {
                    // LAN: chỉ hiện nếu đã thêm từ PC này (không tự kéo mọi IP online).
                    if (!localIds.Contains(p.Id))
                        continue;
                    var host = (p.LanHost ?? "").Trim();
                    if (host.Length == 0) continue;
                    var port = p.LanPort > 0 ? p.LanPort : 9100;
                    var reachable = await TcpReachableAsync(host, port, 700);
                    local.Add(p);
                    _online[p.Id] = reachable;
                }
            }

            // Lần đầu (chưa gắn máy nào): seed USB đang cắm trên PC + LAN đang online (không detached).
            if (_settings.LocalPrinterIds.Count == 0 && local.Count == 0)
            {
                foreach (var p in candidates)
                {
                    if (detached.Contains(p.Id)) continue;
                    if (ConnLabel.IsUsb(p))
                    {
                        var want = (p.UsbDeviceName ?? "").Trim();
                        if (want.Length == 0) continue;
                        var resolved = WindowsSpooler.ResolvePrinterName(want);
                        if (winQueues.Any(n =>
                                string.Equals(n, resolved, StringComparison.OrdinalIgnoreCase) ||
                                string.Equals(n, want, StringComparison.OrdinalIgnoreCase)))
                        {
                            local.Add(p);
                            localIds.Add(p.Id);
                        }
                    }
                    else if (ConnLabel.IsLan(p) && !string.IsNullOrWhiteSpace(p.LanHost))
                    {
                        var port = p.LanPort > 0 ? p.LanPort : 9100;
                        if (await TcpReachableAsync(p.LanHost!, port, 700))
                        {
                            local.Add(p);
                            localIds.Add(p.Id);
                            _online[p.Id] = true;
                        }
                    }
                }
            }

            _settings.LocalPrinterIds = localIds
                .Where(id => !detached.Contains(id))
                .Select(x => x.ToString("D"))
                .Distinct()
                .ToList();
            _printers = local
                .GroupBy(p => p.Id)
                .Select(g => g.First())
                .OrderBy(p => p.Name, StringComparer.CurrentCultureIgnoreCase)
                .ToList();

            _settings.AssignedPrinterIds = _printers.Select(p => p.Id.ToString("D")).ToList();
            _settings.Save();

            foreach (var gone in _online.Keys.Except(_printers.Select(p => p.Id)).ToList())
                _online.Remove(gone);

            RenderPrinterList();
            var hidden = candidates.Count - _printers.Count;
            Log(hidden > 0
                ? $"Máy trên PC này: {_printers.Count} (ẩn {hidden} máy server/đã gỡ)."
                : $"Máy trên PC này: {_printers.Count}.");
        }
        catch (Exception ex)
        {
            Log("Tải máy in: " + UiMsg.ToVi(ex.Message));
        }
    }

    /// <summary>Chỉ restart Agent khi danh sách máy đổi — tránh làm mới làm đứt kết nối.</summary>
    async Task SyncAgentIfNeededAsync()
    {
        if (_api == null) return;
        var ids = _printers.Select(p => p.Id).OrderBy(x => x).ToArray();
        var running = _agent?.IsRunning == true;

        if (ids.Length == 0)
        {
            if (running)
            {
                await _agent!.StopAsync(markOffline: true);
                _agentServingIds = Array.Empty<Guid>();
                UpdateAgentBadge();
            }
            return;
        }

        var same = running &&
                   ids.Length == _agentServingIds.Length &&
                   ids.SequenceEqual(_agentServingIds);
        if (same && _agent != null)
        {
            _agent.SetPrinterCache(_printers);
            return;
        }

        await EnsureAgentRunningAsync();
        _agentServingIds = ids;
    }

    void RenderPrinterList()
    {
        var selectedId = SelectedPrinter()?.Id;
        _printerView.BeginUpdate();
        _printerView.Items.Clear();
        foreach (var p in _printers)
        {
            var localOn = _online.TryGetValue(p.Id, out var on) && on;
            var status = localOn ? "● Online" : "○ Offline";
            var addr = ConnLabel.IsUsb(p)
                ? (p.UsbDeviceName ?? "—")
                : $"{p.LanHost}:{p.LanPort}";
            var item = new ListViewItem(status) { Tag = p.Id, UseItemStyleForSubItems = false };
            item.SubItems.Add(p.Name);
            item.SubItems.Add(ConnLabel.Vi(p.ConnectionType));
            item.SubItems.Add(addr);
            item.SubItems.Add(localOn ? "Online" : (string.IsNullOrWhiteSpace(p.HealthStatus) ? "—" : p.HealthStatus));

            var fg = localOn ? Color.FromArgb(5, 150, 105) : Color.FromArgb(100, 116, 139);
            var bg = localOn ? Color.FromArgb(220, 252, 231) : Color.FromArgb(248, 250, 252);
            item.ForeColor = fg;
            item.BackColor = bg;
            foreach (ListViewItem.ListViewSubItem sub in item.SubItems)
            {
                sub.ForeColor = fg;
                sub.BackColor = bg;
            }
            // Cột trạng thái đậm hơn
            item.SubItems[0].ForeColor = localOn ? Color.FromArgb(4, 120, 87) : Color.FromArgb(148, 163, 184);
            item.Font = localOn
                ? Theme.FontUi(10f, FontStyle.Bold)
                : Theme.FontUi(10f);

            _printerView.Items.Add(item);
            if (selectedId == p.Id) item.Selected = true;
        }
        _printerView.EndUpdate();
    }

    void PrinterView_DrawColumnHeader(object? sender, DrawListViewColumnHeaderEventArgs e)
    {
        e.DrawDefault = true;
    }

    void PrinterView_DrawSubItem(object? sender, DrawListViewSubItemEventArgs e)
    {
        if (e.Item == null || e.SubItem == null) return;
        var selected = e.Item.Selected;
        var bg = selected
            ? Color.FromArgb(204, 251, 241)
            : e.SubItem.BackColor;
        var fg = e.SubItem.ForeColor;
        using var brush = new SolidBrush(bg);
        e.Graphics.FillRectangle(brush, e.Bounds);
        TextRenderer.DrawText(
            e.Graphics,
            e.SubItem.Text,
            e.SubItem.Font ?? _printerView.Font,
            e.Bounds,
            fg,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
    }

    PrinterItem? SelectedPrinter()
    {
        if (_printerView.SelectedItems.Count == 0) return null;
        if (_printerView.SelectedItems[0].Tag is not Guid id) return null;
        return _printers.FirstOrDefault(p => p.Id == id);
    }

    async Task EnsureAgentRunningAsync()
    {
        if (_api == null) return;
        var ids = _printers.Select(p => p.Id).ToList();
        if (ids.Count == 0)
        {
            UpdateAgentBadge();
            Log("Chưa có máy in — thêm LAN/USB rồi Agent sẽ tự nhận lệnh.");
            return;
        }

        try
        {
            if (_agent != null)
            {
                try { await _agent.DisposeAsync(); } catch { /* ignore */ }
                _agent = null;
            }

            _agent = new AgentService(_api, _settings, Log);
            _agent.SetPrinterCache(_printers);
            _agent.SetReloginHandler(async ct =>
            {
                var api = _api ?? throw new InvalidOperationException("Chưa đăng nhập");
                var pass = _settings.RememberPassword ? _settings.Password : _pass.Text;
                if (string.IsNullOrWhiteSpace(pass))
                    throw new InvalidOperationException("Thiếu mật khẩu để đăng nhập lại.");
                await api.LoginAsync(_settings.StoreCode, _settings.Username, pass, ct);
            });
            _agent.StateChanged += () =>
            {
                if (InvokeRequired) BeginInvoke(UpdateAgentBadge);
                else UpdateAgentBadge();
            };
            _agent.ForceStoppedRemotely += () =>
            {
                BeginInvoke(() =>
                {
                    UpdateAgentBadge();
                    UiMsg.Warn("Nhận lệnh in bị tắt từ thiết bị khác.", "Đã tắt");
                });
            };

            await _agent.StartAsync(ids);
            _agentServingIds = ids.OrderBy(x => x).ToArray();
            UpdateAgentBadge();
            Log($"Đang nhận lệnh in từ server · {_printers.Count} máy.");
        }
        catch (Exception ex)
        {
            _agentServingIds = Array.Empty<Guid>();
            UpdateAgentBadge();
            Log("Không bật nhận lệnh: " + UiMsg.ToVi(ex.Message));
        }
    }

    void UpdateAgentBadge()
    {
        var on = _agent?.IsRunning == true;
        _agentBadge.Text = on ? "● Đang nhận lệnh từ server" : "○ Chưa nhận lệnh";
        _agentBadge.ForeColor = on ? Theme.Success : Theme.Warning;
        _tray.Text = on ? "SBOX máy in (đang nhận lệnh)" : "SBOX máy in";
    }

    void RefreshUsbList()
    {
        _usbList.Items.Clear();
        try
        {
            var skip = new[] { "fax", "microsoft print to pdf", "microsoft xps", "onenote", "send to onenote" };
            var list = WindowsSpooler.ListInstalledPrinters()
                .Where(n => !skip.Any(s => n.Contains(s, StringComparison.OrdinalIgnoreCase)))
                .ToList();
            foreach (var n in list)
                _usbList.Items.Add(n);
            Log($"USB thật trên Windows: {list.Count} máy (đã ẩn Fax/PDF).");
        }
        catch (Exception ex)
        {
            UiMsg.Error(ex.Message, "Không đọc được máy in USB");
        }
    }

    void TestUsbSelected()
    {
        if (_usbList.SelectedItem is not string name)
        {
            UiMsg.Warn("Chọn máy USB trong danh sách rồi bấm In thử USB.");
            return;
        }
        try
        {
            WindowsSpooler.SendTest(name);
            Log($"In thử USB → {name}");
            UiMsg.Info($"Đã gửi trang in thử tới «{name}».\nNếu ra giấy → bấm Thêm máy USB.", "In thử USB");
        }
        catch (Exception ex) { UiMsg.Error(ex.Message, "In thử USB thất bại"); }
    }

    async Task ScanLanAsync()
    {
        try
        {
            _btnScan.Enabled = false;
            _hitList.Items.Clear();
            _hits.Clear();
            _settings.SubnetPrefix = SubnetNormalize.Clean(_subnet.Text);
            _subnet.Text = _settings.SubnetPrefix;
            _settings.Save();
            Log($"Đang tìm máy in LAN {_settings.SubnetPrefix}.1–254 :9100…");
            var list = await LanScanner.ScanAsync(
                string.IsNullOrWhiteSpace(_settings.SubnetPrefix) ? null : _settings.SubnetPrefix,
                log: new Progress<string>(s => Log(s)),
                ct: CancellationToken.None);
            _hits.AddRange(list);
            foreach (var h in list)
                _hitList.Items.Add($"{h.Host}:{h.Port}  ({h.LatencyMs} ms)");
            if (list.Count == 0)
            {
                UiMsg.Warn("Không tìm thấy máy in trên mạng.\nKiểm tra cùng Wi‑Fi/LAN với máy in.");
            }
            else
            {
                _hitList.SelectedIndex = 0;
                var first = list[0];
                _lanIp.Text = first.Host;
                _lanPort.Text = first.Port.ToString();
                if (string.IsNullOrWhiteSpace(_nameBox.Text) ||
                    _nameBox.Text.StartsWith("Máy in ", StringComparison.OrdinalIgnoreCase) ||
                    _nameBox.Text.Contains("usb", StringComparison.OrdinalIgnoreCase))
                    _nameBox.Text = "Máy in " + first.Host;
                Log($"Tìm thấy {list.Count} máy. Bấm «In thử IP» rồi «Thêm máy LAN».");
            }
        }
        catch (Exception ex)
        {
            UiMsg.Error(ex.Message, "Tìm máy in");
        }
        finally { _btnScan.Enabled = true; }
    }

    async Task TestLanIpAsync()
    {
        SyncLanFieldsFromSelection();
        var host = _lanIp.Text.Trim();
        if (string.IsNullOrWhiteSpace(host))
        {
            UiMsg.Warn("Nhập IP hoặc Quét mạng → chọn IP trước khi in thử.");
            return;
        }
        if (!int.TryParse(_lanPort.Text.Trim(), out var port) || port <= 0)
            port = 9100;

        try
        {
            _btnTestIp.Enabled = false;
            Log($"In thử IP {host}:{port} (chưa lưu lên server)…");
            var ok = await TcpReachableAsync(host, port, 2500);
            if (!ok)
            {
                UiMsg.Error($"Không kết nối TCP {host}:{port}.\nKiểm tra máy in / cùng mạng.", "In thử thất bại");
                return;
            }
            await LanScanner.SendTestAsync(host, port, "SBOX test " + host, CancellationToken.None);
            Log($"✓ Đã gửi in thử → {host}:{port}");
            UiMsg.Info(
                $"Đã gửi trang in thử tới {host}:{port}.\n" +
                "Nếu ra giấy đúng → bấm «Thêm máy LAN» để lưu và nhận lệnh từ server.",
                "In thử IP thành công");
        }
        catch (Exception ex) { UiMsg.Error(ex.Message, "In thử IP thất bại"); }
        finally { _btnTestIp.Enabled = true; }
    }

    void SyncLanFieldsFromSelection()
    {
        if (_hitList.SelectedIndex < 0 || _hitList.SelectedIndex >= _hits.Count) return;
        var h = _hits[_hitList.SelectedIndex];
        _lanIp.Text = h.Host;
        _lanPort.Text = h.Port.ToString();
    }

    async Task ConnectLanByIpAsync()
    {
        if (_api == null) { UiMsg.Warn("Hãy đăng nhập trước."); return; }
        SyncLanFieldsFromSelection();

        var host = _lanIp.Text.Trim();
        if (string.IsNullOrWhiteSpace(host))
        {
            UiMsg.Warn("Nhập IP máy in (vd: 192.168.1.230).");
            return;
        }
        if (!int.TryParse(_lanPort.Text.Trim(), out var port) || port <= 0)
            port = 9100;

        var name = _nameBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(name) ||
            name.Contains("usb", StringComparison.OrdinalIgnoreCase))
            name = "Máy in " + host;

        try
        {
            _btnAddLan.Enabled = false;
            Log($"Đang kết nối {host}:{port}…");
            var ok = await TcpReachableAsync(host, port, 2500);
            if (!ok)
            {
                UiMsg.Error(
                    $"Không kết nối được {host}:{port}.\n" +
                    "Nên bấm «In thử IP» trước để kiểm tra.",
                    "Kết nối thất bại");
                return;
            }

            Log($"✓ TCP OK {host}:{port}");

            var dup = _printers.FirstOrDefault(p =>
                ConnLabel.IsLan(p) &&
                string.Equals(p.LanHost, host, StringComparison.OrdinalIgnoreCase) &&
                (p.LanPort <= 0 ? 9100 : p.LanPort) == port);

            Guid id;
            if (dup != null)
            {
                id = dup.Id;
                await _api.UpdateLanPrinterAsync(dup.Id, name, host, port, dup.PaperSize,
                    dup.IsDefault, true, sortOrder: 0, CancellationToken.None);
                Log($"Đã cập nhật máy có sẵn «{name}»");
            }
            else
            {
                id = await _api.CreateLanPrinterAsync(name, host, port, "K80", isDefault: false, CancellationToken.None);
                var roles = new[] { "SaleInvoice", "KitchenSlip", "StockIssue", "KitchenLabel" };
                var merged = RouteMerge.AssignTypes(await _api.GetRoutesAsync(CancellationToken.None), roles, id);
                await _api.SaveRoutesAsync(merged, CancellationToken.None);
                Log($"Đã thêm LAN «{name}» → {host}:{port}");
            }

            _online[id] = true;
            _settings.RememberLocalPrinter(id);
            await RefreshPrintersAsync();
            await SyncAgentIfNeededAsync();
            await ProbeHealthAsync();

            // In thử sau khi đã online trên danh sách
            try
            {
                await LanScanner.SendTestAsync(host, port, name, CancellationToken.None);
                Log($"✓ In thử sau kết nối → {name}");
            }
            catch (Exception ex)
            {
                Log("In thử sau kết nối lỗi: " + ex.Message);
            }

            UiMsg.Info(
                $"Đã thêm «{name}» ({host}:{port}) — Online.\n" +
                "Đã gửi thêm 1 trang in thử sau khi kết nối.\n" +
                "Sau này chọn máy trong danh sách → «In thử máy này».",
                "Thành công");
        }
        catch (Exception ex) { UiMsg.Error(ex.Message, "Thêm máy LAN thất bại"); }
        finally { _btnAddLan.Enabled = true; }
    }

    async Task AddLanAsync()
    {
        if (_api == null) { UiMsg.Warn("Hãy đăng nhập trước."); return; }

        if (_hitList.SelectedIndex >= 0 && _hitList.SelectedIndex < _hits.Count)
        {
            var hit = _hits[_hitList.SelectedIndex];
            _lanIp.Text = hit.Host;
            _lanPort.Text = hit.Port.ToString();
        }
        else if (string.IsNullOrWhiteSpace(_lanIp.Text))
        {
            UiMsg.Warn(
                "Cách thêm máy LAN:\n" +
                "1) Quét mạng → chọn IP → In thử IP → Thêm máy LAN\n" +
                "2) Hoặc nhập IP trực tiếp → In thử IP → Thêm máy LAN");
            return;
        }

        await ConnectLanByIpAsync();
    }

    async Task AddUsbAsync()
    {
        if (_api == null) { UiMsg.Warn("Hãy đăng nhập trước."); return; }
        if (_usbList.SelectedItem is not string winName)
        {
            UiMsg.Warn("Chọn máy in USB trong danh sách Windows.");
            return;
        }
        var name = _nameBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(name)) name = winName;

        try
        {
            _btnAddUsb.Enabled = false;
            // Tìm trên server theo tên queue Windows (có thể chưa hiện vì lọc local).
            var raw = await _api.ListPrintersAsync(CancellationToken.None);
            var existing = PrinterListNormalize.ForWindowsAgent(raw).FirstOrDefault(p =>
                ConnLabel.IsUsb(p) &&
                string.Equals(p.UsbDeviceName, winName, StringComparison.OrdinalIgnoreCase));
            Guid id;
            if (existing != null)
            {
                id = existing.Id;
                Log("Máy USB đã có trên server — gắn vào PC này.");
            }
            else
            {
                id = await _api.CreateUsbPrinterAsync(name, winName, "K80", isDefault: false, CancellationToken.None);
            }

            var roles = new[] { "SaleInvoice", "KitchenSlip", "StockIssue", "KitchenLabel" };
            var merged = RouteMerge.AssignTypes(await _api.GetRoutesAsync(CancellationToken.None), roles, id);
            await _api.SaveRoutesAsync(merged, CancellationToken.None);

            _settings.RememberLocalPrinter(id);
            await RefreshPrintersAsync();
            await SyncAgentIfNeededAsync();
            await ProbeHealthAsync();
            _nameBox.Text = "";
            Log($"Đã thêm USB «{name}»");
            UiMsg.Info($"Đã thêm máy in «{name}» vào máy này.", "Thành công");
        }
        catch (Exception ex) { UiMsg.Error(ex.Message, "Không thêm được máy USB"); }
        finally { _btnAddUsb.Enabled = true; }
    }

    async Task RenameSelectedAsync()
    {
        if (_api == null) return;
        var p = SelectedPrinter();
        if (p == null) { UiMsg.Warn("Chọn máy in trong danh sách."); return; }
        var name = _nameBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(name)) { UiMsg.Warn("Nhập tên mới."); return; }

        try
        {
            if (ConnLabel.IsLan(p))
            {
                await _api.UpdateLanPrinterAsync(p.Id, name, p.LanHost!, p.LanPort, p.PaperSize,
                    p.IsDefault, p.IsActive, sortOrder: 0, CancellationToken.None);
            }
            else
            {
                // USB: tạo lại tên qua update LAN API không khớp — dùng UpdateLan chỉ LAN.
                // Tạm: xóa+tạo lại không an toàn. Thêm UpdateUsb nếu thiếu.
                await UpdateUsbNameAsync(p, name);
            }
            await RefreshPrintersAsync();
            Log($"Đã đổi tên → «{name}»");
        }
        catch (Exception ex) { UiMsg.Error(ex.Message, "Đổi tên thất bại"); }
    }

    async Task UpdateUsbNameAsync(PrinterItem p, string name)
    {
        // API hiện chỉ có UpdateLan — gửi PUT chung qua UpdateLanPrinterAsync không đúng connectionType.
        // Dùng CreateUsb không được. Gọi Put với payload USB nếu có method — bổ sung client.
        await _api!.UpdateUsbPrinterAsync(p.Id, name, p.UsbDeviceName!, p.PaperSize,
            p.IsDefault, p.IsActive, CancellationToken.None);
    }

    async Task TestSelectedAsync()
    {
        var p = SelectedPrinter();
        if (p == null) { UiMsg.Warn("Chọn máy in trong danh sách (hàng xanh Online)."); return; }
        try
        {
            if (ConnLabel.IsUsb(p))
                WindowsSpooler.SendTest(p.UsbDeviceName!);
            else
                await LanScanner.SendTestAsync(p.LanHost!, p.LanPort > 0 ? p.LanPort : 9100, p.Name, CancellationToken.None);
            Log($"✓ In thử máy đã kết nối → {p.Name}");
            UiMsg.Info($"Đã gửi in thử tới «{p.Name}».", "In thử máy này");
        }
        catch (Exception ex) { UiMsg.Error(ex.Message, "In thử thất bại"); }
    }

    async Task DeleteSelectedAsync()
    {
        if (_api == null) return;
        var p = SelectedPrinter();
        if (p == null) { UiMsg.Warn("Chọn máy in."); return; }
        if (!UiMsg.Confirm(
                $"Gỡ máy in «{p.Name}» khỏi máy này?\n(Không xóa máy khỏi server cửa hàng — chỉ ẩn trên PC này.)",
                "Gỡ khỏi máy này")) return;
        try
        {
            _settings.ForgetLocalPrinter(p.Id);
            _printers.RemoveAll(x => x.Id == p.Id);
            _online.Remove(p.Id);
            RenderPrinterList();
            await SyncAgentIfNeededAsync();
            Log($"Đã gỡ «{p.Name}» khỏi PC này (không tự hiện lại).");
            UiMsg.Info($"Đã gỡ «{p.Name}» khỏi máy này.\nMuốn dùng lại: Thêm máy LAN/USB.", "Đã gỡ");
        }
        catch (Exception ex) { UiMsg.Error(ex.Message); }
    }

    void StartHealthTimer()
    {
        StopHealthTimer();
        _healthTimer = new System.Windows.Forms.Timer { Interval = 8000 };
        _healthTimer.Tick += async (_, _) => await ProbeHealthAsync();
        _healthTimer.Start();
    }

    void StopHealthTimer()
    {
        if (_healthTimer == null) return;
        _healthTimer.Stop();
        _healthTimer.Dispose();
        _healthTimer = null;
    }

    async Task ProbeHealthAsync()
    {
        if (_api == null || _printers.Count == 0) return;
        foreach (var p in _printers.ToList())
        {
            var ok = false;
            string? err = null;
            try
            {
                if (ConnLabel.IsUsb(p))
                {
                    var resolved = WindowsSpooler.ResolvePrinterName(p.UsbDeviceName ?? "");
                    ok = WindowsSpooler.ListInstalledPrinters()
                        .Any(n => string.Equals(n, resolved, StringComparison.OrdinalIgnoreCase));
                    if (!ok) err = "Không thấy máy in Windows";
                }
                else if (!string.IsNullOrWhiteSpace(p.LanHost))
                {
                    ok = await TcpReachableAsync(p.LanHost!, p.LanPort > 0 ? p.LanPort : 9100, 1200);
                    if (!ok) err = "Không kết nối TCP :9100";
                }
            }
            catch (Exception ex)
            {
                ok = false;
                err = ex.Message;
            }

            _online[p.Id] = ok;
            try
            {
                await _api.ReportHealthAsync(p.Id, ok ? "Online" : "Offline", err, CancellationToken.None);
            }
            catch { /* ignore */ }
        }

        if (IsHandleCreated && !IsDisposed)
        {
            if (InvokeRequired) BeginInvoke(RenderPrinterList);
            else RenderPrinterList();
        }
    }

    static async Task<bool> TcpReachableAsync(string host, int port, int timeoutMs)
    {
        try
        {
            using var client = new TcpClient();
            using var cts = new CancellationTokenSource(timeoutMs);
            await client.ConnectAsync(host, port, cts.Token);
            return client.Connected;
        }
        catch { return false; }
    }
}
