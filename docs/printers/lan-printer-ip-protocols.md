# Máy in LAN khác lớp mạng: dò và đổi IP

Code: `flutter_client/lib/utils/pos_lan_printer_netconfig.dart` (bản sao ở `flutter_pos`),
`tools/SboxPrintAgent/SboxPrintAgent/LanNetConfig.cs`. Máy in giả cho QA: `scripts/qa/fake_udp_printer.py`.

## Hãng nào làm được gì

| Hãng / module | Dò khi khác lớp mạng | Đổi IP qua mạng | Cách |
|---|---|---|---|
| Xprinter (và máy dùng module XP0001) | Có — UDP 9000 | Có (app + Print Agent) | Gói SAVE theo MAC |
| Rongta (MP4200) | Có — UDP 1460 | Có (app + Print Agent) | Gói SAVE theo MAC |
| Zywell (đã thấy ZY80-Q2 trả lời MP4200) | Có — UDP 1460 | Có | Như Rongta |
| Epson (TM-T82/T88, UB-E04…) | Có — ENPC UDP 3289 | Chỉ Print Agent (Windows) | ARP + ping (cần quyền quản trị, nhập MAC; chỉ đổi IP) |
| HPRT, Gprinter, hãng khác | Không (chưa có giao thức xác minh) | Không | Hướng dẫn: trang tự kiểm tra + đặt tạm IP cho máy tính |

Kiểm chứng 2026-10-26: máy Zywell **ZY80-Q2** thật (192.168.1.89) trả lời `MP4200FIND` bằng gói 64 byte
`4d 50 34 32 30 30 46 4f 55 4e 44 | 00 60 35 d1 f3 82 | 3c 00 | c0 a8 01 59 | ff ff ff 00 | c0 a8 01 01 | 8c 23 | 00 | "ZY80-Q2" 00…`
→ MAC @11, IP @19, mask @23, gw @27, DHCP @33, model ASCII @34 (layout giống hệt Xprinter). Chưa gửi SAVE tới máy thật.

Lưu ý khi dùng:
- Gói SAVE không có ACK chuẩn: app gửi 3 lần rồi chờ TCP 9100 ở IP mới (tối đa 20 s). Có máy cần tắt/bật lại.
- Android cần `MulticastLock` (kênh `sbox/lan_printer_net`), không thì Wi‑Fi có thể lọc gói broadcast.
- Router / Wi‑Fi bật «AP isolation» hoặc máy in ở VLAN khác thì broadcast không tới — phải làm tay.

---

## Ghi chú nghiên cứu (nguồn, byte, mức tin cậy)

# Thermal printer LAN discovery and IP change protocols (research notes)

Researched 2026-10-26. Web research plus **static bytecode disassembly (`javap -c`) of vendor Android SDK jars published on GitHub**. Nothing was executed. Byte layouts marked "verified-by-source-code" come from those disassemblies or from open-source code. Everything else carries its own confidence rating.

Confidence scale:
- **[SRC]**: verified by source code (open-source code, or a disassembled vendor SDK).
- **[VENDOR]**: documented by the vendor (manual or PDF).
- **[RE]**: reverse-engineering write-up with packet captures (a single author).
- **[FORUM]**: a single forum post or issue comment.
- **[UNVERIFIED]**: my inference. Do not rely on it without testing.

---

## 0. Key finding: two Chinese module families on UDP (cross-subnet capable)

Two vendor SDKs carry a UDP broadcast "FIND / FOUND / SAVE" protocol. In both, a MAC address selects the target device and the packet goes to **255.255.255.255**. That design works when the printer sits on a different IP subnet of the same L2 segment.

| SDK | Tag prefix | UDP port | Source |
|---|---|---|---|
| Xprinter Android SDK 3.x (`net.posprinter.esc.PosUdpNet`) | `XP0001` | **9000** | jar in https://github.com/KickNext/pos_printers (`android/libs/classes.jar`) |
| Rongta RTPrinter Android SDK (`com.rt.printerlibrary.ipscan.IpScanner` / `IpUpdata`) | `MP4200` | **1460** | jar in https://github.com/warrence/rongta-capacitor-thermal-printer (`android/libs/printer_library.jar`). The same jar also appears in shic/printer-rongta, AsadLeo14/Rongta-Printer-Sample and byshy/rongta_printer |

