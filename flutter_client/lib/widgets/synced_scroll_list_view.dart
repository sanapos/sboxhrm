import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';

/// ListView theo dõi [mainController] (cuộn dọc đồng bộ hai vùng).
class SyncedScrollListView extends StatefulWidget {
  final ScrollController mainController;
  final int itemCount;
  final double? itemExtent;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollPhysics? physics;

  const SyncedScrollListView({
    super.key,
    required this.mainController,
    required this.itemCount,
    required this.itemBuilder,
    this.itemExtent,
    this.physics,
  });

  @override
  State<SyncedScrollListView> createState() => _SyncedScrollListViewState();
}

class _SyncedScrollListViewState extends State<SyncedScrollListView> {
  late final ScrollController _followerController;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _followerController = ScrollController();
    widget.mainController.addListener(_onMainScroll);
    _followerController.addListener(_onFollowerScroll);
  }

  @override
  void didUpdateWidget(SyncedScrollListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mainController != widget.mainController) {
      oldWidget.mainController.removeListener(_onMainScroll);
      widget.mainController.addListener(_onMainScroll);
    }
  }

  void _onMainScroll() {
    if (_isSyncing) return;
    _isSyncing = true;
    if (_followerController.hasClients && widget.mainController.hasClients) {
      _followerController.jumpTo(widget.mainController.offset);
    }
    _isSyncing = false;
  }

  void _onFollowerScroll() {
    if (_isSyncing) return;
    _isSyncing = true;
    if (widget.mainController.hasClients && _followerController.hasClients) {
      widget.mainController.jumpTo(_followerController.offset);
    }
    _isSyncing = false;
  }

  @override
  void dispose() {
    widget.mainController.removeListener(_onMainScroll);
    _followerController.removeListener(_onFollowerScroll);
    _followerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _followerController,
      physics: widget.physics,
      itemCount: widget.itemCount,
      itemExtent: widget.itemExtent,
      itemBuilder: widget.itemBuilder,
    );
  }
}

/// Đồng bộ offset cuộn ngang giữa hai [ScrollController] (hai ScrollView riêng).
void linkHorizontalScrollControllers(
  ScrollController a,
  ScrollController b,
) {
  var syncing = false;

  void sync(ScrollController from, ScrollController to) {
    if (syncing) return;
    if (!from.hasClients || !to.hasClients) return;
    final target = from.offset.clamp(0.0, to.position.maxScrollExtent);
    if ((to.offset - target).abs() < 0.5) return;
    syncing = true;
    to.jumpTo(target);
    syncing = false;
  }

  a.addListener(() => sync(a, b));
  b.addListener(() => sync(b, a));
}

/// Cắt và dịch [child] theo [controller]; vuốt ngang trên vùng dữ liệu vẫn cuộn (đồng bộ header).
class HorizontallySyncedClip extends StatelessWidget {
  final ScrollController controller;
  final double contentWidth;
  final Widget child;

  const HorizontallySyncedClip({
    super.key,
    required this.controller,
    required this.contentWidth,
    required this.child,
  });

  void _applyHorizontalDelta(double deltaDx) {
    if (!controller.hasClients || deltaDx == 0) return;
    final position = controller.position;
    controller.jumpTo(
      (controller.offset - deltaDx)
          .clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          final dx = event.scrollDelta.dx;
          if (dx != 0) _applyHorizontalDelta(dx);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) =>
            _applyHorizontalDelta(details.delta.dx),
        child: ClipRect(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final offset = controller.hasClients ? controller.offset : 0.0;
              return Transform.translate(
                offset: Offset(-offset, 0),
                child: SizedBox(width: contentWidth, child: child),
              );
            },
          ),
        ),
      ),
    );
  }
}
