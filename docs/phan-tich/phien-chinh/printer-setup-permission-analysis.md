# Phân quyền thiết lập máy in / Print Agent — phân tích (2026-11-03)

Chỉ phân tích, CHƯA sửa code. Đường dẫn tương đối từ `ZKTecoADMS-master/`.
Hai app `flutter_client` và `flutter_pos` có bản sao gần giống nhau của các màn dưới đây — sửa phải sửa cả hai.

## 1. Quyền liên quan

| Module | Tên hiển thị | Ý nghĩa thực tế |
|---|---|---|
| `PosPrinters` | Máy in thiết bị | **API máy in cloud dùng module này** (`/api/pos/printers/*`). Xem = tải danh sách máy để in; Sửa = thêm/sửa/xóa/vai trò/gán món |
| `PosStorePrinters` | Máy in cloud | Chỉ dùng để hiện tab «Máy in cloud». Ngầm định 2 chiều với `PosPrinters` cùng action (`ModulePermissionImplicitGrants.cs:254-267`) |
| `PosPrintTemplates` | Mẫu in | Xem mẫu khi bán (PosSell View ngầm cấp Xem) |
| `PosSell` | Bán hàng | Create = gửi lệnh in, đăng ký / heartbeat Print Agent, nhận job |

Bỏ qua bảng quyền: `SuperAdmin`, `Agent`, `Admin` (chủ cửa hàng) — `ModulePermissionDefaults.IsSuperRole`.

Mặc định:
- Mẫu «Phục vụ / Order» (`PermissionPresetCatalog.PosWaiter`) và vai trò `waiter` (`ModulePermissionDefaults.WaiterDefaults`): `PosPrinters` **chỉ Xem**, `PosSell` Xem + Tạo.
- Thu ngân: `PosPrinters` chỉ Xem.
- Quản lý cửa hàng (preset): `Op` trên nhóm thiết lập (gồm `PosPrinters` Sửa). Vai trò `manager` không preset: toàn quyền trừ settings/store/role.
- Chủ cửa hàng (`pos.director`): Full.

=> Nhân viên order cần **Xem `PosPrinters`** để in được (orchestrator gọi GET `/api/pos/printers`). Xem = «dùng», Sửa = «thiết lập» là cách tách sẵn có.

## 2. Ai làm được gì hiện nay

### API (`src/ZKTecoADMS.Api/Controllers`)
| Hành động | Endpoint | Kiểm quyền | Order (mặc định) |
|---|---|---|---|
| Xem máy in, routes, map gán món | GET `api/pos/printers`, `/routes`, `/product-assignment/*` | PosPrinters View | được |
| Thêm/sửa/xóa máy cloud | POST/PUT/DELETE `api/pos/printers` | PosPrinters Edit | **bị chặn** |
| Đổi vai trò (Hóa đơn/Báo bếp/tem) | PUT `/routes` | PosPrinters Edit | bị chặn |
| Gán món / danh mục | `/product-assignment/...` POST/PUT | PosPrinters Edit | bị chặn |
| Đồng bộ máy nội bộ lên server | POST `/device-local` | PosPrinters Edit | bị chặn |
| Dọn máy cũ | POST `/stale/deactivate` | PosPrinters Edit | bị chặn |
| Báo sức khỏe máy in | POST `/{id}/health` | PosPrinters View | được (OK) |
| **Bật Agent / heartbeat** | POST `api/pos/print-jobs/agents/register` | **PosSell Create** + chống chiếm deviceId đang online của người khác | **được** — kể cả gán bất kỳ máy in nào cho Agent |
| Tắt Agent | POST `agents/offline` | PosSell Create; Agent của người khác chỉ Admin/Manager | được với Agent của mình |
| Nhận/hoàn tất job | `agents/{id}/claim`, `{id}/complete`… | PosSell Create | được (cần cho Agent) |

