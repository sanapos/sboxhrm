using System.IO.Ports;
using System.Text;

namespace SboxFlashGui;

public sealed class MainForm : Form
{
    // Offsets khớp partitions.csv + ESP-IDF esp32c3
    private const string OffsetBoot = "0x0";
    private const string OffsetPart = "0x8000";
    private const string OffsetOtaData = "0xe000";
    private const string OffsetApp = "0x20000";

    private readonly ComboBox _cboPort = new();
    private readonly ComboBox _cboBaud = new();
    private readonly TextBox _txtApp = new();
    private readonly TextBox _txtBoot = new();
    private readonly TextBox _txtPart = new();
    private readonly TextBox _txtOtaData = new();
    private readonly TextBox _txtEspTool = new();
    private readonly TextBox _txtIp = new();
    private readonly TextBox _txtPassword = new();
    private readonly RadioButton _rbFull = new() { Text = "USB Full (boot + partition + app)", Checked = true, AutoSize = true };
    private readonly RadioButton _rbAppOnly = new() { Text = "USB chi App (0x20000)", AutoSize = true };
    private readonly RadioButton _rbOta = new() { Text = "OTA WiFi (HTTP /api/ota)", AutoSize = true };
    private readonly CheckBox _chkErase = new() { Text = "Erase flash truoc khi nap (USB)", AutoSize = true };
    private readonly RichTextBox _log = new();
    private readonly Button _btnFlash = new();
    private readonly Button _btnCancel = new();
    private readonly Label _lblStatus = new();

    private CancellationTokenSource? _cts;
    private readonly FlashRunner _runner = new();

    public MainForm()
    {
        Text = "SBOX ZK Gateway — Nap ESP32-C3";
        Width = 860;
        Height = 720;
        MinimumSize = new Size(760, 620);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 9.5f);
        BackColor = Color.FromArgb(248, 250, 252);

        _runner.LineReceived += line =>
        {
            if (IsDisposed) return;
            BeginInvoke(() => AppendLog(line));
        };

