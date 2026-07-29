# SBOX Web UI — Phân tích & đề xuất thiết kế lại (2026)

**Vai trò phân tích:** UI/UX Senior · Front-end Architect · Responsive Design  
**Phạm vi:** Flutter Web client (`flutter_client`), served qua `wwwroot` API  
**Ngày:** 2026-07-29  
**Canvas tương tác:** mở kèm chat nếu dùng Cursor Canvas

---

## 1. Tổng quan hiện trạng

Web SBOX không phải SPA React/Vue — là **Flutter Web** dùng Material + Provider, font **Be Vietnam Pro**, shell `MainLayout` (sidebar / NavigationRail / drawer+bottom nav).

| Khía cạnh | Hiện trạng | Điểm |
|-----------|------------|------|
| Responsive | Breakpoint chính 768 / 1024 / 1440; nhiều màn fork `<600` | C+ |
| Hiện đại / nhất quán | 4 hệ màu; ~5.900 `Color(0x…)` hardcode | C / D+ |
| Typography | `AppTypography` tốt, override ad-hoc nhiều | B- |
| Design System enforce | Theme có, không bắt buộc dùng | D+ |
| Dark mode | Có toggle; surface light-hex còn nhiều | C |
| Accessibility | Chưa audit WCAG 2.2 | C- |

**Kết luận:** Nền tảng đủ để nâng cấp (font, theme, shell 3 mode), nhưng thương hiệu và token bị phân mảnh. Trên laptop 15.6–27" nội dung **stretch full** vì `Responsive.maxContentWidth` luôn `null`.

### Điểm mạnh cần giữ

- Be Vietnam Pro + text theme có hierarchy rõ.
- Shell responsive 3 tầng đã định nghĩa.
- `HrmPageChrome`, `HrmResponsiveListLayout`, `AppResponsiveDialog` là mầm design system.
- POS đã có density cảm ứng (`touchMin = 56`).

### Điểm yếu mang tính hệ thống

1. **4 palette:** HRM navy `#1E3A5F`, login/marketing `#0C56D0`, POS Kiot green/blue, Warehouse iOS `#007AFF`.
2. **Token không enforce** — dashboard/main_layout/god screens tự tô màu.
3. **Breakpoint lệch** — official 768 vs local 600/900.
4. **Wide-screen chưa thiết kế** — thiếu max-width và master–detail.
5. **Material 3** chỉ bật ở customer display; app chính chưa `useMaterial3`.

---

## 2. Danh sách vấn đề phát hiện

### 2.1 Responsive theo màn hình

| Màn hình | Bố cục | Vấn đề | Ảnh hưởng | Điểm |
|----------|--------|--------|-----------|------|
| 12" 1366×768 | Compact (height &lt;720) | Sidebar + toolbar + bảng tranh chiều cao; overflow ngang bảng | Cao | C+ |
| 13–14" ~1440 | Desktop shell | `largeBreakpoint` gần như không dùng | Trung bình | B- |
| 15.6" 1920×1080 | Stretch full | Dòng bảng quá dài; whitespace không kiểm soát | Cao | C |
| 17" / 21–24" | Stretch | Form/list không max column; thiếu density compact | Cao | D+ |
| 27"+ | Stretch | Không dual-pane; lãng phí diện tích | Cao | D |

**Chi tiết kiểm tra (tóm tắt):**

- **Whitespace:** Hẹp trên 1366; “rỗng xấu” (stretch) trên ≥1920 — không phải whitespace có chủ đích.
- **Font:** Body 14–15 ổn; nhiều label 11–12 trên web khó đọc khi scale 100%.
- **Nút:** Theme padding ổn; POS tốt hơn HRM; một số action icon &lt;40px trên web.
- **Menu / sidebar:** 250px chiếm ~18% trên 1366; collapsible 60px tốt nhưng label group dài.
- **Bảng:** `DataTable` vs card list không đồng nhất; sticky header không chuẩn.
- **Form / card / chart / dashboard:** Card radius/border khá hiện đại; dashboard màu ad-hoc; chart palette không token.

