#!/usr/bin/env python3
"""Complete leave_screen.dart fix: encoding + approval strings + helpers (Python only)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
p = ROOT / "lib/screens/leave_screen.dart"

# Start from git cp1258 source
import subprocess
subprocess.run(
    ["git", "checkout", "HEAD", "--", "lib/screens/leave_screen.dart"],
    cwd=ROOT,
    check=True,
)

text = p.read_bytes().decode("cp1258").replace("\r\n", "\n")

# --- phase 1: from fix_leave_all fixes (abbreviated critical set) ---
fixes = [
    ("T?ng quan & b? l?c", "Tổng quan & bộ lọc"),
    ("Quy d?nh ngh? phép", "Quy định nghỉ phép"),
    ("'Đã duy?t'", "'Đã duyệt'"),
    ("'Đã h?y'", "'Đã hủy'"),
    ("'Duyệt $approvalStep/$approvalLevels c?p'", "'Duyệt $approvalStep/$approvalLevels cấp'"),
    ("'Ti?n trình duy?t: $currentStep/$totalLevels c?p'", "'Tiến trình duyệt: $currentStep/$totalLevels cấp'"),
    ("'L?ch s? phê duy?t'", "'Lịch sử phê duyệt'"),
    ("'C?p ${record['stepOrder'] ?? idx + 1}'", "'Cấp ${record['stepOrder'] ?? idx + 1}'"),
    ("'Th?c hi?n: $actualUser'", "'Thực hiện: $actualUser'"),
    ("'${leave['currentApprovalStep'] ?? 0}/${leave['totalApprovalLevels']} c?p'", "'${leave['currentApprovalStep'] ?? 0}/${leave['totalApprovalLevels']} cấp'"),
    ("'Ch? duy?t'", "'Chờ duyệt'"),
    ("title: 'L?i'", "title: 'Lỗi'"),
    ("'VR có luong'", "'Việc riêng có lương'"),
    ("'VR không luong'", "'Việc riêng không lương'"),
    ("'?m dau'", "'Nghỉ ốm'"),
    ("'Thai s?n'", "'Thai sản'"),
    ("'Ngh? bù'", "'Nghỉ bù'"),
    ("'Ngh? dài h?n'", "'Nghỉ dài hạn'"),
    ("'L? t?t'", "'Nghỉ lễ, Tết'"),
    ("'Có luong'", "'Có lương'"),
    ("'T? ngày'", "'Từ ngày'"),
    ("'Đ?n ngày'", "'Đến ngày'"),
    ("'Lý do t? ch?i'", "'Lý do từ chối'"),
    ("'C?p nh?t'", "'Cập nhật'"),
    ("title: 'Lo?i ngh?'", "title: 'Loại nghỉ'"),
    ("title: 'Tr?ng thái'", "title: 'Trạng thái'"),
    ("title: 'Th?i gian'", "title: 'Thời gian'"),
    ("title: 'S? don'", "title: 'Số đơn'"),
    ("title: 'B? l?c'", "title: 'Bộ lọc'"),
    ("'Chua l?c'", "'Chưa lọc'"),
    ("return 'Toàn b?'", "return 'Toàn bộ'"),
    ("(label: 'Toàn b?'", "(label: 'Toàn bộ'"),
    ("return 'T?t c? NV'", "return 'Tất cả NV'"),
    ("'T?t c? nhân viên'", "'Tất cả nhân viên'"),
    ("'Chi ti?t don ngh? phép'", "'Chi tiết đơn nghỉ phép'"),
    ("'Ngh? phép theo pháp lu?t'", "'Nghỉ phép theo pháp luật'"),
    ("title: 'H?y don ngh? phép'", "title: 'Hủy đơn nghỉ phép'"),
    ("content: 'B?n có ch?c ch?n mu?n h?y don ngh? phép này?'", "content: 'Bạn có chắc chắn muốn hủy đơn nghỉ phép này?'"),
    ("'Đã h?y don ngh? phép'", "'Đã hủy đơn nghỉ phép'"),
    ("'Đã duy?t don ngh? phép'", "'Đã duyệt đơn nghỉ phép'"),
    ("'T? ch?i don ngh? phép'", "'Từ chối đơn nghỉ phép'"),
    ("'Phép duy?t nhung v?n tính công'", "'Phép duyệt nhưng vẫn tính công'"),
    ("'Không ghi \"Phép\" trên b?ng chấm công'", "'Không ghi \"Phép\" trên bảng chấm công'"),
    ("'Có · không ghi Phép trên ch?m công'", "'Có · không ghi Phép trên chấm công'"),
    ("'Đã tr? phép nam'", "'Đã trừ phép năm'"),
    ("'Phép nam'", "'Phép năm'"),
    ("'Phép năm còn:", "'Phép năm còn:"),
    ("'S? tr? $daysNeeded ngày phép năm. Còn l?i:", "'Sẽ trừ $daysNeeded ngày phép năm. Còn lại:"),
    ("'S? ngày'", "'Số ngày'"),
    ("' (N?a ca)'", "' (Nửa ca)'"),
    ("'Ca làm vi?c'", "'Ca làm việc'"),
    ("'Ngu?i thay'", "'Người thay'"),
    ("'Ngày t?o'", "'Ngày tạo'"),
    ("'Hi?n th? ", "'Hiển thị "),
    ("Text('Hi?n th?:'", "Text('Hiển thị:'"),
    ("label: 'S?a'", "label: 'Sửa'"),
    ("label: 'H?y'", "label: 'Hủy'"),
    ("label: 'Duy?t'", "label: 'Duyệt'"),
    ("label: 'T? ch?i'", "label: 'Từ chối'"),
    ("child: const Text('H?y')", "child: const Text('Hủy')"),
    ("child: const Text('Duy?t')", "child: const Text('Duyệt')"),
    ("'Xác nh?n duy?t don này?'", "'Xác nhận duyệt đơn này?'"),
    ("'Vui lòng nh?p lý do t? ch?i:'", "'Vui lòng nhập lý do từ chối:'"),
    ("hintText: 'Lý do t? ch?i...'", "hintText: 'Lý do từ chối...'"),
    ("title: 'Thi?u thông tin'", "title: 'Thiếu thông tin'"),
    ("message: 'Vui lòng nh?p lý do t? ch?i'", "message: 'Vui lòng nhập lý do từ chối'"),
    ("'L?i khi", "'Lỗi khi"),
    ("'Đã t? chối don ngh? phép'", "'Đã từ chối đơn nghỉ phép'"),
    ("'Đã xóa don ngh? phép'", "'Đã xóa đơn nghỉ phép'"),
    ("'Đã hoàn tác tr?ng thái don'", "'Đã hoàn tác trạng thái đơn'"),
    (
        "'B?n có ch?c ch?n mu?n hoàn tác tr?ng thái don ngh? phép này v? Ch? duy?t?\\nH? th?ng s? khôi ph?c l?ch làm vi?c n?u don dã du?c duy?t.'",
        "'Bạn có chắc chắn muốn hoàn tác trạng thái đơn nghỉ phép này về Chờ duyệt?\\nHệ thống sẽ khôi phục lịch làm việc nếu đơn đã được duyệt.'",
    ),
    (
        "'M?i ngày ngh? ch? m?t ch? d? — không v?a luong DN v?a tr? c?p BHXH.\\n'",
        "'Mỗi ngày nghỉ chỉ một chế độ — không vừa lương DN vừa trợ cấp BHXH.\\n'",
    ),
    (
        "'Ca ngh?: theo Thi?t l?p luong. Ngu?i thay ca: cùng phòng ban.'",
        "'Ca nghỉ: theo Thiết lập lương. Người thay ca: cùng phòng ban.'",
    ),
    ("'1. Doanh nghi?p tr? luong\\n'", "'1. Doanh nghiệp trả lương\\n'"),
    (
        "'   Phép nam, l?, vi?c riêng có luong, ngh? bù, ?m dùng phép nam.\\n\\n'",
        "'   Phép năm, lễ, việc riêng có lương, nghỉ bù, ốm dùng phép năm.\\n\\n'",
    ),
    ("'2. Không hu?ng luong\\n'", "'2. Không hưởng lương\\n'"),
    (
        "'   Vi?c riêng không luong, ngh? dài h?n không luong.\\n\\n'",
        "'   Việc riêng không lương, nghỉ dài hạn không lương.\\n\\n'",
    ),
    ("'3. BHXH & d?c bi?t\\n'", "'3. BHXH & đặc biệt\\n'"),
    (
        "'   ?m hu?ng BHXH (c?n gi?y ngh?), thai s?n DN + d?i soát BHXH.\\n\\n'",
        "'   Ốm hưởng BHXH (cần giấy nghỉ), thai sản DN + đối soát BHXH.\\n\\n'",
    ),
    ("return 'Chua có ngày ngh?'", "return 'Chưa có ngày nghỉ'"),
    ("' · n?a ca'", "' · nửa ca'"),
    ("return '$startStr ? ${fmt.format", "return '$startStr → ${fmt.format"),
    ("} ? ${DateFormat", "} → ${DateFormat"),
    ("'Các don ngh? phép s? hi?n th? t?i dây'", "'Các đơn nghỉ phép sẽ hiển thị tại đây'"),
    ("label: Text('Thao tác')", "label: Text('Thao tác')"),
    ("1: 'L? t?t'", "1: 'Nghỉ lễ, Tết'"),
    ("2: 'VR c", "2: 'Việc riêng c"),
    ("3: 'VR kh", "3: 'Việc riêng kh"),
    ("4: '?m dau'", "4: 'Nghỉ ốm'"),
    ("5: 'Thai s?n'", "5: 'Thai sản'"),
    ("6: 'Ngh? bù'", "6: 'Nghỉ bù'"),
    ("7: 'Ngh? dài h?n'", "7: 'Nghỉ dài hạn'"),
    ("'Lo?i ngh?'", "'Loại nghỉ'"),
    ("'Chi tr?'", "'Chi trả'"),
    ("'Gi?y BHXH'", "'Giấy BHXH'"),
    ("'Tính công'", "'Tính công'"),
    ("Text('Duy?t don ngh? phép')", "Text('Duyệt đơn nghỉ phép')"),
    ("confirmText: 'H?y don'", "confirmText: 'Hủy đơn'"),
    ("confirmLabel: 'T? ch?i'", "confirmLabel: 'Từ chối'"),
    ("title: 'Hoàn tác duy?t'", "title: 'Hoàn tác duyệt'"),
    ("title: 'Xóa don ngh? phép'", "title: 'Xóa đơn nghỉ phép'"),
    (
        "'B?n có ch?c ch?n mu?n xóa vinh vi?n don ngh? phép này?\\nHành d?ng này kh?ng th? hoàn tác.'",
        "'Bạn có chắc chắn muốn xóa vĩnh viễn đơn nghỉ phép này?\\nHành động này không thể hoàn tác.'",
    ),
]
for old, new in sorted(fixes, key=lambda x: -len(x[0])):
    text = text.replace(old, new)

text = text.replace("Tiến tr\u0301nh", "Tiến trình")

# --- phase 2: remove maybeWrap, add Theme wrapper ---
text = text.replace("import '../widgets/hrm_pushed_screen_shell.dart';\n", "")
if "import '../utils/vietnamese_font.dart';" not in text:
    text = text.replace(
        "import '../utils/navigation_notifier.dart';\n",
        "import '../utils/navigation_notifier.dart';\nimport '../utils/vietnamese_font.dart';\n",
    )

old_wrap = """    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: HrmPushedScreenShell.maybeWrap(
        context,
        title: _l10n.leaveManagement,
        child: Column(
        children: ["""
new_wrap = """    return Theme(
      data: vietnameseThemeOverlay(context),
      child: Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: Column(
        children: ["""
text = text.replace(old_wrap, new_wrap)
text = text.replace(
    """        ],
      ),
      ),
    );
  }

  List<Widget> _leavePageHeaderSections""",
    """        ],
      ),
      ),
    );
  }

  List<Widget> _leavePageHeaderSections""",
)

# --- phase 3: approval step status helper ---
helper = """
  static String _approvalStepStatusLabel(int status) {
    switch (status) {
      case 1:
        return 'Đã phê duyệt';
      case 2:
        return 'Từ chối';
      case 3:
        return 'Đã hủy';
      default:
        return 'Chờ duyệt';
    }
  }

