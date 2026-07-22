#!/usr/bin/env python3
"""Full fix for leave_screen.dart: encoding + remove duplicate back bar."""
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "lib/screens/leave_screen.dart"
text = p.read_bytes().decode("cp1258")
text = text.replace("\r\n", "\n")

fixes = [
    ("T?ng quan & b? l?c", "Tổng quan & bộ lọc"),
    ("Quy d?nh ngh? phép", "Quy định nghỉ phép"),
    ("'L? t?t'", "'Nghỉ lễ, Tết'"),
    ("1: 'L? t?t'", "1: 'Nghỉ lễ, Tết'"),
    ("2: 'VR c", "2: 'Việc riêng c"),
    ("3: 'VR kh", "3: 'Việc riêng kh"),
    ("4: '?m dau'", "4: 'Nghỉ ốm'"),
    ("5: 'Thai s?n'", "5: 'Thai sản'"),
    ("6: 'Ngh? bù'", "6: 'Nghỉ bù'"),
    ("7: 'Ngh? dài h?n'", "7: 'Nghỉ dài hạn'"),
    ("return 'Toàn b?'", "return 'Toàn bộ'"),
    ("return 'T?t c? NV'", "return 'Tất cả NV'"),
    ("'T?t c? nhân viên'", "'Tất cả nhân viên'"),
    ("title: 'Lo?i ngh?'", "title: 'Loại nghỉ'"),
    ("title: 'Tr?ng thái'", "title: 'Trạng thái'"),
    ("title: 'Th?i gian'", "title: 'Thời gian'"),
    ("(label: 'Toàn b?'", "(label: 'Toàn bộ'"),
    ("title: 'S? don'", "title: 'Số đơn'"),
    ("title: 'B? l?c'", "title: 'Bộ lọc'"),
    ("'Chua l?c'", "'Chưa lọc'"),
    ("'Các don ngh? phép s? hi?n th? t?i dây'", "'Các đơn nghỉ phép sẽ hiển thị tại đây'"),
    ("} ? ${DateFormat", "} → ${DateFormat"),
    ("'Hi?n th? ", "'Hiển thị "),
    ("Text('Hi?n th?:'", "Text('Hiển thị:'"),
    ("return 'Chua có ngày ngh?'", "return 'Chưa có ngày nghỉ'"),
    ("' · n?a ca'", "' · nửa ca'"),
    ("return '$startStr ? ${fmt.format", "return '$startStr → ${fmt.format"),
    ("label: 'S?a'", "label: 'Sửa'"),
    ("label: 'H?y'", "label: 'Hủy'"),
    ("label: 'Duy?t'", "label: 'Duyệt'"),
    ("'Duy?t $approvalStep", "'Duyệt $approvalStep"),
    ("'Lo?i ngh?'", "'Loại nghỉ'"),
    ("'Chi tr?'", "'Chi trả'"),
    ("'Gi?y BHXH'", "'Giấy BHXH'"),
    ("'Tính công'", "'Tính công'"),
    ("'Có · không ghi Phép trên ch?m công'", "'Có · không ghi Phép trên chấm công'"),
    ("'Đã tr? phép nam'", "'Đã trừ phép năm'"),
    ("'Đă tr? phép năm'", "'Đã trừ phép năm'"),
    ("'T? ngày'", "'Từ ngày'"),
    ("'Đ?n ngày'", "'Đến ngày'"),
    ("'S? ngày'", "'Số ngày'"),
    ("' (N?a ca)'", "' (Nửa ca)'"),
    ("'Ca làm vi?c'", "'Ca làm việc'"),
    ("'Ngu?i thay'", "'Người thay'"),
    ("'Lý do'", "'Lý do'"),
    ("'Lư do'", "'Lý do'"),
    ("'Lý do t? ch?i'", "'Lý do từ chối'"),
    ("'Lư do t? ch?i'", "'Lý do từ chối'"),
    ("'Ngày t?o'", "'Ngày tạo'"),
    ("'C?p nh?t'", "'Cập nhật'"),
    ("'Ti?n trình duy?t:", "'Tiến trình duyệt:"),
    ("'Lịch sử phê duy?t'", "'Lịch sử phê duyệt'"),
    ("'Phân công:", "'Phân công:"),
    ("'Thực hiện:", "'Thực hiện:"),
    ("'Chi ti?t don ngh? phép'", "'Chi tiết đơn nghỉ phép'"),
    ("'Ngh? phép theo pháp lu?t'", "'Nghỉ phép theo pháp luật'"),
    ("'1. Doanh nghi?p tr? lương\\n'", "'1. Doanh nghiệp trả lương\\n'"),
    ("'1. Doanh nghi?p tr? luong\\n'", "'1. Doanh nghiệp trả lương\\n'"),
    (
        "'   Phép năm, l?, vi?c riêng có lương, ngh? bù, ?m dùng phép năm.\\n\\n'",
        "'   Phép năm, lễ, việc riêng có lương, nghỉ bù, ốm dùng phép năm.\\n\\n'",
    ),
    (
        "'   Phép nam, l?, vi?c riêng có luong, ngh? bù, ?m dùng phép nam.\\n\\n'",
        "'   Phép năm, lễ, việc riêng có lương, nghỉ bù, ốm dùng phép năm.\\n\\n'",
    ),
    ("'2. Không hưởng lương\\n'", "'2. Không hưởng lương\\n'"),
    ("'2. Không hu?ng luong\\n'", "'2. Không hưởng lương\\n'"),
    (
        "'   Vi?c riêng không lương, ngh? dài h?n không lương.\\n\\n'",
        "'   Việc riêng không lương, nghỉ dài hạn không lương.\\n\\n'",
    ),
    (
        "'   Vi?c riêng không luong, ngh? dài h?n không luong.\\n\\n'",
        "'   Việc riêng không lương, nghỉ dài hạn không lương.\\n\\n'",
    ),
    ("'3. BHXH & d?c bi?t\\n'", "'3. BHXH & đặc biệt\\n'"),
    (
        "'   ?m hưởng BHXH (c?n gi?y ngh?), thai s?n DN + d?i soát BHXH.\\n\\n'",
        "'   Ốm hưởng BHXH (cần giấy nghỉ), thai sản DN + đối soát BHXH.\\n\\n'",
    ),
    (
        "'   ?m hu?ng BHXH (c?n gi?y ngh?), thai s?n DN + d?i soát BHXH.\\n\\n'",
        "'   Ốm hưởng BHXH (cần giấy nghỉ), thai sản DN + đối soát BHXH.\\n\\n'",
    ),
    (
        "'M?i ngày ngh? ch? m?t ch? d? — không v?a lương DN v?a tr? c?p BHXH.\\n'",
        "'Mỗi ngày nghỉ chỉ một chế độ — không vừa lương DN vừa trợ cấp BHXH.\\n'",
    ),
    (
        "'M?i ngày ngh? ch? m?t ch? d? — không v?a luong DN v?a tr? c?p BHXH.\\n'",
        "'Mỗi ngày nghỉ chỉ một chế độ — không vừa lương DN vừa trợ cấp BHXH.\\n'",
    ),
    (
        "'Ca ngh?: theo Thi?t l?p lương. Người thay ca: cùng phòng ban.'",
        "'Ca nghỉ: theo Thiết lập lương. Người thay ca: cùng phòng ban.'",
    ),
    (
        "'Ca ngh?: theo Thi?t l?p luong. Ngu?i thay ca: cùng phòng ban.'",
        "'Ca nghỉ: theo Thiết lập lương. Người thay ca: cùng phòng ban.'",
    ),
    (
        "'Ca ngh?: theo Thi?t l?p luong. Ngu?i thay ca: cùng pḥng ban.'",
        "'Ca nghỉ: theo Thiết lập lương. Người thay ca: cùng phòng ban.'",
    ),
    ("title: 'H?y don ngh? phép'", "title: 'Hủy đơn nghỉ phép'"),
    ("title: 'Hủy đơn ngh? phép'", "title: 'Hủy đơn nghỉ phép'"),
    ("content: 'B?n có ch?c ch?n mu?n h?y don ngh? phép này?'", "content: 'Bạn có chắc chắn muốn hủy đơn nghỉ phép này?'"),
    ("confirmText: 'H?y don'", "confirmText: 'Hủy đơn'"),
    ("'Đã h?y don ngh? phép'", "'Đã hủy đơn nghỉ phép'"),
    ("'Đă h?y don ngh? phép'", "'Đã hủy đơn nghỉ phép'"),
    ("'L?i khi h?y don'", "'Lỗi khi hủy đơn'"),
    ("title: 'Hoàn tác duy?t'", "title: 'Hoàn tác duyệt'"),
    (
        "'B?n có ch?c ch?n mu?n hoàn tác tr?ng thái don ngh? phép này v? Ch? duy?t?\\nH? th?ng s? khôi ph?c l?ch làm vi?c n?u don dã du?c duy?t.'",
        "'Bạn có chắc chắn muốn hoàn tác trạng thái đơn nghỉ phép này về Chờ duyệt?\\nHệ thống sẽ khôi phục lịch làm việc nếu đơn đã được duyệt.'",
    ),
    (
        "'B?n có ch?c ch?n mu?n hoàn tác tr?ng thái don ngh? phép này v? Ch? duy?t?\\nH? th?ng s? khôi ph?c l?ch làm vi?c n?u don dă du?c duy?t.'",
        "'Bạn có chắc chắn muốn hoàn tác trạng thái đơn nghỉ phép này về Chờ duyệt?\\nHệ thống sẽ khôi phục lịch làm việc nếu đơn đã được duyệt.'",
    ),
    ("'Đã hoàn tác tr?ng thái don'", "'Đã hoàn tác trạng thái đơn'"),
    ("title: 'Xóa don ngh? phép'", "title: 'Xóa đơn nghỉ phép'"),
    (
        "'B?n có ch?c ch?n mu?n xóa vinh vi?n don ngh? phép này?\\nHành d?ng này kh?ng th? hoàn tác.'",
        "'Bạn có chắc chắn muốn xóa vĩnh viễn đơn nghỉ phép này?\\nHành động này không thể hoàn tác.'",
    ),
    (
        "'B?n có ch?c ch?n mu?n xóa vĩnh viễn don ngh? phép này?\\nHành d?ng này không th? hoàn tác.'",
        "'Bạn có chắc chắn muốn xóa vĩnh viễn đơn nghỉ phép này?\\nHành động này không thể hoàn tác.'",
    ),
    ("'Đã xóa don ngh? phép'", "'Đã xóa đơn nghỉ phép'"),
    ("'Đă xóa don ngh? phép'", "'Đã xóa đơn nghỉ phép'"),
    ("'L?i khi xóa don'", "'Lỗi khi xóa đơn'"),
    ("Text('Duy?t don ngh? phép')", "Text('Duyệt đơn nghỉ phép')"),
    ("'Xác nh?n duy?t don này?'", "'Xác nhận duyệt đơn này?'"),
    ("'S? tr? $daysNeeded ngày phép năm. Còn l?i:", "'Sẽ trừ $daysNeeded ngày phép năm. Còn lại:"),
    ("'Phép duy?t nhung v?n tính công'", "'Phép duyệt nhưng vẫn tính công'"),
    ("'Không ghi \"Phép\" trên b?ng chấm công'", "'Không ghi \"Phép\" trên bảng chấm công'"),
    ("child: const Text('H?y')", "child: const Text('Hủy')"),
    ("child: const Text('Duy?t')", "child: const Text('Duyệt')"),
    ("'Đã duy?t don ngh? phép'", "'Đã duyệt đơn nghỉ phép'"),
    ("'L?i khi duy?t don'", "'Lỗi khi duyệt đơn'"),
    ("'T? ch?i don ngh? phép'", "'Từ chối đơn nghỉ phép'"),
    ("'Vui lòng nh?p lý do t? ch?i:'", "'Vui lòng nhập lý do từ chối:'"),
    ("'Vui ḷng nh?p lư do t? ch?i:'", "'Vui lòng nhập lý do từ chối:'"),
    ("hintText: 'Lý do t? ch?i...'", "hintText: 'Lý do từ chối...'"),
    ("title: 'Thi?u thông tin'", "title: 'Thiếu thông tin'"),
    ("message: 'Vui lòng nh?p lý do t? ch?i'", "message: 'Vui lòng nhập lý do từ chối'"),
    ("confirmLabel: 'T? ch?i'", "confirmLabel: 'Từ chối'"),
    ("'Đã t? ch?i don ngh? phép'", "'Đã từ chối đơn nghỉ phép'"),
    ("'Đă t? ch?i don ngh? phép'", "'Đã từ chối đơn nghỉ phép'"),
    ("'L?i khi t? ch?i don'", "'Lỗi khi từ chối đơn'"),
    ("'Ch? duy?t'", "'Chờ duyệt'"),
    ("'Đã duy?t'", "'Đã duyệt'"),
    ("'T? ch?i'", "'Từ chối'"),
    ("'Đã h?y'", "'Đã hủy'"),
    ("'Phép năm còn:", "'Phép năm còn:"),
    ("'Phép nam'", "'Phép năm'"),
    ("'Có lương'", "'Có lương'"),
    ("'Có luong'", "'Có lương'"),
    ("label: Text('Thao tác')", "label: Text('Thao tác')"),
    ("'Tr?ng thái'", "'Trạng thái'"),
    ("'Đã duy?t đơn ngh? phép'", "'Đã duyệt đơn nghỉ phép'"),
    (
        "'B?n có ch?c ch?n mu?n xóa vinh vi?n đơn ngh? phép này?\\nHành d?ng này không th? hoàn tác.'",
        "'Bạn có chắc chắn muốn xóa vĩnh viễn đơn nghỉ phép này?\\nHành động này không thể hoàn tác.'",
    ),
    ("lo?i ngh?", "loại nghỉ"),
    ("ngày ngh?", "ngày nghỉ"),
    ("d? dd/MM", "đủ dd/MM"),
    ("ḍng", "dòng"),
    ("don ", "đơn "),
    ("don,", "đơn,"),
    ("don)", "đơn)"),
    ("don'", "đơn'"),
    ("Đă ", "Đã "),
]

