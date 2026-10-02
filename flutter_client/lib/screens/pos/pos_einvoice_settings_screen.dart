import 'package:flutter/material.dart';
import '../../utils/pos_sell_store_settings.dart';
import '../../widgets/sbox/sbox_ui.dart';
import '../../widgets/settings/settings_page.dart';

import '../../models/pos_einvoice.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
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
  /// Ảnh chụp lúc tải / lưu xong (null = chụp ở lần vẽ kế tiếp).
  String? _saved;
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
    for (final c in _ctrls) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
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
    _saved = null;
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

  /// Ảnh chụp các giá trị để biết có thay đổi chưa lưu.
  String get _snapshot => [
        _enabled, _provider, _invoiceType, _askAtCheckout, _defaultIssue, _taxMode, _taxPercent, _signType, _printQr,
        for (final c in _ctrls) c.text,
      ].join('|');

  List<TextEditingController> get _ctrls => [
        _userCtrl, _passCtrl, _taxCtrl, _templateCtrl, _seriesCtrl, _urlCtrl, _appIdCtrl, _svcAccountCtrl, _svcPassCtrl, _portalCtrl,
      ];

  /// Lấy cách tính thuế theo «Thông tin cửa hàng» để hóa đơn điện tử khớp hóa đơn bán hàng.
  Future<void> _syncTaxFromStore() async {
    final s = await PosSellStoreSettings.load();
    if (!mounted) return;
    setState(() {
      _taxMode = s.taxMode == PosSellTaxMode.includedInPrice ? 'included' : 'added';
      _taxPercent = s.defaultVatRate;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_saved == null && !_loading) _saved = _snapshot;
    final providerName = posEInvoiceProviderName(_provider);
    final dirty = !_loading && _saved != null && _snapshot != _saved;
    return SettingsPage(
      title: 'Hóa đơn điện tử',
      subtitle: 'Kết nối Viettel, Easy, MISA, VNPT — xuất hóa đơn khi bán hàng',
      icon: Icons.request_quote_outlined,
      loading: _loading,
      dirty: dirty,
      saving: _saving,
      onSave: _save,
      onDiscard: () {
        _saved = null;
        _load();
      },
      headerActions: [
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PosEInvoiceReportScreen())),
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: Text(tr('Quản lý hóa đơn')),
        ),
      ],
      children: [
        SettingsSection(
          title: 'Xuất hóa đơn điện tử',
          subtitle: 'Khi bật, thu ngân chọn xuất hoặc hệ thống tự xuất lúc thanh toán',
          icon: Icons.power_settings_new_rounded,
          trailing: Switch(value: _enabled, onChanged: (v) => setState(() => _enabled = v)),
          children: [
            SettingsTile(
              divider: false,
              label: 'Nhà cung cấp',
              control: DropdownButton<String>(
                value: _provider,
                items: [
                  for (final p in const ['Viettel', 'Easy', 'Misa', 'Vnpt'])
                    DropdownMenuItem(value: p, child: Text(tr(posEInvoiceProviderName(p)))),
                ],
                onChanged: (v) {
                  if (v != null) _onProviderChanged(v);
                },
              ),
            ),
            SettingsTile(
              label: 'Hỏi thu ngân lúc thanh toán',
              help: 'Hiện nút chọn xuất / không xuất hóa đơn',
              control: Switch(value: _askAtCheckout, onChanged: (v) => setState(() => _askAtCheckout = v)),
            ),
            SettingsTile(
              label: 'Mặc định xuất hóa đơn',
              help: _askAtCheckout ? 'Nút «Xuất HĐĐT» bật sẵn, thu ngân vẫn tắt được' : 'Tự xuất mọi đơn đã thanh toán, không hỏi',
              control: Switch(value: _defaultIssue, onChanged: (v) => setState(() => _defaultIssue = v)),
            ),
            SettingsTile(
              label: 'In mã tra cứu + QR trên hóa đơn bán hàng',
              help: 'Mẫu in tự đặt dùng biến {HDDT_So}, {HDDT_Ky_Hieu}, {HDDT_Ma_CQT}, {HDDT_Ma_Tra_Cuu}',
              control: Switch(value: _printQr, onChanged: (v) => setState(() => _printQr = v)),
            ),
          ],
        ),
        SettingsSection(
          title: 'Tài khoản $providerName',
          subtitle: 'Mật khẩu không hiện lại sau khi lưu — để trống là giữ mật khẩu cũ',
          icon: Icons.key_rounded,
          children: [
            const SizedBox(height: 8),
            ..._providerFields(),
            const SizedBox(height: 12),
            TextField(
              controller: _portalCtrl,
              keyboardType: TextInputType.url,
              decoration: _dec('Link trang quản lý của hãng (tùy chọn)', hint: 'Để trống = trang mặc định của $providerName'),
            ),
            const SizedBox(height: 12),
          ],
        ),
        SettingsSection(
          title: 'Thuế khi xuất hóa đơn',
          subtitle: 'Nên khớp cách tính VAT ở «Thông tin cửa hàng» để hóa đơn điện tử giống hóa đơn bán hàng',
          icon: Icons.percent_rounded,
          trailing: TextButton(onPressed: _syncTaxFromStore, child: Text(tr('Lấy theo cửa hàng'))),
          children: [
            SettingsTile(
              divider: false,
              label: 'Giá trên POS',
              control: DropdownButton<String>(
                value: _taxMode,
                items: [
                  DropdownMenuItem(value: 'included', child: Text(tr('Đã gồm VAT (tách thuế)'))),
                  DropdownMenuItem(value: 'added', child: Text(tr('Chưa VAT (cộng thuế)'))),
                  DropdownMenuItem(value: 'none', child: Text(tr('Không thuế / HĐ bán hàng'))),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _taxMode = v);
                },
              ),
            ),
            if (_taxMode != 'none')
              SettingsTile(
                label: 'Thuế suất mặc định',
                control: SettingsSegment<double>(
                  value: [0.0, 5.0, 8.0, 10.0].contains(_taxPercent) ? _taxPercent : 10.0,
                  options: const [(0.0, '0%'), (5.0, '5%'), (8.0, '8%'), (10.0, '10%')],
                  onChanged: (v) => setState(() => _taxPercent = v),
                ),
              ),
          ],
        ),
        SettingsSection(
          title: 'Kiểm tra kết nối',
          subtitle: 'Chỉ xác thực tài khoản, không tạo hóa đơn',
          icon: Icons.wifi_tethering_rounded,
          trailing: SboxButton.secondary(
            label: 'Kiểm tra',
            icon: Icons.play_arrow_rounded,
            loading: _testing,
            onPressed: _testing || dirty ? null : _test,
          ),
          children: [
            if (dirty) const SettingsNote('Lưu thay đổi trước khi kiểm tra.', icon: Icons.info_outline_rounded, tone: SboxTone.neutral),
            if (_testBanner != null)
              SettingsNote(_testBanner!,
                  icon: _testBannerOk ? Icons.check_circle_outline : Icons.error_outline,
                  tone: _testBannerOk ? SboxTone.success : SboxTone.danger),
          ],
        ),
      ],
    );
  }
}
