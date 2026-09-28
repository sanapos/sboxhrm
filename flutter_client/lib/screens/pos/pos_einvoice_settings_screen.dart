import 'package:flutter/material.dart';

import '../../models/pos_einvoice.dart';
import '../../services/api_service.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_einvoice_report_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
/// Cấu hình hóa đơn điện tử — Viettel SInvoice, Easy Invoice, MISA meInvoice, VNPT Invoice.
class PosEInvoiceSettingsScreen extends StatefulWidget {
  const PosEInvoiceSettingsScreen({super.key});

  @override
  State<PosEInvoiceSettingsScreen> createState() =>
      _PosEInvoiceSettingsScreenState();
}

class _PosEInvoiceSettingsScreenState extends State<PosEInvoiceSettingsScreen> {
  final _api = ApiService();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _templateCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _appIdCtrl = TextEditingController();
  final _svcAccountCtrl = TextEditingController();
  final _svcPassCtrl = TextEditingController();
  final _portalCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _enabled = false;
  String _provider = 'Viettel';
  String _invoiceType = '1';
  bool _askAtCheckout = true;
  bool _defaultIssue = false;
  String _taxMode = 'included';
  double _taxPercent = 10;
  int _signType = 2;
  bool _printQr = true;
  bool _hasPassword = false;
  bool _hasServicePassword = false;
  bool _obscurePass = true;
  /// Kết quả «Kiểm tra kết nối» — hiện ngay trên form (không chỉ toast).
  String? _testBanner;
  bool _testBannerOk = false;

  static const _defaultUrls = <String, String>{
    'Viettel': 'https://api-vinvoice.viettel.vn',
    'Easy': 'https://api.easyinvoice.vn',
    'Misa': 'https://api.meinvoice.vn/api/integration',
    'Vnpt': '',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _taxCtrl.dispose();
    _templateCtrl.dispose();
    _seriesCtrl.dispose();
    _urlCtrl.dispose();
    _appIdCtrl.dispose();
    _svcAccountCtrl.dispose();
    _svcPassCtrl.dispose();
    _portalCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosEInvoiceSettings();
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final s = PosEInvoiceSettings.fromJson(
          Map<String, dynamic>.from(res['data'] as Map));
      _enabled = s.enabled;
      _provider = _normalizeProvider(s.provider);
      _urlCtrl.text = s.apiBaseUrl;
      _userCtrl.text = s.username;
      _hasPassword = s.hasPassword;
      _taxCtrl.text = s.supplierTaxCode;
      _templateCtrl.text = s.templateCode;
      _seriesCtrl.text = s.invoiceSeries;
      _invoiceType = s.invoiceType.isEmpty ? '1' : s.invoiceType;
      _askAtCheckout = s.askAtCheckout;
      _defaultIssue = s.defaultIssueAtCheckout;
      _taxMode = s.taxMode;
      _taxPercent = s.defaultTaxPercent;
      _appIdCtrl.text = s.appId;
      _svcAccountCtrl.text = s.serviceAccount;
      _hasServicePassword = s.hasServicePassword;
      _signType = s.signType == 5 ? 5 : 2;
      _portalCtrl.text = s.portalUrl;
      _printQr = s.printQrOnReceipt;
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final body = PosEInvoiceSettings(
      enabled: _enabled,
      provider: _provider,
      apiBaseUrl: _urlCtrl.text.trim(),
      username: _userCtrl.text.trim(),
      hasPassword: _hasPassword,
      supplierTaxCode: _taxCtrl.text.trim(),
      templateCode: _templateCtrl.text.trim(),
      invoiceSeries: _seriesCtrl.text.trim(),
      invoiceType: _invoiceType,
      askAtCheckout: _askAtCheckout,
      defaultIssueAtCheckout: _defaultIssue,
      taxMode: _taxMode,
      defaultTaxPercent: _taxPercent,
      appId: _appIdCtrl.text.trim(),
      serviceAccount: _svcAccountCtrl.text.trim(),
      signType: _signType,
      portalUrl: _portalCtrl.text.trim(),
      printQrOnReceipt: _printQr,
    ).toSaveJson(
      password: _passCtrl.text.trim().isEmpty ? null : _passCtrl.text.trim(),
      servicePassword:
          _svcPassCtrl.text.trim().isEmpty ? null : _svcPassCtrl.text.trim(),
    );
    final res = await _api.savePosEInvoiceSettings(body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      _passCtrl.clear();
      _svcPassCtrl.clear();
      NotificationOverlayManager().showSuccess(
        title: 'Đã lưu',
        message: tr('Cấu hình hóa đơn điện tử đã cập nhật'),
      );
      await _load();
    } else {
      NotificationOverlayManager().showError(
        title: 'Không lưu được',
        message: res['message']?.toString() ?? 'Lỗi lưu cấu hình',
      );
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testBanner = null;
    });
    try {
      final res = await _api.testPosEInvoiceConnection();
      if (!mounted) return;
      final ok = res['isSuccess'] == true;
      String? msg;
      final data = res['data'];
      if (data is Map) {
        msg = (data['message'] ?? data['Message'])?.toString();
      }
      msg ??= res['message']?.toString();
      if (msg != null && msg.trim().isEmpty) msg = null;
      final text = ok
          ? (msg ?? 'Kết nối nhà cung cấp HĐĐT thành công')
          : (msg ?? 'Không kết nối được nhà cung cấp HĐĐT');
      setState(() {
        _testing = false;
        _testBannerOk = ok;
        _testBanner = text;
      });
      if (ok) {
        NotificationOverlayManager().showSuccess(
          title: 'Kết nối OK',
          message: tr(text),
          duration: const Duration(seconds: 5),
        );
      } else {
        NotificationOverlayManager().showError(
          title: 'Kết nối thất bại',
          message: tr(text),
          duration: const Duration(seconds: 6),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final text = e.toString();
      setState(() {
        _testing = false;
        _testBannerOk = false;
        _testBanner = text;
      });
      NotificationOverlayManager().showError(
        title: 'Kết nối thất bại',
        message: text,
        duration: const Duration(seconds: 6),
      );
    }
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: tr(label),
        hintText: hint == null ? null : tr(hint),
        border: const OutlineInputBorder(),
      );

  static String _normalizeProvider(String raw) {
    final p = raw.trim().toLowerCase();
    if (p.contains('easy')) return 'Easy';
    if (p.contains('misa')) return 'Misa';
    if (p.contains('vnpt')) return 'Vnpt';
    return 'Viettel';
  }

  void _onProviderChanged(String v) {
    setState(() {
      final oldDefault = _defaultUrls[_provider] ?? '';
      final url = _urlCtrl.text.trim();
      _provider = v;
      // Đổi hãng: thay URL nếu đang trống hoặc là URL mặc định của hãng cũ.
      if (url.isEmpty || url == oldDefault || _defaultUrls.values.contains(url)) {
        _urlCtrl.text = _defaultUrls[v] ?? '';
      }
      _testBanner = null;
    });
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          tr(text),
          style: TextStyle(fontSize: 12, color: SboxColors.slate700),
        ),
      );

