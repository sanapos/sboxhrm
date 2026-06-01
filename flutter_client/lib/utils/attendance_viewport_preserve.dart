import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Lưu/khôi phục vị trí cuộn sau khi tải lại dữ liệu chấm công.
class AttendanceViewportPreserve {
  double? listScrollOffset;
  double? attHorizOffset;
  double? attVertOffset;

  void capture({
    ScrollController? listScroll,
    ScrollController? attHoriz,
    ScrollController? attVert,
  }) {
    listScrollOffset =
        listScroll != null && listScroll.hasClients ? listScroll.offset : null;
    attHorizOffset =
        attHoriz != null && attHoriz.hasClients ? attHoriz.offset : null;
    attVertOffset =
        attVert != null && attVert.hasClients ? attVert.offset : null;
  }

  void restore({
    ScrollController? listScroll,
    ScrollController? attHoriz,
    ScrollController? attVert,
  }) {
    void apply(ScrollController? c, double? offset) {
      if (c == null || offset == null) return;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!c.hasClients) return;
        final max = c.position.maxScrollExtent;
        c.jumpTo(offset.clamp(0.0, max));
      });
    }

    apply(listScroll, listScrollOffset);
    apply(attHoriz, attHorizOffset);
    apply(attVert, attVertOffset);
  }
}
