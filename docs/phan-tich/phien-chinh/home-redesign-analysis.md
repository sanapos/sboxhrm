# Trang chủ SBOX — phân tích + 3 hướng (chưa sửa code)

Artifact: https://claude.ai/artifact/69tKM4rE8SdYsXTLJaDEgU (riêng tư, của người dùng)

## Vị trí mã
- `flutter_client/lib/screens/main_layout.dart`
  - `_HomeMenuScreen` 4574–4682 (nhóm, màu, mô tả), state 4684–5325
  - Web + điện thoại (<768): `_buildMobileKiotHome` 4798 (PosMobileProfileCard + PosMobileHubSectionGrid 3–6 cột, `MobileQuickActionsPrefs`)
  - C20 / máy tính: chip nhóm 4966, banner chào 5011, lưới `_MenuCard` 3–4 cột 5260
  - `_MenuCard` 5397 (GestureDetector, không Semantics / focus)
  - Khung: desktop ≥1024 (rail 60/250), tablet ≥768, mobile — dòng 2650
- Token: `lib/theme/sbox_tokens.dart`; `HrmPageChrome.primaryNavy` = `PosTheme.kiotBlue` = brand600.

## Điểm yếu chính
1. Chip nhóm mở chức năng ĐẦU TIÊN của nhóm (`items.first.key`), không cuộn tới nhóm.
2. Banner chào khoảng 150 dp, không có thông tin hữu ích; chip + banner chiếm gần 40% màn đầu C20.
3. 12 nhóm cùng một màu navy.
4. 77 ô, cuộn khoảng 6–7 màn trên C20; «Bán hàng» là nhóm thứ 5.
5. Hai giao diện (web/điện thoại kiểu Kiot, C20/máy tính kiểu chip + banner).
6. Chữ phụ 11 px #8A9199, tương phản khoảng 3,2:1; màu hard-code ngoài token.
7. i18n: tr() bọc emoji + biến, tên người, số; ngày ghép tay «Th10».
8. «Check-in hội viên» được xếp vào nhóm «Check-in hội viên (gym)», nhóm này không có trong `_groupOrder` nên ô bị ẩn khỏi Trang chủ (cần kiểm có cố ý không).

## Hướng
- A Bệ phóng gọn: ô ghim (dùng MobileQuickActionsPrefs) + gần đây + mục lục cuộn tới nhóm + ô nhỏ 5 cột. Công sức thấp, không cần API mới. **Khuyến nghị.**
- B Điều hành hôm nay: 4 số + việc cần xử lý + truy cập nhanh; cần endpoint `/home/summary` (màn tổng quan hiện gọi khoảng 25 API).
- C Khu vực công việc: menu trái có nhãn theo khu vực, bên phải là nút chính + 3 số + chức năng theo tầng.
