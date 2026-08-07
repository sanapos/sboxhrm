using SboxPrintAgent.Ui;

namespace SboxPrintAgent;

public sealed class MainForm : Form
{
    readonly AppSettings _settings = AppSettings.Load();
    SboxApiClient? _api;
    AgentService? _agent;
    readonly List<LanScanner.Hit> _hits = new();
    List<PrinterItem> _printers = new();
    List<RouteItem> _routes = new();

    readonly Panel _sidebar = new() { Dock = DockStyle.Left, Width = 228, BackColor = Theme.Sidebar };
    readonly Panel _contentHost = new() { Dock = DockStyle.Fill, BackColor = Theme.Bg, Padding = new Padding(20) };
    readonly Label _headerTitle = new() { AutoSize = true, Font = Theme.FontTitle, ForeColor = Theme.Text };
    readonly Label _headerSub = new() { AutoSize = true, Font = Theme.FontUi(9.5f), ForeColor = Theme.TextMuted };
    readonly Label _footerStatus = new() { Dock = DockStyle.Bottom, Height = 28, ForeColor = Theme.TextMuted, Font = Theme.FontUi(8.5f), Padding = new Padding(12, 6, 12, 0), BackColor = Theme.Bg };
    readonly NotifyIcon _tray = new();
    readonly Dictionary<string, Panel> _pages = new();
    readonly Dictionary<string, Button> _navButtons = new();

    // Đăng nhập
    readonly ModernTextBox _apiUrl = new() { Placeholder = "https://sboxhrm.com", Dock = DockStyle.Top };
    readonly ModernTextBox _storeCode = new() { Placeholder = "Mã cửa hàng", Dock = DockStyle.Top };
    readonly ModernTextBox _user = new() { Placeholder = "Email / số điện thoại / tên đăng nhập", Dock = DockStyle.Top };
    readonly ModernTextBox _pass = new() { Placeholder = "Mật khẩu", ShowPasswordToggle = true, Dock = DockStyle.Top };
    readonly CheckBox _remember = new() { Text = "Lưu mật khẩu trên máy này", AutoSize = true, ForeColor = Theme.Text, Font = Theme.FontUi() };
    readonly CheckBox _autoStart = new() { Text = "Tự bật nhận lệnh in sau khi đăng nhập", AutoSize = true, ForeColor = Theme.Text, Font = Theme.FontUi() };
    readonly CheckBox _runAtBoot = new() { Text = "Tự chạy mỗi khi mở máy (Windows)", AutoSize = true, ForeColor = Theme.Text, Font = Theme.FontUi() };
    readonly Label _connStatus = new() { AutoSize = true, ForeColor = Theme.TextMuted, Font = Theme.FontUi(9.5f), MaximumSize = new Size(640, 0) };
    readonly Label _deviceLbl = new() { AutoSize = true, ForeColor = Theme.TextMuted, Font = Theme.FontUi(9f) };
    readonly ModernButton _btnLogin = new() { Text = "Đăng nhập", Kind = ModernButton.StyleKind.Primary, Width = 180, Height = 44 };

    // Máy in mạng
    readonly ModernTextBox _subnet = new() { Placeholder = "Ví dụ: 192.168.1", Dock = DockStyle.Top };
    readonly ModernTextBox _printerName = new() { Placeholder = "Tên gọi máy in (vd: Máy quầy, Máy bếp)", Dock = DockStyle.Top };
    readonly ListBox _hitList = new() { Dock = DockStyle.Fill, Font = Theme.FontUi(10f), BorderStyle = BorderStyle.None, IntegralHeight = false };
    readonly CheckedListBox _newRoutes = new() { Dock = DockStyle.Fill, CheckOnClick = true, Font = Theme.FontUi(9.5f), BorderStyle = BorderStyle.None };
    readonly ComboBox _paperSize = new() { DropDownStyle = ComboBoxStyle.DropDownList, Font = Theme.FontUi(10f), Width = 140 };
    readonly ModernButton _btnScan = new() { Text = "Tìm máy in trên mạng", Kind = ModernButton.StyleKind.Primary, Width = 190 };
    readonly ModernButton _btnLanTest = new() { Text = "In thử", Kind = ModernButton.StyleKind.Secondary, Width = 100 };
    readonly ModernButton _btnCreateLan = new() { Text = "Lưu máy in này", Kind = ModernButton.StyleKind.Primary, Width = 180 };

    // USB
    readonly ListBox _usbList = new() { Dock = DockStyle.Fill, Font = Theme.FontUi(10f), BorderStyle = BorderStyle.None, IntegralHeight = false };
    readonly ModernTextBox _usbName = new() { Placeholder = "Tên gọi trên SBOX (vd: Máy in USB quầy)", Dock = DockStyle.Top };
    readonly CheckedListBox _usbRoutes = new() { Dock = DockStyle.Fill, CheckOnClick = true, Font = Theme.FontUi(9.5f), BorderStyle = BorderStyle.None };
    readonly ComboBox _usbPaper = new() { DropDownStyle = ComboBoxStyle.DropDownList, Font = Theme.FontUi(10f), Width = 140 };
    readonly ModernButton _btnUsbRefresh = new() { Text = "Tải danh sách máy in Windows", Kind = ModernButton.StyleKind.Secondary, Width = 240 };
    readonly ModernButton _btnUsbTest = new() { Text = "In thử", Kind = ModernButton.StyleKind.Secondary, Width = 100 };
    readonly ModernButton _btnCreateUsb = new() { Text = "Lưu máy in USB", Kind = ModernButton.StyleKind.Primary, Width = 180 };

    // Danh sách máy in
    readonly CheckedListBox _printerList = new() { Dock = DockStyle.Fill, CheckOnClick = true, Font = Theme.FontUi(9.5f), BorderStyle = BorderStyle.None };
    readonly Label _printerDetail = new() { Dock = DockStyle.Fill, Font = Theme.FontUi(9.5f), ForeColor = Theme.TextMuted };
    readonly ModernButton _btnRefreshPrinters = new() { Text = "Làm mới", Kind = ModernButton.StyleKind.Secondary, Width = 110 };
    readonly ModernButton _btnSaveAssign = new() { Text = "Lưu máy sẽ dùng", Kind = ModernButton.StyleKind.Primary, Width = 160 };
    readonly ModernButton _btnUpdateHost = new() { Text = "Đổi IP từ tìm mạng", Kind = ModernButton.StyleKind.Secondary, Width = 170 };
    readonly ModernButton _btnDeletePrinter = new() { Text = "Xóa máy in", Kind = ModernButton.StyleKind.Danger, Width = 120 };
    readonly ModernButton _btnCloudTest = new() { Text = "Gửi lệnh in thử", Kind = ModernButton.StyleKind.Secondary, Width = 160 };