"""
text = text.replace(
    "  // ---------------------------------------------------\n  // HELPERS\n  // ---------------------------------------------------\n  static _StatusInfo _getStatusInfo",
    "  // ---------------------------------------------------\n  // HELPERS\n  // ---------------------------------------------------" + helper + "  static _StatusInfo _getStatusInfo",
)

# --- phase 4: timeline status label ---
old_timeline = """                          if (actualUser.isNotEmpty && stepStatus != 0)
                            Text('Thực hiện: $actualUser',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600)),
                          if (actionDate != null)"""
new_timeline = """                          if (actualUser.isNotEmpty && stepStatus != 0)
                            Text('Thực hiện: $actualUser',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600)),
                          if (stepStatus != 0)
                            Text(
                              _approvalStepStatusLabel(stepStatus is int
                                  ? stepStatus
                                  : int.tryParse('$stepStatus') ?? 0),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: dotColor,
                              ),
                            ),
                          if (actionDate != null)"""
text = text.replace(old_timeline, new_timeline)

# --- phase 5: detail dialog theme ---
text = text.replace(
    """    showDialog(
      context: context,
      builder: (context) {
        if (isMobile) {""",
    """    showDialog(
      context: context,
      builder: (context) => Theme(
        data: vietnameseThemeOverlay(context),
        child: Builder(
          builder: (context) {
        if (isMobile) {""",
    1,
)

# Close Theme/Builder at end of showDialog - find desktop dialog closing
# The showDialog ends before next method - add closing parens before `  Future<void> _showLeaveFormDialog`
text = text.replace(
    """      },
    );
  }

  Future<void> _showLeaveFormDialog""",
    """      },
        ),
      ),
    );
  }

  Future<void> _showLeaveFormDialog""",
    1,
)

p.write_text(text, encoding="utf-8", newline="\n")

# verify key strings
out = p.read_text(encoding="utf-8")
keys = ["Đã duyệt", "Tiến trình duyệt", "Lịch sử phê duyệt", "cấp", "Thực hiện", "_approvalStepStatusLabel", "vietnameseThemeOverlay"]
for k in keys:
    assert k in out, f"missing {k}"
assert "HrmPushedScreenShell" not in out
assert "duy?t" not in out
assert "c?p" not in out
print("OK - leave_screen.dart fully fixed")
