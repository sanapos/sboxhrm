import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../utils/pos_commercial_profile_local.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_commercial_company_fields.dart';
import '../../widgets/pos/pos_theme.dart';

/// Điền mặc định thông tin công ty shop in trên báo giá / hợp đồng A4.
class PosCommercialCompanyScreen extends StatefulWidget {
  const PosCommercialCompanyScreen({super.key});

  @override
  State<PosCommercialCompanyScreen> createState() =>
      _PosCommercialCompanyScreenState();
}

class _PosCommercialCompanyScreenState
    extends State<PosCommercialCompanyScreen> {
  final _api = ApiService();
  final _company = TextEditingController();
  final _tax = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _bankNo = TextEditingController();
  final _bankName = TextEditingController();
  final _bankHolder = TextEditingController();
  final _rep = TextEditingController();
  final _title = TextEditingController(text: 'Giám đốc');
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _company.dispose();
    _tax.dispose();
    _address.dispose();
    _phone.dispose();
    _email.dispose();
    _bankNo.dispose();
    _bankName.dispose();
    _bankHolder.dispose();
    _rep.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosCommercialProfile();
    final local = await loadLocalCommercialProfile();
    if (!mounted) return;
    setState(() => _loading = false);
    Map<String, dynamic> m = {};
    if (res['isSuccess'] == true && res['data'] is Map) {
      m = mergeCommercialProfile(
        Map<String, dynamic>.from(res['data'] as Map),
        local,
      );
    } else if (local.isNotEmpty) {
      m = local;
    }
    if (m.isEmpty) return;
    String t(String a, String b) => (m[a] ?? m[b] ?? '').toString();
    _company.text = t('companyName', 'CompanyName');
    _tax.text = t('taxCode', 'TaxCode');
    _address.text = t('address', 'Address');
    _phone.text = t('phone', 'Phone');
    _email.text = t('email', 'Email');
    _bankNo.text = t('bankAccountNumber', 'BankAccountNumber');
    _bankName.text = t('bankName', 'BankName');
    _bankHolder.text = t('bankAccountHolder', 'BankAccountHolder');
    _rep.text = t('legalRepresentative', 'LegalRepresentative');
    _title.text = t('legalTitle', 'LegalTitle');
    if (_title.text.trim().isEmpty) _title.text = 'Giám đốc';
    setState(() {});
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final body = <String, dynamic>{
      'clientSavedAt': DateTime.now().toUtc().toIso8601String(),
      'companyName': _company.text.trim(),
      'taxCode': _tax.text.trim(),
      'address': _address.text.trim(),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'bankAccountNumber': _bankNo.text.trim(),
      'bankName': _bankName.text.trim(),
      'bankAccountHolder': _bankHolder.text.trim(),
      'legalRepresentative': _rep.text.trim(),
      'legalTitle': _title.text.trim(),
    };
    await saveLocalCommercialProfile({
      ...await loadLocalCommercialProfile(),
      ...body,
    });
    final res = await _api.updatePosCommercialProfile(body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true && res['data'] is Map) {
      final saved = Map<String, dynamic>.from(res['data'] as Map);
      final local = await loadLocalCommercialProfile();
      saved['clientSavedAt'] =
          saved['updatedAt'] ?? saved['UpdatedAt'] ?? body['clientSavedAt'];
      await saveLocalCommercialProfile({...local, ...saved});
    }
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Không lưu được',
        message: res['message']?.toString() ?? tr('Lưu thất bại'),
      );
      return;
    }
    NotificationOverlayManager().showSuccess(
      title: 'Đã lưu',
      message: tr('Thông tin công ty sẽ in trên báo giá / hợp đồng A4'),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final perm = context.watch<PermissionProvider>();
    final canEdit = perm.canEditPosSetup() || perm.canEdit('PosQuotes');
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(title: Text(tr('Thông tin công ty shop'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                PosCommercialCompanyFields(
                  company: _company,
                  tax: _tax,
                  address: _address,
                  phone: _phone,
                  email: _email,
                  bankNo: _bankNo,
                  bankName: _bankName,
                  bankHolder: _bankHolder,
                  rep: _rep,
                  title: _title,
                  enabled: canEdit,
                ),
                const SizedBox(height: 20),
                if (canEdit)
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? tr('Đang lưu…') : tr('Lưu thông tin')),
                  ),
              ],
            ),
    );
  }
}
