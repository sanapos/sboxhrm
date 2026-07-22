#!/usr/bin/env python3
"""Complete leave_screen.dart fix - encoding + UI + structure (Python only)."""
from pathlib import Path
import subprocess
import re

ROOT = Path(__file__).resolve().parents[1]
p = ROOT / "lib/screens/leave_screen.dart"
report = Path(__file__).resolve().parent / "fix_leave_master_report.txt"

subprocess.run(
    ["git", "checkout", "HEAD", "--", "lib/screens/leave_screen.dart"],
    cwd=ROOT,
    check=True,
)

text = p.read_bytes().decode("cp1258").replace("\r\n", "\n")

fixes = [
    ("T?ng quan & b? l?c", "Tổng quan & bộ lọc"),
    ("Quy d?nh ngh? phép", "Quy định nghỉ phép"),
    ("'Đã duy?t'", "'Đã duyệt'"),
    ("'Đã h?y'", "'Đã hủy'"),
    ("'Duy?t $approvalStep/$approvalLevels c?p'", "'Duyệt $approvalStep/$approvalLevels cấp'"),
    ("'Ti?n trình duy?t: $currentStep/$totalLevels c?p'", "'Tiến trình duyệt: $currentStep/$totalLevels cấp'"),
    ("'L?ch s? phê duy?t'", "'Lịch sử phê duyệt'"),
    ("'C?p ${record['stepOrder'] ?? idx + 1}'", "'Cấp ${record['stepOrder'] ?? idx + 1}'"),
    ("'Th?c hi?n: $actualUser'", "'Thực hiện: $actualUser'"),
    ("'${leave['currentApprovalStep'] ?? 0}/${leave['totalApprovalLevels']} c?p'", "'${leave['currentApprovalStep'] ?? 0}/${leave['totalApprovalLevels']} cấp'"),
    ("'Ch? duy?t'", "'Chờ duyệt'"),
    ("title: 'L?i'", "title: 'Lỗi'"),
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
    ("'Tr?ng thái'", "'Trạng thái'"),
    ("'Lý do'", "'Lý do'"),
    ("'Nhân viên'", "'Nhân viên'"),
    ("'Lo?i ngh?'", "'Loại nghỉ'"),
    ("'Chi tr?'", "'Chi trả'"),
    ("'Gi?y BHXH'", "'Giấy BHXH'"),
    ("'Tính công'", "'Tính công'"),
    ("'?ã phê duy?t'", "'Đã phê duyệt'"),
    ("'?ã duy?t'", "'Đã duyệt'"),
    ("'?ã h?y'", "'Đã hủy'"),
    ("'T? ch?i'", "'Từ chối'"),
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
    ("1: 'L? t?t'", "1: 'Nghỉ lễ, Tết'"),
    ("2: 'VR c", "2: 'Việc riêng c"),
    ("3: 'VR kh", "3: 'Việc riêng kh"),
    ("4: '?m dau'", "4: 'Nghỉ ốm'"),
    ("5: 'Thai s?n'", "5: 'Thai sản'"),
    ("6: 'Ngh? bù'", "6: 'Nghỉ bù'"),
    ("7: 'Ngh? dài h?n'", "7: 'Nghỉ dài hạn'"),
    ("Text('Duy?t don ngh? phép')", "Text('Duyệt đơn nghỉ phép')"),
    ("confirmText: 'H?y don'", "confirmText: 'Hủy đơn'"),
    ("confirmLabel: 'T? ch?i'", "confirmLabel: 'Từ chối'"),
    ("title: 'Hoàn tác duy?t'", "title: 'Hoàn tác duyệt'"),
    ("title: 'Xóa don ngh? phép'", "title: 'Xóa đơn nghỉ phép'"),
    (
        "'B?n có ch?c ch?n mu?n xóa vinh vi?n don ngh? phép này?\\nHành d?ng này kh?ng th? hoàn tác.'",
        "'Bạn có chắc chắn muốn xóa vĩnh viễn đơn nghỉ phép này?\\nHành động này không thể hoàn tác.'",
    ),
    ("'Đóng'", "'Đóng'"),
    ("'Phân công: $assignedUser'", "'Phân công: $assignedUser'"),
]

missing = []
for old, new in sorted(fixes, key=lambda x: -len(x[0])):
    if old not in text:
        missing.append(old[:80])
    text = text.replace(old, new)

text = text.replace("Tiến tr\u0301nh", "Tiến trình")

# Remove HrmPushedScreenShell, add Theme
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
if old_wrap not in text:
    raise SystemExit("maybeWrap block not found")
text = text.replace(old_wrap, new_wrap)

# approval helper
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
marker = "  // ---------------------------------------------------\n  // HELPERS\n  // ---------------------------------------------------\n  static _StatusInfo _getStatusInfo"
if "_approvalStepStatusLabel" not in text:
    text = text.replace(marker, marker.replace("  static _StatusInfo", helper + "  static _StatusInfo", 1))

# timeline label
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
if old_timeline in text:
    text = text.replace(old_timeline, new_timeline)

# detail dialog theme wrap
old_dialog = """    showDialog(
      context: context,
      builder: (context) {
        if (isMobile) {"""
new_dialog = """    showDialog(
      context: context,
      builder: (context) => Theme(
        data: vietnameseThemeOverlay(context),
        child: Builder(
          builder: (context) {
        if (isMobile) {"""