### 2.2 Giao diện lỗi thời / không đồng nhất

| Dấu hiệu | Vị trí điển hình | Mức độ |
|----------|------------------|--------|
| `Colors.blue` Material cũ | payroll, attendance, cash, bonus… (~47 files) | Cao |
| Brand blue login ≠ navy app | `login_screen`, marketing HTML | Trung bình |
| POS “app khác” khi fullscreen | `pos_theme.dart` vs HRM chrome | Trung bình (chấp nhận domain accent) |
| Shadow/elevation lẫn | Card elev 0 + border vs ElevatedButton elev 1 | Thấp–TB |
| Spacing cảm tính | POS/HRM `EdgeInsets` 8–24 rải rác | Trung bình |
| Splash Flutter logo | Web load `/login-app` | Trung bình (brand) |
| God screens | `main_layout.dart`, `dashboard_screen.dart` | Cao (maintainability) |
| Overflow bị nuốt debug | `main.dart` | Cao (che lỗi layout) |

### 2.3 Design System

| Token / component | Trạng thái | Ghi chú |
|-------------------|------------|---------|
| Typography | Partial | AppTypography tốt |
| Color | Broken | 4 hệ |
| Spacing | Weak | 12/16/24 helper; không scale 4-based bắt buộc |
| Grid | Weak | `gridColumns`; không 12-col page grid |
| Radius | Partial | 10/14/16/20 vs POS 8–12 |
| Elevation | Partial | Flat card + shadow rời |
| Button / Form | Partial | Theme OK; override nhiều |
| Table | Broken | Không HrmDataGrid |
| Modal / Toast | Partial | Dialog responsive; SnackBar mặc định |
| Card / Badge / Tag / Avatar | Weak | Tự vẽ |
| Breadcrumb / Tabs / Pagination | Partial | Tab theme có; breadcrumb yếu |

---

## 3. Ảnh minh họa / mô tả vị trí lỗi

| # | Vị trí | Mô tả |
|---|--------|-------|
| A | `responsive_helper.dart` → `maxContentWidth` | Luôn `return null` — root cause wide-screen stretch |
| B | `theme_provider.dart` vs `pos_theme.dart` vs login `#0C56D0` | Ba primary khác nhau trong một sản phẩm |
| C | `main_layout.dart` | Shell + nav + chrome ~4.8k LOC — khó redesign đồng bộ |
| D | `dashboard_screen.dart` | Hàng trăm hex màu; không dùng token |
| E | 30+ file `width < 600` | Layout flip sớm hơn shell (768) → “nhảy” layout lệch |
| F | Web splash | Logo Flutter giữa nền navy — thiếu brand SBOX app icon |

---

## 4. Mức độ ảnh hưởng

| Mã | Vấn đề | UX | Brand | Dev cost nếu trì hoãn |
|----|--------|----|-------|------------------------|
| H1 | Đa palette + hardcode màu | Cao | Cao | Compound mỗi sprint |
| H2 | Breakpoint fork | Cao | — | Regression liên tục |
| H3 | Không max-width | Cao (desktop) | Trung bình | Phải sửa từng màn |
| H4 | Table không chuẩn | Cao | — | Copy-paste bug |
| H5 | God screens | Trung bình | — | Block redesign |
| M1 | Chưa M3 / dark semantic | Trung bình | Trung bình | Rework theme 2 lần |
| M2 | Form/dialog density | Trung bình | — | — |
| L1 | Motion / icon polish | Thấp | Thấp | — |

---

## 5. Đề xuất giải pháp

### 5.1 Phong cách UI mới (2026)

**Chọn:** Modern Enterprise Dashboard + Clean Minimal  
**Không:** Glassmorphism toàn app; không đổi stack sang Tailwind/Bootstrap.

