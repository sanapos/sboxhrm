import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/vn_admin_address_fields.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Cấu hình API GHN / GHTK / Viettel Post / AhaMove theo cửa hàng.
class PosShippingSettingsScreen extends StatefulWidget {
  const PosShippingSettingsScreen({super.key});

  @override
  State<PosShippingSettingsScreen> createState() =>
      _PosShippingSettingsScreenState();
}

class _PosShippingSettingsScreenState extends State<PosShippingSettingsScreen> {
  final _api = ApiService();
  bool _loading = true;
  bool _saving = false;
  String? _busyCode;
  List<_CarrierForm> _forms = [];
  final Map<String, bool> _reveal = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosShippingSettings();
    if (!mounted) return;
    final list = <_CarrierForm>[];
    if (res['isSuccess'] == true && res['data'] is List) {
      for (final e in res['data'] as List) {
        if (e is Map) {
          list.add(_CarrierForm.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    } else if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Không tải được cấu hình',
        message: '${res['message'] ?? res}',
      );
    }
    if (list.isEmpty) {
      for (final c in const ['Ghn', 'Ghtk', 'ViettelPost', 'Ahamove']) {
        list.add(_CarrierForm(code: c, displayName: _displayName(c)));
      }
    }
    setState(() {
      _forms = list;
      _loading = false;
    });
  }

  static String _displayName(String code) {
    switch (code) {
      case 'Ghn':
        return 'GHN';
      case 'Ghtk':
        return 'GHTK';
      case 'ViettelPost':
        return 'Viettel Post';
      case 'Ahamove':
        return 'AhaMove';
      default:
        return code;
    }
  }

