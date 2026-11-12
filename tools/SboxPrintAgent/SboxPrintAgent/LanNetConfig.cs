using System.Diagnostics;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;

namespace SboxPrintAgent;

/// <summary>
/// Dò máy in LAN bằng UDP broadcast — tới được máy in KHÁC lớp mạng IP nhưng cùng mạng vật lý
/// (vd. máy in còn IP nhà máy 192.168.123.100, mạng cửa hàng 192.168.1.x) — và đặt IP tĩnh qua mạng.
/// Cùng giao thức với app (flutter_client/lib/utils/pos_lan_printer_netconfig.dart); nguồn:
/// <list type="bullet">
/// <item>Xprinter: SDK Android 3.x net.posprinter.esc.PosUdpNet / model.UdpDevice
/// (jar trong github.com/KickNext/pos_printers). UDP 9000, XP0001FIND / FOUND / SAVE.</item>
/// <item>Rongta (và Zywell — ZY80-Q2 thật trả lời họ này): SDK RTPrinter com.rt.printerlibrary.ipscan
/// (jar trong github.com/warrence/rongta-capacitor-thermal-printer). UDP 1460, MP4200FIND / FOUND / SAVE.</item>
/// <item>Epson: ENPC UDP 3289 (Epson UB-E04 Technical Reference Guide); gói dò theo SANE epson2.c.
/// Đổi IP Epson: ARP + ping theo cùng tài liệu (arp -s IP MAC rồi ping IP; chỉ đặt IP, cần quyền quản trị).</item>
/// </list>
/// Chi tiết byte: docs/printers/lan-printer-ip-protocols.md.
/// </summary>
public static class LanNetConfig
{
    public enum Proto { Xprinter, Rongta, Epson }

    public static int UdpPort(Proto p) => p switch { Proto.Xprinter => 9000, Proto.Rongta => 1460, _ => 3289 };

    public static string Label(Proto p) => p switch
    {
        Proto.Xprinter => "Xprinter / tương thích",
        Proto.Rongta => "Rongta / Zywell / tương thích",
        _ => "Epson (ENPC)",
    };

    public sealed record Device(Proto Proto, string Ip, byte[]? Mac, string? Mask, string? Gateway, bool? Dhcp, string? Model)
    {
        public string MacText => Mac == null ? "" : string.Join(":", Mac.Select(b => b.ToString("X2")));
        public string Key => Mac != null ? $"{Proto}/{MacText}" : $"{Proto}/{Ip}";
        /// <summary>Đổi IP bằng gói SAVE (Xprinter / Rongta).</summary>
        public bool CanSave => Proto != Proto.Epson && Mac is { Length: 6 };
        public string Title => (Model ?? Label(Proto)) + " · " + Ip;
    }

    /// <summary>Card mạng của PC: IP, mask, gateway, chỉ số interface (cho netsh).</summary>
    public sealed record Link(string Ip, string Mask, string Gateway, int IfIndex, string IfName)
    {
        public override string ToString() => $"{Ip} / {Mask} — {IfName}";
    }

    // —— Gói tin ——

    public static readonly byte[] XpFind = Encoding.ASCII.GetBytes("XP0001FIND");
    public static readonly byte[] RtFind = Encoding.ASCII.GetBytes("MP4200FIND");
    /// <summary>SANE epson2.c: "EPSONP\x00\xff\x00\x00\x00\x00\x00\x00\x00".</summary>
    public static readonly byte[] EpsonProbe = Encoding.ASCII.GetBytes("EPSONP").Concat(new byte[] { 0x00, 0xFF, 0, 0, 0, 0, 0, 0, 0 }).ToArray();

    static bool StartsWith(byte[] d, string tag)
    {
        if (d.Length < tag.Length) return false;
        for (var i = 0; i < tag.Length; i++)
            if (d[i] != (byte)tag[i]) return false;
        return true;
    }

