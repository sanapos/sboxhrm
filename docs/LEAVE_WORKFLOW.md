# Quy trình nghỉ phép (SBOX HRM)

## Giao diện mới (wizard)

1. **Nhóm chế độ** — chọn một trong ba:
   - **Doanh nghiệp trả lương**
   - **Không hưởng lương**
   - **BHXH & chế độ đặc biệt**
2. **Loại cụ thể** — ví dụ phép năm, ốm BHXH, ốm dùng phép năm, thai sản…
3. **Chi tiết** — ngày, ca (thiết lập lương), người thay ca, giấy BHXH (nếu có), lý do.

## Chuẩn bị (HR)

| Hạng mục | Việc cần làm |
|----------|----------------|
| Ca làm việc | Thiết lập ca + gắn trong **Thiết lập lương** (`shifts: …`) |
| Phòng ban | Gắn trên hồ sơ NV → lọc **người thay ca** cùng phòng ban |
| Cấp duyệt | `leave_approval_levels` trong cài đặt |

## Bảng loại phép & chi trả

| Loại trên app | Ai trả | Ghi chú |
|---------------|--------|---------|
| Phép năm, Lễ, VR có lương, Nghỉ bù | DN | Trừ quỹ phép (nếu có) |
| Ốm — dùng phép năm | DN | Không hưởng ốm BHXH cùng ngày |
| Ốm — hưởng BHXH | BHXH | Bắt buộc số giấy nghỉ / hồ sơ |
| Thai sản | DN + BHXH | Đối soát trợ cấp |
| VR không lương, Nghỉ dài hạn | Không lương | |

## Tùy chọn quản lý

- **Duyệt luôn khi tạo** — bỏ chờ duyệt (tạo hộ NV).
- **Phép duyệt nhưng vẫn tính công** — có đơn phép nhưng chấm công không ghi «Phép».

## Trùng đơn

Không tạo hai đơn **cùng ngày và cùng ca** (có thể nghỉ ca sáng và ca chiều bằng hai đơn khác ca).

## Quỹ phép năm

- Quỹ lưu trên **hồ sơ lương** (`BalancedPaidLeaveDays` trong Thiết lập lương).
- Khi **duyệt xong** đơn **Phép năm** hoặc **Ốm — dùng phép năm** (và không bật «vẫn tính công»): hệ thống **tự trừ** số ngày (nửa ca = 0,5/ngày).
- Không đủ quỹ → **không duyệt được**.
- **Hoàn duyệt / xóa đơn đã duyệt** → hoàn lại phép đã trừ.
- API: `GET /api/Leaves/annual-balance/{employeeId}`.

## Triển khai kỹ thuật

Sau khi deploy API, DB tự thêm cột: `PaymentSource`, `SickLeaveMode`, `BhxhDocumentNote`, `AnnualLeaveDaysDeducted`, `AnnualBalanceApplied` (cùng `CountAsWork`).