  void _toast({
    required String title,
    required String message,
    required bool success,
  }) {
    if (success) {
      NotificationOverlayManager().showSuccess(
        title: title,
        message: message,
        duration: const Duration(seconds: 5),
      );
    } else {
      NotificationOverlayManager().showError(
        title: title,
        message: message,
        duration: const Duration(seconds: 5),
      );
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text('$title — $message'),
        backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<bool> _save(_CarrierForm f, {bool silent = false}) async {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    if (!perm.canEditPosSetup() && !perm.canEdit('PosSell')) {
      if (!silent) {
        NotificationOverlayManager().showWarning(
          title: 'Không có quyền sửa',
          message: tr('Cần quyền Sửa thiết lập POS hoặc Sửa bán hàng'),
        );
      }
      return false;
    }
    setState(() {
      _saving = true;
      _busyCode = f.code;
    });
    final body = <String, dynamic>{
      'carrierCode': f.code,
      'enabled': f.enabled,
      'useSandbox': f.useSandbox,
      'pickupName': f.pickupNameCtrl.text.trim(),
      'pickupPhone': f.pickupPhoneCtrl.text.trim(),
      'pickupAddress': f.pickupAddressCtrl.text.trim(),
      'fromProvinceName': f.fromProvinceCtrl.text.trim(),
      'fromDistrictName': f.fromDistrictCtrl.text.trim().isEmpty
          ? f.fromWardCtrl.text.trim()
          : f.fromDistrictCtrl.text.trim(),
      'fromWardName': f.fromWardCtrl.text.trim(),
    };
    if (f.shopIdCtrl.text.trim().isNotEmpty) {
      body['shopId'] = f.shopIdCtrl.text.trim();
    }
    if (f.fromDistrictIdCtrl.text.trim().isNotEmpty) {
      body['fromDistrictId'] = f.fromDistrictIdCtrl.text.trim();
    }
    if (f.fromWardCodeCtrl.text.trim().isNotEmpty) {
      body['fromWardCode'] = f.fromWardCodeCtrl.text.trim();
    }
    if (f.extraJsonCtrl.text.trim().isNotEmpty) {
      body['extraJson'] = f.extraJsonCtrl.text.trim();
    }
    if (f.code == 'ViettelPost') {
      if (f.usernameCtrl.text.trim().isNotEmpty) {
        body['username'] = f.usernameCtrl.text.trim();
      }
      if (f.passwordCtrl.text.trim().isNotEmpty) {
        body['password'] = f.passwordCtrl.text.trim();
      }
    }
    if (f.tokenCtrl.text.trim().isNotEmpty) {
      body['apiToken'] = f.tokenCtrl.text.trim();
    }
    final res = await _api.putPosShippingSettings(body);
    if (!mounted) return false;
    setState(() {
      _saving = false;
      _busyCode = null;
    });
    if (res['isSuccess'] == true) {
      if (f.tokenCtrl.text.trim().isNotEmpty) f.hasToken = true;
      if (f.passwordCtrl.text.trim().isNotEmpty) f.hasPassword = true;
      if (res['data'] is Map) {
        final saved =
            _CarrierForm.fromJson(Map<String, dynamic>.from(res['data'] as Map));
        f.enabled = saved.enabled;
        f.useSandbox = saved.useSandbox;
        f.hasToken = saved.hasToken;
        f.hasPassword = saved.hasPassword;
        f.apiTokenHint = saved.apiTokenHint;
        f.apiTokenKind = saved.apiTokenKind;
        f.passwordCtrl.clear();
        f.tokenCtrl.clear();
        final notice = saved.notice;
        if (!silent && notice != null && notice.trim().isNotEmpty) {
          final jwtOk = saved.apiTokenKind == 'Jwt';
          _toast(
            title: jwtOk ? 'Đã lưu · JWT OK' : 'Đã lưu · cần kiểm tra',
            message: notice,
            success: jwtOk,
          );
          setState(() {});
          return true;
        }
      }
      if (!silent) {
        _toast(
          title: 'Đã lưu',
          message: '${f.displayName}${f.useSandbox ? " · Sandbox BẬT" : " · Production"}',
          success: true,
        );
      }
      setState(() {});
      return true;
    }
    if (!silent) {
      _toast(
        title: 'Không lưu được',
        message: '${res['message'] ?? res}',
        success: false,
      );
    }
    return false;
  }

  Future<void> _test(_CarrierForm f) async {
    if (f.enabled) {
      final ok = await _save(f, silent: true);
      if (!ok) return;
    }
    setState(() {
      _saving = true;
      _busyCode = f.code;
    });
    final res = await _api.quotePosShipping({
      'carrierCode': f.code,
      'toName': 'Khách test',
      'toPhone': '0900000000',
      'toAddress': '01 Lê Duẩn, Hải Châu, Đà Nẵng',
      'toProvince': 'Thành phố Đà Nẵng',
      'toDistrict': 'Hải Châu',
      'toWard': 'Phường Hải Châu',
      'weightGrams': 500,
      'codAmount': 0,
      'insuranceValue': 100000,
    });
    if (!mounted) return;
    setState(() {
      _saving = false;
      _busyCode = null;
    });
    final data = res['data'];
    final ok = res['isSuccess'] == true &&
        data is Map &&
        (data['success'] == true || data['Success'] == true);
    if (ok) {
      final fee = data['fee'] ?? data['Fee'] ?? 0;
      NotificationOverlayManager().showSuccess(
        title: 'Kết nối OK',
        message: 'Ước tính phí: $fee đ',
      );
    } else {
      final msg = data is Map
          ? (data['message'] ?? data['Message'] ?? res['message'])
          : res['message'];
      NotificationOverlayManager().showError(
        title: 'Kết nối thất bại',
        message: '${msg ?? res}',
      );
    }
  }

  bool get _canEdit =>
      context.watch<PermissionProvider>().canEditPosSetup() ||
      context.watch<PermissionProvider>().canEdit('PosSell');

  @override
  Widget build(BuildContext context) {
    final canEdit = _canEdit;
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      // Hub / MainLayout đã có tiêu đề — tránh AppBar trùng «Đơn vị giao hàng».
      appBar: HrmPageChrome.appBar(
        title: 'Đơn vị giao hàng',
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            color: HrmPageChrome.textDark,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
              children: [
                if (!canEdit)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      tr('Chỉ xem — không có quyền sửa.'),
                      style: TextStyle(
                          color: Colors.orange.shade900, fontSize: 12),
                    ),
                  ),
                Text(
                  tr(
                    'Bật hãng → dán API Token → địa chỉ lấy hàng đủ '
                    '(số nhà, phường, tỉnh) → Lưu. '
                    'GHN: thêm ShopId · GHTK: Partner code · AhaMove: tọa độ nếu cần.',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 10),
                for (final f in _forms) ...[
                  _carrierCard(f, canEdit),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  Widget _carrierCard(_CarrierForm f, bool canEdit) {
    final busy = _saving && _busyCode == f.code;
    final hasCreds = f.hasToken ||
        f.hasPassword ||
        (f.code == 'ViettelPost' && f.usernameCtrl.text.trim().isNotEmpty);
    final status = !f.enabled
        ? 'Tắt'
        : (hasCreds ? 'Đã cấu hình' : 'Chưa cấu hình');
    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: f.enabled,
          tilePadding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: Icon(
            Icons.local_shipping_outlined,
            color: f.enabled ? PosTheme.kiotBlue : Colors.grey,
          ),
          title: Text(
            f.displayName,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          subtitle: Text(
            status,
            style: TextStyle(
              fontSize: 12,
              color: f.enabled && hasCreds
                  ? Colors.green.shade700
                  : Colors.grey.shade600,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch.adaptive(
                value: f.enabled,
                onChanged: canEdit && !busy
                    ? (v) => setState(() => f.enabled = v)
                    : null,
              ),
              const Icon(Icons.expand_more),
            ],
          ),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(tr('Sandbox (môi trường test)'),
                  style: const TextStyle(fontSize: 13)),
              value: f.useSandbox,
              onChanged: canEdit && !busy
                  ? (v) => setState(() => f.useSandbox = v)
                  : null,
            ),
            _secretField(
              f.tokenCtrl,
              label: f.hasToken
                  ? 'API Token (để trống = giữ đã lưu)'
                  : 'API Token',
              enabled: canEdit && !busy,
              visibilityKey: 'tk_${f.code}',
            ),
            if (f.hasToken && (f.apiTokenHint ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.vpn_key_outlined,
                        size: 16, color: Colors.green.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Token đã lưu: ${f.apiTokenHint}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (f.code == 'ViettelPost' &&
                f.apiTokenKind == 'Partner' &&
                f.hasToken)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  tr(
                    'Token Partner (32 ký tự) chỉ tra cước — không tạo vận đơn được. '
                    'Nhập đúng Mật khẩu Viettel Post rồi Lưu (hệ thống lấy JWT), '
                    'hoặc dán Token JWT (eyJ...) từ partner.viettelpost.vn.',
                  ),
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
                ),
              ),
            if (f.code == 'Ghn')
              _field(f.shopIdCtrl, label: 'ShopId (GHN)', enabled: canEdit),
            if (f.code == 'Ghtk')
              _field(f.shopIdCtrl,
                  label: 'Partner code (GHTK)', enabled: canEdit),
            if (f.code == 'ViettelPost') ...[
              _field(f.usernameCtrl,
                  label: 'Tài khoản / SĐT Viettel Post', enabled: canEdit),
              _secretField(
                f.passwordCtrl,
                label: f.hasPassword
                    ? 'Mật khẩu (để trống = giữ đã lưu)'
                    : 'Mật khẩu Viettel Post',
                enabled: canEdit && !busy,
                visibilityKey: 'pwd_${f.code}',
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  tr(
                    'Tra cước: Token Partner 32 ký tự hoặc Username. '
                    'Tạo vận đơn: cần JWT (eyJ...) hoặc Username + Mật khẩu đúng → Lưu. '
                    'Tắt Sandbox nếu dùng partner.viettelpost.vn (production).',
                  ),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(tr('Điểm lấy hàng'),
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            _field(f.pickupNameCtrl, label: 'Tên người gửi', enabled: canEdit),
            _field(f.pickupPhoneCtrl, label: 'SĐT lấy hàng', enabled: canEdit),
            _field(f.pickupAddressCtrl,
                label: 'Địa chỉ (số nhà, đường)',
                maxLines: 2,
                enabled: canEdit),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: VnAdminAddressFields(
                provinceCtrl: f.fromProvinceCtrl,
                wardCtrl: f.fromWardCtrl,
                dense: true,
                enabled: canEdit && !busy,
                onChanged: () {
                  f.fromDistrictCtrl.text = f.fromWardCtrl.text;
                  setState(() {});
                },
              ),
            ),
            if (f.code == 'Ghn' || f.code == 'Ahamove') ...[
              const SizedBox(height: 2),
              Text(tr('Nâng cao (tuỳ chọn)'),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 6),
              if (f.code == 'Ghn') ...[
                _field(f.fromDistrictIdCtrl,
                    label: 'Mã quận GHN', enabled: canEdit),
                _field(f.fromWardCodeCtrl,
                    label: 'Mã phường GHN', enabled: canEdit),
              ],
              if (f.code == 'Ahamove')
                _field(
                  f.extraJsonCtrl,
                  label:
                      'Tọa độ: {"lat":16.06,"lng":108.15,"service_id":"SGN-BIKE"}',
                  maxLines: 2,
                  enabled: canEdit,
                ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (!canEdit || busy) ? null : () => _test(f),
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering, size: 18),
                    label: Text(tr('Thử kết nối')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (!canEdit || busy) ? null : () => _save(f),
                    style: FilledButton.styleFrom(
                        backgroundColor: PosTheme.kiotBlue),
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(tr('Lưu')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _secretField(
    TextEditingController ctrl, {
    required String label,
    required bool enabled,
    required String visibilityKey,
  }) {
    final show = _reveal[visibilityKey] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        enabled: enabled,
        obscureText: !show,
        decoration: InputDecoration(
          labelText: tr(label),
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: IconButton(
            tooltip: show ? tr('Ẩn') : tr('Hiện'),
            onPressed: () => setState(() => _reveal[visibilityKey] = !show),
            icon: Icon(show ? Icons.visibility_off : Icons.visibility),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl, {
    required String label,
    int maxLines = 1,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        enabled: enabled,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: tr(label),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

class _CarrierForm {
  _CarrierForm({
    required this.code,
    required this.displayName,
    this.enabled = false,
    this.useSandbox = false,
    this.hasToken = false,
    this.hasPassword = false,
    this.apiTokenHint,
    this.apiTokenKind,
    this.notice,
  });

  final String code;
  final String displayName;
  bool enabled;
  bool useSandbox;
  bool hasToken;
  bool hasPassword;
  String? apiTokenHint;
  String? apiTokenKind;
  String? notice;
  final tokenCtrl = TextEditingController();
  final usernameCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final shopIdCtrl = TextEditingController();
  final pickupNameCtrl = TextEditingController();
  final pickupPhoneCtrl = TextEditingController();
  final pickupAddressCtrl = TextEditingController();
  final fromProvinceCtrl = TextEditingController();
  final fromDistrictCtrl = TextEditingController();
  final fromWardCtrl = TextEditingController();
  final fromDistrictIdCtrl = TextEditingController();
  final fromWardCodeCtrl = TextEditingController();
  final extraJsonCtrl = TextEditingController();

  factory _CarrierForm.fromJson(Map<String, dynamic> j) {
    final code = (j['carrierCode'] ?? j['CarrierCode'] ?? '').toString();
    final f = _CarrierForm(
      code: code,
      displayName: (j['displayName'] ?? j['DisplayName'] ?? code).toString(),
      enabled: j['enabled'] == true || j['Enabled'] == true,
      useSandbox: j['useSandbox'] == true || j['UseSandbox'] == true,
      hasToken: j['hasApiToken'] == true || j['HasApiToken'] == true,
      hasPassword: j['hasPassword'] == true || j['HasPassword'] == true,
      apiTokenHint: (j['apiTokenHint'] ?? j['ApiTokenHint'])?.toString(),
      apiTokenKind: (j['apiTokenKind'] ?? j['ApiTokenKind'])?.toString(),
      notice: (j['notice'] ?? j['Notice'])?.toString(),
    );
    f.usernameCtrl.text = (j['username'] ?? j['Username'] ?? '').toString();
    f.shopIdCtrl.text = (j['shopId'] ?? j['ShopId'] ?? '').toString();
    f.pickupNameCtrl.text = (j['pickupName'] ?? j['PickupName'] ?? '').toString();
    f.pickupPhoneCtrl.text =
        (j['pickupPhone'] ?? j['PickupPhone'] ?? '').toString();
    f.pickupAddressCtrl.text =
        (j['pickupAddress'] ?? j['PickupAddress'] ?? '').toString();
    f.fromProvinceCtrl.text =
        (j['fromProvinceName'] ?? j['FromProvinceName'] ?? '').toString();
    f.fromDistrictCtrl.text =
        (j['fromDistrictName'] ?? j['FromDistrictName'] ?? '').toString();
    f.fromWardCtrl.text =
        (j['fromWardName'] ?? j['FromWardName'] ?? '').toString();
    f.fromDistrictIdCtrl.text =
        (j['fromDistrictId'] ?? j['FromDistrictId'] ?? '').toString();
    f.fromWardCodeCtrl.text =
        (j['fromWardCode'] ?? j['FromWardCode'] ?? '').toString();
    f.extraJsonCtrl.text = (j['extraJson'] ?? j['ExtraJson'] ?? '').toString();
    return f;
  }
}
