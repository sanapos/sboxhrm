using SboxPrintAgent.Ui;

namespace SboxPrintAgent;

/// <summary>
/// «Khác lớp mạng…»: dò máy in bằng UDP broadcast (kể cả còn IP nhà máy khác lớp mạng PC),
/// đặt IP tĩnh cùng lớp mạng (kiểm tra IP chưa ai dùng). Xong: <see cref="NewIp"/> = IP mới, cổng 9100.
/// </summary>
public sealed class NetConfigForm : Form
{
    public string? NewIp { get; private set; }
    public string? OldIp { get; private set; }
    public string? DeviceTitle { get; private set; }

    readonly ListView _list = new()
    {
        Dock = DockStyle.Fill, View = View.Details, FullRowSelect = true, MultiSelect = false,
        HideSelection = false, Font = Theme.FontUi(10f), BorderStyle = BorderStyle.FixedSingle,
    };
    readonly ComboBox _link = new() { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList, Font = Theme.FontUi(10f) };
    readonly ModernTextBox _ip = new() { Placeholder = "IP mới (tĩnh)", Dock = DockStyle.Fill };
    readonly ModernTextBox _mask = new() { Placeholder = "Subnet mask", Dock = DockStyle.Fill };
    readonly ModernTextBox _gw = new() { Placeholder = "Gateway", Dock = DockStyle.Fill };
    readonly ModernTextBox _mac = new() { Placeholder = "MAC (Epson: xem trang tự kiểm tra)", Dock = DockStyle.Fill };
    readonly Label _status = new() { Dock = DockStyle.Fill, ForeColor = Theme.TextMuted, Font = Theme.FontUi(9.5f) };
    readonly ModernButton _btnFind = new() { Text = "Dò lại", Kind = ModernButton.StyleKind.Secondary, Width = 100, Height = 38 };
    readonly ModernButton _btnSuggest = new() { Text = "Gợi ý IP trống", Kind = ModernButton.StyleKind.Secondary, Width = 140, Height = 38 };
    readonly ModernButton _btnApply = new() { Text = "Đổi IP", Kind = ModernButton.StyleKind.Primary, Width = 110, Height = 38 };
    readonly ModernButton _btnHelp = new() { Text = "Hướng dẫn", Kind = ModernButton.StyleKind.Ghost, Width = 110, Height = 38 };

    readonly List<LanNetConfig.Device> _devices = new();
    readonly ISet<string> _knownIps;
    readonly CancellationTokenSource _cts = new();

