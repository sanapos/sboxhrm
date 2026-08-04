import 'package:flutter/material.dart';

import '../../models/cancel_return_reason_config.dart';
import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
import 'pos_theme.dart';

/// Tải cấu hình kiểm soát lý do từ sell-settings.
Future<CancelReturnReasonConfig> fetchCancelReturnReasonConfig(
    ApiService api) async {
  final res = await api.getPosSellSettings();
  if (res['isSuccess'] == true && res['data'] is Map) {
    final dto = PosStoreSellSettingsDto.fromJson(
      Map<String, dynamic>.from(res['data'] as Map),
    );
    return CancelReturnReasonConfig.fromExtraJson(dto.extraJson);
  }
  return const CancelReturnReasonConfig();
}

/// Hộp chọn lý do hủy/trả khi bật kiểm soát trong Thiết lập ngành.
Future<CancelReturnReasonResult?> showPosCancelReturnReasonDialog(
  BuildContext context, {
  required CancelReturnReasonConfig config,
  String title = 'Lý do hủy / trả',
}) async {
  if (!config.enabled) {
    return const CancelReturnReasonResult(reason: '');
  }
  final reasons = config.reasons.isEmpty
      ? CancelReturnReasonConfig.defaultReasons
      : config.reasons;
  var selected = reasons.first;
  final noteCtrl = TextEditingController();

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text(tr(title)),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('Chọn lý do'),
                      style: TextStyle(
                          fontSize: 13, color: PosTheme.textSecondary)),
                  const SizedBox(height: 8),
                  for (final r in reasons)
                    RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr(r)),
                      value: r,
                      groupValue: selected,
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() => selected = v);
                      },
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: tr('Ghi chú chi tiết (tuỳ chọn)'),
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Huỷ')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Xác nhận')),
              ),
            ],
          );
        },
      );
    },
  );

  final note = noteCtrl.text.trim();
  noteCtrl.dispose();
  if (ok != true) return null;
  return CancelReturnReasonResult(
    reason: selected,
    detailNote: note.isEmpty ? null : note,
  );
}