        BuildUi();
        RefreshPorts();
        AutoFindEspTool();
        TryPrefillFromBuildFolder();
        UpdateModeUi();
    }

    private void BuildUi()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 6,
            Padding = new Padding(16),
        };
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 52));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 88));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 210));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 72));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 52));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        // Header
        var header = new Panel { Dock = DockStyle.Fill };
        var title = new Label
        {
            Text = "SBOX Flash Tool",
            Font = new Font("Segoe UI Semibold", 16f),
            ForeColor = Color.FromArgb(15, 23, 42),
            AutoSize = true,
            Location = new Point(0, 4),
        };
        var sub = new Label
        {
            Text = "Chon ROM + cong COM (hoac IP OTA). Loi hien trong khung log ben duoi.",
            ForeColor = Color.FromArgb(71, 85, 105),
            AutoSize = true,
            Location = new Point(0, 32),
        };
        header.Controls.Add(title);
        header.Controls.Add(sub);
        root.Controls.Add(header, 0, 0);

        // Mode
        var modeBox = MakeGroup("Che do nap");
        var modeFlow = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            Padding = new Padding(8),
        };
        _rbFull.CheckedChanged += (_, _) => UpdateModeUi();
        _rbAppOnly.CheckedChanged += (_, _) => UpdateModeUi();
        _rbOta.CheckedChanged += (_, _) => UpdateModeUi();
        modeFlow.Controls.Add(_rbFull);
        modeFlow.Controls.Add(_rbAppOnly);
        modeFlow.Controls.Add(_rbOta);
        modeBox.Controls.Add(modeFlow);
        root.Controls.Add(modeBox, 0, 1);

        // Files + port
        var filesBox = MakeGroup("File ROM & ket noi");
        var grid = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 3,
            RowCount = 7,
            Padding = new Padding(8),
        };
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 100));

        void AddRow(int row, string label, Control field, Control? browse)
        {
            grid.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0, 8, 0, 0) }, 0, row);
            field.Dock = DockStyle.Fill;
            grid.Controls.Add(field, 1, row);
            if (browse != null)
            {
                browse.Dock = DockStyle.Fill;
                grid.Controls.Add(browse, 2, row);
            }
            else
            {
                grid.SetColumnSpan(field, 2);
            }
        }

        _cboPort.DropDownStyle = ComboBoxStyle.DropDownList;
        var portPanel = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2 };
        portPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        portPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 90));
        var btnRefresh = new Button { Text = "Lam moi", Dock = DockStyle.Fill };
        btnRefresh.Click += (_, _) => RefreshPorts();
        portPanel.Controls.Add(_cboPort, 0, 0);
        portPanel.Controls.Add(btnRefresh, 1, 0);

        _cboBaud.DropDownStyle = ComboBoxStyle.DropDownList;
        _cboBaud.Items.AddRange(new object[] { "115200", "230400", "460800", "921600" });
        _cboBaud.SelectedItem = "460800";

        AddRow(0, "Cong COM", portPanel, null);
        AddRow(1, "Baud", _cboBaud, null);
        AddRow(2, "App ROM (.bin)", _txtApp, BrowseBtn("Chon file app ROM", _txtApp, "Firmware|*.bin|All|*.*", AfterPickApp));
        AddRow(3, "Bootloader", _txtBoot, BrowseBtn("Chon bootloader", _txtBoot, "Bin|*.bin|All|*.*", null));
        AddRow(4, "Partition", _txtPart, BrowseBtn("Chon partition-table", _txtPart, "Bin|*.bin|All|*.*", null));
        AddRow(5, "OTA data", _txtOtaData, BrowseBtn("Chon ota_data_initial", _txtOtaData, "Bin|*.bin|All|*.*", null));
        AddRow(6, "esptool.exe", _txtEspTool, BrowseBtn("Chon esptool.exe", _txtEspTool, "esptool|esptool.exe|Exe|*.exe|All|*.*", null));

        filesBox.Controls.Add(grid);
        root.Controls.Add(filesBox, 0, 2);

        // OTA + erase
        var otaBox = MakeGroup("OTA (khi chon che do OTA WiFi)");
        var otaGrid = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 4, Padding = new Padding(8) };
        otaGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 100));
        otaGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 40));
        otaGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 110));
        otaGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 60));
        otaGrid.Controls.Add(new Label { Text = "IP gateway", AutoSize = true, Margin = new Padding(0, 8, 0, 0) }, 0, 0);
        _txtIp.Dock = DockStyle.Fill;
        _txtIp.PlaceholderText = "vd: 192.168.1.124";
        otaGrid.Controls.Add(_txtIp, 1, 0);
        otaGrid.Controls.Add(new Label { Text = "Mat khau portal", AutoSize = true, Margin = new Padding(8, 8, 0, 0) }, 2, 0);
        _txtPassword.Dock = DockStyle.Fill;
        _txtPassword.UseSystemPasswordChar = true;
        _txtPassword.PlaceholderText = "(de trong neu khong khoa)";
        otaGrid.Controls.Add(_txtPassword, 3, 0);
        _chkErase.Margin = new Padding(0, 10, 0, 0);
        otaGrid.Controls.Add(_chkErase, 0, 1);
        otaGrid.SetColumnSpan(_chkErase, 4);
        otaBox.Controls.Add(otaGrid);
        root.Controls.Add(otaBox, 0, 3);

        // Actions
        var actions = new Panel { Dock = DockStyle.Fill };
        _btnFlash.Text = "Nap firmware";
        _btnFlash.Width = 160;
        _btnFlash.Height = 36;
        _btnFlash.Location = new Point(0, 6);
        _btnFlash.BackColor = Color.FromArgb(14, 165, 233);
        _btnFlash.ForeColor = Color.White;
        _btnFlash.FlatStyle = FlatStyle.Flat;
        _btnFlash.FlatAppearance.BorderSize = 0;
        _btnFlash.Click += async (_, _) => await StartFlashAsync();

        _btnCancel.Text = "Huy";
        _btnCancel.Width = 90;
        _btnCancel.Height = 36;
        _btnCancel.Location = new Point(170, 6);
        _btnCancel.Enabled = false;
        _btnCancel.Click += (_, _) => _cts?.Cancel();

        _lblStatus.AutoSize = true;
        _lblStatus.Location = new Point(280, 14);
        _lblStatus.ForeColor = Color.FromArgb(71, 85, 105);
        _lblStatus.Text = "San sang";

        actions.Controls.Add(_btnFlash);
        actions.Controls.Add(_btnCancel);
        actions.Controls.Add(_lblStatus);
        root.Controls.Add(actions, 0, 4);

        // Log
        var logBox = MakeGroup("Log / loi");
        _log.Dock = DockStyle.Fill;
        _log.ReadOnly = true;
        _log.BackColor = Color.FromArgb(15, 23, 42);
        _log.ForeColor = Color.FromArgb(226, 232, 240);
        _log.Font = new Font("Consolas", 9.5f);
        _log.BorderStyle = BorderStyle.None;
        logBox.Controls.Add(_log);
        root.Controls.Add(logBox, 0, 5);

        Controls.Add(root);
    }

    private static GroupBox MakeGroup(string title) => new()
    {
        Text = title,
        Dock = DockStyle.Fill,
        Padding = new Padding(8),
        ForeColor = Color.FromArgb(30, 41, 59),
    };

    private Button BrowseBtn(string title, TextBox target, string filter, Action? after)
    {
        var btn = new Button { Text = "Chon..." };
        btn.Click += (_, _) =>
        {
            using var dlg = new OpenFileDialog
            {
                Title = title,
                Filter = filter,
                CheckFileExists = true,
            };
            if (!string.IsNullOrWhiteSpace(target.Text) && File.Exists(target.Text))
                dlg.InitialDirectory = Path.GetDirectoryName(target.Text);
            if (dlg.ShowDialog(this) == DialogResult.OK)
            {
                target.Text = dlg.FileName;
                after?.Invoke();
            }
        };
        return btn;
    }

    private void AfterPickApp()
    {
        try
        {
            var app = _txtApp.Text.Trim();
            if (!File.Exists(app)) return;
            var buildDir = Path.GetDirectoryName(app);
            if (string.IsNullOrEmpty(buildDir)) return;

            // If user picked from build/, auto-fill siblings
            var boot = Path.Combine(buildDir, "bootloader", "bootloader.bin");
            var part = Path.Combine(buildDir, "partition_table", "partition-table.bin");
            var ota = Path.Combine(buildDir, "ota_data_initial.bin");

            if (File.Exists(boot) && string.IsNullOrWhiteSpace(_txtBoot.Text)) _txtBoot.Text = boot;
            if (File.Exists(part) && string.IsNullOrWhiteSpace(_txtPart.Text)) _txtPart.Text = part;
            if (File.Exists(ota) && string.IsNullOrWhiteSpace(_txtOtaData.Text)) _txtOtaData.Text = ota;

            // Also try one level up if bin is not in build root
            if (!File.Exists(_txtBoot.Text))
            {
                var altBoot = Path.Combine(buildDir, "..", "bootloader", "bootloader.bin");
                if (File.Exists(altBoot)) _txtBoot.Text = Path.GetFullPath(altBoot);
            }
        }
        catch (Exception ex)
        {
            AppendLog($"[canh bao] Tu dien day file: {ex.Message}", warn: true);
        }
    }

    private void TryPrefillFromBuildFolder()
    {
        var candidates = new[]
        {
            @"E:\zkgw\build\zk_gateway.bin",
            Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "build", "zk_gateway.bin")),
            @"E:\SBOX CURSOR\ZKTecoADMS-master\firmware\esp32c3-zk-gateway\build\zk_gateway.bin",
        };
        foreach (var c in candidates)
        {
            if (!File.Exists(c)) continue;
            _txtApp.Text = c;
            AfterPickApp();
            AppendLog($"Da nap san ROM: {c}");
            return;
        }
    }

    private void AutoFindEspTool()
    {
        var found = EspToolLocator.Find();
        if (found != null)
        {
            _txtEspTool.Text = found.Display;
            AppendLog($"esptool: {found.Display}");
        }
        else
        {
            AppendLog("Chua tim thay esptool — cai ESP-IDF hoac: pip install esptool", warn: true);
        }
    }

    private void RefreshPorts()
    {
        var selected = _cboPort.SelectedItem?.ToString();
        _cboPort.Items.Clear();
        string[] ports;
        try
        {
            ports = SerialPort.GetPortNames().OrderBy(p => p, StringComparer.OrdinalIgnoreCase).ToArray();
        }
        catch (Exception ex)
        {
            AppendLog($"Loi doc COM: {ex.Message}", error: true);
            ports = Array.Empty<string>();
        }

        foreach (var p in ports)
            _cboPort.Items.Add(p);

        if (_cboPort.Items.Count == 0)
        {
            AppendLog("Khong thay cong COM. Cam USB ESP32-C3 roi bam Lam moi.", warn: true);
            _lblStatus.Text = "Khong co COM";
            return;
        }

        if (selected != null && _cboPort.Items.Contains(selected))
            _cboPort.SelectedItem = selected;
        else
            _cboPort.SelectedIndex = 0;

        _lblStatus.Text = $"{_cboPort.Items.Count} cong COM";
        AppendLog("COM: " + string.Join(", ", ports));
    }

    private void UpdateModeUi()
    {
        var usb = _rbFull.Checked || _rbAppOnly.Checked;
        var full = _rbFull.Checked;
        _cboPort.Enabled = usb;
        _cboBaud.Enabled = usb;
        _txtBoot.Enabled = full;
        _txtPart.Enabled = full;
        _txtOtaData.Enabled = full;
        _chkErase.Enabled = usb;
        _txtIp.Enabled = _rbOta.Checked;
        _txtPassword.Enabled = _rbOta.Checked;
        _txtEspTool.Enabled = usb;
    }

    private async Task StartFlashAsync()
    {
        _log.Clear();
        _cts = new CancellationTokenSource();
        SetBusy(true);
        try
        {
            (bool Ok, string Message) result;
            if (_rbOta.Checked)
            {
                result = await _runner.RunOtaAsync(
                    _txtIp.Text.Trim(),
                    _txtPassword.Text,
                    _txtApp.Text.Trim(),
                    _cts.Token);
            }
            else
            {
                var images = BuildImageList();
                if (!int.TryParse(_cboBaud.SelectedItem?.ToString(), out var baud))
                    baud = 460800;
                var tool = EspToolLocator.FromUserPath(_txtEspTool.Text);
                result = await _runner.RunUsbAsync(
                    tool,
                    _cboPort.SelectedItem?.ToString() ?? "",
                    baud,
                    images,
                    _chkErase.Checked,
                    _cts.Token);
            }

            if (result.Ok)
            {
                AppendLog(result.Message, ok: true);
                _lblStatus.Text = "Thanh cong";
                _lblStatus.ForeColor = Color.FromArgb(22, 163, 74);
                MessageBox.Show(this, result.Message, "Thanh cong", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            else
            {
                AppendLog(result.Message, error: true);
                _lblStatus.Text = "That bai";
                _lblStatus.ForeColor = Color.FromArgb(220, 38, 38);
                MessageBox.Show(this, result.Message, "Loi nap firmware", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
        catch (Exception ex)
        {
            AppendLog(ex.ToString(), error: true);
            _lblStatus.Text = "Loi";
            MessageBox.Show(this, ex.Message, "Loi", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            SetBusy(false);
            _cts = null;
        }
    }

    private List<(string Offset, string Path)> BuildImageList()
    {
        var list = new List<(string, string)>();
        var app = _txtApp.Text.Trim();
        if (string.IsNullOrWhiteSpace(app))
            throw new InvalidOperationException("Chua chon App ROM (.bin).");

        if (_rbAppOnly.Checked)
        {
            list.Add((OffsetApp, app));
            return list;
        }

        var boot = _txtBoot.Text.Trim();
        var part = _txtPart.Text.Trim();
        var ota = _txtOtaData.Text.Trim();

        if (string.IsNullOrWhiteSpace(boot) || !File.Exists(boot))
            throw new InvalidOperationException("Che do Full can Bootloader (build/bootloader/bootloader.bin).");
        if (string.IsNullOrWhiteSpace(part) || !File.Exists(part))
            throw new InvalidOperationException("Che do Full can Partition (build/partition_table/partition-table.bin).");

        list.Add((OffsetBoot, boot));
        list.Add((OffsetPart, part));
        if (!string.IsNullOrWhiteSpace(ota) && File.Exists(ota))
            list.Add((OffsetOtaData, ota));
        list.Add((OffsetApp, app));
        return list;
    }

    private void SetBusy(bool busy)
    {
        _btnFlash.Enabled = !busy;
        _btnCancel.Enabled = busy;
        UseWaitCursor = busy;
        if (busy)
        {
            _lblStatus.Text = "Dang nap...";
            _lblStatus.ForeColor = Color.FromArgb(14, 165, 233);
        }
    }

    private void AppendLog(string text, bool error = false, bool warn = false, bool ok = false)
    {
        if (string.IsNullOrEmpty(text)) return;
        var color = Color.FromArgb(226, 232, 240);
        if (error) color = Color.FromArgb(248, 113, 113);
        else if (warn) color = Color.FromArgb(251, 191, 36);
        else if (ok) color = Color.FromArgb(74, 222, 128);
        else if (text.Contains("error", StringComparison.OrdinalIgnoreCase) ||
                 text.Contains("fail", StringComparison.OrdinalIgnoreCase) ||
                 text.Contains("A fatal", StringComparison.OrdinalIgnoreCase))
            color = Color.FromArgb(248, 113, 113);

        _log.SelectionStart = _log.TextLength;
        _log.SelectionLength = 0;
        _log.SelectionColor = color;
        _log.AppendText(text.EndsWith('\n') ? text : text + Environment.NewLine);
        _log.ScrollToCaret();
    }
}