### UI
Lối vào: Thiết lập SBOX › Máy in (`settings_hub_screen.dart` case 18/29 → `PosPrintersTabsScreen`). Tab «Trên máy này» hiện khi có Xem `PosPrinters`, tab «Máy in cloud» khi Xem `PosStorePrinters` → **order thấy cả hai tab**. Menu chính `main_layout.dart:512-513` cũng vậy.

Màn «Máy in cloud» (`screens/pos/pos_store_printers_screen.dart`) — đã có `_canManageCloudPrinters = canEdit('PosPrinters')` (dòng 234):
- Đã ẩn đúng: Thêm máy in (FAB/nút), Sửa, Xóa, chip vai trò, Gán món, chạm vào máy để sửa.
- **Chưa ẩn**: công tắc «Chia sẻ máy in của thiết bị này» = bật Agent (`_toggleAgent`, ~dòng 1284); chip «Chọn máy in muốn chia sẻ» (`_toggleLocalAsAgent`, ~1324 — gọi create/delete máy cloud, server chặn nhưng lỗi xóa bị nuốt, cờ Agent trên máy vẫn lưu); «Dọn máy in cũ» (FAB ~816, server chặn); xóa máy mồ côi (~1614, server chặn); «Buộc tắt» Agent máy khác (~1496, server chặn nếu không phải QL).

Màn «Máy in nội bộ» (`screens/pos/pos_local_printers_screen.dart`) — chỉ «Gán sản phẩm» kiểm `canEdit('PosPrinters')` (dòng 418):
- **Không kiểm quyền**: Thêm máy in (FAB 435, nút 688), Sửa (menu + chạm dòng 644), Xóa (`_delete`), đổi kết nối LAN/BT/USB/Sunmi, IP, khổ giấy, vai trò Hóa đơn / Báo bếp / tem, bật/tắt máy, «Tìm lại IP», «Đồng bộ».
- Lưu vào SharedPreferences của máy (`utils/pos_local_printers_store.dart`), đồng bộ server bị 403 nhưng **cấu hình trên máy vẫn đổi** → đây là chỗ order đổi nhầm được nhiều nhất.

Màn «Thiết lập in» (`widgets/pos/pos_sell_mobile_print_settings_screen.dart`, tab «Trên máy này» qua `PosPrinterSettingsHubScreen`): tự in khi thanh toán, số liên, mẫu HĐ, chế độ tem ly, chế độ phiếu bếp, máy in BT… — **không kiểm quyền Sửa**, lưu trên máy. Riêng chế độ tem ly còn thử ghi thiết lập cửa hàng lên server (`_pushStoreCupMode`, lỗi quyền thì bỏ qua).

Khóa `pos_print_agent_*` (`utils/pos_print_agent_settings.dart`): chỉ là cấu hình cục bộ (bật Agent, danh sách máy gán, storeId, migration reset_v1). Không có kiểm quyền nào trước khi `save()`.

## 3. Lỗ hổng
1. Order sửa / xóa / thêm máy in nội bộ và đổi vai trò Hóa đơn/Báo bếp trên máy mình (hoặc máy quầy dùng chung) — không UI nào chặn; server không biết vì dữ liệu nằm trên máy.
2. Order bật Print Agent và gán máy in bất kỳ → máy order thành «Agent ma» tranh job in của máy thu ngân (đúng lỗi từng gặp A6/A7). API `agents/register` chỉ đòi PosSell Create.
3. Nút hiện nhưng bấm mới 403 (Dọn máy cũ, xóa mồ côi, chip chia sẻ) → khó hiểu, và chip chia sẻ để lại trạng thái nửa vời.
4. Cửa hàng tự chỉnh vai trò có thể đã tick Sửa «Máy in» cho order/thu ngân — cần kiểm dữ liệu production.

## 4. Đề xuất

**Quyền**: dùng luôn `PosPrinters` **Sửa** làm quyền «Thiết lập máy in» (Xem = được in). Lý do: API đã dùng đúng ranh giới này, mẫu order/thu ngân mặc định chỉ Xem, không cần migration bảng quyền. Đổi nhãn module trong `FeatureModuleCatalog.cs:193` + `permission_navigation.dart` thành «Máy in (Sửa = thiết lập)» cho chủ dễ hiểu.
Phương án B (module mới `PosPrinterSetup`): an toàn hơn nếu nhiều cửa hàng đã tick Sửa cho order, nhưng phải seed Permission, preset, implicit grant, gói, migration cấp cho Director/Manager. Chỉ chọn nếu truy vấn production cho thấy nhiều vai trò order có Sửa.

