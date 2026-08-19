import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Hàng chip ngang: kéo được + mũi tên «xem thêm» khi tràn.
class PosHScrollChipRow extends StatefulWidget {
  const PosHScrollChipRow({
    super.key,
    required this.children,
    this.trailing,
    this.height = 52,
    this.padding = const EdgeInsets.fromLTRB(10, 6, 4, 6),
    this.iconColor,
  });

  final List<Widget> children;
  final Widget? trailing;
  final double height;
  final EdgeInsets padding;
  final Color? iconColor;

  @override
  State<PosHScrollChipRow> createState() => _PosHScrollChipRowState();
}

class _PosHScrollChipRowState extends State<PosHScrollChipRow> {
  final _ctrl = ScrollController();
  var _canBack = false;
  var _canFwd = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(covariant PosHScrollChipRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _ctrl.removeListener(_sync);
    _ctrl.dispose();
    super.dispose();
  }

  void _sync() {
    if (!_ctrl.hasClients) {
      if (_canBack || _canFwd) {
        setState(() {
          _canBack = false;
          _canFwd = false;
        });
      }
      return;
    }
    final p = _ctrl.position;
    final back = p.pixels > 4;
    final fwd = p.maxScrollExtent > 8 && p.pixels < p.maxScrollExtent - 4;
    if (back != _canBack || fwd != _canFwd) {
      setState(() {
        _canBack = back;
        _canFwd = fwd;
      });
    }
  }

  Future<void> _jump(double dir) async {
    if (!_ctrl.hasClients) return;
    final next = (_ctrl.offset + dir * 240)
        .clamp(0.0, _ctrl.position.maxScrollExtent);
    await _ctrl.animateTo(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.iconColor ?? const Color(0xFF64748B);
    return SizedBox(
      height: widget.height,
      child: Row(
        children: [
          if (_canBack)
            IconButton(
              tooltip: tr('Xem thêm'),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: Icon(Icons.chevron_left, color: iconColor),
              onPressed: () => unawaited(_jump(-1)),
            ),
          Expanded(
            child: ScrollConfiguration(
              behavior: const MaterialScrollBehavior().copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.stylus,
                },
              ),
              child: Scrollbar(
                controller: _ctrl,
                thumbVisibility: _canBack || _canFwd,
                child: ListView.separated(
                  controller: _ctrl,
                  scrollDirection: Axis.horizontal,
                  primary: false,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: widget.padding,
                  itemCount: widget.children.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => Center(child: widget.children[i]),
                ),
              ),
            ),
          ),
          if (_canFwd)
            IconButton(
              tooltip: tr('Xem thêm'),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: Icon(Icons.chevron_right, color: iconColor),
              onPressed: () => unawaited(_jump(1)),
            ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }
}
