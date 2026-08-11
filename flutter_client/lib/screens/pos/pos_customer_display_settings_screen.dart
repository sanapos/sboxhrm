import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/customer_display_models.dart';
import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import '../../utils/customer_display_media.dart';
import '../../utils/pos_sell_settings_helper.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Thiết lập màn hình phụ: ảnh trình chiếu · video · tùy chọn.
class PosCustomerDisplaySettingsScreen extends StatefulWidget {
  const PosCustomerDisplaySettingsScreen({super.key});

  @override
  State<PosCustomerDisplaySettingsScreen> createState() =>
      _PosCustomerDisplaySettingsScreenState();
}

class _PosCustomerDisplaySettingsScreenState
    extends State<PosCustomerDisplaySettingsScreen> {
  final _api = ApiService();
  late final PosSellSettingsHelper _helper = PosSellSettingsHelper(_api);
  PosStoreSellSettingsDto? _settings;
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  CustomerDisplayConfig get _cfg =>
      CustomerDisplayConfig.fromExtraJson(_settings?.extraJson);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _helper.load();
    if (!mounted) return;
    var settings = r.settings;
    // Đảm bảo có viewerCode để copy link máy khác.
    if (settings != null) {
      final cfg = CustomerDisplayConfig.fromExtraJson(settings.extraJson);
      final raw = settings.extraJson ?? '';
      if (!raw.contains('viewerCode') || cfg.viewerCode.length < 4) {
        final patched = settings.copyWith(
          extraJson: cfg.mergeIntoExtraJson(settings.extraJson),
        );
        final saved = await _helper.save(patched);
        if (saved.settings != null) settings = saved.settings;
      }
    }
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _error = r.error;
      _loading = false;
    });
  }

  String get _viewerLink {
    final code = _cfg.viewerCode.trim();
    if (code.length < 4) return '';
    if (kIsWeb) {
      final origin = Uri.base.origin;
      return '$origin/customer-display?v=$code';
    }
    return 'https://sboxhrm.com/customer-display?v=$code';
  }

  Future<void> _copyViewerLink() async {
    final link = _viewerLink;
    if (link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: link));
    NotificationOverlayManager().showSuccess(
      title: 'Đã copy link',
      message: tr('Dán trên máy/TV khác → mở trình duyệt (không cần đăng nhập)'),
    );
  }

  Future<void> _patchCd(
    CustomerDisplayConfig Function(CustomerDisplayConfig) fn,
  ) async {
    final s = _settings;
    if (s == null || _saving) return;
    final next = fn(CustomerDisplayConfig.fromExtraJson(s.extraJson));
    final patched =
        s.copyWith(extraJson: next.mergeIntoExtraJson(s.extraJson));
    setState(() {
      _settings = patched;
      _saving = true;
    });
    final r = await _helper.save(patched);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.settings != null) {
      setState(() => _settings = r.settings);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: r.error ?? 'Không lưu được',
      );
      await _load();
    }
  }

  Future<void> _pickAndUploadImages() async {
    if (_uploading || !_cfg.enabled) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    setState(() => _uploading = true);
    final added = <String>[];
    String? lastErr;
    for (final f in result.files) {
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      final name = (f.name.isNotEmpty)
          ? f.name
          : 'promo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final res = await _api.uploadCustomerDisplayMedia(
        Uint8List.fromList(bytes).toList(),
        name,
      );
      if (res['isSuccess'] == true && res['data'] is Map) {
        final data = res['data'] as Map;
        final path = (data['filePath'] ?? data['fileUrl'] ?? '').toString();
        if (path.isNotEmpty) added.add(path);
      } else {
        lastErr = res['message']?.toString();
      }
    }
    if (!mounted) return;
    setState(() => _uploading = false);

    if (added.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Upload ảnh',
        message: lastErr ?? tr('Không tải được ảnh lên máy chủ'),
      );
      return;
    }
    await _patchCd(
      (c) => c.copyWith(promoImageUrls: [...c.promoImageUrls, ...added]),
    );
    NotificationOverlayManager().showSuccess(
      title: 'Đã thêm ảnh',
      message: '${added.length} ảnh trình chiếu',
    );
  }

  Future<void> _removeVideoAt(int index) async {
    final list = [..._cfg.promoVideoUrls];
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    await _patchCd((c) => c.copyWith(promoVideoUrls: list));
  }

  Future<void> _editImageUrls() async {
    final ctrl = TextEditingController(text: _cfg.promoImageUrls.join('\n'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('URL / đường dẫn ảnh trình chiếu')),
        content: SizedBox(
          width: 440,
          child: TextField(
            controller: ctrl,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: tr(
                  'stores/.../customer-display/a.jpg\nhttps://...\nmỗi dòng một ảnh'),
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Hủy')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Lưu')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final urls = ctrl.text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    await _patchCd((c) => c.copyWith(promoImageUrls: urls));
  }

  Future<void> _editVideoUrls() async {
    final ctrl = TextEditingController(text: _cfg.promoVideoUrls.join('\n'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Link video (Drive / CDN)')),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Dán link Google Drive hoặc URL .mp4 trực tiếp. '
                    'Không upload video lên server SBOX. Không dùng YouTube.'),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: tr(
                      'https://drive.google.com/file/d/xxxxx/view\n'
                      'https://cdn.../clip.mp4'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Hủy')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Lưu')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final urls = ctrl.text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => CustomerDisplayConfig.normalizeExternalMediaUrl(e.trim()))
        .where((e) => e.isNotEmpty)
        .toList();
    await _patchCd((c) => c.copyWith(promoVideoUrls: urls));
  }

  Future<void> _removeImageAt(int index) async {
    final list = [..._cfg.promoImageUrls];
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    await _patchCd((c) => c.copyWith(promoImageUrls: list));
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Text(tr(_error!)))
            : _buildBody();

    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Màn hình phụ (khách)')),
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
        actions: [
          if (_saving || _uploading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody() {
    final cd = _cfg;
    final busy = _saving || _uploading;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          tr('Cột trái (~60%): ảnh/video full khung · Cột phải: hóa đơn. '
              'Không media → branding SBOX HRM.'),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Kích thước chuẩn trình chiếu'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 6),
              Text(
                tr('• Ảnh: ${CustomerDisplayMediaSpec.recommendedImage}\n'
                    '• Video: ${CustomerDisplayMediaSpec.recommendedVideo}\n'
                    '• ${CustomerDisplayMediaSpec.layoutNote}'),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade800, height: 1.35),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.link, color: PosTheme.kiotBlue),
          title: Text(tr('Link mở trên máy / TV khác')),
          subtitle: Text(
            tr(_viewerLink.isEmpty
                ? 'Bật màn phụ để tạo mã'
                : _viewerLink),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          trailing: IconButton(
            tooltip: tr('Copy link'),
            onPressed: _viewerLink.isEmpty ? null : _copyViewerLink,
            icon: const Icon(Icons.copy, size: 20),
          ),
        ),
        Text(
          tr('Máy thu ngân phải đang mở bán hàng (để đẩy hóa đơn). '
              'Máy phụ chỉ cần mở link — không đăng nhập.'),
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Bật màn hình phụ')),
          value: cd.enabled,
          onChanged:
              busy ? null : (v) => _patchCd((c) => c.copyWith(enabled: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Tự mở khi vào bán hàng')),
          subtitle: Text(tr('Android: display phụ · iOS/Web: mở link trình duyệt')),
          value: cd.autoOpenOnPos,
          onChanged: busy || !cd.enabled
              ? null
              : (v) => _patchCd((c) => c.copyWith(autoOpenOnPos: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Chiếu thêm ảnh sản phẩm khi chờ')),
          subtitle: Text(tr('Lấy ảnh từ danh mục hàng hóa')),
          value: cd.useProductImages,
          onChanged: busy || !cd.enabled
              ? null
              : (v) => _patchCd((c) => c.copyWith(useProductImages: v)),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Thời gian đổi ảnh/video')),
          trailing: DropdownButton<int>(
            value: const {3, 5, 8, 10, 15, 20, 30}.contains(cd.idleSeconds)
                ? cd.idleSeconds
                : 8,
            items: [
              for (final s in [3, 5, 8, 10, 15, 20, 30])
                DropdownMenuItem(value: s, child: Text(tr('$s giây'))),
            ],
            onChanged: busy || !cd.enabled
                ? null
                : (v) {
                    if (v == null) return;
                    _patchCd((c) => c.copyWith(idleSeconds: v));
                  },
          ),
        ),
        const Divider(height: 28),
        Text(tr('Ảnh trình chiếu'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 4),
        Text(
          tr('Đây là chỗ nhập ảnh chiếu trên màn phụ. Upload từ máy hoặc dán URL.'),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: busy || !cd.enabled ? null : _pickAndUploadImages,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file, size: 18),
              label: Text(tr('Upload ảnh')),
            ),
            OutlinedButton.icon(
              onPressed: busy || !cd.enabled ? null : _editImageUrls,
              icon: const Icon(Icons.link, size: 18),
              label: Text(tr('Sửa danh sách URL')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (cd.promoImageUrls.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              tr('Chưa có ảnh trình chiếu — nhấn «Upload ảnh» hoặc dán URL.'),
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          )
        else
          SizedBox(
            height: 108,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cd.promoImageUrls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final raw = cd.promoImageUrls[i];
                final url = _api.getPublicFileUrl(raw);
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 140,
                        height: 108,
                        child: url.isEmpty
                            ? Container(
                                color: Colors.grey.shade200,
                                child: const Icon(Icons.broken_image),
                              )
                            : CachedNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: Colors.grey.shade200,
                                  alignment: Alignment.center,
                                  child: Text(tr('Lỗi ảnh'),
                                      style: const TextStyle(fontSize: 11)),
                                ),
                              ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: busy ? null : () => _removeImageAt(i),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.close,
                                size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        const Divider(height: 28),
        Text(tr('Video trình chiếu (Google Drive)'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 4),
        Text(
          tr('Không upload video lên server SBOX (nặng máy chủ). '
              'Upload lên Google Drive rồi dán link vào đây.'),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Text(
            tr('Hướng dẫn Drive:\n'
                '1. Upload file .mp4 (khuyến nghị 1280×720 H.264) lên Google Drive\n'
                '2. Chuột phải → Chia sẻ → «Bất kỳ ai có đường liên kết»\n'
                '3. Copy link (dạng /file/d/…/view) → dán vào «Thêm link video»\n'
                '4. Phần mềm tự đổi sang link phát trực tiếp\n'
                'Lưu ý: Web có thể bị CORS Drive — ưu tiên TV/Android hoặc CDN .mp4'),
            style: TextStyle(
                fontSize: 12, color: Colors.grey.shade800, height: 1.4),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: busy || !cd.enabled ? null : _editVideoUrls,
          icon: const Icon(Icons.link, size: 18),
          label: Text(tr('Thêm / sửa link video')),
        ),
        const SizedBox(height: 12),
        if (cd.promoVideoUrls.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              tr('Chưa có video — dùng hướng dẫn Drive phía trên.'),
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          )
        else
          Column(
            children: [
              for (var i = 0; i < cd.promoVideoUrls.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.movie_outlined,
                      color: PosTheme.kiotBlue),
                  title: Text(
                    tr(cd.promoVideoUrls[i].split('/').last),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    tr(cd.promoVideoUrls[i]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  trailing: IconButton(
                    tooltip: tr('Xóa'),
                    onPressed: busy ? null : () => _removeVideoAt(i),
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
