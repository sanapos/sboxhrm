import 'dart:convert';

/// Một ca trong thiết lập lần chấm. [halves]: khung giờ của ca — ca có nghỉ trưa trong ca có 2 khung
/// (mỗi khung một cặp vào / ra), còn lại 1 khung. Giờ tính bằng phút từ 0h.
typedef PunchSlotShift = ({String id, String name, List<({int start, int end})> halves});

/// Thiết lập của cửa hàng: giờ vào / ra của từng ca nằm ở cột «Lần» nào khi chọn «Giờ chấm theo ca».
/// Giá trị: id mẫu ca → các số Lần (tính từ 1) [vào, ra] hoặc [vào, ra, vào, ra] với ca có nghỉ trưa.
/// Lần lẻ là vào, lần chẵn là ra — đúng màu và cách thêm giờ của các ô trên bảng.
class AttendancePunchSlots {
  AttendancePunchSlots._();

  static const settingKey = 'attendance_shift_punch_slots';

  static Map<String, List<int>> parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return {};
      final out = <String, List<int>>{};
      decoded.forEach((k, v) {
        if (v is! List) return;
        final cols = v.whereType<int>().toList();
        if (cols.length != v.length || !isValid(cols)) return;
        out[k.toString()] = cols;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  static String encode(Map<String, List<int>> slots) => json.encode(slots);

  /// Cặp vào / ra đầy đủ, vào ở lần lẻ, ra ở lần chẵn, lần sau lớn hơn lần trước.
  static bool isValid(List<int> cols) {
    if (cols.isEmpty || cols.length.isOdd) return false;
    for (var i = 0; i < cols.length; i++) {
      if (cols[i] < 1 || cols[i].isOdd != i.isEven) return false;
      if (i > 0 && cols[i] <= cols[i - 1]) return false;
    }
    return true;
  }

  /// Số Lần của mọi ca: lấy theo [saved]; ca chưa thiết lập (vd. ca mới tạo) theo [autoColumns].
  static Map<String, List<int>> withDefaults(List<PunchSlotShift> shifts, Map<String, List<int>> saved) {
    final auto = autoColumns(shifts);
    return {
      for (final s in shifts) s.id: saved[s.id] != null ? _fit(saved[s.id]!, s.halves.length) : auto[s.id]!,
    };
  }

  /// Xếp tự động theo giờ ca. Các ca nối tiếp nhau trong ngày mỗi ca một cặp (sáng 1–2, chiều 3–4, tối 5–6); ca trùng
  /// giờ với chúng dùng chung các lần đó (hành chính 08–17: vào Lần 1, ra Lần 4) để bảng không thừa cột.
  static Map<String, List<int>> autoColumns(List<PunchSlotShift> shifts) {
    int span(PunchSlotShift s) => s.halves.last.end - s.halves.first.start;
    final sorted = [...shifts]
      ..sort((a, b) => a.halves.first.start != b.halves.first.start
          ? a.halves.first.start.compareTo(b.halves.first.start)
          : span(a).compareTo(span(b)));
    final out = <String, List<int>>{};
    final chain = <({int start, int end, int lan})>[];
    int? chainEnd;
    for (final s in sorted) {
      if (chainEnd != null && s.halves.first.start < chainEnd) continue;
      final cols = <int>[];
      for (final h in s.halves) {
        final lan = chain.length * 2 + 1;
        chain.add((start: h.start, end: h.end, lan: lan));
        cols.addAll([lan, lan + 1]);
      }
      out[s.id] = cols;
      chainEnd = s.halves.last.end;
    }

    /// Ca trong chuỗi gần giờ [minute] nhất.
    ({int start, int end, int lan}) nearest(int minute) {
      int dist(({int start, int end, int lan}) c) =>
          minute < c.start ? c.start - minute : (minute > c.end ? minute - c.end : 0);
      var best = chain.first;
      for (final c in chain) {
        if (dist(c) < dist(best)) best = c;
      }
      return best;
    }

    for (final s in sorted) {
      if (out.containsKey(s.id)) continue;
      final cols = <int>[];
      for (final h in s.halves) {
        var lanIn = nearest(h.start).lan;
        if (cols.isNotEmpty && lanIn <= cols.last) lanIn = cols.last + 1;
        var lanOut = nearest(h.end).lan + 1;
        if (lanOut <= lanIn) lanOut = lanIn + 1;
        cols.addAll([lanIn, lanOut]);
      }
      out[s.id] = cols;
    }
    return out;
  }

  /// Mẫu ca đổi có / không nghỉ trưa sau khi đã thiết lập: bỏ nghỉ trưa → vào đầu, ra cuối; thêm → 4 lần liền nhau.
  static List<int> _fit(List<int> cols, int halves) {
    if (cols.length == halves * 2) return cols;
    if (halves == 1) return [cols.first, cols.last];
    return [for (var i = 0; i < halves * 2; i++) cols.first + i];
  }
}

/// Giờ chấm xếp vào các ô «Lần» của một dòng.
class ShiftPunchColumns {
  /// Chỉ số giờ chấm ở từng ô (null = ô trống).
  final List<int?> cols;

  /// Ô cùng cặp vào / ra. Chỉ có ở ca đã có giờ chấm: ô trống có ô cặp đã chấm là thiếu chấm.
  final Map<int, int> pairOf;

  const ShiftPunchColumns(this.cols, this.pairOf);

  /// Xếp theo cột của từng khung ca ([columns] cùng thứ tự [ins] / [outs], cột tính từ 0). Giờ ngoài ca ([extra])
  /// hoặc rơi vào ô đã có giờ thì nối ở các ô cuối — không làm mất giờ chấm.
  factory ShiftPunchColumns.place({
    required List<DateTime> punches,
    required List<DateTime?> ins,
    required List<DateTime?> outs,
    required List<DateTime> extra,
    required List<({int inCol, int outCol})> columns,
  }) {
    var len = 0;
    for (final c in columns) {
      if (c.outCol + 1 > len) len = c.outCol + 1;
    }
    final cols = List<int?>.filled(len, null, growable: true);
    final pairOf = <int, int>{};
    final overflow = [...extra];
    void put(DateTime? p, int col) {
      if (p == null) return;
      if (cols[col] == null) {
        cols[col] = punches.indexOf(p);
      } else {
        overflow.add(p);
      }
    }

    for (var k = 0; k < columns.length; k++) {
      final c = columns[k];
      if (ins[k] == null && outs[k] == null) continue;
      pairOf[c.inCol] = c.outCol;
      pairOf[c.outCol] = c.inCol;
      put(ins[k], c.inCol);
      put(outs[k], c.outCol);
    }
    overflow.sort();
    cols.addAll(overflow.map(punches.indexOf));
    if (cols.length.isOdd) cols.add(null);
    return ShiftPunchColumns(cols, pairOf);
  }
}