**API (chặn thật)**
- `PosPrintJobsController.RegisterAgent`: nếu chưa có bản ghi Agent cho deviceId, hoặc tập `PrinterIds` khác bản đang lưu (thêm máy), hoặc Agent đã bị force-stop → yêu cầu `PosPrinters` Edit (gọi `IModulePermissionService.HasPermissionAsync`). Heartbeat cùng tập máy → giữ PosSell Create, để máy quầy do QL bật vẫn chạy khi thu ngân đăng nhập.
- Các endpoint máy in cloud / routes / gán món / device-local: giữ nguyên (đã Edit).
- Thêm test trong `tests/` cho RegisterAgent: order đăng ký mới → 403; heartbeat Agent có sẵn → 200.

**UI (cả flutter_client và flutter_pos)**
- `pos_local_printers_screen.dart`: Thêm/Sửa/Xóa/Đồng bộ/đổi vai trò chỉ khi `canEdit('PosPrinters')`; người chỉ Xem được «In thử» và xem trạng thái; chạm dòng → thông báo «Chỉ xem».
- `pos_store_printers_screen.dart`: công tắc Agent, chip chia sẻ, «Dọn máy in cũ», xóa mồ côi, «Buộc tắt» → theo `_canManageCloudPrinters`.
- `pos_sell_mobile_print_settings_screen.dart`: khóa phần máy in/khổ giấy/chế độ báo bếp/tem/mẫu khi không có Sửa.
- `PosPrintAgentService.ensureRunning`: không tự bật Agent mới nếu không có quyền (chỉ chạy tiếp Agent đã được QL bật trên máy).
- Chuỗi mới → pipeline `tool/i18n_*`.

**Cần người dùng quyết**
- Order có được «Tìm lại IP» (máy in đổi IP do router) không? Đây là thao tác cứu sự cố hay gặp.
- Order có được bật/tắt «In hóa đơn khi thanh toán», số liên trên máy mình không?
- Phương án A (dùng Sửa «Máy in») hay B (module mới).

## 5. File cần sửa (phương án A)
- `src/ZKTecoADMS.Api/Controllers/PosPrintJobsController.cs` (RegisterAgent)
- `src/ZKTecoADMS.Application/Authorization/FeatureModuleCatalog.cs` (nhãn), test API
- `flutter_client/lib/screens/pos/pos_local_printers_screen.dart` + bản `flutter_pos`
- `flutter_client/lib/screens/pos/pos_store_printers_screen.dart` + bản `flutter_pos`
- `flutter_client/lib/widgets/pos/pos_sell_mobile_print_settings_screen.dart` + bản `flutter_pos`
- `flutter_client/lib/services/pos_print_agent_service.dart` + bản `flutter_pos`
- `flutter_client/lib/utils/permission_navigation.dart` (nhãn) + bản `flutter_pos`
- i18n: chạy `tool/i18n_extract` → chunk → dịch → check

## 6. Bổ sung: gói chức năng «Thiết lập máy in Agent» (yêu cầu thêm của người dùng)

Hiện trạng gói (Super Admin tạo gói):
- Đã có module chọn được `PosStorePrinters` «Máy in cloud — Print Agent dùng chung cửa hàng» (`FeatureModuleCatalog.cs:194`), chỉ preset `pos_full` có sẵn.
- Nhưng **không có tác dụng thật**:
  - `StorePackageModuleMiddleware.cs:276-280`: gói có `PosPrinters` thì coi như có `PosStorePrinters` — mọi gói POS đều có `PosPrinters` (`PosSellCore`, `FeatureModuleCatalog.cs:379`).
  - `/api/pos/print-jobs` (đăng ký Agent, gửi lệnh in, nhận job) gắn với gói `PosSell` (`StorePackageModuleMiddleware.cs:108`), không với máy in cloud.
  - Không thể đơn giản bỏ fallback cho `/api/pos/printers` vì in cơ bản (máy nội bộ device-local, gán món) cũng dùng API này.

