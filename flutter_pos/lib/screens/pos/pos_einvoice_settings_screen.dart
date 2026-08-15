import 'package:flutter/material.dart';

import '../../models/pos_einvoice.dart';
import '../../services/api_service.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Cấu hình hóa đơn điện tử — Viettel SInvoice và Easy Invoice.
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
  bool _hasPassword = false;
  bool _obscurePass = true;

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
    ).toSaveJson(
      password: _passCtrl.text.trim().isEmpty ? null : _passCtrl.text.trim(),
    );
    final res = await _api.savePosEInvoiceSettings(body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      _passCtrl.clear();
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
    setState(() => _testing = true);
    final res = await _api.testPosEInvoiceConnection();
    if (!mounted) return;
    setState(() => _testing = false);
    final ok = res['isSuccess'] == true;
    final msg = res['data'] is Map
        ? (res['data']['message'] ?? res['message'])?.toString()
        : res['message']?.toString();
    if (ok) {
      NotificationOverlayManager().showSuccess(
        title: 'Kết nối OK',
        message: tr(msg ?? 'Kết nối nhà cung cấp HĐĐT thành công'),
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'Kết nối thất bại',
        message: msg ?? 'Không kết nối được nhà cung cấp HĐĐT',
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
    return 'Viettel';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final viettel = _provider == 'Viettel';
    final easy = _provider == 'Easy';
    final canTest = viettel || easy;
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
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
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _provider,
            decoration: _dec('Nhà cung cấp'),
            items: [
              DropdownMenuItem(value: 'Viettel', child: Text(tr('Viettel SInvoice'))),
              DropdownMenuItem(value: 'Easy', child: Text(tr('Easy Invoice'))),
              DropdownMenuItem(
                  value: 'Misa', child: Text(tr('MISA Invoice (sắp có)'))),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _provider = v;
                final url = _urlCtrl.text.trim();
                if (v == 'Easy' &&
                    (url.isEmpty || url.contains('viettel'))) {
                  _urlCtrl.text = 'https://api.easyinvoice.vn';
                } else if (v == 'Viettel' &&
                    (url.isEmpty ||
                        url.contains('easyinvoice') ||
                        url.contains('softdreams'))) {
                  _urlCtrl.text = 'https://api-vinvoice.viettel.vn';
                }
              });
            },
          ),
          if (_provider == 'Misa') ...[
            const SizedBox(height: 12),
            Text(
              tr('MISA Invoice chưa hỗ trợ xuất. Chọn Viettel SInvoice hoặc Easy Invoice.'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
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
          const Divider(height: 28),
          Text(
              tr(easy
                  ? 'Tài khoản Easy Invoice'
                  : 'Tài khoản Viettel SInvoice'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _urlCtrl,
            decoration: _dec('API base URL',
                hint: easy
                    ? 'https://api.easyinvoice.vn'
                    : 'https://api-vinvoice.viettel.vn'),
          ),
          if (easy) ...[
            const SizedBox(height: 6),
            Text(
              tr('Demo: http://api.softdreams.vn — token kèm MST từ 01/01/2026.'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _userCtrl,
            decoration: _dec('Tài khoản API',
                hint: easy ? 'Username Easy Invoice' : 'MST-xxx'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: _obscurePass,
            decoration: _dec(
              _hasPassword ? 'Mật khẩu (để trống = giữ mật khẩu cũ)' : 'Mật khẩu',
            ).copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                    _obscurePass ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _taxCtrl,
            decoration: _dec('MST người bán', hint: '0100109106 hoặc 0100109106-001'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _templateCtrl,
            decoration: _dec(
                easy
                    ? 'Ký hiệu mẫu số (Serial)'
                    : 'Ký hiệu mẫu (templateCode)',
                hint: '1/001'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _seriesCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: _dec(
                easy
                    ? 'Ký hiệu hóa đơn (Pattern)'
                    : 'Ký hiệu hóa đơn (invoiceSeries)',
                hint: 'C24AAA'),
          ),
          if (viettel) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _invoiceType,
              decoration: _dec('Loại hóa đơn (TT78)'),
              items: [
                DropdownMenuItem(value: '1', child: Text(tr('1 — Hóa đơn GTGT'))),
                DropdownMenuItem(value: '2', child: Text(tr('2 — Hóa đơn bán hàng'))),
                DropdownMenuItem(value: '5', child: Text(tr('5 — HĐ khác'))),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _invoiceType = v);
              },
            ),
          ],
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
            onPressed: _testing || !canTest ? null : _test,
            icon: _testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering),
            label: Text(tr(easy
                ? 'Kiểm tra kết nối Easy Invoice'
                : 'Kiểm tra kết nối Viettel')),
          ),
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
