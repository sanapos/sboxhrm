/// Câu nói ngắn điều khiển thẻ chờ xác nhận của Trợ lý ảo — xử lý ngay trên máy, không gửi AI:
/// «xác nhận» / «đồng ý» / «lưu đi» → bấm Xác nhận; «bỏ» / «không» → bỏ thẻ; «hoàn tác» → hoàn tác thẻ vừa lưu;
/// «đọc lại» → đọc lại câu trả lời vừa rồi; «dừng» / «tạm biệt» → tắt chế độ rảnh tay. Câu dài hoặc có nội dung khác («ừ, 500k thôi») vẫn gửi AI như thường.
enum AiVoiceCommandKind { confirm, discard, undo, stop, repeat }

class AiVoiceCommand {
  const AiVoiceCommand(this.kind, {this.index, this.sure = false});

  final AiVoiceCommandKind kind;

  /// Thẻ thứ mấy (1 = thẻ đầu) khi người dùng chỉ rõ («xác nhận thẻ hai»); null = mọi thẻ đang chờ.
  final int? index;

  /// Có nói «chắc chắn» — đủ để xác nhận thẻ rủi ro cao (xóa / hủy) bằng giọng.
  final bool sure;

  /// null = không phải lệnh điều khiển thẻ.
  static AiVoiceCommand? parse(String raw) {
    final native = _nativeWords[raw.trim().replaceAll(RegExp(r'[。.!！?？、,，\s]+$'), '')];
    if (native != null) return AiVoiceCommand(native);
    final t = _norm(raw);
    if (t.isEmpty) return null;
    final words = t.split(' ');
    // Lệnh điều khiển luôn ngắn; câu dài là nội dung mới cho AI.
    if (words.length > 6) return null;
    final index = _index(words);
    final sure = t.contains('chac chan');

    // «đừng lưu», «không xác nhận» = bỏ thẻ. «đừng bỏ», «không bỏ» = giữ thẻ → để AI hiểu, không bấm gì cả.
    final first = words.first;
    if (first == _dont || first == 'khong') {
      final after = _strip(words.skip(1).join(' '));
      if (first == _dont && after.isEmpty) return AiVoiceCommand(AiVoiceCommandKind.discard, index: index);
      if (_any(after, _confirm)) return AiVoiceCommand(AiVoiceCommandKind.discard, index: index);
      if (first == _dont && _any(after, _discard)) return null;
      if (after == 'bo' && !raw.contains(',')) return null;
    }
    if (words.contains(_dont)) return null;

    final rest = _strip(t);

    if (_any(rest, _undo)) return const AiVoiceCommand(AiVoiceCommandKind.undo);
    if (_any(rest, _repeat)) return const AiVoiceCommand(AiVoiceCommandKind.repeat);
    if (_any(rest, _confirm)) return AiVoiceCommand(AiVoiceCommandKind.confirm, index: index, sure: sure);
    if (_any(rest, _discard)) return AiVoiceCommand(AiVoiceCommandKind.discard, index: index);
    if (_any(rest, _stop)) return const AiVoiceCommand(AiVoiceCommandKind.stop);
    return null;
  }

  static const _confirm = [
    'xac nhan', 'dong y', 'ok', 'oke', 'okay', 'u', 'uh', 'um', 'vang', 'da', 'co', 'duoc', 'dung roi', 'dung', 'chuan',
    'luu', 'luu di', 'luu lai', 'lam di', 'tao di', 'gui di', 'chot', 'chot di', 'duyet di', 'tien hanh', 'thuc hien',
    'yes', 'confirm',
  ];
  static const _discard = ['bo', 'bo di', 'bo qua', 'huy', 'huy bo', 'khong', 'khong can', 'khong lam', 'khong lam nua', 'thoi khoi',
    'no', 'cancel'];

  static const _repeat = ['doc lai', 'nhac lai', 'noi lai', 'repeat'];