- Primary: giữ navy SBOX `#1E3A5F` (enterprise).
- Accent semantic: success / warning / info / danger — **không** dùng pink làm secondary chính cho action.
- Radius 8–12 (control) / 12–16 (card).
- Soft elevation 0–2 + hairline border.
- Density: Comfortable (default) / Compact (power user, ≥1440).
- Dark mode: semantic `surface`, `onSurface`, `outline`.
- POS: giữ green/blue thao tác như **domain accent**, đồng bộ type/radius/spacing với App DS.
- A11y: WCAG 2.2 AA, focus visible, target ≥24×24 (web) / 48 (touch).

### 5.2 Design tokens (Flutter)

```
lib/design_system/
  tokens/
    colors.dart      # AppColors + ColorScheme light/dark
    space.dart       # 4,8,12,16,24,32,48
    radius.dart      # 8,10,12,16
    typography.dart  # wrap AppTypography
    elevation.dart
  components/
    hrm_button.dart
    hrm_field.dart
    hrm_card.dart
    hrm_data_grid.dart
    hrm_badge.dart
    hrm_tabs.dart
    hrm_skeleton.dart
    hrm_page.dart    # max-width + header + toolbar
```

### 5.3 Responsive & layout

| Breakpoint | Width | Shell | Content |
|------------|-------|-------|---------|
| compact | &lt;768 | Drawer + bottom | Full; card lists |
| medium | 768–1023 | Rail | max 960 |
| expanded | 1024–1439 | Sidebar | max 1280 |
| large | 1440–1919 | Sidebar compact option | max 1360; density toggle |
| xlarge | ≥1920 | Sidebar | max 1440; optional master–detail 40/60 |

Sửa `maxContentWidth` thành giá trị thực theo breakpoint trên.

### 5.4 Kỹ thuật front-end

- **Không** migrate CSS framework — map ý tưởng Grid/Flex/Tokens sang Flutter.
- CSS Variables tương đương = Dart constants + `ThemeExtension`.
- Component hóa; cấm hardcode brand hex mới (CI grep / custom lint).
- Lazy/deferred load module POS nặng trên web.
- Skeleton loading thống nhất.
- Tối ưu CWV: giảm main.dart.js ban đầu, tree-shake icons, image sizes.

### 5.5 Wireframe shell (văn bản)

```
┌────────┬─────────────────────────────────────────────────────────┐
│ Side   │ Top: Breadcrumb · ⌘K Search · Notify · User             │
│ 220/64 ├─────────────────────────────────────────────────────────┤
│        │ PageHeader: Title · subtitle · [Primary CTA]            │
│ Nav    │ FilterRow: chips · date · search                        │
│ groups │                                                         │
│        │ ┌─ Content max 1360 ─────────────────────────────────┐  │
│        │ │ Table / Cards / Dashboard grid 12-col               │  │
│        │ └─────────────────────────────────────────────────────┘  │
└────────┴─────────────────────────────────────────────────────────┘
≥1920: có thể tách List | Detail thay vì chỉ stretch bảng.
```

---

## 6. Độ ưu tiên & công sức

### High

| Hạng mục | Giải pháp | Công sức |
|----------|-----------|----------|
| Unify brand tokens | AppColors + ThemeExtension; POS accent map | L |
| Hardcoded colors | Migrate dần + lint | XL |
| Breakpoints | Chỉ `Responsive.*`; xóa `<600` HRM | M |
| maxContentWidth | Implement thật | S |
| Shell refactor | Tách component + density | L |
| HrmDataGrid | Sticky, density, empty, skeleton | L |
| Dashboard | Widgetize + chart tokens | XL |

### Medium

| Hạng mục | Giải pháp | Công sức |
|----------|-----------|----------|
| Material 3 | `useMaterial3: true` + scheme | M |
| Forms/dialogs | HrmField kit | M |
| Home hub | Grouped cards + command palette | M |
| Login splash | Brand asset | S |
| Dark semantic | Pass surfaces | L |
| WCAG | Contrast + focus | M |

### Low

| Hạng mục | Giải pháp | Công sức |
|----------|-----------|----------|
| Motion | 150–200ms transitions | S |
| Icons | Material Symbols rounded | S |
| Hover micro | Desktop only | S |

