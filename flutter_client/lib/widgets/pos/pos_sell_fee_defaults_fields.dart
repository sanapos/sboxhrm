import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Tên phụ phí, mức cố định, gợi ý phí GH — dùng chung hub + dialog.
class PosSellFeeDefaultsFields extends StatelessWidget {
  const PosSellFeeDefaultsFields({
    super.key,
    required this.enableSurcharge,
    required this.enableDeliveryFee,
    required this.surchargeNameCtrl,
    required this.surchargeDefaultCtrl,
    required this.deliveryDefaultCtrl,
    required this.surchargeIsPercent,
    required this.onSurchargeMode,
    this.compact = false,
  });

  final bool enableSurcharge;
  final bool enableDeliveryFee;
  final TextEditingController surchargeNameCtrl;
  final TextEditingController surchargeDefaultCtrl;
  final TextEditingController deliveryDefaultCtrl;
  final bool surchargeIsPercent;
  final ValueChanged<bool> onSurchargeMode;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hintSize = compact ? 11.0 : 12.0;
    if (!enableSurcharge && !enableDeliveryFee) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (enableSurcharge) ...[
          const SizedBox(height: 8),
          TextField(
            controller: surchargeNameCtrl,
            decoration: InputDecoration(
              labelText: tr('Tên phụ phí trên hóa đơn'),
              hintText: tr('VD: Phụ thu dịch vụ, Phí bàn...'),
              border: const OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 8),
          Text(
            tr('Mức cố định (tự nhảy khi tạo đơn mới)'),
            style: TextStyle(fontSize: hintSize, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              ChoiceChip(
                label: Text(tr('%')),
                selected: surchargeIsPercent,
                onSelected: (_) => onSurchargeMode(true),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: Text(tr('Tiền (đ)')),
                selected: !surchargeIsPercent,
                onSelected: (_) => onSurchargeMode(false),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: surchargeDefaultCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: surchargeIsPercent
                        ? tr('Mặc định (%)')
                        : tr('Mặc định (đ)'),
                    hintText: tr('0 = không tự nhảy'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (enableDeliveryFee) ...[
          const SizedBox(height: 10),
          TextField(
            controller: deliveryDefaultCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: tr('Phí giao hàng mặc định (đ)'),
              hintText: tr('Gợi ý tự nhảy khi tạo đơn. 0 = nhập tay'),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }
}