if old_dialog not in text:
    raise SystemExit("showDialog block not found")
text = text.replace(old_dialog, new_dialog, 1)

# close Theme/Builder before _detailRow
old_close = """      },
    );
  }

  // ignore: unused_element
  Widget _detailRow"""
new_close = """          },
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _detailRow"""
if old_close not in text:
    raise SystemExit("dialog close block not found")
text = text.replace(old_close, new_close, 1)

p.write_text(text, encoding="utf-8", newline="\n")

# --- phase 2: broad substring cleanup (cp1258 edge cases) ---
out = p.read_text(encoding="utf-8")
phase2 = [
    ("Đă ", "Đã "),
    ("dă du?c", "đã được"),
    ("duy?t", "duyệt"),
    ("c?p", "cấp"),
    ("ch?m công", "chấm công"),
    ("b?ng ch", "bảng ch"),
    ("tr?ng th", "trạng th"),
    ("tr? phép", "trừ phép"),
    ("Lư do", "Lý do"),
    ("lư do", "lý do"),
    ("ḷng nh?p", "lòng nhập"),
    ("Vui ḷng", "Vui lòng"),
    ("Ti?n trình", "Tiến trình"),
    ("Tiến tr\u0301nh", "Tiến trình"),
    ("Ti?n tr\u0301nh", "Tiến trình"),
    ("phép nam", "phép năm"),
    ("Phép nam", "Phép năm"),
    (" don ", " đơn "),
    (" don'", " đơn'"),
    ("ngh? ph", "nghỉ ph"),
    ("ngh?:", "nghỉ:"),
    ("Thi?t l?p", "Thiết lập"),
    ("l?p luong", "lập lương"),
    ("Ngu?i", "Người"),
    ("ph\u0323ng", "phòng"),
    ("c\u0323n l?i", "còn lại"),
    ("S? tr?", "Sẽ trừ"),
    ("B?n có ch?c ch?n mu?n", "Bạn có chắc chắn muốn"),
    ("vinh vi?n", "vĩnh viễn"),
    ("Hành d?ng", "Hành động"),
    ("kh?ng th?", "không thể"),
    ("v? Ch?", "về Chờ"),
    ("H? th?ng s?", "Hệ thống sẽ"),
    ("n?u đơn", "nếu đơn"),
    ("n?u don", "nếu đơn"),
    ("t? ch?i", "từ chối"),
    ("T? ch?i", "Từ chối"),
    ("Ch? duyệt", "Chờ duyệt"),
    ("h?y đơn", "hủy đơn"),
    ("h?y don", "hủy đơn"),
    ("L?i khi", "Lỗi khi"),
    ("L?ch s?", "Lịch sử"),
    ("Th?c hi?n", "Thực hiện"),
    ("Tr?ng thái", "Trạng thái"),
    ("Lo?i ngh?", "Loại nghỉ"),
    ("C?p nh?t", "Cập nhật"),
    ("?m dau", "Nghỉ ốm"),
    ("?m hu?ng", "Ốm hưởng"),
    ("d?c bi?t", "đặc biệt"),
    ("d?i soát", "đối soát"),
    ("gi?y ngh?", "giấy nghỉ"),
    ("c?n gi?y", "cần giấy"),
    ("thai s?n", "thai sản"),
    ("hu?ng lương", "hưởng lương"),
    ("Doanh nghi?p tr?", "Doanh nghiệp trả"),
    ("M?i ngày ngh?", "Mỗi ngày nghỉ"),
    ("ch? m?t ch? d?", "chỉ một chế độ"),
    ("v?a lương", "vừa lương"),
    ("tr? c?p", "trợ cấp"),
    ("nh?p lý", "nhập lý"),
    ("Xác nh?n", "Xác nhận"),
    ("nhung v?n", "nhưng vẫn"),
    ("C\u0323n ", "Còn "),
    ("c\u0323n:", "còn:"),
]
for a, b in sorted(phase2, key=lambda x: -len(x[0])):
    out = out.replace(a, b)
p.write_text(out, encoding="utf-8", newline="\n")

# verify
out = p.read_text(encoding="utf-8")
issues = []
for pat in ["duy?t", "c?p", "HrmPushedScreenShell", "Đă "]:
    if pat in out:
        issues.append(f"still has {pat}")
keys = ["Đã duyệt", "Tiến trình duyệt", "Lịch sử phê duyệt", "_approvalStepStatusLabel", "vietnameseThemeOverlay"]
for k in keys:
    if k not in out:
        issues.append(f"missing {k}")

# suspicious literals with ? (not dart syntax)
for i, line in enumerate(out.splitlines(), 1):
    for m in re.finditer(r"'([^'\\]|\\.)*'", line):
        s = m.group(0)
        if "?" in s and "??" not in s and "?." not in s and "${" not in s:
            if not (s.endswith("?'") or s.endswith("?'")):
                if "?" in s[1:-1]:
                    issues.append(f"L{i}: {s[:60]}")

report.write_text(
    "missing fixes:\n" + "\n".join(missing[:30]) + "\n\nissues:\n" + "\n".join(issues[:40]),
    encoding="utf-8",
)
if issues:
    raise SystemExit(f"verification failed: {len(issues)} issues, see report")
print("OK")
