import '../../widgets/settings/settings_page.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/sbox_endpoints.dart';
import '../../models/customer_display_models.dart';
import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import '../../utils/customer_display_media.dart';
import '../../utils/pos_sell_settings_helper.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
/// Thiết lập màn hình phụ: ảnh trình chiếu · video · tùy chọn.
class PosCustomerDisplaySettingsScreen extends StatefulWidget {
  const PosCustomerDisplaySettingsScreen({
    super.key,
    this.embeddedInSettings = false,
  });

  /// Khi mở trong Settings hub đã có AppBar — không vẽ AppBar thứ hai.
  final bool embeddedInSettings;

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
    return '${SboxEndpoints.publicSiteFor(ApiService.baseUrl)}/customer-display?v=$code';
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
      message: tr('${added.length} ảnh trình chiếu'),
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
                style: TextStyle(fontSize: 12, color: SboxColors.slate600),
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
            ? SboxEmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Không tải được thiết lập',
                message: _error,
                action: SboxButton.secondary(label: 'Thử lại', icon: Icons.refresh_rounded, onPressed: _load),
              )
            : _buildBody();

    if (HrmPageChrome.hideOuterChrome(context)) {
      return ColoredBox(color: PosTheme.background, child: body);
    }

    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: shellAwareAppBar(context, AppBar(
        title: Text(tr('Màn hình phụ (khách)')),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0.5,
        foregroundColor: SboxColors.text,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: tr('Quay lại'),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          if (_saving || _uploading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: SboxColors.primary),
                ),
              ),
            ),
        ],
      )),
      body: body,
    );
  }

  /// Chia nhóm (trước đây 1 cột dài nhãn / công tắc / chữ hướng dẫn xen kẽ, khó tìm):
  /// 1 Bật & loại màn · 2 Mở trên máy / TV khác · 3 Khi chờ khách · 4 Ảnh · 5 Video.
  Widget _buildBody() {
    final cd = _cfg;
    final busy = _saving || _uploading;
    final off = busy || !cd.enabled;
    const gap = SizedBox(height: 12);
    // Màn rộng (tablet ngang / desktop): giữ cột cài đặt ≤ 960px ở giữa.
    return LayoutBuilder(builder: (context, c) {
      final side = c.maxWidth > 992 ? (c.maxWidth - 960) / 2 : 16.0;
      return ListView(
        padding: EdgeInsets.fromLTRB(side, 16, side, 24),
        children: [
          // ── 1. Bật & loại màn hình
          SettingsSection(
            title: 'Màn hình phụ cho khách',
            subtitle: 'Chờ khách: chiếu ảnh / video toàn màn · Có đơn: media kèm hóa đơn. Không có media → màn chào của cửa hàng',
            icon: Icons.monitor_outlined,
            trailing: Switch(
              value: cd.enabled,
              onChanged: busy ? null : (v) => _patchCd((c) => c.copyWith(enabled: v)),
            ),
            children: [
              SettingsTile(
                label: 'Loại màn hình phụ',
                help: cd.target.hintVi,
                inline: false,
                control: SizedBox(
                  width: 360,
                  child: DropdownButtonFormField<CustomerDisplayTarget>(
                    isExpanded: true,
                    value: cd.target,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: [
                      for (final t in CustomerDisplayTarget.values)
                        DropdownMenuItem(
                          value: t,
                          child: Text(tr(t.labelVi), style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: off
                        ? null
                        : (v) {
                            if (v == null) return;
                            _patchCd((c) => c.copyWith(target: v));
                          },
                  ),
                ),
              ),
              if (cd.target == CustomerDisplayTarget.t1Native)
                const SettingsNote(
                  'T1 dùng ảnh trình chiếu khi chờ khách. Video không chạy trên DSKernel — chọn «Android Flutter» '
                  'hoặc «Window» nếu cần video.',
                  icon: Icons.info_outline_rounded,
                  tone: SboxTone.neutral,
                ),
              SettingsTile(
                label: 'Tự mở khi vào bán hàng',
                help: cd.target == CustomerDisplayTarget.window
                    ? 'Window: chỉ đẩy state — mở link trên máy/TV khác'
                    : 'Android: display phụ · iOS/Web: mở link trình duyệt',
                control: Switch(
                  value: cd.autoOpenOnPos,
                  onChanged: off ? null : (v) => _patchCd((c) => c.copyWith(autoOpenOnPos: v)),
                ),
              ),
            ],
          ),
          gap,
          // ── 2. Mở trên máy / TV khác
          SettingsSection(
            title: 'Mở trên máy / TV khác',
            subtitle: 'Máy phụ chỉ cần mở link, không đăng nhập. Máy thu ngân phải đang mở bán hàng để đẩy hóa đơn',
            icon: Icons.cast_outlined,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                decoration: BoxDecoration(
                  color: SboxColors.slate50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: SboxColors.border),
                ),
                child: Row(children: [
                  const Icon(Icons.link, size: 18, color: PosTheme.kiotBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      _viewerLink.isEmpty ? tr('Bật màn phụ để tạo mã') : _viewerLink,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 12.5, color: SboxColors.slate700),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Copy link'),
                    onPressed: _viewerLink.isEmpty ? null : _copyViewerLink,
                    icon: const Icon(Icons.copy, size: 20),
                  ),
                ]),
              ),
            ],
          ),
          gap,
          // ── 3. Khi chờ khách
          SettingsSection(
            title: 'Khi chờ khách',
            subtitle: 'Cách chiếu ảnh / video lúc chưa có đơn',
            icon: Icons.slideshow_outlined,
            children: [
              SettingsTile(
                divider: false,
                label: 'Chiếu thêm ảnh sản phẩm',
                help: cd.target == CustomerDisplayTarget.t1Native
                    ? 'T1: lấy ảnh promo / sản phẩm đầu tiên làm welcome'
                    : 'Lấy ảnh từ danh mục hàng hóa',
                control: Switch(
                  value: cd.useProductImages,
                  onChanged: off ? null : (v) => _patchCd((c) => c.copyWith(useProductImages: v)),
                ),
              ),
              SettingsTile(
                label: 'Thời gian đổi ảnh / video',
                control: DropdownButton<int>(
                  value: const {3, 5, 8, 10, 15, 20, 30}.contains(cd.idleSeconds) ? cd.idleSeconds : 8,
                  items: [
                    for (final s in [3, 5, 8, 10, 15, 20, 30])
                      DropdownMenuItem(value: s, child: Text(tr('$s giây'))),
                  ],
                  onChanged: off
                      ? null
                      : (v) {
                          if (v == null) return;
                          _patchCd((c) => c.copyWith(idleSeconds: v));
                        },
                ),
              ),
              SettingsTile(
                label: 'Bật tiếng video',
                help: cd.target == CustomerDisplayTarget.t1Native
                    ? 'Không áp dụng cho Sunmi T1 (DSKernel không phát video)'
                    : 'Mặc định tắt. Trình duyệt / TV chặn tự phát có tiếng thì màn phụ hiện nút «Chạm để bật tiếng»',
                control: Switch(
                  value: cd.videoSound,
                  onChanged: off ? null : (v) => _patchCd((c) => c.copyWith(videoSound: v)),
                ),
              ),
            ],
          ),
          gap,
          // ── 4. Ảnh trình chiếu
          SettingsSection(
            title: 'Ảnh trình chiếu',
            subtitle: 'Upload từ máy hoặc dán URL',
            icon: Icons.photo_library_outlined,
            trailing: Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: off ? null : _editImageUrls,
                icon: const Icon(Icons.link, size: 18),
                label: Text(tr('Sửa URL')),
              ),
              FilledButton.icon(
                onPressed: off ? null : _pickAndUploadImages,
                icon: _uploading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file, size: 18),
                label: Text(tr('Upload ảnh')),
              ),
            ]),
            children: [
              const SizedBox(height: 4),
              if (cd.promoImageUrls.isEmpty)
                const SettingsNote('Chưa có ảnh — bấm «Upload ảnh» hoặc dán URL.',
                    icon: Icons.image_not_supported_outlined, tone: SboxTone.neutral)
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(height: 108, child: _imageStrip(cd, busy)),
                ),
              SettingsHelp(
                summary: 'Kích thước ảnh / video chuẩn',
                steps: [
                  'Ảnh: ${CustomerDisplayMediaSpec.recommendedImage}',
                  'Video: ${CustomerDisplayMediaSpec.recommendedVideo}',
                  CustomerDisplayMediaSpec.layoutNote,
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
          gap,
          // ── 5. Video trình chiếu
          SettingsSection(
            title: 'Video trình chiếu',
            subtitle: 'Không upload video lên server SBOX — để trên Google Drive / CDN rồi dán link',
            icon: Icons.smart_display_outlined,
            trailing: OutlinedButton.icon(
              onPressed: off ? null : _editVideoUrls,
              icon: const Icon(Icons.link, size: 18),
              label: Text(tr('Thêm / sửa link')),
            ),
            children: [
              const SizedBox(height: 4),
              if (cd.promoVideoUrls.isEmpty)
                const SettingsNote('Chưa có video.', icon: Icons.videocam_off_outlined, tone: SboxTone.neutral)
              else
                for (var i = 0; i < cd.promoVideoUrls.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.movie_outlined, color: PosTheme.kiotBlue),
                    title: Text(
                      tr(cd.promoVideoUrls[i].split('/').last),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      tr(cd.promoVideoUrls[i]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: SboxColors.slate600),
                    ),
                    trailing: IconButton(
                      tooltip: tr('Xóa'),
                      onPressed: busy ? null : () => _removeVideoAt(i),
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                  ),
              const SettingsHelp(
                summary: 'Cách lấy link video từ Google Drive',
                steps: [
                  'Upload file .mp4 (khuyến nghị 1280×720 H.264) lên Google Drive',
                  'Chuột phải → Chia sẻ → «Bất kỳ ai có đường liên kết»',
                  'Copy link (dạng /file/d/…/view) → dán vào «Thêm / sửa link» — phần mềm tự đổi sang link phát trực tiếp',
                  'Web có thể bị Drive chặn (CORS) — ưu tiên TV / Android hoặc link CDN .mp4',
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ],
      );
    });
  }

  Widget _imageStrip(CustomerDisplayConfig cd, bool busy) => ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cd.promoImageUrls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final url = _api.getPublicFileUrl(cd.promoImageUrls[i]);
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 140,
                  height: 108,
                  child: url.isEmpty
                      ? Container(color: SboxColors.slate200, child: const Icon(Icons.broken_image))
                      : CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: SboxColors.slate200,
                            alignment: Alignment.center,
                            child: Text(tr('Lỗi ảnh'), style: const TextStyle(fontSize: 11)),
                          ),
                        ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: Material(
                  color: SboxColors.textSecondary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: busy ? null : () => _removeImageAt(i),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
}
