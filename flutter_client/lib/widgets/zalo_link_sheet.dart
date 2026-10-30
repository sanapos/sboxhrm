import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_tr.dart';
import '../services/zalo_bot_api.dart';
import 'notification_overlay.dart';
import 'sbox/sbox_ui.dart';

/// Cài đặt › Liên kết Zalo: lấy mã 6 số, gửi mã cho bot Zalo của cửa hàng để nhận thông báo qua Zalo.
class ZaloLinkSheet extends StatefulWidget {
  const ZaloLinkSheet({super.key, required this.initial, this.api});

  /// Kết quả /api/zalo-bot/me: { available, linked, zaloName, linkedAt, botName, botLink }.
  final Map<String, dynamic> initial;
  final ZaloBotApi? api;

  /// Trả về trạng thái mới nhất khi đóng (để trang Cài đặt cập nhật dòng «Liên kết Zalo»).
  static Future<Map<String, dynamic>?> show(BuildContext context, Map<String, dynamic> initial) =>
      showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ZaloLinkSheet(initial: initial),
      );

  @override
  State<ZaloLinkSheet> createState() => _ZaloLinkSheetState();
}

class _ZaloLinkSheetState extends State<ZaloLinkSheet> {
  late final ZaloBotApi _api = widget.api ?? ZaloBotApi();
  late Map<String, dynamic> _me = widget.initial;
  String? _code;
  DateTime? _expiresAt;
  bool _busy = false;
  Timer? _poll;

  bool get _linked => _me['linked'] == true;
  String? get _botLink {
    final l = _codeBotLink ?? _me['botLink']?.toString();
    return l == null || l.isEmpty ? null : l;
  }

  String? _codeBotLink;

  /// Giờ máy chủ (UTC, có thể thiếu «Z») → giờ máy.
  static DateTime? _localTime(Object? raw) {
    final s = raw?.toString();
    if (s == null || s.isEmpty) return null;
    final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(s);
    return DateTime.tryParse(hasZone ? s : '${s}Z')?.toLocal();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final r = await _api.getMyLink();
    if (!mounted || r['isSuccess'] != true || r['data'] is! Map) return;
    setState(() {
      _me = Map<String, dynamic>.from(r['data'] as Map);
      if (_linked) {
        _code = null;
        _poll?.cancel();
      }
    });
  }

  Future<void> _getCode() async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await _api.createMyCode();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['isSuccess'] == true && r['data'] is Map) {
      final d = r['data'] as Map;
      setState(() {
        _code = d['code']?.toString();
        _expiresAt = _localTime(d['expiresAt']);
        _codeBotLink = d['botLink']?.toString();
      });
      // Tự nhận biết khi người dùng đã gửi mã cho bot.
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    } else {
      NotificationOverlayManager().showError(title: 'Lỗi', message: (r['message'] ?? 'Không lấy được mã').toString());
    }
  }

  Future<void> _unlink() async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await _api.unlinkMe();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['isSuccess'] == true) {
      await _refresh();
      NotificationOverlayManager().showSuccess(title: 'Xong', message: 'Đã hủy liên kết Zalo');
    } else {
      NotificationOverlayManager().showError(title: 'Lỗi', message: (r['message'] ?? 'Không thực hiện được').toString());
    }
  }

  Future<void> _openBot() async {
    final l = _botLink;
    if (l == null) return;
    final uri = Uri.tryParse(l);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final botName = (_me['botName'] ?? '').toString();
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.forum_outlined, color: SboxColors.brand600),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tr('Liên kết Zalo'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context, _me),
          ),
        ]),
        const SizedBox(height: 8),
        if (_linked) ..._linkedBody() else ..._linkBody(botName),
      ]),
    );
  }

  List<Widget> _linkedBody() => [
        const SboxStatusChip(label: 'Đã liên kết', tone: SboxTone.success, icon: Icons.check_circle_outline_rounded),
        const SizedBox(height: 12),
        Text(
          tr('Thông báo lương, phạt, duyệt đơn… đang được gửi về Zalo «{name}».')
              .replaceAll('{name}', (_me['zaloName'] ?? '').toString()),
        ),
        const SizedBox(height: 16),
        SboxButton.danger(
          label: 'Hủy liên kết',
          icon: Icons.link_off_rounded,
          loading: _busy,
          expand: true,
          onPressed: _busy ? null : _unlink,
        ),
      ];

  List<Widget> _linkBody(String botName) {
    final code = _code;
    return [
      Text(
        tr('Nhận thông báo lương, phạt, duyệt đơn… qua Zalo. Lấy mã rồi nhắn mã đó cho bot {bot} trên Zalo.')
            .replaceAll('{bot}', botName.isEmpty ? tr('của cửa hàng') : '«$botName»'),
        style: const TextStyle(color: SboxColors.slate600),
      ),
      const SizedBox(height: 16),
      if (code == null)
        SboxButton(
          label: 'Lấy mã liên kết',
          icon: Icons.pin_outlined,
          loading: _busy,
          expand: true,
          onPressed: _busy ? null : _getCode,
        )
      else ...[
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: SboxColors.brand50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            SelectableText(
              '${code.substring(0, 3)} ${code.substring(3)}',
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 4, color: SboxColors.brand700),
            ),
            if (_expiresAt != null)
              Text(
                tr('Hết hạn lúc {time}').replaceAll('{time}',
                    '${_expiresAt!.hour.toString().padLeft(2, '0')}:${_expiresAt!.minute.toString().padLeft(2, '0')}'),
                style: const TextStyle(color: SboxColors.slate500, fontSize: 12.5),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: SboxButton.secondary(
              label: 'Sao chép mã',
              icon: Icons.copy_rounded,
              expand: true,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                NotificationOverlayManager().showSuccess(title: 'Đã sao chép', message: code);
              },
            ),
          ),
          if (_botLink != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: SboxButton(
                label: 'Mở bot Zalo',
                icon: Icons.open_in_new_rounded,
                expand: true,
                onPressed: _openBot,
              ),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        Text(
          tr('Gửi mã xong, trang này tự cập nhật. Bot trả lời «Đã liên kết» là xong.'),
          style: const TextStyle(color: SboxColors.slate500, fontSize: 12.5),
          textAlign: TextAlign.center,
        ),
        TextButton(onPressed: _busy ? null : _getCode, child: Text(tr('Lấy mã mới'))),
      ],
    ];
  }
}
