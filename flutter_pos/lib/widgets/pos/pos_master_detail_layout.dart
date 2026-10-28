import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pos_theme.dart';

/// Màn ngang rộng: danh sách bên trái · chi tiết bên phải, kéo vạch giữa để đổi độ rộng
/// (nhớ theo [prefsKey] trên máy). Dùng cho Hàng hóa, Hóa đơn, các phiếu kho.
class PosMasterDetailLayout extends StatefulWidget {
  const PosMasterDetailLayout({
    super.key,
    required this.prefsKey,
    required this.master,
    required this.detail,
    this.initialFraction = 0.38,
    this.minMasterWidth = 360,
    this.minDetailWidth = 480,
  });

  final String prefsKey;
  final Widget master;
  final Widget detail;
  final double initialFraction;
  final double minMasterWidth;
  final double minDetailWidth;

  @override
  State<PosMasterDetailLayout> createState() => _PosMasterDetailLayoutState();
}

class _PosMasterDetailLayoutState extends State<PosMasterDetailLayout> {
  double? _fraction;
  bool _dragging = false;

  String get _key => 'pos_md_split_${widget.prefsKey}';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final v = p.getDouble(_key);
      if (v != null && mounted) setState(() => _fraction = v);
    }).catchError((_) {});
  }

  void _save() {
    final f = _fraction;
    if (f == null) return;
    SharedPreferences.getInstance()
        .then((p) => p.setDouble(_key, f))
        .catchError((_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final maxMaster = (w - widget.minDetailWidth).clamp(widget.minMasterWidth, w);
        final masterW = (w * (_fraction ?? widget.initialFraction))
            .clamp(widget.minMasterWidth, maxMaster);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: masterW, child: widget.master),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) => setState(() => _dragging = true),
                onHorizontalDragUpdate: (d) => setState(() {
                  _fraction = ((masterW + d.delta.dx) / w)
                      .clamp(widget.minMasterWidth / w, maxMaster / w);
                }),
                onHorizontalDragEnd: (_) {
                  setState(() => _dragging = false);
                  _save();
                },
                // Vùng chạm 14dp (ngón tay trên T1), vạch hiển thị 1dp + nắm kéo ở giữa.
                child: SizedBox(
                  width: 14,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: _dragging ? 3 : 1,
                        color: _dragging ? PosTheme.kiotBlue : PosTheme.border,
                      ),
                      Container(
                        width: 6,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _dragging ? PosTheme.kiotBlue : const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: widget.detail),
          ],
        );
      },
    );
  }
}