    // Gán phiếu
    readonly DataGridView _routeGrid = new()
    {
        Dock = DockStyle.Fill,
        AllowUserToAddRows = false,
        AllowUserToDeleteRows = false,
        RowHeadersVisible = false,
        AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill,
        SelectionMode = DataGridViewSelectionMode.FullRowSelect,
        BackgroundColor = Theme.Card,
        BorderStyle = BorderStyle.None,
        Font = Theme.FontUi(9.5f),
        EnableHeadersVisualStyles = false,
    };
    readonly ModernButton _btnSaveRoutes = new() { Text = "Lưu cách gán phiếu", Kind = ModernButton.StyleKind.Primary, Width = 180 };

    // Nhận lệnh in
    readonly Label _agentStatus = new() { AutoSize = true, Font = Theme.FontSection, ForeColor = Theme.Text };
    readonly ListBox _agentsBox = new() { Dock = DockStyle.Fill, Font = Theme.FontUi(9.5f), BorderStyle = BorderStyle.None, IntegralHeight = false };
    readonly ModernButton _btnStart = new() { Text = "Bật nhận lệnh in", Kind = ModernButton.StyleKind.Primary, Width = 180 };
    readonly ModernButton _btnStop = new() { Text = "Tắt nhận lệnh in", Kind = ModernButton.StyleKind.Danger, Width = 170 };
    readonly ModernButton _btnRefreshAgents = new() { Text = "Làm mới", Kind = ModernButton.StyleKind.Secondary, Width = 110 };

    readonly TextBox _logBox = new()
    {
        Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill,
        BorderStyle = BorderStyle.None, Font = Theme.FontMono,
        BackColor = Color.FromArgb(15, 23, 42), ForeColor = Color.FromArgb(226, 232, 240),
    };

    public MainForm()
    {
        Text = "SBOX — Kết nối máy in";
        Width = 1140;
        Height = 780;
        MinimumSize = new Size(980, 680);
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Theme.Bg;
        Font = Theme.FontUi();
        DoubleBuffered = true;

        var icon = AppIcon.LoadIcon();
        if (icon != null) Icon = icon;

        _apiUrl.Text = string.IsNullOrWhiteSpace(_settings.ApiBaseUrl) ? AppSettings.DefaultApiBaseUrl : _settings.ApiBaseUrl;
        _storeCode.Text = _settings.StoreCode;
        _user.Text = _settings.Username;
        _pass.Text = _settings.RememberPassword ? _settings.Password : "";
        _subnet.Text = _settings.SubnetPrefix;
        _remember.Checked = _settings.RememberPassword;
        _autoStart.Checked = _settings.AutoStartAgent;
        _runAtBoot.Checked = _settings.RunAtWindowsStartup || WindowsStartup.IsEnabled();
        _deviceLbl.Text = "Mã máy này: " + _settings.EnsureDeviceId();

        foreach (var c in new[] { _paperSize, _usbPaper })
        {
            c.Items.AddRange(new object[] { "Giấy 80mm", "Giấy 58mm", "Tem 50×30", "Tem 40×30" });
            c.SelectedIndex = 0;
        }

        foreach (var (_, label) in DocTypes.All)
        {
            var def = label is "Hóa đơn" or "Phiếu báo bếp" or "Tem dán ly";
            _newRoutes.Items.Add(label, def);
            _usbRoutes.Items.Add(label, def);
        }

        BuildChrome();
        BuildPages();
        WireEvents();
        SetupTray();
        ShowPage("conn");
        SetLoggedInUi(false);

        Shown += async (_, _) =>
        {
            if (_settings.AutoStartAgent &&
                !string.IsNullOrWhiteSpace(_settings.StoreCode) &&
                !string.IsNullOrWhiteSpace(_settings.Username) &&
                !string.IsNullOrWhiteSpace(_settings.Password))
            {
                try
                {
                    await LoginAsync(silent: true);
                    if (_api != null && _settings.AssignedGuids().Count > 0)
                        await StartAgentAsync();
                }
                catch (Exception ex) { Log("Tự khởi động: " + UiMsg.ToVi(ex.Message)); }
            }
        };

        FormClosing += async (_, e) =>
        {
            if (_agent?.IsRunning == true)
            {
                e.Cancel = true;
                Hide();
                _tray.ShowBalloonTip(2500, "SBOX máy in",
                    "Đang chạy nền — vẫn nhận lệnh in từ phần mềm bán hàng.", ToolTipIcon.Info);
            }
            else
            {
                if (_agent != null) await _agent.DisposeAsync();
                _tray.Visible = false;
            }
        };
    }

    void BuildChrome()
    {
        var brand = new Panel { Dock = DockStyle.Top, Height = 108, BackColor = Theme.Sidebar };
        var logo = AppIcon.LoadLogoImage(44);
        if (logo != null)
        {
            brand.Controls.Add(new PictureBox
            {
                Image = logo,
                SizeMode = PictureBoxSizeMode.Zoom,
                Size = new Size(44, 44),
                Location = new Point(18, 22),
                BackColor = Color.Transparent,
            });
        }
        brand.Controls.Add(new Label
        {
            Text = "SBOX",
            Font = Theme.FontUi(18f, FontStyle.Bold),
            ForeColor = Color.White,
            AutoSize = true,
            Location = new Point(72, 22),
        });
        brand.Controls.Add(new Label
        {
            Text = "Kết nối máy in",
            Font = Theme.FontUi(9f),
            ForeColor = Color.FromArgb(148, 163, 184),
            AutoSize = true,
            Location = new Point(74, 52),
        });

        var navHost = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            Padding = new Padding(12, 16, 12, 12),
            BackColor = Theme.Sidebar,
        };
        AddNav(navHost, "conn", "Đăng nhập");
        AddNav(navHost, "scan", "Máy in mạng");
        AddNav(navHost, "usb", "Máy in USB");
        AddNav(navHost, "printers", "Danh sách máy in");
        AddNav(navHost, "routes", "Gán phiếu in");
        AddNav(navHost, "agent", "Bật nhận lệnh in");
        AddNav(navHost, "log", "Nhật ký");
        _sidebar.Controls.Add(navHost);
        _sidebar.Controls.Add(brand);

        var header = new Panel { Dock = DockStyle.Top, Height = 72, BackColor = Theme.Bg, Padding = new Padding(4, 8, 4, 0) };
        _headerTitle.Location = new Point(4, 8);
        _headerSub.Location = new Point(6, 42);
        header.Controls.Add(_headerTitle);
        header.Controls.Add(_headerSub);