    static string Ip(byte[] d, int o) => $"{d[o]}.{d[o + 1]}.{d[o + 2]}.{d[o + 3]}";
    static bool Zero(byte[] d, int o) => d[o] == 0 && d[o + 1] == 0 && d[o + 2] == 0 && d[o + 3] == 0;

    static string? CString(byte[] d, int o)
    {
        var sb = new StringBuilder();
        for (var i = o; i < d.Length && d[i] != 0; i++)
        {
            if (d[i] < 0x20 || d[i] > 0x7E) return null;
            sb.Append((char)d[i]);
        }
        var s = sb.ToString().Trim();
        return s.Length >= 2 ? s : null;
    }

    public static Device? Parse(byte[] d, string sourceIp)
    {
        // UdpDevice: MAC 11..16, IP 19, mask 23, gw 27, DHCP [33] == 1.
        if (StartsWith(d, "XP0001FOUND") && d.Length >= 34)
            return new Device(Proto.Xprinter, Ip(d, 19), d[11..17], Ip(d, 23), Ip(d, 27), d[33] == 1, null);
        // IpScanner: MAC 11..16, DHCP [33] != 0; IP/mask/gw 19/23/27 + model từ 34 theo gói thật ZY80-Q2.
        if (StartsWith(d, "MP4200FOUND") && d.Length >= 34)
            return new Device(Proto.Rongta, Zero(d, 19) ? sourceIp : Ip(d, 19), d[11..17],
                Zero(d, 23) ? null : Ip(d, 23), Zero(d, 27) ? null : Ip(d, 27), d[33] != 0, CString(d, 34));
        // ENPC: trả lời có loại gói viết thường (gói dò của chính mình là 'P').
        if (StartsWith(d, "EPSON") && d.Length >= 6 && d[5] >= 0x61 && d[5] <= 0x7A)
            return new Device(Proto.Epson, sourceIp, null, null, null, null, null);
        return null;
    }

    /// <summary>Gói SAVE 33 byte đặt IP tĩnh — hằng số đúng theo từng SDK.</summary>
    public static byte[] BuildSave(Proto proto, byte[] mac, string ip, string mask, string gateway)
    {
        if (mac.Length != 6) throw new ArgumentException("MAC phải 6 byte");
        var ipB = ParseIp(ip) ?? throw new ArgumentException("IP không hợp lệ");
        var maskB = ParseIp(mask) ?? throw new ArgumentException("Mask không hợp lệ");
        var gwB = ParseIp(gateway) ?? throw new ArgumentException("Gateway không hợp lệ");
        var (tag, c1, c2) = proto switch
        {
            // udpNetConfig: tag + MAC + 22 00 + IP + mask + gw + 8C 17 + dhcp(00 = tĩnh)
            Proto.Xprinter => ("XP0001SAVE", new byte[] { 0x22, 0x00 }, new byte[] { 0x8C, 0x17, 0x00 }),
            // IpUpdata: tag + MAC + 0F 00 + IP + mask + gw + 05 B4 + 00
            Proto.Rongta => ("MP4200SAVE", new byte[] { 0x0F, 0x00 }, new byte[] { 0x05, 0xB4, 0x00 }),
            _ => throw new NotSupportedException("Epson: không có gói đổi IP đã xác minh — dùng ARP + ping."),
        };
        return Encoding.ASCII.GetBytes(tag).Concat(mac).Concat(c1).Concat(ipB).Concat(maskB).Concat(gwB).Concat(c2).ToArray();
    }

    // —— IPv4 ——

    public static byte[]? ParseIp(string s)
    {
        var parts = (s ?? "").Trim().Split('.');
        if (parts.Length != 4) return null;
        var o = new byte[4];
        for (var i = 0; i < 4; i++)
        {
            if (parts[i].Length is 0 or > 3 || !parts[i].All(char.IsAsciiDigit) || !byte.TryParse(parts[i], out o[i]))
                return null;
        }
        return o;
    }

