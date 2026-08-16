#!/usr/bin/env python3
"""Deep-fix English UI map: domain terms, missing POS/permission keys, fragments.

Source UI stays Vietnamese. This map is what tr() uses when locale is English.
Machine translation often maps duyệt→browse, phiếu→vote, báo bếp→newspaper —
those mix meaning and leave leftover Vietnamese (fragment replace is all-or-nothing).
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CLIENT_LIB = HERE.parent / "lib"
POS_LIB = HERE.parents[1] / "flutter_pos" / "lib"
JSON_PATH = HERE / "en_ui_map.json"
VN_SRC = HERE / "vn_strings.json"

VN = re.compile(
    r"[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ"
    r"ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ]"
)
STR = re.compile(r"'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"")
TR_CALL = re.compile(r"\btr(?:N|Or)?\(\s*'((?:[^'\\\n]|\\.)*)'")
EXPR = re.compile(r"\$\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}|\$[A-Za-z_][A-Za-z0-9_]*")

# Exact overrides — win over machine translation.
CURATED: dict[str, str] = {
    # ── POS modules / menus ──
    "Ca thu ngân": "Cashier shift",
    "Ca thu ngân (mở ca / đóng két)": "Cashier shift (open / close drawer)",
    "QR order bàn": "QR table order",
    "Màn hình bếp (KDS)": "Kitchen display (KDS)",
    "Máy in POS": "POS printers",
    "Máy in (thiết bị)": "Device printers",
    "Máy in & mẫu in": "Printers & templates",
    "Hóa đơn điện tử": "E-invoice",
    "Hóa đơn điện tử POS": "POS e-invoice",
    "Bán hàng POS (Order / Thu ngân)": "POS sell (order / cashier)",
    "Hàng hóa POS": "POS products",
    "Mẫu in POS": "POS print templates",
    "Đơn hàng POS": "POS orders",
    "Kiểm kho POS": "POS stock count",
    "Xuất hủy POS": "POS damage issue",
    "Báo cáo doanh thu POS": "POS sales report",
    "Đặt bàn / lịch hẹn": "Reservations / appointments",
    "Đặt bàn / đặt phòng / lịch hẹn": "Tables / rooms / appointments",
    "Khách hàng POS": "POS customers",
    "Bảo hành POS": "POS warranty",
    "Màn hình phụ POS": "POS customer display",
    "Màn hình phụ": "Customer display",
    "Nhiều hơn": "More",
    "Trung tâm Kho": "Warehouse hub",
    "Hoá đơn": "Invoices",
    "Lịch sử hủy / trả": "Cancel / return history",
    "Cuối ngày": "End of day",
    "Hàng hoá": "Products",
    "Bảng giá": "Price lists",
    "Tra cứu BH": "Warranty lookup",
    "Dùng nội bộ": "Internal use",
    "Công nợ KH": "Customer debt",
    "Thiết lập POS": "POS setup",
    "Thiết lập HRM / POS": "HRM / POS setup",
    "Ngành hàng": "Industry",
    "Ngành hàng & bán hàng": "Industry & selling",
    "Thiết lập cửa hàng": "Store setup",
    "Báo cáo bán hàng": "Sales report",
    "Báo cáo hàng hóa": "Goods report",
    "Phân tích kinh doanh": "Business analysis",
    "Lợi nhuận theo chiều": "Profit by dimension",
    "Tồn chậm / cháy hàng": "Slow / out of stock",
    "Bán theo khách": "Sales by customer",
    "Đặt chỗ / cọc": "Reservations / deposits",
    "Báo cáo chi tiết": "Detailed report",
    "Quản lý bàn / phòng": "Tables / rooms",
    "Kho hàng": "Warehouse",
    "Giao dịch": "Transactions",
    "Vào Nhiều hơn → Ca thu ngân để mở ca trước khi thanh toán":
        "Go to More → Cashier shift to open a shift before payment",
    "«Ca thu ngân (mở ca / đóng két)» rồi quay lại đây để mở ca.":
        "«Cashier shift (open / close drawer)» then come back here to open the shift.",
    "Đơn đang được máy khác giữ.": "Order is held by another device.",
    "Đơn đang được máy khác lưu — thử lại":
        "Order is being saved on another device — try again",
    "Phiếu chưa in — máy in/Agent offline quá 5 phút. In lại từ hàng chờ.":
        "Ticket not printed — printer/Agent offline over 5 minutes. Reprint from the queue.",
    "Phiếu chưa in": "Ticket not printed",
    "Khu vực bàn được phép": "Allowed table areas",
    "Tất cả khu": "All areas",
    "Xuất HĐĐT": "Issue e-invoice",
    "Xuất HĐĐT thất bại": "E-invoice issue failed",
    "Gán máy in": "Assign printers",
    "Gán máy in theo sản phẩm": "Assign printers by product",
    "Gán máy in theo chứng từ đã lưu lên máy chủ":
        "Document printer assignment saved to the server",
    "Chip «Xuất HĐĐT» bật sẵn. Thu ngân vẫn tắt được.":
        "«Issue e-invoice» chip is on by default. Cashier can still turn it off.",
    "Báo bếp": "Kitchen ticket",
    "Báo chế biến": "Kitchen slip",
    "*** BÁO CHẾ BIẾN ***": "*** KITCHEN SLIP ***",
    "In tem khi Báo bếp / thông báo bếp": "Print labels on kitchen ticket / kitchen notify",
    "Thiết kế mẫu tem báo bếp / tem ly": "Design kitchen / cup label template",
    "Loại mẫu: Tem báo bếp (KitchenLabel)": "Type: Kitchen label (KitchenLabel)",
    "Thiết kế mẫu phiếu báo bếp": "Design kitchen slip template",
    "Loại: Phiếu chế biến (KitchenSlip) · khổ K58/K80/A5/A4":
        "Type: Kitchen slip (KitchenSlip) · size K58/K80/A5/A4",
    "Máy in nội bộ (gán Báo bếp)": "Local printer (kitchen ticket)",
    "hết hàng": "out of stock",
    "Nhỏ (0.9)": "Small (0.9)",
    "Vừa (1.0)": "Medium (1.0)",
    "Lớn (1.2)": "Large (1.2)",
    "Rất lớn (1.4)": "Extra large (1.4)",
    "MISA Invoice (sắp có)": "MISA Invoice (coming soon)",
    "1 — Hóa đơn GTGT": "1 — VAT invoice",
    "2 — Hóa đơn bán hàng": "2 — Sales invoice",
    "5 — HĐ khác": "5 — Other invoice",
    "Giá đã gồm VAT (tách thuế khi xuất)": "Price includes VAT (split tax on issue)",
    "Giá chưa VAT (cộng VAT trên đơn)": "Price excludes VAT (add VAT on the order)",
    "Không thuế / HĐ bán hàng (-2)": "No tax / sales invoice (-2)",

    # ── Permission action labels ──
    "Vào bán": "Open sell",
    "Xem trả hàng": "View returns",
    "Vào bếp": "Open kitchen",
    "Bump món": "Bump items",
    "Xem QR": "View QR",
    "In / bật QR": "Print / enable QR",
    "Xem ca": "View shift",
    "Mở / đóng ca": "Open / close shift",
    "Xem máy in": "View printers",
    "Xem HĐĐT": "View e-invoice",
    "Xuất HĐĐT Viettel cho đơn": "Issue Viettel e-invoice for order",

    # ── Permission module labels ──
    "Tổng quan (cũ)": "Overview (legacy)",
    "Tổng quan chấm công": "Attendance overview",
    "Chỉ số nhân sự & vận hành": "HR & operations metrics",
    "Lịch làm việc hôm nay": "Today's schedule",
    "Chấm công thời gian thực": "Realtime attendance",
    "Nhân viên vắng mặt": "Absent employees",
    "Đi trễ / về sớm": "Late / early leave",
    "KPI (Dashboard)": "KPI (Dashboard)",
    "Bản tin nội bộ": "Internal news",
    "Nhân sự chấm công": "Attendance staff",
    "Phiếu lương": "Payslip",
    "Tài liệu HR": "HR documents",
    "Sơ đồ tổ chức": "Org chart",
    "Chấm công thô": "Raw attendance",
    "Tổng hợp chấm công theo ca": "Attendance by shift",
    "Đi trễ / Về sớm": "Late / early leave",
    "Báo cáo đi đường": "Travel-hours report",
    "Chỉnh sửa chấm công": "Attendance correction",
    "Duyệt chấm công": "Attendance approval",
    "Duyệt chấm công Mobile": "Mobile attendance approval",
    "Duyệt lịch làm việc": "Schedule approval",
    "Tổng hợp lương": "Payroll summary",
    "Đăng ký chấm công Mobile": "Mobile attendance registration",
    "Chấm công Mobile": "Mobile attendance",
    "Chấm cơm": "Meal punch",
    "Bản đồ nhân sự": "Staff map",
    "Sổ sách HKD": "Household-business books",
    "Phiếu thưởng": "Bonus tickets",
    "Phiếu phạt": "Penalty tickets",
    "Ứng lương": "Salary advance",
    "Công tác phí": "Business-trip expense",
    "Thu chi": "Cash in/out",
    "Tài khoản ngân hàng": "Bank accounts",
    "Phản ánh / Ý kiến": "Feedback",
    "Báo cáo chấm công": "Attendance report",
    "Báo cáo nghỉ phép": "Leave report",
    "Báo cáo thu chi": "Cash report",
    "Báo cáo phạt": "Penalty report",
    "Báo cáo ứng lương": "Advance report",
    "Báo cáo công tác phí": "Business-trip report",
    "Báo cáo tài sản": "Asset report",
    "Thiết lập HRM": "HRM setup",
    "Thiết lập ca": "Shift setup",
    "Ngày lễ": "Holidays",
    "Máy chấm công": "Attendance devices",
    "Phụ cấp": "Allowances",
    "Phạt": "Penalties",
    "Bảo hiểm": "Insurance",
    "Thuế TNCN": "PIT tax",
    "Lương sản phẩm": "Piece-rate pay",
    "Vùng chấm công": "Geofence",
    "Tài khoản": "Accounts",
    "Phân quyền": "Permissions",
    "PQ Phòng ban": "Department permissions",
    "Hệ thống": "System",
    "Thiết lập thông báo": "Notification setup",
    "Thiết lập AI": "AI setup",
    "Ca làm việc (API)": "Work shift (API)",
    "Mẫu ca (API)": "Shift template (API)",
    "Bậc lương ca (API)": "Shift pay grade (API)",
    "Phúc lợi (API)": "Benefits (API)",
    "Giao dịch (API)": "Transactions (API)",
    "Báo cáo (cũ)": "Reports (legacy)",

    # ── Domain: approve / reject / slip (not browse / refuse / vote) ──
    " (duyệt)": "(approve)",
    " (từ chối)": "(reject)",
    " (chờ)": "(pending)",
    " (tạo phiếu chi)": "(create payment voucher)",
    "duyệt": "approve",
    "Duyệt": "Approve",
    "Tạo & Duyệt": "Create & Approve",
    "Không thể duyệt": "Cannot approve",
    "Tự duyệt": "Self-approve",
    "Duyệt yêu cầu": "Approve request",
    "Duyệt ứng": "Approve advance",
    "Duyệt lịch làm việc": "Approve work schedule",
    "Duyệt chấm công Mobile": "Approve mobile attendance",
    "Duyệt qua 3 cấp quản lý": "Approve through 3 management levels",
    "Loại người duyệt": "Approver type",
    "Bạn có chắc muốn duyệt tất cả": "Are you sure you want to approve all",
    "duyệt tất cả": "approve all",
    "từ chối": "reject",
    "Từ chối": "Reject",
    "Đã từ chối": "Rejected",
    "Không thể từ chối": "Cannot reject",
    "Từ chối yêu cầu": "Reject request",
    "Từ chối đăng ký": "Reject registration",
    "Đã từ chối đăng ký": "Registration rejected",
    "Từ chối nhận việc": "Reject the job",
    "Từ chối hoạch toán": "Reject posting",
    "Không từ chối được": "Cannot reject",
    "Từ chối ứng": "Reject advance",
    "Xóa phiếu": "Delete slip",
    "Phiếu trống": "Blank slip",
    "Đã lưu phiếu tạm": "Draft slip saved",
    "Tạo phiếu": "Create slip",
    "Mở phiếu": "Open slip",
    "Chưa có phiếu": "No slips yet",
    "phiếu": "slip",
    "Chọn phiếu": "Select slip",
    "Tạo phiếu XH": "Create damage-issue slip",
    "Tổng phiếu vi phạm": "Total violation tickets",
    "Hủy phiếu": "Cancel slip",
    "Phiếu nhập": "Goods receipt",
    "Phiếu chi đã được tạo.": "Payment voucher created.",
    "Phiếu thu đã được tạo.": "Receipt voucher created.",
    "X đủ công": "X has enough work days",
    "% đủ 1 công": "% completes 1 work day",
    "Công": "Work day",
    "Số công": "Work-day count",
    "Giờ công": "Work hours",
    "! thiếu chấm": "! missing punch",
    "Máy Requests": "My Requests",
    "0đ": "0đ",
    "Tiếng Việt: ĂÂÊÔƠƯ Đ": "Vietnamese: ĂÂÊÔƠƯ Đ",

    # ── Attendance / HR fragments ──
    "Thứ": "Day",
    "Lần": "Punch",
    "Giờ ca": "Shift hours",
    "Đi đường": "Travel",
    "Giờ thập phân": "Decimal hours",
    "Trễ (p)": "Late (m)",
    "Sớm (p)": "Early (m)",
    "Tái phạm": "Repeat",
    "Đã phạt": "Fined",
    "Giải trình": "Explanation",
    "Thao tác": "Actions",
    "Bắt đầu": "Start",
    "Đến điểm": "Arrived",
    "Chuyến": "Trips",
    "Thiếu": "Missing",
    "Sổ khuyến nghị:": "Recommended books:",
    "Nhóm 1 — miễn GTGT/TNCN (S1a)": "Group 1 — VAT/PIT exempt (S1a)",
    "Nhóm 2 — % trên doanh thu (S2a)": "Group 2 — % of revenue (S2a)",
    "Nhóm 3 — TNCN theo thu nhập (S2b/S2c/S2d/S2e)":
        "Group 3 — PIT on income (S2b/S2c/S2d/S2e)",
    "≥ 1 phút": "≥ 1 min",
    "≥ 5 phút": "≥ 5 min",
    "≥ 10 phút": "≥ 10 min",
    "≥ 15 phút": "≥ 15 min",
    "≥ 30 phút": "≥ 30 min",
    "Mã số thuế (MST)": "Tax code (TIN)",
    "Tên hộ kinh doanh": "Household-business name",
    "Ngành nghề (ghi trên sổ doanh thu)": "Industry (on revenue book)",
    "Tỷ lệ % GTGT (S2b)": "VAT rate % (S2b)",
    "Tỷ lệ % GTGT": "VAT rate %",
    "Tỷ lệ % TNCN (trên thu nhập)": "PIT rate % (on income)",
    "Tỷ lệ % TNCN": "PIT rate %",
    "STT": "No.",
    "TT": "Status",
    "Mã": "Code",
    "Chạm để sửa / xóa": "Tap to edit / delete",
}

# PermissionModuleLabels.byModule values (already partly in CURATED).
_MODULE_LABELS = {
    "Trang chủ": "Home",
    "Thông báo": "Notifications",
    "Hồ sơ nhân sự": "HR records",
    "Phòng ban": "Departments",
    "Nghỉ phép": "Leave",
    "Thiết lập lương": "Salary setup",
    "Lịch làm việc": "Work schedule",
    "Tổng hợp chấm công": "Attendance summary",
    "Tăng ca": "Overtime",
    "Đổi ca": "Shift swap",
    "Tài sản": "Assets",
    "Công việc": "Tasks",
    "Truyền thông": "Communications",
    "Sản lượng": "Production",
    "Chi nhánh": "Branches",
    "Cài đặt": "Settings",
}


def unescape(s: str) -> str:
    body = s[1:-1]
    return (
        body.replace(r"\n", "\n")
        .replace(r"\t", "\t")
        .replace(r"\'", "'")
        .replace(r"\"", '"')
        .replace(r"\\", "\\")
    )


def extract_vn_from_lib(lib: Path) -> set[str]:
    found: set[str] = set()
    for p in lib.rglob("*.dart"):
        if "l10n" in p.parts or p.name.endswith(".bak"):
            continue
        text = p.read_text(encoding="utf-8", errors="ignore")
        for m in STR.finditer(text):
            body = unescape(m.group(0)).strip()
            if 2 <= len(body) <= 180 and VN.search(body) and "$" not in body:
                if body.startswith("package:"):
                    continue
                found.add(body)
        for m in TR_CALL.finditer(text):
            raw = m.group(1).encode().decode("unicode_escape")
            if VN.search(raw):
                if "$" in raw:
                    for part in EXPR.sub("\x00", raw).split("\x00"):
                        piece = part.strip(" \t:·•|/()[]-—,.?!%\"«»\n")
                        if len(piece) >= 2 and VN.search(piece):
                            found.add(piece)
                else:
                    found.add(raw)
    return found


def fix_machine_value(vi: str, en: str) -> str:
    """Correct systematic Google-translate mistakes from the Vietnamese key."""
    if not en or vi == en:
        return en
    low = vi.lower()

    # duyệt = approve, except trình duyệt = web browser
    if "duyệt" in low and "trình duyệt" not in low:
        en = re.sub(r"\bBrowse through\b", "Approve through", en)
        en = re.sub(r"\bBrowse by yourself\b", "Self-approve", en)
        en = re.sub(r"\bBrowser type\b", "Approver type", en)
        en = re.sub(r"\bTime Attendance Browse\b", "Attendance approval", en)
        en = re.sub(r"\b[Bb]rowse(s|d|ing)?\b", lambda m: {
            "Browse": "Approve", "browse": "approve",
            "Browses": "Approves", "browses": "approves",
            "Browsed": "Approved", "browsed": "approved",
            "Browsing": "Approving", "browsing": "approving",
        }[m.group(0)], en)

    # phiếu = slip/ticket, not vote/ballot
    if "phiếu" in low:
        if "lương" in low:
            en = re.sub(r"\b(votes?|ballots?)\b", "payslip", en, flags=re.I)
        elif "phạt" in low or "vi phạm" in low:
            en = re.sub(r"\b(votes?|ballots?)\b", "tickets", en, flags=re.I)
        elif "thưởng" in low:
            en = re.sub(r"\b(votes?|ballots?)\b", "bonus tickets", en, flags=re.I)
        elif re.search(r"phiếu thu", low):
            en = re.sub(r"\b(votes?|ballots?)\b", "receipt voucher", en, flags=re.I)
        elif re.search(r"phiếu chi", low):
            en = re.sub(r"\b(votes?|ballots?)\b", "payment voucher", en, flags=re.I)
        else:
            en = re.sub(r"\bballots\b", "slips", en, flags=re.I)
            en = re.sub(r"\bballot\b", "slip", en, flags=re.I)
            en = re.sub(r"\bvotes\b", "slips", en, flags=re.I)
            en = re.sub(r"\bvote\b", "slip", en, flags=re.I)

    # báo bếp / báo chế biến ≠ newspaper
    if "báo bếp" in low or "báo chế biến" in low or "chế biến" in low and "báo" in low:
        en = re.sub(r"\*\*\*\s*PROCESSING NEWSPAPER\s*\*\*\*", "*** KITCHEN SLIP ***", en, flags=re.I)
        en = re.sub(r"Kitchen newspaper", "Kitchen ticket", en, flags=re.I)
        en = re.sub(r"Processing newspaper", "Kitchen slip", en, flags=re.I)
        en = re.sub(r"\bnewspaper\b", "slip", en, flags=re.I)

    # từ chối = reject (approval), not refuse
    if "từ chối" in low:
        en = re.sub(r"\bRefuse to\b", "Reject ", en)
        en = re.sub(r"\brefuse to\b", "reject ", en)
        en = re.sub(r"\bRefused\b", "Rejected", en)
        en = re.sub(r"\brefused\b", "rejected", en)
        en = re.sub(r"\bRefuse\b", "Reject", en)
        en = re.sub(r"\brefuse\b", "reject", en)
        en = re.sub(r"  +", " ", en)

    # công (work day) ≠ merit — skip công ty / công việc / công tác / cộng
    if re.search(r"(đủ công|số công|giờ công|\b1 công\b|đủ 1 công)", low):
        en = re.sub(r"\bmerits\b", "work days", en, flags=re.I)
        en = re.sub(r"\bmerit\b", "work day", en, flags=re.I)
        en = re.sub(r"\b1 job\b", "1 work day", en, flags=re.I)

    return en.strip()


JUNK = re.compile(
    r"NavItem\(|Icons\.|return;|\)\.format\(|\$\{|[{}]|"
    r"progress\.clamp|_updateSync|_storeStandard|syncKey|"
    r"^\s*,|^\s*\)|// ═|const maxWait|cmdStatus"
)


def is_junk(s: str) -> bool:
    if not s or not s.strip():
        return True
    if JUNK.search(s):
        return True
    if s.count("\n") >= 2:
        return True
    if "\n" in s and any(x in s for x in ("Widget", "const ", "void ", "setState")):
        return True
    return False


def translate_missing(todo: list[str]) -> dict[str, str]:
    if not todo:
        return {}
    try:
        from deep_translator import GoogleTranslator
    except ImportError:
        print("deep_translator not installed — skip machine translate", flush=True)
        return {}

    out: dict[str, str] = {}
    tx = GoogleTranslator(source="vi", target="en")
    batch: list[str] = []
    batch_len = 0

    def flush() -> None:
        nonlocal batch, batch_len
        if not batch:
            return
        try:
            joined = "\n".join(batch)
            result = tx.translate(joined)
            lines = (result or "").split("\n")
            if len(lines) == len(batch):
                for vi, en in zip(batch, lines):
                    out[vi] = (en or vi).strip() or vi
            else:
                for vi in batch:
                    out[vi] = (tx.translate(vi) or vi).strip() or vi
        except Exception as e:
            print(f"  translate batch failed: {e}", flush=True)
            for vi in batch:
                try:
                    out[vi] = (tx.translate(vi) or vi).strip() or vi
                except Exception:
                    out[vi] = vi
        batch, batch_len = [], 0

    for i, s in enumerate(todo, 1):
        batch.append(s)
        batch_len += len(s) + 1
        if batch_len > 3000 or len(batch) >= 30:
            flush()
            print(f"  translated {len(out)}/{len(todo)}", flush=True)
    flush()
    return out


def main() -> None:
    data: dict[str, str] = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    before = len(data)

    # 1) Systematic fix of existing machine translations
    fixed = 0
    for k, v in list(data.items()):
        if not isinstance(k, str) or not isinstance(v, str):
            continue
        nv = fix_machine_value(k, v)
        if nv != v:
            data[k] = nv
            fixed += 1

    # 2) Curated overrides win
    data.update(_MODULE_LABELS)
    data.update(CURATED)

    # 3) Collect every display string still missing
    needed: set[str] = set()
    if VN_SRC.exists():
        for item in json.loads(VN_SRC.read_text(encoding="utf-8")):
            vi = item.get("vi") if isinstance(item, dict) else None
            if isinstance(vi, str) and vi.strip():
                needed.add(vi)
    needed.update(extract_vn_from_lib(CLIENT_LIB))
    if POS_LIB.exists():
        needed.update(extract_vn_from_lib(POS_LIB))
    needed.update(CURATED)
    needed.update(_MODULE_LABELS)
    needed = {s for s in needed if not is_junk(s)}

    missing = sorted(s for s in needed if s not in data)
    print(f"map={before} systematic_fixed={fixed} missing={len(missing)}", flush=True)

    # 4) Machine-translate leftovers, then curated again
    if missing:
        translated = translate_missing(missing)
        for vi, en in translated.items():
            data[vi] = fix_machine_value(vi, en)
        still = [s for s in missing if s not in data]
        print(f"  machine_added={len(translated)} still_unmapped={len(still)}", flush=True)

    data.update(CURATED)
    data.update(_MODULE_LABELS)

    JSON_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8"
    )
    print(f"wrote {JSON_PATH} entries={len(data)}", flush=True)

    subprocess.run(
        [sys.executable, str(HERE / "generate_en_ui_map_dart.py")], check=True
    )
    src_dart = CLIENT_LIB / "l10n" / "en_ui_map.g.dart"
    dst_dart = POS_LIB / "l10n" / "en_ui_map.g.dart"
    if dst_dart.parent.exists():
        shutil.copy2(src_dart, dst_dart)
        print(f"copied map → {dst_dart}", flush=True)


if __name__ == "__main__":
    main()