        Controls.Add(_contentHost);
        Controls.Add(_footerStatus);
        Controls.Add(header);
        Controls.Add(_sidebar);
    }

    void AddNav(FlowLayoutPanel host, string key, string text)
    {
        var btn = new Button
        {
            Text = "  " + text,
            Width = 196,
            Height = 44,
            FlatStyle = FlatStyle.Flat,
            Font = Theme.FontUi(10f),
            ForeColor = Color.FromArgb(203, 213, 225),
            BackColor = Theme.Sidebar,
            TextAlign = ContentAlignment.MiddleLeft,
            Cursor = Cursors.Hand,
            Margin = new Padding(0, 0, 0, 8),
            Tag = key,
            UseCompatibleTextRendering = false,
        };
        btn.FlatAppearance.BorderSize = 0;
        btn.Click += (_, _) => ShowPage(key);
        host.Controls.Add(btn);
        _navButtons[key] = btn;
    }

    void ShowPage(string key)
    {
        foreach (var (k, p) in _pages) p.Visible = k == key;
        foreach (var (k, b) in _navButtons)
        {
            var active = k == key;
            b.BackColor = active ? Theme.SidebarActive : Theme.Sidebar;
            b.ForeColor = Color.White;
            b.Font = Theme.FontUi(10f, active ? FontStyle.Bold : FontStyle.Regular);
        }
        (_headerTitle.Text, _headerSub.Text) = key switch
        {
            "conn" => ("Đăng nhập", "Kết nối cửa hàng — mặc định https://sboxhrm.com"),
            "scan" => ("Máy in mạng", "Tìm máy in nhiệt trên Wi‑Fi/LAN rồi lưu vào cửa hàng"),
            "usb" => ("Máy in USB", "Chọn máy in đã cài driver trên Windows (cắm USB)"),
            "printers" => ("Danh sách máy in", "Chọn máy mà máy tính này sẽ in hộ"),
            "routes" => ("Gán phiếu in", "Hóa đơn, báo bếp, tem… in ra máy nào"),
            "agent" => ("Bật nhận lệnh in", "Để phần mềm bán hàng gửi lệnh in tới máy tính này"),
            "log" => ("Nhật ký", "Theo dõi đăng nhập và lệnh in"),
            _ => ("SBOX", ""),
        };
        if (key == "usb") RefreshUsbList();
    }

    void BuildPages()
    {
        _pages["conn"] = BuildConnPage();
        _pages["scan"] = BuildScanPage();
        _pages["usb"] = BuildUsbPage();
        _pages["printers"] = BuildPrintersPage();
        _pages["routes"] = BuildRoutesPage();
        _pages["agent"] = BuildAgentPage();
        _pages["log"] = WrapPage(new CardPanel { Controls = { _logBox }, Padding = new Padding(8) });
        foreach (var p in _pages.Values)
        {
            p.Dock = DockStyle.Fill;
            p.Visible = false;
            _contentHost.Controls.Add(p);
        }
    }

    Panel BuildConnPage()
    {
        // AutoScroll tránh nút Đăng nhập bị che
        var scroll = new Panel { Dock = DockStyle.Fill, AutoScroll = true, BackColor = Theme.Bg };
        var card = new CardPanel { Width = 560, Height = 560, Location = new Point(0, 0) };
        var y = 8;
        void addLabel(string t)
        {
            card.Controls.Add(new Label
            {
                Text = t, Font = Theme.FontUi(9f, FontStyle.Bold), ForeColor = Theme.TextMuted,
                Location = new Point(8, y), AutoSize = true,
            });
            y += 22;
        }
        void addBox(ModernTextBox box)
        {
            box.Location = new Point(8, y);
            box.Width = 500;
            box.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            card.Controls.Add(box);
            y += 56;
        }

        addLabel("Địa chỉ máy chủ");
        addBox(_apiUrl);
        addLabel("Mã cửa hàng");
        addBox(_storeCode);
        addLabel("Tài khoản");
        addBox(_user);
        addLabel("Mật khẩu");
        addBox(_pass);

        _remember.Location = new Point(8, y); card.Controls.Add(_remember); y += 30;
        _autoStart.Location = new Point(8, y); card.Controls.Add(_autoStart); y += 30;
        _runAtBoot.Location = new Point(8, y); card.Controls.Add(_runAtBoot); y += 40;
        _btnLogin.Location = new Point(8, y);
        _btnLogin.Size = new Size(200, 48);
        card.Controls.Add(_btnLogin); y += 64;
        _connStatus.Location = new Point(8, y); card.Controls.Add(_connStatus); y += 32;
        _deviceLbl.Location = new Point(8, y); card.Controls.Add(_deviceLbl);
        card.Height = y + 48;

        scroll.Controls.Add(card);
        scroll.Resize += (_, _) =>
        {
            card.Width = Math.Max(480, scroll.ClientSize.Width - 8);
            foreach (Control c in card.Controls)
                if (c is ModernTextBox tb) tb.Width = card.Width - 40;
        };
        return scroll;
    }

    Panel BuildScanPage()
    {
        var split = CreateSplit(0.58);
        var leftCard = new CardPanel { Dock = DockStyle.Fill };
        var left = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 6, ColumnCount = 1, BackColor = Theme.Card };
        left.RowStyles.Add(new RowStyle(SizeType.Absolute, 24));
        left.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
        left.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        left.RowStyles.Add(new RowStyle(SizeType.Absolute, 24));
        left.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
        left.RowStyles.Add(new RowStyle(SizeType.Absolute, 64));
        left.Controls.Add(Muted("Dải mạng (thường để trống hoặc 192.168.1)"), 0, 0);
        left.Controls.Add(_subnet, 0, 1);
        left.Controls.Add(PadList(_hitList), 0, 2);
        left.Controls.Add(Muted("Tên gọi máy in"), 0, 3);
        left.Controls.Add(_printerName, 0, 4);
        _paperSize.Height = 44;
        _paperSize.Margin = new Padding(0, 2, 10, 2);
        var paperLbl = new Label
        {
            Text = "Khổ giấy", AutoSize = false, Size = new Size(70, 44),
            TextAlign = ContentAlignment.MiddleLeft, ForeColor = Theme.TextMuted,
            Font = Theme.FontUi(9.5f), Margin = new Padding(4, 2, 4, 2),
        };
        left.Controls.Add(ButtonBar.Create(_btnScan, _btnLanTest, paperLbl, _paperSize), 0, 5);
        leftCard.Controls.Add(left);

        var rightCard = new CardPanel { Dock = DockStyle.Fill };
        var right = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 3, BackColor = Theme.Card };
        right.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        right.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        right.RowStyles.Add(new RowStyle(SizeType.Absolute, 64));
        right.Controls.Add(Muted("Máy này dùng để in những phiếu nào?"), 0, 0);
        right.Controls.Add(PadList(_newRoutes), 0, 1);
        right.Controls.Add(ButtonBar.Create(_btnCreateLan), 0, 2);
        rightCard.Controls.Add(right);
        split.Panel1.Controls.Add(leftCard);
        split.Panel2.Controls.Add(rightCard);
        return WrapPage(split);
    }

    Panel BuildUsbPage()
    {
        var split = CreateSplit(0.55);
        var leftCard = new CardPanel { Dock = DockStyle.Fill };
        var left = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 4, BackColor = Theme.Card };
        left.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        left.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        left.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
        left.RowStyles.Add(new RowStyle(SizeType.Absolute, 64));
        left.Controls.Add(Muted("Máy in đã cài trên Windows (USB / chia sẻ)"), 0, 0);
        left.Controls.Add(PadList(_usbList), 0, 1);
        left.Controls.Add(_usbName, 0, 2);
        _usbPaper.Height = 44;
        _usbPaper.Margin = new Padding(0, 2, 10, 2);
        var usbPaperLbl = new Label
        {
            Text = "Khổ giấy", AutoSize = false, Size = new Size(70, 44),
            TextAlign = ContentAlignment.MiddleLeft, ForeColor = Theme.TextMuted,
            Font = Theme.FontUi(9.5f), Margin = new Padding(4, 2, 4, 2),
        };
        left.Controls.Add(ButtonBar.Create(_btnUsbRefresh, _btnUsbTest, usbPaperLbl, _usbPaper), 0, 3);
        leftCard.Controls.Add(left);

        var rightCard = new CardPanel { Dock = DockStyle.Fill };
        var right = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 3, BackColor = Theme.Card };
        right.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        right.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        right.RowStyles.Add(new RowStyle(SizeType.Absolute, 64));
        right.Controls.Add(Muted("Máy này dùng để in những phiếu nào?"), 0, 0);
        right.Controls.Add(PadList(_usbRoutes), 0, 1);
        right.Controls.Add(ButtonBar.Create(_btnCreateUsb), 0, 2);
        rightCard.Controls.Add(right);
        split.Panel1.Controls.Add(leftCard);
        split.Panel2.Controls.Add(rightCard);
        return WrapPage(split);
    }

    Panel BuildPrintersPage()
    {
        var split = CreateSplit(0.62);
        var leftCard = new CardPanel { Dock = DockStyle.Fill };
        var left = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 3, BackColor = Theme.Card };
        left.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        left.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        left.RowStyles.Add(new RowStyle(SizeType.Absolute, 72));
        left.Controls.Add(Muted("Tick máy in mà máy tính này sẽ nhận lệnh in hộ"), 0, 0);
        left.Controls.Add(PadList(_printerList), 0, 1);
        left.Controls.Add(ButtonBar.Create(
            _btnRefreshPrinters, _btnSaveAssign, _btnUpdateHost, _btnCloudTest, _btnDeletePrinter), 0, 2);
        leftCard.Controls.Add(left);
        var rightCard = new CardPanel { Dock = DockStyle.Fill };
        rightCard.Controls.Add(_printerDetail);
        split.Panel1.Controls.Add(leftCard);
        split.Panel2.Controls.Add(rightCard);
        return WrapPage(split);
    }

    Panel BuildRoutesPage()
    {
        var card = new CardPanel { Dock = DockStyle.Fill };
        var panel = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 3, BackColor = Theme.Card };
        panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        panel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 64));
        panel.Controls.Add(Muted("Chọn máy in cho từng loại phiếu"), 0, 0);
        _routeGrid.ColumnHeadersDefaultCellStyle = new DataGridViewCellStyle
        {
            BackColor = Color.FromArgb(248, 250, 252), ForeColor = Theme.Text, Font = Theme.FontUi(9.5f, FontStyle.Bold),
        };
        _routeGrid.DefaultCellStyle.SelectionBackColor = Color.FromArgb(204, 251, 241);
        _routeGrid.DefaultCellStyle.SelectionForeColor = Theme.Text;
        _routeGrid.Columns.Add(new DataGridViewTextBoxColumn { Name = "Doc", HeaderText = "Loại phiếu", ReadOnly = true, FillWeight = 42 });
        _routeGrid.Columns.Add(new DataGridViewComboBoxColumn { Name = "Printer", HeaderText = "Máy in", FillWeight = 43, FlatStyle = FlatStyle.Flat });
        _routeGrid.Columns.Add(new DataGridViewTextBoxColumn { Name = "Copies", HeaderText = "Số bản", FillWeight = 15 });
        panel.Controls.Add(_routeGrid, 0, 1);
        panel.Controls.Add(ButtonBar.Create(_btnSaveRoutes), 0, 2);
        card.Controls.Add(panel);
        return WrapPage(card);
    }

    Panel BuildAgentPage()
    {
        var card = new CardPanel { Dock = DockStyle.Fill };
        var panel = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 4, BackColor = Theme.Card };
        panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
        panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 64));
        panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        panel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        _agentStatus.Text = "Trạng thái: chưa bật";
        panel.Controls.Add(_agentStatus, 0, 0);
        panel.Controls.Add(ButtonBar.Create(_btnStart, _btnStop, _btnRefreshAgents), 0, 1);
        panel.Controls.Add(Muted("Máy đang nhận lệnh in trên cửa hàng (máy tính / điện thoại)"), 0, 2);
        panel.Controls.Add(PadList(_agentsBox), 0, 3);
        card.Controls.Add(panel);
        return WrapPage(card);
    }

    static Panel WrapPage(Control inner)
    {
        var host = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Bg };
        inner.Dock = DockStyle.Fill;
        host.Controls.Add(inner);
        return host;
    }

    static SplitContainer CreateSplit(double ratio)
    {
        var split = new SplitContainer
        {
            Dock = DockStyle.Fill, Orientation = Orientation.Vertical, BackColor = Theme.Bg,
            Panel1MinSize = 120, Panel2MinSize = 120, SplitterWidth = 6,
        };
        void Apply()
        {
            try
            {
                if (split.Width <= split.Panel1MinSize + split.Panel2MinSize + split.SplitterWidth) return;
                var max = split.Width - split.Panel2MinSize - split.SplitterWidth;
                split.SplitterDistance = Math.Clamp((int)(split.Width * ratio), split.Panel1MinSize, max);
            }
            catch { /* ignore */ }
        }
        split.SizeChanged += (_, _) => Apply();
        split.HandleCreated += (_, _) => Apply();
        return split;
    }

    static Label Muted(string t) => new()
    {
        Text = t, Dock = DockStyle.Fill, Font = Theme.FontUi(9f), ForeColor = Theme.TextMuted,
        TextAlign = ContentAlignment.MiddleLeft,
    };

    static Panel PadList(Control list)
    {
        var p = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Card, Padding = new Padding(1), BorderStyle = BorderStyle.FixedSingle };
        list.Dock = DockStyle.Fill;
        p.Controls.Add(list);
        return p;
    }

    static string PaperCode(ComboBox box) => box.SelectedIndex switch
    {
        1 => "K58",
        2 => "Label50x30",
        3 => "Label40x30",
        _ => "K80",
    };

    static List<string> SelectedDocCodes(CheckedListBox box)
    {
        var codes = new List<string>();
        foreach (var item in box.CheckedItems)
        {
            var label = item?.ToString() ?? "";
            var hit = DocTypes.All.FirstOrDefault(x => x.Label == label);
            if (!string.IsNullOrEmpty(hit.Code)) codes.Add(hit.Code);
        }
        return codes.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    }

    void WireEvents()
    {
        _btnLogin.Click += async (_, _) => await LoginAsync(false);
        _runAtBoot.CheckedChanged += (_, _) => ApplyRunAtBoot(_runAtBoot.Checked, quiet: false);
        _btnScan.Click += async (_, _) => await ScanAsync();
        _btnLanTest.Click += async (_, _) => await LanTestAsync();
        _btnCreateLan.Click += async (_, _) => await CreateLanAsync();
        _btnUsbRefresh.Click += (_, _) => RefreshUsbList();
        _btnUsbTest.Click += (_, _) => UsbTest();
        _btnCreateUsb.Click += async (_, _) => await CreateUsbAsync();
        _btnRefreshPrinters.Click += async (_, _) => await RefreshPrintersAsync();
        _btnSaveAssign.Click += (_, _) => SaveAssignment(showMsg: true);
        _btnUpdateHost.Click += async (_, _) => await UpdateHostFromScanAsync();
        _btnDeletePrinter.Click += async (_, _) => await DeletePrinterAsync();
        _btnCloudTest.Click += async (_, _) => await CloudTestAsync();
        _btnSaveRoutes.Click += async (_, _) => await SaveRoutesAsync();
        _btnStart.Click += async (_, _) => await StartAgentAsync();
        _btnStop.Click += async (_, _) => await StopAgentAsync();
        _btnRefreshAgents.Click += async (_, _) => await RefreshAgentsAsync();
        _printerList.SelectedIndexChanged += (_, _) => ShowPrinterDetail();
        _hitList.SelectedIndexChanged += (_, _) =>
        {
            if (_hitList.SelectedItem is string s)
            {
                var host = s.Split(' ', StringSplitOptions.RemoveEmptyEntries)[0].Split(':')[0];
                if (string.IsNullOrWhiteSpace(_printerName.Text) || _printerName.Text.StartsWith("Máy "))
                    _printerName.Text = "Máy " + host;
            }
        };
        _usbList.SelectedIndexChanged += (_, _) =>
        {
            if (_usbList.SelectedItem is string name &&
                (string.IsNullOrWhiteSpace(_usbName.Text) || _usbName.Text.StartsWith("USB ")))
                _usbName.Text = "USB " + name;
        };
    }

    void SetupTray()
    {
        _tray.Text = "SBOX máy in";
        _tray.Icon = Icon ?? SystemIcons.Application;
        _tray.Visible = true;
        _tray.DoubleClick += (_, _) => { Show(); WindowState = FormWindowState.Normal; Activate(); };
        var menu = new ContextMenuStrip();
        menu.Items.Add("Mở cửa sổ", null, (_, _) => { Show(); Activate(); });
        menu.Items.Add("Tắt nhận lệnh in và thoát", null, async (_, _) =>
        {
            await StopAgentAsync();
            _tray.Visible = false;
            Application.Exit();
        });
        _tray.ContextMenuStrip = menu;
    }

    void ApplyRunAtBoot(bool enabled, bool quiet)
    {
        try
        {
            WindowsStartup.SetEnabled(enabled);
            _settings.RunAtWindowsStartup = enabled;
            _settings.Save();
            if (!quiet)
            {
                Log(enabled
                    ? "Đã bật tự chạy khi mở máy Windows."
                    : "Đã tắt tự chạy khi mở máy.");
                if (enabled)
                    UiMsg.Info(
                        "Đã bật tự chạy khi mở máy.\n\nLần khởi động Windows tiếp theo, SBOX sẽ tự mở (có thể thu nhỏ xuống khay hệ thống).",
                        "Tự chạy khi mở máy");
            }
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
            File.AppendAllText(Path.Combine(dir, "agent.log"), line + Environment.NewLine);
        }
        catch { /* ignore log IO */ }

        if (InvokeRequired)
        {
            BeginInvoke(() =>
            {
                _logBox.AppendText(line + Environment.NewLine);
                _footerStatus.Text = msg.Length > 100 ? msg[..100] + "…" : msg;
            });
            return;
        }
        _logBox.AppendText(line + Environment.NewLine);
        _footerStatus.Text = msg.Length > 100 ? msg[..100] + "…" : msg;
    }

    void SetLoggedInUi(bool on)
    {
        _btnScan.Enabled = true;
        _btnLanTest.Enabled = true;
        _btnUsbRefresh.Enabled = true;
        _btnUsbTest.Enabled = true;
        _btnCreateLan.Enabled = on;
        _btnCreateUsb.Enabled = on;
        _btnRefreshPrinters.Enabled = on;
        _btnSaveAssign.Enabled = on;
        _btnSaveRoutes.Enabled = on;
        _btnCloudTest.Enabled = on;
        _btnDeletePrinter.Enabled = on;
        _btnUpdateHost.Enabled = on;
        _btnRefreshAgents.Enabled = on;
        _btnStop.Enabled = _agent?.IsRunning == true;
        _btnStart.Enabled = on && _agent?.IsRunning != true;
    }

    async Task LoginAsync(bool silent)
    {
        try
        {
            _btnLogin.Enabled = false;
            var baseUrl = _apiUrl.Text.Trim().TrimEnd('/');
            if (string.IsNullOrWhiteSpace(baseUrl))
                throw new InvalidOperationException("Vui lòng nhập địa chỉ máy chủ (mặc định https://sboxhrm.com).");
            if (!baseUrl.StartsWith("http", StringComparison.OrdinalIgnoreCase))
                baseUrl = "https://" + baseUrl;
            if (string.IsNullOrWhiteSpace(_storeCode.Text))
                throw new InvalidOperationException("Vui lòng nhập mã cửa hàng.");
            if (string.IsNullOrWhiteSpace(_user.Text))
                throw new InvalidOperationException("Vui lòng nhập tài khoản.");

            _api = new SboxApiClient(baseUrl);
            await _api.LoginAsync(_storeCode.Text.Trim(), _user.Text.Trim(), _pass.Text, CancellationToken.None);

            _settings.ApiBaseUrl = baseUrl;
            _settings.StoreCode = _storeCode.Text.Trim();
            _settings.Username = _user.Text.Trim();
            _settings.RememberPassword = _remember.Checked;
            _settings.Password = _remember.Checked ? _pass.Text : "";
            _settings.AutoStartAgent = _autoStart.Checked;
            _settings.RunAtWindowsStartup = _runAtBoot.Checked;
            _settings.StoreId = _api.StoreId ?? Guid.Empty;
            _settings.Save();
            ApplyRunAtBoot(_runAtBoot.Checked, quiet: true);

            _connStatus.Text = $"Đăng nhập thành công · {_api.DisplayName}";
            _connStatus.ForeColor = Theme.Success;
            Log(_connStatus.Text);
            SetLoggedInUi(true);
            await RefreshPrintersAsync();
            await RefreshAgentsAsync();
            if (!silent)
                UiMsg.Info("Đăng nhập thành công.\n\nTiếp theo: thêm máy in mạng hoặc USB → bật nhận lệnh in.", "Đăng nhập");
        }
        catch (Exception ex)
        {
            _connStatus.Text = "Đăng nhập thất bại";
            _connStatus.ForeColor = Theme.Danger;
            Log("Đăng nhập lỗi: " + UiMsg.ToVi(ex.Message));
            if (!silent) UiMsg.Error(ex.Message, "Đăng nhập thất bại");
            if (silent) throw;
        }
        finally { _btnLogin.Enabled = true; }
    }

    async Task ScanAsync()
    {
        try
        {
            _btnScan.Enabled = false;
            _hits.Clear();
            _hitList.Items.Clear();
            Log("Đang tìm máy in trên mạng…");
            var list = await LanScanner.ScanAsync(_subnet.Text.Trim(), log: new Progress<string>(Log));
            _hits.AddRange(list);
            foreach (var h in list)
                _hitList.Items.Add($"{h.Host}:{h.Port}   ({h.LatencyMs} ms)");
            _settings.SubnetPrefix = _subnet.Text.Trim();
            _settings.Save();
            Log(list.Count == 0
                ? "Không thấy máy in. Kiểm tra cùng Wi‑Fi và máy in đã bật."
                : $"Tìm thấy {list.Count} máy in.");
            if (list.Count == 0)
                UiMsg.Warn("Không tìm thấy máy in trên mạng.\n\nKiểm tra máy in và máy tính cùng mạng Wi‑Fi/LAN.");
        }
        catch (Exception ex)
        {
            Log("Tìm máy in lỗi: " + UiMsg.ToVi(ex.Message));
            UiMsg.Error(ex.Message, "Không tìm được máy in");
        }
        finally { _btnScan.Enabled = true; }
    }

    LanScanner.Hit? SelectedHit()
    {
        if (_hitList.SelectedIndex < 0 || _hitList.SelectedIndex >= _hits.Count) return null;
        return _hits[_hitList.SelectedIndex];
    }

    async Task LanTestAsync()
    {
        var hit = SelectedHit();
        if (hit == null) { UiMsg.Warn("Hãy chọn một máy trong danh sách sau khi tìm."); return; }
        try
        {
            await LanScanner.SendTestAsync(hit.Host, hit.Port, hit.Host);
            Log($"Đã gửi in thử → {hit.Host}");
            UiMsg.Info($"Đã gửi trang in thử tới {hit.Host}.\nKiểm tra giấy ra máy in.", "In thử");
        }
        catch (Exception ex) { UiMsg.Error(ex.Message, "In thử thất bại"); }
    }

    async Task CreateLanAsync()
    {
        if (_api == null) { UiMsg.Warn("Vui lòng đăng nhập trước."); return; }
        var hit = SelectedHit();
        if (hit == null) { UiMsg.Warn("Chọn máy in trong danh sách tìm được."); return; }
        var name = string.IsNullOrWhiteSpace(_printerName.Text) ? "Máy " + hit.Host : _printerName.Text.Trim();
        var roles = SelectedDocCodes(_newRoutes);
        if (roles.Count == 0) { UiMsg.Warn("Chọn ít nhất một loại phiếu (hóa đơn, báo bếp, tem…)."); return; }

        try
        {
            _btnCreateLan.Enabled = false;
            var paper = PaperCode(_paperSize);
            var existing = _printers.FirstOrDefault(p =>
                string.Equals(p.LanHost, hit.Host, StringComparison.OrdinalIgnoreCase));
            Guid printerId;
            if (existing != null)
            {
                printerId = existing.Id;
                await _api.UpdateLanPrinterAsync(printerId, name, hit.Host, hit.Port, paper,
                    roles.Contains("SaleInvoice", StringComparer.OrdinalIgnoreCase), true, 0, CancellationToken.None);
            }
            else
            {
                printerId = await _api.CreateLanPrinterAsync(name, hit.Host, hit.Port, paper,
                    roles.Contains("SaleInvoice", StringComparer.OrdinalIgnoreCase), CancellationToken.None);
            }

            var merged = RouteMerge.AssignTypes(await _api.GetRoutesAsync(CancellationToken.None), roles, printerId);
            await _api.SaveRoutesAsync(merged, CancellationToken.None);
            AssignLocal(printerId);
            await RefreshPrintersAsync();
            UiMsg.Info($"Đã lưu máy in «{name}».\n\nSang «Bật nhận lệnh in» để bắt đầu nhận lệnh từ phần mềm bán hàng.", "Thành công");
            ShowPage("agent");
        }
        catch (Exception ex) { UiMsg.Error(ex.Message, "Không lưu được máy in"); }
        finally { _btnCreateLan.Enabled = _api != null; }
    }

    void RefreshUsbList()
    {
        _usbList.Items.Clear();
        try
        {
            foreach (var p in WindowsSpooler.ListInstalledPrinters())
                _usbList.Items.Add(p);
            Log($"Có {_usbList.Items.Count} máy in trên Windows.");
        }
        catch (Exception ex) { UiMsg.Error(ex.Message, "Không đọc được danh sách máy in"); }
    }

    void UsbTest()
    {
        if (_usbList.SelectedItem is not string name) { UiMsg.Warn("Chọn một máy in trong danh sách."); return; }
        try
        {
            WindowsSpooler.SendTest(name);
            Log("Đã gửi in thử USB → " + name);
            UiMsg.Info($"Đã gửi trang in thử tới «{name}».", "In thử");
        }
        catch (Exception ex) { UiMsg.Error(ex.Message, "In thử thất bại"); }
    }

    async Task CreateUsbAsync()
    {
        if (_api == null) { UiMsg.Warn("Vui lòng đăng nhập trước."); return; }
        if (_usbList.SelectedItem is not string winName) { UiMsg.Warn("Chọn máy in Windows."); return; }
        var name = string.IsNullOrWhiteSpace(_usbName.Text) ? "USB " + winName : _usbName.Text.Trim();
        var roles = SelectedDocCodes(_usbRoutes);
        if (roles.Count == 0) { UiMsg.Warn("Chọn ít nhất một loại phiếu."); return; }

        try
        {
            _btnCreateUsb.Enabled = false;
            var paper = PaperCode(_usbPaper);
            var existing = _printers.FirstOrDefault(p =>
                ConnLabel.IsUsb(p) &&
                string.Equals(p.UsbDeviceName, winName, StringComparison.OrdinalIgnoreCase));
            Guid printerId;
            if (existing != null)
            {
                printerId = existing.Id;
                // cập nhật qua create không có — dùng lại id + routes
                Log("Máy USB đã có trên cửa hàng — cập nhật gán phiếu.");
            }
            else
            {
                printerId = await _api.CreateUsbPrinterAsync(name, winName, paper,
                    roles.Contains("SaleInvoice", StringComparer.OrdinalIgnoreCase), CancellationToken.None);
            }

            var merged = RouteMerge.AssignTypes(await _api.GetRoutesAsync(CancellationToken.None), roles, printerId);
            await _api.SaveRoutesAsync(merged, CancellationToken.None);
            AssignLocal(printerId);
            await RefreshPrintersAsync();
            UiMsg.Info($"Đã lưu máy in USB «{name}».\n\nSang «Bật nhận lệnh in» để bắt đầu.", "Thành công");
            ShowPage("agent");
        }
        catch (Exception ex) { UiMsg.Error(ex.Message, "Không lưu được máy in USB"); }
        finally { _btnCreateUsb.Enabled = _api != null; }
    }

    void AssignLocal(Guid printerId)
    {
        var assigned = _settings.AssignedGuids();
        if (!assigned.Contains(printerId)) assigned.Add(printerId);
        _settings.AssignedPrinterIds = assigned.Select(x => x.ToString()).ToList();
        _settings.Save();
    }

    async Task RefreshPrintersAsync()
    {
        if (_api == null) return;
        try
        {
            _printers = await _api.ListPrintersAsync(CancellationToken.None);
            _routes = await _api.GetRoutesAsync(CancellationToken.None);
            _agent?.SetPrinterCache(_printers);

            var assigned = _settings.AssignedGuids().ToHashSet();
            if (assigned.Count == 0)
            {
                assigned = _printers.Where(ConnLabel.CanPrintOnWindows).Select(p => p.Id).ToHashSet();
                _settings.AssignedPrinterIds = assigned.Select(x => x.ToString()).ToList();
                _settings.Save();
            }

            _printerList.Items.Clear();
            foreach (var p in _printers)
            {
                var addr = ConnLabel.IsUsb(p)
                    ? (p.UsbDeviceName ?? "USB")
                    : $"{p.LanHost ?? "—"}:{p.LanPort}";
                var docs = p.DocumentTypes.Count == 0
                    ? ""
                    : " · " + string.Join(", ", p.DocumentTypes.Select(DocTypes.LabelOf));
                var idx = _printerList.Items.Add($"{p.Name}   ·  {ConnLabel.Vi(p.ConnectionType)}  {addr}{docs}");
                _printerList.SetItemChecked(idx, assigned.Contains(p.Id));
            }
            RebuildRouteGrid();
            Log($"Đã tải {_printers.Count} máy in của cửa hàng.");
        }
        catch (Exception ex) { Log("Tải máy in: " + UiMsg.ToVi(ex.Message)); }
    }

    void SaveAssignment(bool showMsg)
    {
        var ids = new List<Guid>();
        for (var i = 0; i < _printerList.Items.Count && i < _printers.Count; i++)
            if (_printerList.GetItemChecked(i)) ids.Add(_printers[i].Id);
        _settings.AssignedPrinterIds = ids.Select(x => x.ToString()).ToList();
        _settings.Save();
        Log($"Đã chọn {ids.Count} máy in để dùng trên máy này.");
        if (showMsg)
            UiMsg.Info($"Đã lưu {ids.Count} máy in.\nNếu đang bật nhận lệnh in: tắt rồi bật lại để áp dụng.", "Đã lưu");
    }

    void ShowPrinterDetail()
    {
        var i = _printerList.SelectedIndex;
        if (i < 0 || i >= _printers.Count) { _printerDetail.Text = ""; return; }
        var p = _printers[i];
        _printerDetail.Text =
            $"{p.Name}\n\n" +
            $"Kiểu: {ConnLabel.Vi(p.ConnectionType)}\n" +
            (ConnLabel.IsUsb(p)
                ? $"Máy Windows: {p.UsbDeviceName}\n"
                : $"Địa chỉ mạng: {p.LanHost}:{p.LanPort}\n") +
            $"Khổ giấy: {p.PaperSize}\n" +
            $"Trạng thái: {HealthVi(p.HealthStatus)}\n" +
            $"Phiếu in: {(p.DocumentTypes.Count == 0 ? "—" : string.Join(", ", p.DocumentTypes.Select(DocTypes.LabelOf)))}";
    }

    static string HealthVi(string? s) => s switch
    {
        "Online" => "Sẵn sàng",
        "Offline" => "Mất kết nối",
        "Busy" => "Đang in",
        "Error" => "Lỗi",
        _ => "Chưa rõ",
    };

    async Task UpdateHostFromScanAsync()
    {
        if (_api == null) return;
        var i = _printerList.SelectedIndex;
        var hit = SelectedHit();
        if (i < 0 || i >= _printers.Count || hit == null)
        {
            UiMsg.Warn("Chọn máy in ở đây và một địa chỉ ở mục «Máy in mạng».");
            return;
        }
        var p = _printers[i];
        if (!ConnLabel.IsLan(p)) { UiMsg.Warn("Chỉ đổi IP cho máy in mạng."); return; }
        try
        {
            await _api.UpdateLanPrinterAsync(p.Id, p.Name, hit.Host, hit.Port, p.PaperSize,
                p.IsDefault, p.IsActive, 0, CancellationToken.None);
            await RefreshPrintersAsync();
            UiMsg.Info($"Đã đổi địa chỉ thành {hit.Host}.", "Cập nhật");
        }
        catch (Exception ex) { UiMsg.Error(ex.Message); }
    }

    async Task DeletePrinterAsync()
    {
        if (_api == null) return;
        var i = _printerList.SelectedIndex;
        if (i < 0 || i >= _printers.Count) return;
        var p = _printers[i];
        if (!UiMsg.Confirm($"Xóa máy in «{p.Name}» khỏi cửa hàng?", "Xóa máy in")) return;
        try
        {
            await _api.DeletePrinterAsync(p.Id, CancellationToken.None);
            await RefreshPrintersAsync();
        }
        catch (Exception ex) { UiMsg.Error(ex.Message); }
    }

    async Task CloudTestAsync()
    {
        if (_api == null) return;
        var i = _printerList.SelectedIndex;
        if (i < 0 || i >= _printers.Count) { UiMsg.Warn("Chọn một máy in."); return; }
        if (_agent?.IsRunning != true)
        {
            UiMsg.Warn("Hãy bật nhận lệnh in trước, rồi gửi lệnh in thử.");
            return;
        }
        try
        {
            var p = _printers[i];
            await _api.CreateTestJobAsync(p.Id, CancellationToken.None);
            UiMsg.Info($"Đã gửi lệnh in thử tới «{p.Name}».", "In thử");
        }
        catch (Exception ex) { UiMsg.Error(ex.Message); }
    }

    void RebuildRouteGrid()
    {
        var printerCol = (DataGridViewComboBoxColumn)_routeGrid.Columns["Printer"]!;
        var items = new List<PrinterPick> { new(Guid.Empty, "(không gán)") };
        items.AddRange(_printers.Select(p => new PrinterPick(p.Id, p.Name)));
        printerCol.DataSource = items;
        printerCol.DisplayMember = nameof(PrinterPick.Name);
        printerCol.ValueMember = nameof(PrinterPick.Id);

        var byDoc = _routes
            .GroupBy(r => r.DocumentType, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.First(), StringComparer.OrdinalIgnoreCase);

        _routeGrid.Rows.Clear();
        foreach (var (code, label) in DocTypes.All)
        {
            byDoc.TryGetValue(code, out var route);
            _routeGrid.Rows.Add(label, route?.PrinterId ?? Guid.Empty, route?.Copies ?? 1);
            _routeGrid.Rows[^1].Tag = code;
        }
    }

    sealed record PrinterPick(Guid Id, string Name);

    async Task SaveRoutesAsync()
    {
        if (_api == null) return;
        try
        {
            var routes = new List<RouteItem>();
            foreach (DataGridViewRow row in _routeGrid.Rows)
            {
                var code = row.Tag as string ?? "";
                if (string.IsNullOrEmpty(code)) continue;
                var pidObj = row.Cells["Printer"].Value;
                Guid g = Guid.Empty;
                if (pidObj is Guid gg) g = gg;
                else if (pidObj is PrinterPick pp) g = pp.Id;
                else Guid.TryParse(pidObj?.ToString(), out g);
                if (g == Guid.Empty) continue;
                var copies = 1;
                if (int.TryParse(row.Cells["Copies"].Value?.ToString(), out var c))
                    copies = Math.Clamp(c, 1, 10);
                routes.Add(new RouteItem(code, g, copies));
            }
            await _api.SaveRoutesAsync(routes, CancellationToken.None);
            await RefreshPrintersAsync();
            UiMsg.Info("Đã lưu cách gán phiếu in.", "Thành công");
        }
        catch (Exception ex) { UiMsg.Error(ex.Message); }
    }

    async Task StartAgentAsync()
    {
        if (_api == null) { UiMsg.Warn("Vui lòng đăng nhập trước."); return; }
        try
        {
            SaveAssignment(showMsg: false);
            var assigned = _settings.AssignedGuids();
            var ids = _printers.Where(p => assigned.Contains(p.Id) && ConnLabel.CanPrintOnWindows(p))
                .Select(p => p.Id).ToList();
            if (ids.Count == 0)
            {
                UiMsg.Warn("Chưa chọn máy in mạng/USB.\n\nThêm máy in rồi tick chọn ở «Danh sách máy in».");
                return;
            }

            _agent ??= new AgentService(_api, _settings, Log);
            _agent.SetPrinterCache(_printers);
            _agent.StateChanged += () =>
            {
                if (InvokeRequired) { BeginInvoke(UpdateAgentUi); return; }
                UpdateAgentUi();
            };
            _agent.ForceStoppedRemotely += () =>
            {
                BeginInvoke(() =>
                {
                    UiMsg.Warn("Nhận lệnh in đã bị tắt từ thiết bị khác.", "Đã tắt");
                    UpdateAgentUi();
                });
            };

            await _agent.StartAsync(ids);
            _settings.AutoStartAgent = _autoStart.Checked;
            _settings.Save();
            UpdateAgentUi();
            await RefreshAgentsAsync();
            UiMsg.Info($"Đang nhận lệnh in cho {ids.Count} máy.\nCó thể thu nhỏ cửa sổ — vẫn chạy ở khay hệ thống.", "Đã bật");
        }
        catch (Exception ex) { UiMsg.Error(ex.Message, "Không bật được"); }
    }

    async Task StopAgentAsync()
    {
        if (_agent == null) return;
        await _agent.StopAsync(markOffline: true);
        UpdateAgentUi();
        await RefreshAgentsAsync();
        Log("Đã tắt nhận lệnh in.");
    }

    void UpdateAgentUi()
    {
        var running = _agent?.IsRunning == true;
        _agentStatus.Text = running ? "Trạng thái: ĐANG NHẬN LỆNH IN" : "Trạng thái: chưa bật";
        _agentStatus.ForeColor = running ? Theme.Success : Theme.Text;
        _btnStart.Enabled = _api != null && !running;
        _btnStop.Enabled = running;
        _tray.Text = running ? "SBOX máy in (đang chạy)" : "SBOX máy in";
    }

    async Task RefreshAgentsAsync()
    {
        if (_api == null) return;
        try
        {
            var snap = await _api.ListAgentsAsync(onlineOnly: false, CancellationToken.None);
            _agentsBox.Items.Clear();
            if (snap.HasPrinterConflict)
                _agentsBox.Items.Add("⚠ Có nhiều máy cùng nhận lệnh cho một máy in — chỉ nên bật trên một máy gần máy in.");
            foreach (var a in snap.Agents.OrderByDescending(x => x.IsOnline).ThenByDescending(x => x.LastHeartbeatAt))
            {
                var mine = string.Equals(a.DeviceId, _settings.DeviceId, StringComparison.OrdinalIgnoreCase)
                    ? "  ★ MÁY NÀY" : "";
                var printers = a.PrinterNames.Count > 0
                    ? string.Join(", ", a.PrinterNames)
                    : "—";
                _agentsBox.Items.Add(
                    $"{(a.IsOnline ? "● Đang bật" : "○ Tắt")} · {a.DeviceName ?? a.DeviceId} · {a.AccountLabel ?? ""} · [{printers}]{mine}");
            }
        }
        catch (Exception ex) { Log("Danh sách máy nhận lệnh: " + UiMsg.ToVi(ex.Message)); }
    }
}