    static uint? U(string s)
    {
        var b = ParseIp(s);
        return b == null ? null : (uint)(b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3]);
    }

    static string S(uint v) => $"{v >> 24 & 255}.{v >> 16 & 255}.{v >> 8 & 255}.{v & 255}";

    public static bool IsValidMask(string mask)
    {
        if (U(mask) is not uint m) return false;
        var inv = ~m;
        if ((inv & (inv + 1)) != 0) return false;
        var bits = System.Numerics.BitOperations.PopCount(m);
        return bits is >= 8 and <= 30;
    }

    public static bool SameSubnet(string a, string b, string mask)
        => U(a) is uint x && U(b) is uint y && U(mask) is uint m && (x & m) == (y & m);

    public static bool IsUsableHost(string ip, string mask)
    {
        if (U(ip) is not uint x || U(mask) is not uint m) return false;
        var host = x & ~m;
        return host != 0 && host != ~m;
    }

    /// <summary>Thứ tự thử IP trống: .200–.250 rồi .100–.199, bỏ IP PC / gateway / [avoid].</summary>
    public static List<string> FreeIpCandidates(string localIp, string mask, string gateway, ISet<string>? avoid = null)
    {
        var res = new List<string>();
        if (U(localIp) is not uint x || U(mask) is not uint m) return res;
        var net = x & m;
        var hostMax = ~m - 1;
        foreach (var h in Enumerable.Range(200, 51).Concat(Enumerable.Range(100, 100)))
        {
            if (h < 1 || h > hostMax) continue;
            var ip = S(net | (uint)h);
            if (ip == localIp || ip == gateway || (avoid?.Contains(ip) ?? false)) continue;
            res.Add(ip);
        }
        return res;
    }

    public static List<Link> LocalLinks()
    {
        var res = new List<Link>();
        foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (ni.OperationalStatus != OperationalStatus.Up) continue;
            if (ni.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel) continue;
            IPInterfaceProperties props;
            int idx;
            try
            {
                props = ni.GetIPProperties();
                idx = props.GetIPv4Properties()?.Index ?? -1;
            }
            catch { continue; }
            var gw = props.GatewayAddresses.Select(g => g.Address)
                .FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetwork && !a.Equals(IPAddress.Any))?.ToString();
            foreach (var ua in props.UnicastAddresses)
            {
                if (ua.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                var ip = ua.Address.ToString();
                if (ip.StartsWith("127.") || ip.StartsWith("169.254.")) continue;
                var mask = ua.IPv4Mask?.ToString() ?? "255.255.255.0";
                if (mask == "0.0.0.0") mask = "255.255.255.0";
                var g = gw != null && SameSubnet(gw, ip, mask) ? gw : S((U(ip)!.Value & U(mask)!.Value) | 1);
                res.Add(new Link(ip, mask, g, idx, ni.Name));
            }
        }
        return res;
    }

    // —— Mạng ——

    static UdpClient? Bind(string localIp, int port)
    {
        try
        {
            var u = new UdpClient(AddressFamily.InterNetwork);
            u.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
            u.EnableBroadcast = true;
            u.Client.Bind(new IPEndPoint(IPAddress.Parse(localIp), port));
            return u;
        }
        catch { return null; }
    }

    /// <summary>
    /// Mỗi card mạng một socket (Windows chỉ phát 255.255.255.255 ra một card nếu bind Any).
    /// Bind cổng 9000 như SDK Xprinter (máy in trả lời về cổng này); bận thì cổng tạm.
    /// </summary>
    static List<UdpClient> OpenSockets()
    {
        var list = new List<UdpClient>();
        foreach (var l in LocalLinks())
        {
            var u = Bind(l.Ip, 9000) ?? Bind(l.Ip, 0);
            if (u != null) list.Add(u);
        }
        return list;
    }

    static IPEndPoint Bcast(int port) => new(IPAddress.Broadcast, port);

    public static async Task<List<Device>> DiscoverAsync(int timeoutMs = 3000, IProgress<Device>? found = null, CancellationToken ct = default)
    {
        var res = new Dictionary<string, Device>();
        var socks = OpenSockets();
        try
        {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            var receivers = socks.Select(s => Task.Run(async () =>
            {
                while (!cts.IsCancellationRequested)
                {
                    UdpReceiveResult r;
                    try { r = await s.ReceiveAsync(cts.Token); }
                    catch { return; }
                    var d = Parse(r.Buffer, r.RemoteEndPoint.Address.ToString());
                    if (d == null) continue;
                    lock (res)
                    {
                        if (!res.TryAdd(d.Key, d)) continue;
                    }
                    found?.Report(d);
                }
            })).ToList();

            const int rounds = 3;
            var step = timeoutMs / (rounds + 1);
            for (var i = 0; i < rounds && !ct.IsCancellationRequested; i++)
            {
                foreach (var s in socks)
                {
                    try
                    {
                        await s.SendAsync(XpFind, Bcast(UdpPort(Proto.Xprinter)));
                        await s.SendAsync(RtFind, Bcast(UdpPort(Proto.Rongta)));
                        await s.SendAsync(EpsonProbe, Bcast(UdpPort(Proto.Epson)));
                    }
                    catch { /* card mạng không gửi broadcast được */ }
                }
                try { await Task.Delay(step, ct); } catch { break; }
            }
            try { await Task.Delay(step, ct); } catch { }
            cts.Cancel();
            foreach (var s in socks) s.Close();
            await Task.WhenAll(receivers);
        }
        finally
        {
            foreach (var s in socks) s.Dispose();
        }
        lock (res) return res.Values.ToList();
    }

    /// <summary>Gửi SAVE (broadcast, máy in chọn theo MAC) 3 lần — SDK không có ACK chuẩn.</summary>
    public static async Task SendStaticIpAsync(Device d, string ip, string mask, string gateway)
    {
        var pkt = BuildSave(d.Proto, d.Mac!, ip, mask, gateway);
        var socks = OpenSockets();
        try
        {
            for (var i = 0; i < 3; i++)
            {
                foreach (var s in socks)
                {
                    try { await s.SendAsync(pkt, Bcast(UdpPort(d.Proto))); } catch { }
                }
                await Task.Delay(250);
            }
        }
        finally
        {
            foreach (var s in socks) s.Dispose();
        }
    }

    public static async Task<bool> TcpOpenAsync(string host, int port, int timeoutMs = 800)
    {
        try
        {
            using var c = new TcpClient();
            using var cts = new CancellationTokenSource(timeoutMs);
            await c.ConnectAsync(host, port, cts.Token);
            return c.Connected;
        }
        catch { return false; }
    }

    /// <summary>Chờ máy in lên IP mới: TCP 9100 mở được, hoặc dò thấy đúng MAC ở IP mới.</summary>
    public static async Task<bool> WaitForIpAsync(Device d, string ip, int timeoutMs = 20000, CancellationToken ct = default)
    {
        var sw = Stopwatch.StartNew();
        while (sw.ElapsedMilliseconds < timeoutMs && !ct.IsCancellationRequested)
        {
            if (await TcpOpenAsync(ip, 9100)) return true;
            if (d.Mac != null)
            {
                var list = await DiscoverAsync(1500, ct: ct);
                if (list.Any(x => x.Key == d.Key && x.Ip == ip) && await TcpOpenAsync(ip, 9100, 2000)) return true;
            }
            else
            {
                try { await Task.Delay(1000, ct); } catch { break; }
            }
        }
        return false;
    }

    [DllImport("iphlpapi.dll", ExactSpelling = true)]
    static extern int SendARP(uint destIp, uint srcIp, byte[] macAddr, ref uint macLen);

    /// <summary>IP đã có thiết bị dùng? ARP (cùng lớp mạng — chắc nhất), ping, rồi TCP vài cổng phổ biến.</summary>
    public static async Task<bool> IsIpInUseAsync(string ip)
    {
        var addr = IPAddress.Parse(ip);
        var arp = await Task.Run(() =>
        {
            try
            {
                var mac = new byte[6];
                uint len = 6;
#pragma warning disable CS0618 // Address (uint, thứ tự mạng) đúng kiểu SendARP cần
                return SendARP((uint)addr.Address, 0, mac, ref len) == 0 && len > 0;
#pragma warning restore CS0618
            }
            catch { return false; }
        });
        if (arp) return true;
        try
        {
            using var p = new Ping();
            var r = await p.SendPingAsync(addr, 800);
            if (r.Status == IPStatus.Success) return true;
        }
        catch { }
        int[] ports = { 9100, 80, 443, 515, 631, 22, 445, 8080, 554 };
        var tcp = await Task.WhenAll(ports.Select(port => TcpAliveAsync(ip, port)));
        return tcp.Any(x => x);
    }

    static async Task<bool> TcpAliveAsync(string ip, int port)
    {
        try
        {
            using var c = new TcpClient();
            using var cts = new CancellationTokenSource(700);
            await c.ConnectAsync(ip, port, cts.Token);
            return true;
        }
        catch (SocketException e) when (e.SocketErrorCode == SocketError.ConnectionRefused) { return true; }
        catch { return false; }
    }

    public static async Task<string?> SuggestFreeIpAsync(Link link, ISet<string>? avoid = null, CancellationToken ct = default)
    {
        var cands = FreeIpCandidates(link.Ip, link.Mask, link.Gateway, avoid);
        for (var i = 0; i < cands.Count && i < 60; i += 6)
        {
            if (ct.IsCancellationRequested) return null;
            var chunk = cands.Skip(i).Take(6).ToList();
            var used = await Task.WhenAll(chunk.Select(IsIpInUseAsync));
            for (var j = 0; j < chunk.Count; j++)
                if (!used[j]) return chunk[j];
        }
        return null;
    }

    /// <summary>
    /// Epson «arp+ping IP setting» (UB-E04 TRG): gắn tạm ARP IP mới → MAC máy in, ping IP mới, rồi gỡ ARP.
    /// netsh cần quyền quản trị — mở cmd nâng quyền (UAC). Chỉ đổi IP; mask / gateway giữ nguyên (đổi bằng web / EpsonNet Config).
    /// </summary>
    public static async Task<bool> EpsonArpPingAsync(Link link, byte[] mac, string newIp)
    {
        if (mac.Length != 6 || ParseIp(newIp) == null) throw new ArgumentException("MAC / IP không hợp lệ");
        var macDash = string.Join("-", mac.Select(b => b.ToString("x2")));
        var cmd = $"/c netsh interface ipv4 add neighbors {link.IfIndex} {newIp} {macDash} " +
                  $"& ping -n 4 -w 1000 {newIp} " +
                  $"& netsh interface ipv4 delete neighbors {link.IfIndex} {newIp}";
        var psi = new ProcessStartInfo("cmd.exe", cmd)
        {
            UseShellExecute = true,
            Verb = "runas",
            WindowStyle = ProcessWindowStyle.Hidden,
        };
        using var p = Process.Start(psi) ?? throw new InvalidOperationException("Không chạy được netsh.");
        await p.WaitForExitAsync();
        return await WaitForIpAsync(new Device(Proto.Epson, newIp, mac, null, null, null, null), newIp, 15000);
    }

    public static byte[]? ParseMac(string s)
    {
        var hex = new string((s ?? "").Where(Uri.IsHexDigit).ToArray());
        if (hex.Length != 12) return null;
        return Enumerable.Range(0, 6).Select(i => Convert.ToByte(hex.Substring(i * 2, 2), 16)).ToArray();
    }
}