  Widget _passwordField(
    TextEditingController ctrl,
    String label, {
    required bool hasExisting,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: _obscurePass,
      decoration: _dec(
        hasExisting ? '$label (để trống = giữ mật khẩu cũ)' : label,
      ).copyWith(
        suffixIcon: IconButton(
          icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _obscurePass = !_obscurePass),
        ),
      ),
    );
  }

  List<Widget> _providerFields() {
    switch (_provider) {
      case 'Easy':
        return [
          TextField(
            controller: _urlCtrl,
            decoration: _dec('API base URL', hint: 'https://api.easyinvoice.vn'),
          ),
          _hint('Demo: http://api.softdreams.vn — token kèm MST từ 01/01/2026.'),
          const SizedBox(height: 12),
          TextField(
            controller: _userCtrl,
            decoration: _dec('Tài khoản API', hint: 'Username Easy Invoice'),
          ),
          const SizedBox(height: 12),
          _passwordField(_passCtrl, 'Mật khẩu', hasExisting: _hasPassword),
          const SizedBox(height: 12),
          _taxField(),
          const SizedBox(height: 12),
          TextField(
            controller: _templateCtrl,
            decoration: _dec('Mẫu số SoftDreams (Pattern)',
                hint: '1C26MAA  (đúng như trên portal)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _seriesCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: _dec('Ký hiệu (Serial) — thường để trống',
                hint: 'Để trống nếu portal để trống cột Ký hiệu'),
          ),
          _hint('Trên portal Pattern = «1C26MAA» (HĐ máy tính tiền), cột Ký hiệu trống. '
              'Điền Pattern=1C26MAA, Serial để trống. «Kiểm tra kết nối» chỉ xác thực — không tạo HĐ.'),
        ];
      case 'Misa':
        return [
          TextField(
            controller: _urlCtrl,
            decoration: _dec('API base URL',
                hint: 'https://api.meinvoice.vn/api/integration'),
          ),
          _hint('Thử nghiệm: https://testapi.meinvoice.vn/api/integration'),
          const SizedBox(height: 12),
          TextField(
            controller: _appIdCtrl,
            decoration: _dec('AppID (MISA cấp khi đăng ký tích hợp)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _userCtrl,
            decoration: _dec('Tài khoản đăng nhập meInvoice',
                hint: 'Email / SĐT đăng nhập app.meinvoice.vn'),
          ),
          const SizedBox(height: 12),
          _passwordField(_passCtrl, 'Mật khẩu', hasExisting: _hasPassword),
          const SizedBox(height: 12),
          _taxField(),
          const SizedBox(height: 12),
          TextField(
            controller: _seriesCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: _dec('Ký hiệu hóa đơn (InvSeries)', hint: '1C25TAA'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: _signType,
            decoration: _dec('Hình thức phát hành'),
            items: [
              DropdownMenuItem(
                  value: 2, child: Text(tr('Ký số HSM (hóa đơn GTGT thường)'))),
              DropdownMenuItem(
                  value: 5,
                  child: Text(tr('Hóa đơn khởi tạo từ máy tính tiền (không ký)'))),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _signType = v);
            },
          ),
          _hint('Ký hiệu đầy đủ như trên meInvoice, vd. 1C25TAA (HĐ có mã) hoặc 1C25MAA (máy tính tiền). '
              'Chọn «máy tính tiền» khi ký hiệu có chữ M ở vị trí thứ 5.'),
        ];
      case 'Vnpt':
        return [
          TextField(
            controller: _urlCtrl,
            decoration: _dec('Địa chỉ web service VNPT',
                hint: 'https://<MST>-tt78admin.vnpt-invoice.com.vn'),
          ),
          _hint('Mỗi doanh nghiệp có domain riêng do VNPT cấp (bản thử: …-tt78admindemo…).'),
          const SizedBox(height: 12),
          TextField(
            controller: _svcAccountCtrl,
            decoration: _dec('Account web service', hint: 'vd. 0101234567service'),
          ),
          const SizedBox(height: 12),
          _passwordField(_svcPassCtrl, 'ACpass web service',
              hasExisting: _hasServicePassword),
          const SizedBox(height: 12),
          TextField(
            controller: _userCtrl,
            decoration: _dec('Tài khoản phát hành (username)',
                hint: 'vd. 0101234567admin'),
          ),
          const SizedBox(height: 12),
          _passwordField(_passCtrl, 'Mật khẩu phát hành', hasExisting: _hasPassword),
          const SizedBox(height: 12),
          _taxField(),
          const SizedBox(height: 12),
          TextField(
            controller: _templateCtrl,
            decoration: _dec('Mẫu số (pattern)', hint: '1/001'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _seriesCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: _dec('Ký hiệu (serial)', hint: 'C25TAA'),
          ),
        ];
      default:
        return [
          TextField(
            controller: _urlCtrl,
            decoration:
                _dec('API base URL', hint: 'https://api-vinvoice.viettel.vn'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _userCtrl,
            decoration: _dec('Tài khoản API', hint: 'MST-xxx'),
          ),
          const SizedBox(height: 12),
          _passwordField(_passCtrl, 'Mật khẩu', hasExisting: _hasPassword),
          const SizedBox(height: 12),
          _taxField(),
          const SizedBox(height: 12),
          TextField(
            controller: _templateCtrl,
            decoration: _dec('Ký hiệu mẫu (templateCode)', hint: '1/001'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _seriesCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: _dec('Ký hiệu hóa đơn (invoiceSeries)', hint: 'C24AAA'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _invoiceType,
            decoration: _dec('Loại hóa đơn (TT78)'),
            items: [
              DropdownMenuItem(value: '1', child: Text(tr('1 — Hóa đơn GTGT'))),
              DropdownMenuItem(
                  value: '2', child: Text(tr('2 — Hóa đơn bán hàng'))),
              DropdownMenuItem(value: '5', child: Text(tr('5 — HĐ khác'))),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _invoiceType = v);
            },
          ),
        ];
    }
  }

  Widget _taxField() => TextField(
        controller: _taxCtrl,
        decoration:
            _dec('MST người bán', hint: '0100109106 hoặc 0100109106-001'),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      const spinner = Center(child: CircularProgressIndicator());
      if (HrmPageChrome.hideOuterChrome(context)) return spinner;
      return Scaffold(
        backgroundColor: HrmPageChrome.background,
        appBar: HrmPageChrome.appBar(
          context: context,
          title: 'Hóa đơn điện tử',
        ),
        body: spinner,
      );
    }
    final providerName = posEInvoiceProviderName(_provider);
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: HrmPageChrome.appBar(
        context: context,
        title: 'Hóa đơn điện tử',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Bật xuất hóa đơn điện tử'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tr(
                'Khi thanh toán có thể chọn xuất HĐĐT. Đơn hàng hiện trạng thái xuất.')),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(tr('Quản lý hóa đơn điện tử')),
            subtitle: Text(tr(
                'Xem lại, gửi email, thay thế, hủy, đồng bộ, tải danh sách từ hãng, báo cáo')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PosEInvoiceReportScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _provider,
            decoration: _dec('Nhà cung cấp'),
            items: [
              for (final p in const ['Viettel', 'Easy', 'Misa', 'Vnpt'])
                DropdownMenuItem(
                    value: p, child: Text(tr(posEInvoiceProviderName(p)))),
            ],
            onChanged: (v) {
              if (v != null) _onProviderChanged(v);
            },
          ),
          const SizedBox(height: 16),
          Text(tr('Khi thanh toán'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Hiện nút chọn xuất / không xuất lúc thanh toán')),
            value: _askAtCheckout,
            onChanged: (v) => setState(() => _askAtCheckout = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Mặc định xuất hóa đơn')),
            subtitle: Text(tr(_askAtCheckout
                ? 'Chip «Xuất HĐĐT» bật sẵn. Thu ngân vẫn tắt được.'
                : 'Xuất tự động mọi đơn đã thanh toán, không hỏi thu ngân.')),
            value: _defaultIssue,
            onChanged: (v) => setState(() => _defaultIssue = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('In mã HĐĐT + QR tra cứu trên hóa đơn bán hàng')),
            subtitle: Text(tr(
                'Bill in sau khi xuất HĐĐT có thêm: ký hiệu, số hóa đơn, mã CQT, '
                'mã tra cứu và mã QR để khách quét tra cứu. '
                'Mẫu in tự đặt có thể dùng biến {HDDT_So}, {HDDT_Ky_Hieu}, {HDDT_Ma_CQT}, {HDDT_Ma_Tra_Cuu}.')),
            value: _printQr,
            onChanged: (v) => setState(() => _printQr = v),
          ),
          const Divider(height: 28),
          Text(tr('Tài khoản $providerName'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ..._providerFields(),
          const SizedBox(height: 12),
          TextField(
            controller: _portalCtrl,
            keyboardType: TextInputType.url,
            decoration: _dec('Link trang quản lý HĐĐT của hãng (tùy chọn)',
                hint: 'Để trống = trang mặc định của $providerName'),
          ),
          const SizedBox(height: 16),
          Text(tr('Thuế suất khi xuất HĐĐT'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _taxMode,
            decoration: _dec('Cách tính giá trên POS'),
            items: [
              DropdownMenuItem(
                  value: 'included',
                  child: Text(tr('Giá đã gồm VAT (tách thuế khi xuất)'))),
              DropdownMenuItem(
                  value: 'added',
                  child: Text(tr('Giá chưa VAT (cộng VAT trên đơn)'))),
              DropdownMenuItem(
                  value: 'none', child: Text(tr('Không thuế / HĐ bán hàng (-2)'))),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _taxMode = v);
            },
          ),
          if (_taxMode != 'none') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<double>(
              value: _taxPercent,
              decoration: _dec('Thuế suất mặc định (%)'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('0%')),
                DropdownMenuItem(value: 5, child: Text('5%')),
                DropdownMenuItem(value: 8, child: Text('8%')),
                DropdownMenuItem(value: 10, child: Text('10%')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _taxPercent = v);
              },
            ),
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _testing ? null : _test,
            icon: _testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering),
            label: Text(tr('Kiểm tra kết nối $providerName')),
          ),
          _hint('Lưu cấu hình trước khi kiểm tra kết nối.'),
          if (_testBanner != null) ...[
            const SizedBox(height: 12),
            Material(
              color: _testBannerOk
                  ? SboxColors.successSoft
                  : SboxColors.dangerSoft,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _testBannerOk
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      color: _testBannerOk
                          ? SboxColors.success
                          : SboxColors.danger,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tr(_testBanner!),
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: _testBannerOk
                              ? SboxColors.successText
                              : SboxColors.dangerText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: PosTheme.kiotBlue,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(tr('Lưu cấu hình')),
          ),
        ],
      ),
    );
  }
}
