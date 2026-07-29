#!/usr/bin/env python3
"""Fast parallel VI→EN translation into en_ui_map.json."""
from __future__ import annotations

import json
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from deep_translator import GoogleTranslator

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "vn_strings.json"
OUT = ROOT / "en_ui_map.json"
CACHE = ROOT / "en_ui_map.partial.json"
LOCK = threading.Lock()
WORKERS = 8

SEED = {
    "Lỗi": "Error",
    "Hủy": "Cancel",
    "Thành công": "Success",
    "Xóa": "Delete",
    "Tất cả": "All",
    "Lưu": "Save",
    "Đóng": "Close",
    "Trạng thái": "Status",
    "Chờ duyệt": "Pending approval",
    "Từ chối": "Reject",
    "Nhân viên": "Employee",
    "Đã hủy": "Cancelled",
    "Đã duyệt": "Approved",
    "Ghi chú": "Note",
    "Sửa": "Edit",
    "Tiền mặt": "Cash",
    "Mô tả": "Description",
    "Thêm": "Add",
    "Khác": "Other",
    "Hoàn thành": "Completed",
    "Tìm kiếm": "Search",
    "Xác nhận": "Confirm",
    "Quay lại": "Back",
    "Tiếp tục": "Continue",
    "Bỏ qua": "Skip",
    "Tải lại": "Reload",
    "Làm mới": "Refresh",
    "Cài đặt": "Settings",
    "Đăng xuất": "Log out",
    "Đăng nhập": "Log in",
    "Mật khẩu": "Password",
    "Số điện thoại": "Phone number",
    "Họ tên": "Full name",
    "Họ và tên": "Full name",
    "Ngày": "Date",
    "Giờ": "Time",
    "Hôm nay": "Today",
    "Hôm qua": "Yesterday",
    "Tuần này": "This week",
    "Tháng này": "This month",
    "Tùy chọn": "Custom",
    "Bán hàng": "Sell",
    "Hàng hóa": "Products",
    "Đơn hàng": "Orders",
    "Trả hàng bán": "Sales returns",
    "Nhập hàng NCC": "Purchase receipts",
    "Trả hàng nhập": "Purchase returns",
    "Kiểm kho": "Stock count",
    "Xuất hủy": "Damage issue",
    "Xuất dùng nội bộ": "Internal use",
    "Báo cáo POS": "POS report",
    "Báo cáo phạt": "Penalty report",
    "Báo cáo chấm công": "Attendance report",
    "Báo cáo thu chi": "Cash report",
    "Báo cáo ứng lương": "Advance report",
    "Báo cáo công tác phí": "Business trip report",
    "Báo cáo nghỉ phép": "Leave report",
    "Báo cáo tài sản": "Asset report",
    "Chấm công": "Attendance",
    "Nghỉ phép": "Leave",
    "Duyệt chấm công": "Attendance approval",
    "Tổng hợp chấm công": "Attendance summary",
    "Thêm công": "Add attendance",
    "Thêm công và phạt": "Add attendance & fine",
    "Vắng": "Absent",
    "Phép": "Leave",
    "Nghỉ": "Off",
    "Lễ": "Holiday",
    "Chờ phép": "Leave pending",
    "Thiếu chấm": "Missing punch",
    "Đi trễ": "Late",
    "Về sớm": "Early leave",
    "Tăng ca": "Overtime",
    "Hợp lệ": "Valid",
    "Công tác phí": "Business trip expense",
    "Phiếu phạt": "Penalty tickets",
    "Phản ánh / Ý kiến": "Feedback",
    "POS / Bán hàng": "POS / Sales",
    "Tổng quan": "Overview",
    "Hồ sơ nhân sự": "HR records",
    "Tài chính": "Finance",
    "Quản lý Vận hành": "Operations",
    "Báo cáo": "Reports",
    "Đại lý": "Agent",
    "Tiếng Việt": "Vietnamese",
    "Ngôn ngữ": "Language",
    "Giao diện, ngôn ngữ, kết nối": "Appearance, language, connection",
    "Thông báo": "Notifications",
    "Trang chủ": "Home",
    "Không có dữ liệu": "No data",
    "Đang tải...": "Loading...",
    "Đang tải": "Loading",
    "Chi nhánh": "Branch",
    "Cửa hàng": "Store",
    "Phòng ban": "Department",
    "Chức vụ": "Position",
    "Mã NV": "Employee code",
    "Mã nhân viên": "Employee code",
    "In": "Print",
    "Xuất Excel": "Export Excel",
    "Nhập Excel": "Import Excel",
    "Lọc": "Filter",
    "Áp dụng": "Apply",
    "Từ ngày": "From date",
    "Đến ngày": "To date",
    "Số lượng": "Quantity",
    "Đơn giá": "Unit price",
    "Thành tiền": "Amount",
    "Tổng cộng": "Total",
    "Giảm giá": "Discount",
    "Thanh toán": "Payment",
    "Khách hàng": "Customer",
    "Nhà cung cấp": "Supplier",
    "Sản phẩm": "Product",
    "Tồn kho": "Stock",
    "Duyệt": "Approve",
    "Chi tiết": "Details",
    "Có": "Yes",
    "Không": "No",
    "Đồng ý": "OK",
    "Tạo mới": "Create new",
    "Cập nhật": "Update",
    "Chỉnh sửa": "Edit",
    "Cảnh báo": "Warning",
    "Thông tin": "Information",
    "Thất bại": "Failed",
    "Đồng bộ": "Sync",
    "Thiết bị": "Device",
    "Ca": "Shift",
    "Vào": "In",
    "Ra": "Out",
    "Thêm chấm công": "Add punch",
    "Sửa chấm công": "Edit punch",
    "Công": "Work day",
    "Số công": "Work count",
    "Giờ công": "Work hours",
}


def translate_one(text: str) -> tuple[str, str]:
    try:
        en = GoogleTranslator(source="vi", target="en").translate(text)
        return text, en if en else text
    except Exception:
        time.sleep(0.5)
        try:
            en = GoogleTranslator(source="vi", target="en").translate(text)
            return text, en if en else text
        except Exception:
            return text, text


def main() -> None:
    items = json.loads(SRC.read_text(encoding="utf-8"))
    done: dict[str, str] = dict(SEED)
    if CACHE.exists():
        for k, v in json.loads(CACHE.read_text(encoding="utf-8")).items():
            done.setdefault(k, v)
    print(f"start with {len(done)}", flush=True)

    todo = [i["vi"] for i in items if i["vi"] not in done]
    print(f"todo {len(todo)}", flush=True)
    done_count = 0

    def flush():
        with LOCK:
            CACHE.write_text(json.dumps(done, ensure_ascii=False), encoding="utf-8")

    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futs = {ex.submit(translate_one, s): s for s in todo}
        for fut in as_completed(futs):
            vi, en = fut.result()
            with LOCK:
                done[vi] = en
                done_count += 1
                if done_count % 50 == 0:
                    print(f"progress {done_count}/{len(todo)} map={len(done)}", flush=True)
                    flush()

    done.update(SEED)
    flush()
    OUT.write_text(json.dumps(done, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"done entries={len(done)} -> {OUT}", flush=True)


if __name__ == "__main__":
    main()