The two families use the same field offsets: the ASCII tag, then MAC at a fixed offset, then IP, mask and gateway, then a DHCP flag at byte 33 of FOUND. That strongly suggests a common OEM network-module firmware where only the tag string and the port differ per vendor. **[SRC]** for each layout. Whether a module answers the *other* vendor's tag is **[UNVERIFIED]**, so send both.

---

## 1. Xprinter

### 1a. UDP discovery (Xprinter SDK 3.x `PosUdpNet.searchNetDevice`) [SRC]
- Socket: `DatagramSocket` with `setReuseAddress(true)`, **bound to local UDP port 9000** (`new InetSocketAddress(9000)`).
- Request: ASCII `XP0001FIND` (10 bytes, no terminator), sent to **255.255.255.255:9000**.
  - Hex: `58 50 30 30 30 31 46 49 4E 44`
- Receive loop: 1024-byte buffer. A packet is accepted when `new String(data,0,len).contains("XP0001FOUND")`.
- Socket auto-closes 30 s later (`postDelayed(..., 30000)`).
- Response parse (`net.posprinter.model.UdpDevice(byte[])`, offsets from packet start):

| Offset | Len | Field |
|---|---|---|
| 0 | 11 | `XP0001FOUND` (ASCII) |
| 11 | 6 | MAC |
| 17 | 2 | not read by SDK (unknown) |
| 19 | 4 | IP |
| 23 | 4 | Subnet mask |
| 27 | 4 | Gateway |
| 31 | 2 | not read by SDK (unknown) |
| 33 | 1 | DHCP: `== 1` means enabled |