for old, new in sorted(fixes, key=lambda x: -len(x[0])):
    if old != new:
        text = text.replace(old, new)

# Remove HrmPushedScreenShell import
text = text.replace("import '../widgets/hrm_pushed_screen_shell.dart';\n", "")

# Structural: remove maybeWrap + wrap Theme
marker = "    if (_tabController == null) {"
idx = text.find(marker)
tail = text[idx:]
tail = tail.replace(
    """    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: HrmPushedScreenShell.maybeWrap(
        context,
        title: _l10n.leaveManagement,
        child: Column(
        children: [""",
    """    return Theme(
      data: vietnameseThemeOverlay(context),
      child: Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: Column(
        children: [""",
    1,
)
tail = tail.replace(
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
    1,
)
text = text[:idx] + tail

if "import '../utils/vietnamese_font.dart';" not in text:
    text = text.replace(
        "import '../utils/navigation_notifier.dart';\n",
        "import '../utils/navigation_notifier.dart';\nimport '../utils/vietnamese_font.dart';\n",
    )

p.write_text(text, encoding="utf-8", newline="\n")

# verify utf-8
out = p.read_text(encoding="utf-8")
checks = ["Tổng quan & bộ lọc", "Đến ngày", "Tiến trình duyệt", "vietnameseThemeOverlay", "HrmPushedScreenShell"]
for c in checks:
    print(c, "OK" if c in out else "MISSING", "(want MISSING for HrmPushed)" if "Hrm" in c else "")

bad = sum(1 for line in out.splitlines() if "?" in line and "'" in line and "?" not in line and "??" not in line and not any(x in line for x in ["?.", "int?", "String?", "bool?", "num?", "Widget?", "dynamic?", "TabController?", "Timer?", "Future?", "List?", "Map?", "double?", "DateTimeRange?", "StreamSubscription?", "IconData?", "VoidCallback?", "TextInputType?", "DateTime?", "WorkTaskStatus?", "AppButtonVariant?"]))
print("suspicious lines:", bad)
