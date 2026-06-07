import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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

/// Layout con theo [contentWidth] đầy đủ, báo cáo chiều cao thật cho cha (cuộn dọc).
class _HorizontalClipRender extends SingleChildRenderObjectWidget {
  final double contentWidth;
  final double scrollOffset;

  const _HorizontalClipRender({
    required this.contentWidth,
    required this.scrollOffset,
    required Widget child,
  }) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderHorizontalClip(
      contentWidth: contentWidth,
      scrollOffset: scrollOffset,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHorizontalClip renderObject,
  ) {
    renderObject
      ..contentWidth = contentWidth
      ..scrollOffset = scrollOffset;
  }
}

class _RenderHorizontalClip extends RenderProxyBox {
  _RenderHorizontalClip({
    required double contentWidth,
    double scrollOffset = 0,
  })  : _contentWidth = contentWidth,
        _scrollOffset = scrollOffset;

  double _contentWidth;
  double get contentWidth => _contentWidth;
  set contentWidth(double value) {
    if (_contentWidth == value) return;
    _contentWidth = value;
    markNeedsLayout();
  }

  double _scrollOffset = 0;
  double get scrollOffset => _scrollOffset;
  set scrollOffset(double value) {
    if (_scrollOffset == value) return;
    _scrollOffset = value;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child!.layout(
      BoxConstraints(
        minWidth: contentWidth,
        maxWidth: contentWidth,
        minHeight: 0,
        maxHeight: constraints.maxHeight,
      ),
      parentUsesSize: true,
    );
    size = Size(
      constraints.constrainWidth(constraints.maxWidth),
      child!.size.height,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) {
        context.paintChild(
          child!,
          offset + Offset(-scrollOffset, 0),
        );
      },
    );
  }
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
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final offset = controller.hasClients ? controller.offset : 0.0;
            return _HorizontalClipRender(
              contentWidth: contentWidth,
              scrollOffset: offset,
              child: child,
            );
          },
        ),
      ),
    );
  }
}