- The newer SDK 3.5.8 also exposes `UdpDevice.getModelName()` (per PR https://github.com/KickNext/pos_printers/pull/2). Its offset was **not** in the jar I disassembled, so it is unknown.

### 1b. UDP set IP (Xprinter SDK 3.x `PosUdpNet.udpNetConfig(mac, ip, mask, gw, dhcp)`) [SRC]
- Same socket (bound to 9000). The packet is sent to **255.255.255.255:9000**.
- Payload (33 bytes):

| Offset | Len | Bytes |
|---|---|---|
| 0 | 10 | `XP0001SAVE` = `58 50 30 30 30 31 53 41 56 45` |
| 10 | 6 | target MAC (from FOUND) |
| 16 | 2 | `22 00` (constant, meaning unknown) |
| 18 | 4 | new IP |
| 22 | 4 | new mask |
| 26 | 4 | new gateway |
| 30 | 1 | `8C` (constant, `bipush -116`) |
| 31 | 1 | `17` (constant, 23) |
| 32 | 1 | DHCP: `01` enables, `00` disables (static) |

- Example: static 192.168.1.200/24, gateway 192.168.1.1, MAC 00:11:22:33:44:55:
  `58 50 30 30 30 31 53 41 56 45 00 11 22 33 44 55 22 00 C0 A8 01 C8 FF FF FF 00 C0 A8 01 01 8C 17 00`
- The SDK does not wait for an ACK. Auth: none. Reboot: the SDK sends no reboot command, so whether the module restarts itself is **unknown**. Re-run FIND afterwards to confirm.

### 1c. ESC/POS-style set-IP over TCP 9100 or USB (prefix `1F 1B 1F`, "US ESC US")
There are two command families. Both are present in the same Xprinter SDK 3.x jar (`net.posprinter.POSPrinter`). **[SRC]**

Family A (old). The same codes appear in the Zywell/"PosPrinterSDK" jar (`net.posprinter.utils.PosSetting`, https://github.com/lehoi2195/react-native-zywell-thermal-printer `android/libs/PosPrinterSDK.jar`) and in the Wireshark captures at https://blog.lambda.cx/posts/xprinter-wifi/ (raw source: https://git.lambda.cx/blog/plain/content/posts/xprinter-wifi/index.org). The repo name says Zywell, but the jar's provenance as Zywell-official is not proven.

| Purpose | Bytes | SDK method |
|---|---|---|
| Set IP | `1F 1B 1F 22` + IP(4) | `POSPrinter.setIp` / `PosSetting.sendSetip` |
| Set mask | `1F 1B 1F B0` + mask(4) | `setMask` / `sendSetym` |
| Set gateway | `1F 1B 1F B1` + gw(4) | `setGateway` / `sendSetwg` |
| IP + mask + gw | `1F 1B 1F B2` + IP + mask + gw | `PosSetting.sendSetNet` |
| WiFi SSID/key | `1F 1B 1F B3` + keyType(1) + SSID + `00` + key + `00` | `sendSetWifi` |
| All (wifi printers) | `1F 1B 1F B4` + IP + mask + gw + keyType + SSID + `00` + key + `00` | `POSPrinter.wifiConfig` / `sendSetNetall` |

Lambda.cx quotes: "`0000   1f 1b 1f 22 c0 a8 00 07`" (set IP 192.168.0.7) and "`1f 1b 1f b2 c0 a8 00 07 ff ff ff 00 c0 a8 00 01`". The author reports that **only `B4` worked reliably** on their WiFi model, and only over USB. Key types per the post: 00 NULL, 01 WEP64, 02 WEP128, 03 WPA_AES_PSK, 04 WPA_TKIP_PSK, 05 WPA_TKIP_AES_PSK, 06 WPA2_AES_PSK, 07 WPA2_TKIP, 08 WPA2_TKIP_AES_PSK, 09 WPA_WPA2_MixedMode. **[RE]** plus **[SRC]** (https://github.com/dantecatalfamo/xprinter-wifi, `xprinter-wifi.rb`: `PREAMBLE = "\x1f\e\x1f"`, `NETWORK_COMMAND = "\xb4"`, IP/mask/gw as `hton`).

Family B (newer, `POSPrinter.setNetAll(ip, mask, gw, dhcp)`) **[SRC]**:
```
1F 1B 1F 91 00 49 FA  <dhcp:00|01>  5A  <IP 4>  <MASK 4>  <GW 4>
```
(Header bytes from the bytecode: `31, 27, 31, -111, 0, 73, -6`, then `(byte)dhcp`, then `90`, then ip, mask, gw.)

The individual `1F 1B 1F 91 00 49 5x` commands are documented in a vendor-style command manual (M5Stack ATOM Printer, a Chinese OEM board; https://m5stack.oss-cn-shenzhen.aliyuncs.com/resource/docs/datasheet/atombase/atom_pritner/ATOM_PRINTER_CMD_v1.06.pdf, §1.50–1.52) **[VENDOR, other OEM]**:
- "1.50 US ESC 修改 IP 地址 … 十六进制码 1F 1B 1F 91 00 49 50 X X X X  最后 4 位为 IP 地址"
- §1.51 mask: `1F 1B 1F 91 00 49 51 XX XX XX XX`
- §1.52 gateway: `1F 1B 1F 91 00 49 52 XX XX XX XX`
- The same manual, chapter 8, also lists `ESC ## IPAD` = `1B 23 23 49 50 41 44 d0..d3` (IP), `ESC ## IPMK` = `1B 23 23 49 50 4D 4B` + 4 (mask), `ESC ## IPGW` = `1B 23 23 49 50 47 57` + 4 (gw), and `ESC ## DHCP` = `1B 23 23 44 48 43 50 n` (n=1 on, 0 off). It does not say which models those apply to.
- There is no DHCP on/off inside the 91-family per-field commands. DHCP is only carried in `setNetAll` (`…FA <dhcp> 5A…`).

TCP commands need the POS to reach the printer's current IP. They therefore do **not** solve the cross-subnet case by themselves. Use UDP SAVE, or temporarily add an IP alias on the PC (see §6). Reboot after a TCP set: unknown. Most units apply it after a power cycle **[UNVERIFIED]**.

---

## 2. Rongta (RP80, RP326, ACE and others)

### 2a. UDP discovery (`IpScanner.run`) [SRC]
- Socket: `new DatagramSocket()` (ephemeral local port), `setBroadcast(true)`, `setSoTimeout(1500)`.
- Request: ASCII `MP4200FIND` = `4D 50 34 32 30 30 46 49 4E 44`, sent to **255.255.255.255:1460**.
- Reads up to 30 replies on the same socket, so the printer replies to the source port.
- Accept a reply when `data[0..10] == "MP4200FOUND"`. The device IP is taken from the **UDP source address** (`packet.getAddress()`), and the port is hard-set to 9100.
- Parse: MAC = `data[11..16]` (formatted `%02X-…`). DHCP = `data[33] != 0`. The SDK reads no IP/mask/gw from the payload. By analogy with Xprinter they are probably at 19/23/27 **[UNVERIFIED]**.

### 2b. UDP set IP (`IpUpdata.b()`) [SRC]
- Sent to **255.255.255.255:1460** with broadcast enabled. The SDK then does one `receive()` (1500 ms timeout) and only logs the reply length, so the ACK format is unknown.
- Payload (33 bytes):

| Offset | Len | Bytes |
|---|---|---|
| 0 | 10 | `MP4200SAVE` = `4D 50 34 32 30 30 53 41 56 45` |
| 10 | 6 | target MAC (parsed from hex strings) |
| 16 | 2 | `0F 00` (constant) |
| 18 | 4 | IP |
| 22 | 4 | mask |
| 26 | 4 | gateway |
| 30 | 2 | `05 B4` (= 1460, big-endian, from field `f=1460`) |
| 32 | 1 | `00` (constant; DHCP is likely always off) |

- Note that bytes 16–17 and 30–31 differ from Xprinter's (`22 00` and `8C 17`). The semantics are unknown, so copy each vendor's constants exactly.

### 2c. Rongta ESC-style net commands, sent over an open connection (`com.rt.printerlibrary.cmd.SettingsCmd`) [SRC]
These are used in the SDK sample `WifiIpDhcpSettingActivity` (https://github.com/shic/printer-rongta). The sample sends `setDhcp(false)`, then `setStaticIp(...)`.
- DHCP: `1F 62 44 n` (n=01 enable, 00 disable).
- Static IP (20 bytes): `1F 69 <IP4> 1F 25 00 <MASK4> 1F 25 01 <GW4>`.
- Model applicability (WiFi only, or Ethernet too): unknown.

---

## 3. Epson (TM-T82, TM-T88, TM-m30; UB-E04 and similar)

### 3a. ENPC: UDP 3289
- Vendor statement (UB-E04 Technical Reference, https://files.support.epson.com/pdf/ube04_/ube04_trg.pdf) **[VENDOR]**: "ENPC: The network configuration tool (EpsonNet Config) and the dedicated driver software (such as OPOS/APD) use this to acquire and set the TM printer status. Protocol UDP/IP, UDP port number 3289, Compatible packet types Probe, Initialize, Query, Setup, Notify."
- Also vendor: "If the printer is still set to factory defaults, the printer's MAC address is listed up, even if the computer does not have the same network address." EpsonNet Config therefore discovers across subnets, but only for factory-default units. Factory default IP: **192.168.192.168**. Admin password: user "epson", password empty by default.
- Header layout. Wireshark Lua dissector https://github.com/BlackLotus/epson-stuff/blob/master/enpc.lua **[SRC, RE-derived]**:

| Offset | Len | Field |
|---|---|---|
| 0 | 5 | `EPSON` |
| 5 | 1 | type: `Q` query, `C` command, `S` "something" (lowercase = reply). `P` (probe) is used by SANE and EpsonNet |
| 6 | 1 | device type |
| 7 | 1 | device number |
| 8 | 2 | function (BE). Values: 0x0000 basic info, 0x0010 status, 0x0011 forced tx, 0x0012 reset, 0x0013 buffer flash, 0x0016 clear timeout |
| 10 | 2 | request: 0x0000. Reply: result (0 OK, 0xFFFE no device, 0xFFFF unsupported) |
| 12 | 2 | parameter/reply length (BE) |
| 14 | n | data |

- Discovery probes seen in source:
  - SANE epson2 backend (https://gitlab.com/sane-project/backends/-/raw/master/backend/epson2.c, `e2_network_discovery`) **[SRC]**: `"EPSONP\x00\xff\x00\x00\x00\x00\x00\x00\x00"`, 15 bytes broadcast to UDP 3289. The comment there reads "minimal check, protocol unknown". It only checks that the reply starts with `EPSON`, and it takes the IP from the UDP source.
  - escpos-php issue https://github.com/mike42/escpos-php/issues/923 **[FORUM]**: EpsonNET probe `45 50 53 4F 4E 50 00 FF 00 00 00 00 00 00` (14 bytes) and Epson SDK broadcast `45 50 53 4F 4E 51 03 00 00 00 10 00 00 00 00 00`. A TM-T88V reply begins `45 50 53 4f 4e 71 03 00 00 00 00 00 00 85 00 05 20 02 64 54 4d 2d 54 38 38 56…` (model "TM-T88V" at offset 0x13).
  - Epson ePOS SDK, per https://wes4m.io/posts/epson_rev/ **[RE]**: query `45 50 53 4f 4e 51 03 00 00 00 00 00 00 00` (EPSONQ, devtype 03, function 0000, length 0) gives the model-name reply (length 0x85, model ASCII at offset 0x13).
- **Network info reply** (wes4m capture, function `00 00 00 10` in the author's 4-byte view, i.e. devtype 00, devno 00, function 0x0010) **[RE]**:
  `45 50 53 4f 4e 71 00 00 00 10 00 00 00 17 01 02 00 00 00 00 00 00 04 c0 a8 01 09 ff ff ff 00 c0 a8 01 01 80 7c`
  Offsets: 14 `01`, **15–20 MAC**, 21–22 `00 04`, **23–26 IP**, **27–30 mask**, **31–34 gateway**, 35–36 `80 7c`. The author's spoofer builds it as `01 <mac6> 00 04 <ip> <mask> <gw> 80 7c`. The matching request was not printed verbatim. It is presumably `45 50 53 4F 4E 51 00 00 00 10 00 00 00 00` **[UNVERIFIED]**.
- **Setting the IP via ENPC ("Setup" packet type): no public byte layout found.** The format is unknown. EpsonNet Config does it, possibly with the admin password.

### 3b. ARP + ping IP assignment (Epson-documented, works with a different subnet on the same L2) [VENDOR]
From the UB-E04 TRG, "Set up using arp/ping commands". It requires "arp+ping IP setting" = Enable, which is the factory default.
```
arp -d 192.168.0.10
arp -s 192.168.0.10 00-26-AB-7B-00-00     (printer MAC from status sheet / ENPC reply)
ping 192.168.0.10
```
"When a message like 'Reply From 192.168.0.10…' is displayed, the IP address setting is complete." Only the IP is set this way. Mask and gateway must be set with EpsonNet Config or the web UI. On Windows 10/11, `arp -s` needs admin rights. The C# equivalent is `netsh interface ipv4 add neighbors "<if>" <ip> <mac>`, then ping, then `delete neighbors`.

### 3c. ESC/POS command to set the Epson IP
None found in any public source.

---

## 4. Gprinter, HPRT, Zywell

- **Gprinter**: I disassembled the Android SDK v2.1 jar (https://github.com/zabio/gainscha, `GprinterSDKV2.1/Sample Code/gprinter-2.1.jar`). It has no UDP and no set-IP code, only TCP `EthernetPort`. The factory default IP 192.168.123.100 and the Windows "GPETHERNET" tool are documented only in blogs (e.g. https://blog.csdn.net/syjszn/article/details/128065990), with no protocol. **Gprinter protocol: unknown.** Whether its modules answer `XP0001FIND` or `MP4200FIND` is **[UNVERIFIED]**. Test with both.
- **HPRT**: Android ESC SDK v0.1.5 (https://github.com/krushkamx/nativescript-hprt, `src/platforms/android/Android_SDK_ESC_V0.1.5.jar`, `HPRTPrinterHelper`) **[SRC]**:
  - `ReadIP`: write `12 43 45 52` (DC2 'C' 'E' 'R'), then read 2 bytes. The return parsing is degenerate, so the reply format is unknown.
  - `setIP(byte[13])`: after ReadIP, write `12 43 45 57` (DC2 'C' 'E' 'W'), then write a caller-supplied **13-byte** block. The layout of those 13 bytes is unknown (plausibly IP+mask+gw+1, **[UNVERIFIED]**).
  - This is an old mobile-printer SDK. Applicability to TP805 or TP808 is unknown. No UDP discovery was found.
- **Zywell**: the `PosPrinterSDK.jar` from the Zywell RN wrapper is the old `net.posprinter` SDK (the same package as Xprinter). Its `PosSetting` has the Family-A `1F 1B 1F 22/B0/B1/B2/B3/B4` commands (§1c) **[SRC]**. It has no UDP discovery. Zywell's "NETtool" (zywell.com/download) protocol is unknown.

## 5. WIZnet-style generic search
WIZnet S2E modules use UDP-broadcast config tools (FIND/SETT on older WIZ1xxSR; port 50001 on WIZ750SR, per docs.wiznet.io). I could not get a source showing WIZnet itself on port 1460 with FIND/IMIN. The source-verified 1460 protocol in this report is **Rongta's `MP4200FIND`**. Any WIZnet tie-in is **[UNVERIFIED]**.

## 6. Implementation notes for the cross-subnet case [UNVERIFIED engineering advice]
- Send to **255.255.255.255** (limited broadcast), not to a directed broadcast like 192.168.1.255. An off-subnet printer's IP stack drops directed broadcasts for a foreign network. On a multi-NIC Windows PC, bind one socket per local interface IP, because a limited broadcast leaves via only one interface otherwise.
- Xprinter: bind local UDP **9000**, since the SDK does and the reply may come back to port 9000 or as a broadcast. Rongta: the reply goes to the ephemeral source port. Receive on the same socket.
- An off-subnet printer can't normally unicast back to you unless it ARPs on-link or routes via its gateway. A reply may never arrive even though the printer processed SAVE. Re-run FIND, or try printing to the new IP.
- On Android, acquire `WifiManager.MulticastLock` so broadcast receive isn't filtered on some devices.
- Fallback for any brand (Windows tool, needs admin): temporarily add a secondary IP on the NIC in the printer's subnet, e.g. `netsh interface ipv4 add address "<if>" 192.168.123.250 255.255.255.0`. Then use TCP 9100 commands or the printer's web UI, and remove the IP afterwards. The vendor/blog tutorials do the same thing with a direct cable and a manual IP.

## 7. Summary table

| Brand | Discover across subnet? | Change IP over network? | Via |
|---|---|---|---|
| Xprinter | **Yes** [SRC]: UDP `XP0001FIND` to 255.255.255.255:9000 | **Yes** [SRC]: UDP `XP0001SAVE`+MAC (static/DHCP). Also TCP 9100 `1F1B1F 22/B0/B1/B2` or `1F1B1F 91 00 49 FA` (same subnet only) | UDP 9000; TCP 9100 |
| Rongta | **Yes** [SRC]: UDP `MP4200FIND` to 255.255.255.255:1460 | **Yes** [SRC]: UDP `MP4200SAVE`+MAC (static). Also `1F 69…`/`1F 62 44 n` over a connection | UDP 1460 |
| Zywell | Unknown (try both UDP tags) | TCP/USB `1F1B1F 22/B0/B1/B2/B4` [SRC, SDK jar of unconfirmed provenance] | TCP 9100 |
| Gprinter | Unknown (try both UDP tags; vendor GPETHERNET tool, protocol unpublished) | Unknown | — |
| HPRT | Unknown | Possibly `12 43 45 57`+13 bytes over a connection [SRC, old mobile SDK, layout unknown] | TCP / BT |
| Epson | **Yes** [VENDOR+SRC]: ENPC UDP 3289 broadcast `EPSONP…`/`EPSONQ…`. Off-subnet listing is vendor-documented for factory-default units | **IP only**, via ARP+ping [VENDOR]. ENPC Setup format unpublished. Mask/gw need EpsonNet Config or the web UI | UDP 3289; ARP+ICMP |
| Generic OEM boards (ATOM/M5Stack doc) | — | `1F 1B 1F 91 00 49 50/51/52` + 4 bytes, `1B 23 23 "IPAD"/"IPMK"/"IPGW"/"DHCP"` [VENDOR-OEM] | TCP/serial |

### Sources
- Xprinter SDK 3.x jar: https://github.com/KickNext/pos_printers (android/libs/classes.jar; ExtendPosUdpNet.kt, network/UdpNetworkManager.kt); PR: https://github.com/KickNext/pos_printers/pull/2
- Rongta SDK jar: https://github.com/warrence/rongta-capacitor-thermal-printer (android/libs/printer_library.jar); sample: https://github.com/shic/printer-rongta (RongtaPrinterExample/.../WifiIpDhcpSettingActivity.java)
- Zywell/PosPrinterSDK jar: https://github.com/lehoi2195/react-native-zywell-thermal-printer (android/libs/PosPrinterSDK.jar)
- HPRT jar: https://github.com/krushkamx/nativescript-hprt (src/platforms/android/Android_SDK_ESC_V0.1.5.jar)
- Gprinter jar: https://github.com/zabio/gainscha
- Xprinter captures: https://blog.lambda.cx/posts/xprinter-wifi/ ; https://github.com/dantecatalfamo/xprinter-wifi
- OEM command manual: https://m5stack.oss-cn-shenzhen.aliyuncs.com/resource/docs/datasheet/atombase/atom_pritner/ATOM_PRINTER_CMD_v1.06.pdf
- Epson UB-E04 TRG: https://files.support.epson.com/pdf/ube04_/ube04_trg.pdf
- ENPC dissector: https://github.com/BlackLotus/epson-stuff (enpc.lua, epson.py)
- SANE epson2: https://gitlab.com/sane-project/backends/-/raw/master/backend/epson2.c
- ENPC captures: https://wes4m.io/posts/epson_rev/ ; https://github.com/mike42/escpos-php/issues/923