---

## 7. Checklist triển khai

### Phase 1 — Foundation (2–3 tuần)

- [ ] Tạo `lib/design_system/tokens`
- [ ] Sửa `maxContentWidth` + dùng `largeBreakpoint`
- [ ] Login/splash brand (bỏ Flutter logo)
- [ ] Migrate `MainLayout` chrome sang tokens
- [ ] CI: fail nếu thêm `Colors.blue` / hex brand mới ngoài tokens

### Phase 2 — Patterns (3–5 tuần)

- [ ] `HrmDataGrid` + density
- [ ] `HrmForm` / dialog / toast / skeleton
- [ ] Xóa breakpoint `<600` trên top HRM screens
- [ ] Dashboard split widgets + chart palette

### Phase 3 — Surfaces (4–6 tuần)

- [ ] Home hub + command search
- [ ] Settings hub refresh
- [ ] POS align type/radius (giữ accent xanh)
- [ ] Dark mode semantic pass
- [ ] Dual-pane ≥1600 cho Employees / Orders / Warehouse docs

### Phase 4 — Polish (2 tuần)

- [ ] Icons unified
- [ ] Motion + hover
- [ ] WCAG audit
- [ ] Deferred POS on web
- [ ] Visual QA matrix: 1366 · 1440 · 1920 · 2560

---

## 8. Bảng tổng hợp

| Hạng mục | Hiện trạng | Đề xuất | Ưu tiên | Công sức |
| -------- | ---------- | ------- | ------- | -------- |
| Brand / color system | 4 palette | 1 AppColors + POS accent | High | L |
| Hardcoded Color(0x…) | ~5.900 literals | Tokens + lint | High | XL |
| Breakpoints | 768/1024 + fork 600 | Chỉ Responsive.* | High | M |
| maxContentWidth | Luôn null | 1280–1440 theo BP | High | S |
| Shell navigation | MainLayout 4.8k LOC | Shell components + density | High | L |
| Data tables | DataTable/card lệch | HrmDataGrid chuẩn | High | L |
| Dashboard | God screen + hex | Widgetize + tokens | High | XL |
| Typography | AppTypography + override | Chỉ TextTheme | Medium | M |
| Material 3 | Chưa toàn app | Bật M3 + scheme | Medium | M |
| Forms / dialogs | Partial responsive | Form kit + density | Medium | M |
| Home module grid | Tile launcher cũ | Hub + command palette | Medium | M |
| Login / marketing | Brand lệch + Flutter splash | Brand splash + split login | Medium | S |
| Dark mode | Toggle; hex light | Semantic surfaces | Medium | L |
| Accessibility | Chưa audit | WCAG 2.2 AA | Medium | M |
| Motion / micro-UX | Ít | Transition + skeleton | Low | S |
| Icons | Material lẫn kiểu | Material Symbols | Low | S |

---

## Triển khai (2026-07-29)

Đã ship nền tảng Design System trong repo (không chờ redesign toàn bộ 173 màn):

- `flutter_client/lib/design_system/` — tokens + HrmPage/Card/Button/DataGrid/Skeleton/Toast/CommandPalette
- ThemeProvider: Material 3, `AppDesignTokens`, density toggle
- `Responsive.maxContentWidth` + Home/Dashboard constrain
- Migrate `Colors.blue` → `AppColors.info`, marketing `#0C56D0` → navy, breakpoint 600→768 (~66 files)
- Ctrl/Cmd+K command palette trên MainLayout
- Guardrail: `scripts/check-design-tokens.ps1`

Còn lại (theo phase): dual-pane ≥1600, deferred POS thật, migrate hex còn lại trong dashboard god-file, visual QA matrix.

---

## Mục tiêu cuối

Một giao diện web **hiện đại, chuyên nghiệp, đồng nhất**, tối ưu 12" → 27"+, token-first, component-first, dễ bảo trì trong **Flutter Web**, đạt chuẩn UI/UX 2026 và WCAG 2.2 AA — không cần đổi stack front-end.