Đề xuất:
- Dùng lại `PosStorePrinters`, đổi tên trong gói thành «Máy in Agent (order điện thoại in qua máy quầy)» — hoặc tạo module mới `PosPrintAgent` nếu muốn tách hẳn khỏi «Máy in cloud».
- Middleware: các route Agent/cloud job — `print-jobs/agents/*`, tạo job gửi tới máy in cần Agent, `{id}/claim|complete|...` — yêu cầu gói có module này **nghiêm ngặt** (không fallback `PosPrinters`). `/api/pos/printers` giữ như cũ.
- UI: không có gói → ẩn tab/công tắc Agent, màn bán trên điện thoại không gửi lệnh in cloud mà báo «Gói chưa có Máy in Agent» (vẫn in trực tiếp BT/LAN nếu máy có).
- Dữ liệu: cửa hàng đang có Agent hoạt động mà gói thiếu module → cần migration thêm module cho họ (hoặc danh sách để Super Admin quyết), tránh tắt in đột ngột. Cần truy vấn production đếm cửa hàng có `PosPrintAgents` online gần đây mà gói không có `PosStorePrinters`.
- File thêm: `StorePackageModuleMiddleware.cs`, `StorePackageHelper.cs`, `FeatureModuleCatalog.cs`/`PosPackageDefaults.cs`, `PosPrintJobsController.cs`, `pos_print_agent_service.dart`, `pos_print_orchestrator.dart`, `pos_store_printers_screen.dart`, `pos_printers_tabs_screen.dart` (cả 2 app), màn tạo gói (admin) nếu cần đổi nhãn.

Cần người dùng xác nhận: «order điện thoại được» nghĩa là (a) không có gói thì điện thoại vẫn order nhưng không in qua Agent, hay (b) điện thoại không được order luôn?

## 7. Đã triển khai (2026-11-03, chưa commit / chưa deploy)
Người dùng chọn: gói thiếu module → máy NV vẫn order nhưng không gửi lệnh in qua Agent (Agent vẫn in QR/Tingee); cửa hàng đang dùng Agent tự được thêm module.
- API `PosPrintJobsController.RegisterAgent`: deviceId CHƯA có Agent → cần PosPrinters Edit (403 nếu không). Agent đã có → heartbeat bằng PosSell Create như cũ.
- `StorePackageModuleMiddleware`: POST `/api/pos/print-jobs` cần gói có `PosStorePrinters` đúng nghĩa (`PosPackageDefaults.PrintAgentModule`, không fallback PosPrinters). Agent/queue/retry không đổi.
- `PrintAgentPackageBackfill` (SboxDataMigrations id `print-agent-package-v1`, gọi trong SeedAsync): cửa hàng có PosPrintAgents, có PosSell, gói thiếu module, không bị chặn riêng → thêm `PosStorePrinters` vào Store.ExtraModules.
- Mô tả module gói «Máy in cloud» đổi (FeatureModuleCatalog).
- App (cả 2): màn Máy in nội bộ khóa Thêm/Sửa/Xóa/Đồng bộ/Gán món theo canEdit('PosPrinters') (In thử, Tìm lại IP, Kiểm tra kết nối vẫn mở); màn Máy in cloud khóa bật Agent (vẫn tắt được), chip chia sẻ, Dọn máy cũ, xóa mồ côi, Buộc tắt; màn Thiết lập in chỉ xem.
- Test: `PrintAgentAccessTests` (5 test PG) + toàn bộ 1589 test API đạt. Flutter analyze 6 file không lỗi. i18n: 2 chuỗi mới đã dịch en/ko/ja/zh.
- Chưa: chạy thử trên máy thật / web; app không có thông báo riêng về gói (dùng thông báo 403 của API).