  /// Giao diện tiếng Hàn / Nhật / Trung: [_norm] chỉ giữ chữ Latin nên so nguyên câu ngắn.
  static const _nativeWords = <String, AiVoiceCommandKind>{
    '확인': AiVoiceCommandKind.confirm, '네': AiVoiceCommandKind.confirm, '저장': AiVoiceCommandKind.confirm,
    '취소': AiVoiceCommandKind.discard, '아니요': AiVoiceCommandKind.discard,
    '되돌리기': AiVoiceCommandKind.undo, '다시 읽어줘': AiVoiceCommandKind.repeat, '중지': AiVoiceCommandKind.stop,
    '確認': AiVoiceCommandKind.confirm, 'はい': AiVoiceCommandKind.confirm, '保存': AiVoiceCommandKind.confirm,
    'キャンセル': AiVoiceCommandKind.discard, 'いいえ': AiVoiceCommandKind.discard,
    '元に戻す': AiVoiceCommandKind.undo, 'もう一度': AiVoiceCommandKind.repeat, 'ストップ': AiVoiceCommandKind.stop,
    '确认': AiVoiceCommandKind.confirm, '确定': AiVoiceCommandKind.confirm, '好的': AiVoiceCommandKind.confirm,
    '取消': AiVoiceCommandKind.discard, '不要': AiVoiceCommandKind.discard,
    '撤销': AiVoiceCommandKind.undo, '再读一遍': AiVoiceCommandKind.repeat, '停止': AiVoiceCommandKind.stop,
  };

  /// «đừng» bỏ dấu trùng «đúng» (nói «đừng lưu» từng lưu luôn thẻ) → đổi thành từ riêng trước khi bỏ dấu.
  static const _dont = 'dungx';
  static const _undo = ['hoan tac', 'undo', 'lay lai', 'tra lai nhu cu'];
  // «dừng» bỏ dấu trùng «đúng» → đổi thành «ngừng» trước khi bỏ dấu (xem [_norm]).
  static const _stop = ['ngung', 'ngung lai', 'thoi', 'tam biet', 'ket thuc', 'tat mic', 'stop', 'bye'];

  /// Câu (sau khi bỏ từ đệm) khớp nguyên một cụm lệnh.
  static bool _any(String rest, List<String> keys) => keys.contains(rest);

  /// Bỏ từ đệm / xưng hô / số thẻ: «ừ xác nhận đi em» → «xac nhan», «xác nhận thẻ 2» → «xac nhan».
  static String _strip(String t) {
    const filler = {
      'di', 'nhe', 'nha', 'em', 'anh', 'chi', 'ban', 'a', 'oi', 'giup', 'toi', 'minh', 'cho', 'luon', 'the', 'phieu',
      'cai', 'thu', 'so', 'nay', 'do', 'tat', 'ca', 'het', 'chac', 'chan', 'vay', 'roi', 'nhat', 'hai', 'ba', 'bon', 'tu',
      'nam', 'mot', 'dau', 'tien', 'cuoi',
    };
    // Giữ nguyên các cụm có nghĩa trước khi lọc từ đệm.
    // Từ một chữ cùng nghĩa đi kèm («ừ xác nhận», «ok lưu đi») không làm hỏng lệnh.
    for (final list in [_undo, _repeat, _confirm, _discard, _stop]) {
      for (final k in [...list]..sort((a, b) => b.length - a.length)) {
        if (k.contains(' ') && t.contains(k)) {
          final others = t.replaceFirst(k, ' ').split(' ')
              .where((w) => w.isNotEmpty && !filler.contains(w) && !_isNum(w) && !list.contains(w));
          if (others.isEmpty) return k;
        }
      }
    }
    final words = t.split(' ').where((w) => !filler.contains(w) && !_isNum(w)).toList();
    for (final list in [_undo, _confirm, _discard, _stop]) {
      if (words.isNotEmpty && words.every(list.contains)) return words.first;
    }
    return words.join(' ');
  }

  static bool _isNum(String w) => int.tryParse(w) != null;

  static int? _index(List<String> words) {
    const ordinals = {'nhat': 1, 'mot': 1, 'dau': 1, 'hai': 2, 'ba': 3, 'bon': 4, 'tu': 4, 'nam': 5};
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      final n = int.tryParse(w);
      if (n != null && n >= 1 && n <= 20) return n;
      // «thẻ hai», «cái thứ ba», «phiếu đầu tiên» — số đứng sau từ chỉ thẻ.
      if (i > 0 && const {'the', 'thu', 'phieu', 'cai', 'so'}.contains(words[i - 1]) && ordinals.containsKey(w)) {
        return ordinals[w];
      }
    }
    return null;
  }

  static String _norm(String s) {
    var t = s.toLowerCase().trim().replaceAll('dừng', 'ngừng').replaceAll('đừng', _dont);
    const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    final b = StringBuffer();
    for (final ch in t.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    t = b.toString().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