    public NetConfigForm(IEnumerable<string> knownLanIps)
    {
        _knownIps = new HashSet<string>(knownLanIps);
        Text = "Đổi IP máy in / đặt IP tĩnh";
        Width = 900;
        Height = 600;
        MinimumSize = new Size(820, 520);
        StartPosition = FormStartPosition.CenterParent;
        BackColor = Theme.Bg;
        Font = Theme.FontUi();

        _list.Columns.Add("Máy in", 230);
        _list.Columns.Add("MAC", 140);
        _list.Columns.Add("IP hiện tại", 120);
        _list.Columns.Add("Mask", 110);
        _list.Columns.Add("DHCP", 60);
        _list.Columns.Add("Trạng thái", 200);

        var root = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 7, Padding = new Padding(14) };
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 60));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 22));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 44));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
        root.Controls.Add(new Label
        {
            Dock = DockStyle.Fill, ForeColor = Theme.Text, Font = Theme.FontUi(9.5f),
            Text = "Dò broadcast UDP: Xprinter (9000), Rongta / Zywell (1460), Epson (3289) — thấy cả máy in còn IP nhà máy " +
                   "khác lớp mạng với PC (cùng switch / router). Chọn máy → nhập IP mới cùng lớp mạng → «Đổi IP». " +
                   "Máy đang DHCP (IP có thể nhảy): chọn máy → giữ IP → «Đổi IP» để tắt DHCP.",
        }, 0, 0);
        root.Controls.Add(_list, 0, 1);

        var linkRow = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, Margin = new Padding(0) };
        linkRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 150));
        linkRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        linkRow.Controls.Add(new Label { Text = "Mạng của PC:", AutoSize = true, Anchor = AnchorStyles.Left, ForeColor = Theme.Text }, 0, 0);
        linkRow.Controls.Add(_link, 1, 0);
        root.Controls.Add(linkRow, 0, 2);

        var labels = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 4, Margin = new Padding(0) };
        var fields = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 4, Margin = new Padding(0) };
        string[] names = { "IP mới (tĩnh)", "Subnet mask", "Gateway", "MAC (chỉ Epson)" };
        Control[] boxes = { _ip, _mask, _gw, _mac };
        for (var i = 0; i < 4; i++)
        {
            labels.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25));
            fields.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25));
            labels.Controls.Add(new Label { Text = names[i], AutoSize = true, ForeColor = Theme.TextMuted, Font = Theme.FontUi(9f) }, i, 0);
            boxes[i].Margin = new Padding(0, 0, 8, 0);
            fields.Controls.Add(boxes[i], i, 0);
        }
        root.Controls.Add(labels, 0, 3);
        root.Controls.Add(fields, 0, 4);
        root.Controls.Add(_status, 0, 5);

        var btns = new FlowLayoutPanel { Dock = DockStyle.Fill, WrapContents = false, Margin = new Padding(0) };
        foreach (var b in new Control[] { _btnFind, _btnSuggest, _btnApply, _btnHelp })
        {
            b.Margin = new Padding(0, 0, 8, 0);
            btns.Controls.Add(b);
        }
        root.Controls.Add(btns, 0, 6);
        Controls.Add(root);

        foreach (var l in LanNetConfig.LocalLinks()) _link.Items.Add(l);
        if (_link.Items.Count > 0) _link.SelectedIndex = 0;
        _link.SelectedIndexChanged += (_, _) => FillFromLink();
        FillFromLink();

        _btnFind.Click += async (_, _) => await FindAsync();
        _btnSuggest.Click += async (_, _) => await SuggestAsync();
        _btnApply.Click += async (_, _) => await ApplyAsync();
        _btnHelp.Click += (_, _) => ShowHelp(Selected());
        _list.SelectedIndexChanged += (_, _) => OnSelect();
        Shown += async (_, _) => await FindAsync();
        FormClosed += (_, _) => _cts.Cancel();
    }

    LanNetConfig.Link? CurrentLink => _link.SelectedItem as LanNetConfig.Link;

    LanNetConfig.Device? Selected()
        => _list.SelectedIndices.Count == 1 && _list.SelectedIndices[0] < _devices.Count ? _devices[_list.SelectedIndices[0]] : null;

    void FillFromLink()
    {
        var l = CurrentLink;
        if (l == null) return;
        _mask.Text = l.Mask;
        _gw.Text = l.Gateway;
    }

    bool OtherSubnet(LanNetConfig.Device d)
        => !LanNetConfig.LocalLinks().Any(l => LanNetConfig.SameSubnet(d.Ip, l.Ip, l.Mask));

    void SetBusy(bool busy, string? status = null)
    {
        _btnFind.Enabled = _btnSuggest.Enabled = _btnApply.Enabled = !busy;
        if (status != null) _status.Text = status;
        UseWaitCursor = busy;
    }

    async Task FindAsync()
    {
        SetBusy(true, "Đang dò máy in (UDP broadcast)…");
        _devices.Clear();
        _list.Items.Clear();
        try
        {
            var list = await LanNetConfig.DiscoverAsync(3000, ct: _cts.Token);
            if (IsDisposed) return;
            foreach (var d in list.OrderByDescending(OtherSubnet).ThenByDescending(d => d.Dhcp == true).ThenBy(d => d.Ip))
            {
                _devices.Add(d);
                var other = OtherSubnet(d);
                var item = new ListViewItem(d.Model ?? LanNetConfig.Label(d.Proto));
                item.SubItems.Add(d.MacText);
                item.SubItems.Add(d.Ip);
                item.SubItems.Add(d.Mask ?? "");
                item.SubItems.Add(d.Dhcp == null ? "" : d.Dhcp.Value ? "Bật" : "Tắt");
                var dhcp = !other && d.Dhcp == true;
                item.SubItems.Add(other
                    ? (d.Proto == LanNetConfig.Proto.Epson ? "⚠ Khác lớp mạng — đổi IP bằng ARP+ping" : "⚠ Khác lớp mạng — cần đổi IP")
                    : dhcp ? "⚠ DHCP — IP có thể nhảy, nên đặt IP tĩnh" : "Cùng lớp mạng");
                if (other || dhcp) item.ForeColor = Theme.Warning;
                _list.Items.Add(item);
            }
            _status.Text = list.Count == 0
                ? "Không có máy in nào trả lời. Máy in hãng khác (HPRT, Gprinter…) không hỗ trợ dò — bấm «Hướng dẫn»."
                : $"Thấy {list.Count} máy in. Chọn máy cần đổi IP.";
            if (_list.Items.Count > 0) _list.Items[0].Selected = true;
        }
        catch (Exception ex) { _status.Text = "Dò lỗi: " + ex.Message; }
        finally { if (!IsDisposed) SetBusy(false); }
    }

    void OnSelect()
    {
        var d = Selected();
        if (d == null) return;
        _mac.Text = d.MacText;
        if (d.Mac != null && !OtherSubnet(d)) _ip.Text = d.Ip; // cùng lớp mạng: giữ IP, chuyển sang tĩnh
        else if (string.IsNullOrWhiteSpace(_ip.Text) || !OtherSubnet(d)) _ = SuggestAsync();
    }

    ISet<string> Avoid(LanNetConfig.Device? d)
    {
        var s = new HashSet<string>(_knownIps);
        foreach (var x in _devices) s.Add(x.Ip);
        if (d != null) s.Remove(d.Ip);
        return s;
    }

    async Task SuggestAsync()
    {
        var l = CurrentLink;
        if (l == null) { _status.Text = "PC chưa có mạng IPv4."; return; }
        SetBusy(true, $"Đang tìm IP trống trong lớp {l.Ip}/{l.Mask}…");
        try
        {
            var ip = await LanNetConfig.SuggestFreeIpAsync(l, Avoid(Selected()), _cts.Token);
            if (IsDisposed) return;
            if (ip != null)
            {
                _ip.Text = ip;
                _status.Text = $"Gợi ý {ip} (ARP / ping / TCP không thấy máy nào dùng). Có thể sửa.";
            }
            else _status.Text = "Không tìm được IP trống — nhập tay.";
        }
        finally { if (!IsDisposed) SetBusy(false); }
    }

    string? CheckInput(LanNetConfig.Link l, string ip, string mask, string gw)
    {
        if (LanNetConfig.ParseIp(ip) == null) return "IP mới không hợp lệ.";
        if (!LanNetConfig.IsValidMask(mask)) return "Subnet mask không hợp lệ (vd. 255.255.255.0).";
        if (LanNetConfig.ParseIp(gw) == null) return "Gateway không hợp lệ.";
        if (!LanNetConfig.SameSubnet(ip, l.Ip, mask)) return $"IP {ip} không cùng lớp mạng với PC ({l.Ip}).";
        if (!LanNetConfig.IsUsableHost(ip, mask)) return $"IP {ip} là địa chỉ mạng / broadcast.";
        if (!LanNetConfig.SameSubnet(gw, ip, mask)) return "Gateway phải cùng lớp mạng với IP mới.";
        if (ip == l.Ip) return "Đây là IP của chính PC này.";
        if (ip == gw) return "Trùng IP gateway (router).";
        return null;
    }

    async Task ApplyAsync()
    {
        var d = Selected();
        var l = CurrentLink;
        if (d == null || l == null) { UiMsg.Warn("Chọn máy in trong danh sách."); return; }
        var ip = _ip.Text.Trim();
        var mask = _mask.Text.Trim();
        var gw = _gw.Text.Trim();
        var err = CheckInput(l, ip, mask, gw);
        if (err != null) { UiMsg.Warn(err, "Đổi IP"); return; }

        byte[]? epsonMac = null;
        if (!d.CanSave)
        {
            if (d.Proto != LanNetConfig.Proto.Epson) { ShowHelp(d); return; }
            epsonMac = LanNetConfig.ParseMac(_mac.Text);
            if (epsonMac == null)
            {
                UiMsg.Warn("Epson: nhập MAC máy in (in trang tự kiểm tra: giữ FEED khi bật nguồn).", "Đổi IP Epson");
                return;
            }
        }

        SetBusy(true, $"Kiểm tra {ip} chưa có thiết bị dùng…");
        try
        {
            if (ip != d.Ip && (Avoid(d).Contains(ip) || await LanNetConfig.IsIpInUseAsync(ip)))
            {
                UiMsg.Warn($"IP {ip} đã có thiết bị dùng — chọn IP khác.", "Đổi IP");
                return;
            }
            var msg = epsonMac != null
                ? $"Đặt IP {ip} cho máy Epson MAC {_mac.Text.Trim()} bằng ARP + ping?\n" +
                  "Windows sẽ hỏi quyền quản trị (netsh). Mask / gateway của máy in không đổi."
                : $"Đặt IP tĩnh {ip} / {mask}, gateway {gw} cho «{d.Model ?? LanNetConfig.Label(d.Proto)}» (MAC {d.MacText})?";
            if (!UiMsg.Confirm(msg, "Đổi IP máy in")) return;

            bool ok;
            if (epsonMac != null)
            {
                _status.Text = "Đang gán ARP + ping (cửa sổ quyền quản trị)…";
                ok = await LanNetConfig.EpsonArpPingAsync(l, epsonMac, ip);
            }
            else
            {
                _status.Text = "Đang gửi cấu hình tới máy in…";
                await LanNetConfig.SendStaticIpAsync(d, ip, mask, gw);
                _status.Text = $"Đang chờ máy in lên {ip}:9100 (tối đa 20 giây)…";
                ok = await LanNetConfig.WaitForIpAsync(d, ip, ct: _cts.Token);
            }
            if (IsDisposed) return;
            if (!ok)
            {
                _status.Text = $"Chưa kết nối được {ip}:9100.";
                UiMsg.Warn(
                    $"Đã gửi lệnh nhưng chưa kết nối được {ip}:9100.\n" +
                    "Tắt rồi bật lại máy in, chờ ~10 giây, bấm «Dò lại».\n" +
                    "Vẫn không được: in trang tự kiểm tra (giữ FEED khi bật nguồn) xem IP thực tế, hoặc bấm «Hướng dẫn».",
                    "Đổi IP");
                return;
            }
            OldIp = d.Ip;
            NewIp = ip;
            DeviceTitle = d.Model ?? LanNetConfig.Label(d.Proto);
            DialogResult = DialogResult.OK;
            Close();
        }
        catch (System.ComponentModel.Win32Exception)
        {
            _status.Text = "Đã hủy cấp quyền quản trị.";
        }
        catch (Exception ex) { UiMsg.Error(ex.Message, "Đổi IP thất bại"); }
        finally { if (!IsDisposed) SetBusy(false); }
    }

    public static void ShowHelp(LanNetConfig.Device? d)
    {
        var epson = d?.Proto == LanNetConfig.Proto.Epson;
        var text =
            (d != null ? $"Máy in {d.Title} — khác lớp mạng nên chưa in được.\n\n" : "") +
            (epson
                ? "Epson: chọn máy → nhập MAC (trên trang tự kiểm tra) → «Đổi IP» (ARP + ping, cần quyền quản trị). " +
                  "Hoặc dùng EpsonNet Config của Epson.\n\n"
                : "") +
            "Hãng không hỗ trợ đổi IP qua mạng (HPRT, Gprinter, máy không trả lời dò):\n" +
            "1. Xem IP: tắt máy in, giữ FEED rồi bật nguồn → trang tự kiểm tra ghi IP / mask / gateway / DHCP.\n" +
            "2. Đặt tạm IP tĩnh cho PC cùng lớp với máy in (vd. máy in 192.168.123.100 → PC 192.168.123.50, mask 255.255.255.0).\n" +
            "3. Mở http://<IP máy in> hoặc công cụ của hãng (Xprinter Printer Tool, Rongta Ethernet Setting, " +
            "HPRT Printer Utility, Gprinter Ethernet Tool) → đặt IP tĩnh cùng lớp mạng cửa hàng (vd. 192.168.1.200) → lưu, tắt/bật máy in.\n" +
            "4. Trả PC về «Obtain an IP address automatically», rồi «Quét mạng».\n\n" +
            "Mẹo: nhiều máy in có reset mạng (giữ FEED ~10 giây khi đang bật) để về DHCP.";
        UiMsg.Info(text, "Đưa máy in về cùng lớp mạng");
    }
}
