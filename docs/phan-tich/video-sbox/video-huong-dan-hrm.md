# Chương trình làm bộ video hướng dẫn sử dụng SBOX HRM

*Phân tích ngày 14/11/2026. Mọi số liệu lấy trực tiếp từ mã nguồn và tài sản trong kho, không ước đoán.*

---

## 1. Kết luận ngắn

Làm được, và làm nhanh hơn hẳn các bộ video trước, vì **giáo trình và ảnh màn đã có sẵn gần như đủ**:

- Giáo trình HRM: **47 bài, 9 nhóm, 294 ý gạch đầu dòng** — nằm trong
  `src/ZKTecoADMS.Api/Services/HelpCorpus/landing-guide.json`.
- Ảnh màn: **115 ảnh HRM, đủ cả bản ngang (1920×1200) lẫn bản dọc (mobile)** — trong
  `flutter_client/web/images/guide`, sinh từ 43 bộ test ở `flutter_client/test/guide_shots`.
- Khung dựng video: đã chạy thật 2 lần (`dist/guide-fnb` 4 phút 15, `dist/guide-trasua` 4 video).
- Cách đọc tên riêng HRM đã chốt với người dùng: `dist/promo-hrm/pron.py`.

Đề xuất: **bộ 9 video, tổng khoảng 22 phút**, mỗi video 1 phút 40 đến 3 phút 20 — bằng đúng
độ dài bộ trà sữa mà người dùng đã duyệt.

---

## 2. Tài sản đang có

### 2.1 Giáo trình (nguồn lời thoại)

`landing-guide.json` → `steps` lọc `area == "hrm"`. Mỗi bài có: `title`, `desc`, `bullets`
(các bước làm), `tip`, `keywords`, và `shots` (tên ảnh + chú thích ①②③ + chèn sau ý nào).

| Nhóm | Bài | Ảnh | Dung lượng chữ |
|---|---:|---:|---:|
| Khởi tạo ban đầu | 6 | 14 | ~4.300 |
| Ca & lịch làm việc | 5 | 13 | ~3.400 |
| Chấm công | 9 | 23 | ~8.100 |
| Đơn từ & phê duyệt | 3 | 8 | ~2.000 |
| Lương & chính sách | 7 | 18 | ~4.000 |
| Phiếu tài chính & chốt lương | 5 | 14 | ~2.500 |
| Báo cáo & vận hành hằng ngày | 4 | 5 | ~3.700 |
| Dành cho nhân viên | 1 | 3 | ~1.100 |
| Giao tiếp & công cụ | 7 | 17 | ~4.200 |
| **Tổng** | **47** | **115** | |

Chia theo mức: **26 bài cơ bản (basic)**, **21 bài nâng cao (advanced)**.

### 2.2 Ảnh màn

- 115/115 ảnh HRM **có cả bản ngang và bản `-mobile`** → bản dọc 9:16 không phải chụp lại.
- Ảnh trong `web/images/guide` là bản **đã vẽ sẵn số ①②③ và khung đỏ** — dùng cho trang trợ giúp,
  **không dùng được cho video** (video tự vẽ khung sáng chạy theo lời đọc).
- Bản sạch lấy bằng `GUIDE_SHOT_PLAIN=1` + `GUIDE_SHOT_DIR=<thư mục>`; bản vá ghi kèm
  `<tên>.json` (toạ độ từng điểm đánh dấu) **đã có sẵn trong worktree `E:\gtmp\fnb_video`**
  (`flutter_client/test/guide_shots/guide_shot_kit.dart`, dòng ~329) — chưa commit vào nhánh chính.

### 2.3 Bốn bài KHÔNG có ảnh

`getting_started` (checklist 7 ngày), `daily_ops` (quy trình hằng ngày / cuối tháng),
`common_hrm` (tình huống thường gặp), `ai_assistant` (trợ lý AI).

Ba bài đầu là bài tổng hợp — hợp với **đồ hoạ dựng bằng HTML** (dòng thời gian, bảng việc theo
ngày) hơn là ảnh màn. Riêng `ai_assistant` cần chụp bổ sung, nhưng **tài khoản QA không có khóa
Gemini** nên màn AI local báo «Chưa cấu hình» — phải dựng ảnh bằng mock, hoặc bỏ bài này khỏi video.

### 2.4 Khung dựng (dùng lại nguyên)

`dist/guide-fnb`: ảnh màn sạch + `shots.js` (toạ độ đánh dấu) → `index.html` vẽ khung sáng, số
thứ tự, vòng chạm, camera zoom theo `at('khóa','cụm từ')`; `tts.py` → `timeline.js`;
`probe.js` → `sfx.json`; `audio.py` → `mix.wav`; `render.js` (Playwright + Chrome → ffmpeg).

`dist/guide-trasua`: đúng khung đó nhưng **nhiều video dùng chung một bộ mã** — `videos.py` khai
báo từng video (`ch` = chương, `scn` = khóa câu → ảnh + các cặp [số đánh dấu, cụm từ trong lời
đọc]); `build.py` sinh `index_<vid>.html`. **Đây là khung nên dùng cho HRM**, vì HRM cũng là bộ
nhiều video.

---

## 3. Đề xuất chương trình: 9 video

Ước thời lượng theo tỉ lệ thực đo: guide-fnb 30 câu/4 phút 15 (~8,5 giây/câu);
guide-trasua 15–22 câu/1 phút 38 – 3 phút 34 (~10,5 giây/câu). Lấy **9 giây/cảnh**.

| # | Tên video | Bài trong giáo trình | Cảnh | Ước dài |
|---|---|---|---:|---|
| 1 | **Khởi tạo & nhân sự** | register, org_structure, branches, employees, employee_account | 14 | ~2:40 |
| 2 | **Ca làm việc & phân lịch** | shifts, work_schedule_basic, work_schedule, shift_swap, holidays | 13 | ~2:30 |
| 3 | **Máy chấm công ZKTeco** | device_connect, device_users, gateway_wifi, attendance_modes | 10 | ~2:00 |
| 4 | **Chấm công mobile, sửa công, chấm cơm** | mobile_attendance, attendance_correction, raw_attendance, field_checkin, meal | 13 | ~2:30 |
| 5 | **Đơn từ: nghỉ phép, tăng ca, công tác** | leave, overtime, business_trip | 8 | ~1:40 |
| 6 | **Lương & chính sách** | salary, allowance, insurance_tax, bonus, penalty, production, kpi | 18 | ~3:20 |
| 7 | **Phiếu tài chính & chốt lương tháng đầu** | penalty_ticket, bonus_ticket, advance, cash, first_payroll | 14 | ~2:40 |
| 8 | **Báo cáo & app cho nhân viên** | reports, hr_analytics, daily_ops\*, common_hrm\*, employee_self_service | 8 + đồ hoạ | ~2:10 |
| 9 | **Truyền thông, Zalo, công việc, tài sản** | communication, feedback, notifications, zalo_bot, tasks, asset | 17 | ~3:10 |

\* bài không có ảnh — dựng bằng đồ hoạ HTML.

**Tổng: 115 cảnh, ~22 phút, 9 video.**

### Vì sao chia như vậy

- **Theo đúng 9 nhóm của giáo trình**, chỉ tách nhóm «Chấm công» (9 bài, 23 ảnh — quá dài cho một
  video) thành 2 phần theo đúng ranh giới nghiệp vụ: phần cứng (máy ZKTeco) và phần mềm (mobile,
  sửa công), và gộp nhóm «Báo cáo» với nhóm «Dành cho nhân viên» (cả hai đều quá ngắn để đứng riêng).
- Người xem thường là **chủ quán / kế toán**, mỗi người chỉ cần vài video: chủ mới mở xem 1–2–3,
  kế toán xem 6–7, nhân viên xem 8. Chia nhỏ giúp gửi đúng video cho đúng người.
- Mỗi video dưới 3 phút 30 — đúng khoảng người dùng đã duyệt ở bộ trà sữa.

### Thứ tự quay đề nghị

Quay **video 1, 2, 7** trước. Ba video này phủ trọn vòng đời tối thiểu (lập cửa hàng → phân ca →
ra bảng lương), đủ để gửi khách mới ngay, và là phép thử xem khung dựng có vướng gì với ảnh HRM
không trước khi đổ công vào 6 video còn lại.

---

## 4. Việc phải làm trước khi quay

1. **Chụp lại 115 ảnh bản sạch + JSON toạ độ.**
   Dùng worktree `E:\gtmp\fnb_video` (kit đã vá sẵn để ghi JSON), chạy 43 bộ test guide_shots của
   HRM với `GUIDE_SHOT_PLAIN=1` và `GUIDE_SHOT_DIR` trỏ sang thư mục video.
   Lưu ý: lần chạy ngày 12/11/2026 có **khoảng 55 test lỗi sẵn** (lỗi «ChoiceChip: No Material
   widget» ở advance, org_structure, reports…) nhưng vẫn ra được ~95 ảnh HRM. Phải rà lại danh
   sách ảnh thiếu rồi vá từng test, hoặc dựng màn thiếu bằng HTML.
2. **Tạo `dist/guide-hrm`** theo khuôn `guide-trasua`: `videos.py` (9 video), `build.py`,
   `tts.py`, `audio.py`, `probe.js`, `render.js`, `fin.sh`, `stills.sh`.
3. **Chép `pron.py` từ `dist/promo-hrm`** (đã có SBOX HRM, sboxhrm.com, ZKTeco, KPI, GPS, WiFi)
   và bổ sung: TNCN, BHXH, OT, ADMS nếu lời thoại có.
4. **Viết lời thoại** từ `bullets` của từng bài: mỗi ảnh một câu, câu phải chứa đúng **cụm từ**
   dùng cho `at()` để khung sáng bật đúng lúc. Có sẵn chú thích ①②③ trong `shots[].caption` để
   bám theo.
5. **Bản dọc 9:16**: ảnh `-mobile` đã có đủ; dùng lại `mix.wav` của bản ngang như guide-fnb.

---

## 5. Bẫy đã biết (lấy từ các bộ trước)

- Ảnh trong `web/images/guide` **luôn có đánh dấu** — đừng lấy nhầm cho video.
- Cụm từ truyền cho `at()` phải là **các chữ liền nhau có thật trong đúng câu đó**, nếu không
  `render()` ném lỗi; nên có script kiểm cụm từ trước khi dựng (bộ trà sữa đã có).
- `edge-tts` **lỗi ngẫu nhiên** («No audio received») → `tts.py` phải thử lại có chờ; vài câu lỗi
  mãi thì đổi cách viết.
- `probe.js` ghi `sfx.json` bằng `writeFileSync` có khi không ra file → in `SFX=` rồi chuyển hướng
  ở shell.
- Form dài hơn khung ảnh và **không cuộn được trong test** → chụp với `size` cao hơn rồi cắt ảnh
  và dời toạ độ đánh dấu bằng PIL.
- Lời thoại **chỉ được nói tính năng có trong `landing-guide.json`** — đây cũng là chuẩn để
  không quảng cáo quá khả năng app.
- Trợ lý AI trên QA báo «Chưa cấu hình» vì không có khóa Gemini.

---

## 6. Ước công

| Việc | Ước |
|---|---|
| Chụp lại ảnh sạch + JSON (gồm vá test lỗi) | nặng nhất, phụ thuộc số test hỏng |
| Dựng `dist/guide-hrm` từ khuôn trà sữa | nhẹ — đổi cấu hình, không viết lại lõi |
| Viết lời thoại 115 câu | vừa — bám `bullets` + `caption` sẵn có |
| Sinh giọng, trộn tiếng, quay 9 video × 2 tỉ lệ | máy chạy; mỗi video ~2,5 phút quay mỗi tỉ lệ |

Rủi ro lớn nhất không nằm ở khâu dựng video mà ở **khâu chụp lại ảnh màn**: nếu nhiều test
guide_shots còn hỏng thì phải vá từng cái, đúng như lần làm bộ trà sữa.

---

## 7. Tình trạng (cập nhật 14/11/2026)

Đã dựng bộ `dist/guide-hrm` và làm xong **10 video** (9 video theo kế hoạch + 1 video Trợ lý AI), mỗi video kèm bản dọc 9:16:

| # | Video | Dài |
|---|---|---|
| 1 | Khởi tạo & nhân sự | 3:04 |
| 2 | Ca làm việc & phân lịch | 2:50 |
| 3 | Máy chấm công ZKTeco | 2:41 |
| 4 | Chấm công mobile & sửa công | 3:28 |
| 5 | Nghỉ phép · tăng ca · công tác | 1:55 |
| 6 | Lương & chính sách | 4:02 |
| 7 | Phiếu tài chính & chốt lương | 3:05 |
| 8 | Báo cáo & app cho nhân viên | 3:43 |
| 9 | Truyền thông, Zalo, công việc, tài sản | 4:42 |
| 10 | Trợ lý ảo AI | 2:20 |

Tổng 31 phút 50 giây, 10 tệp ngang + 10 tệp dọc, nằm ở thư mục `video sbox` trên ổ E.

Hai video cuối lệch so với kế hoạch ở ba chỗ:

- **Video 8 dài 3:43 thay vì ~2:10 và có 12 cảnh thay vì 8.** Hai bài `daily_ops`
  (quy trình hằng ngày / cuối tháng) và `common_hrm` (tình huống thường gặp) vốn định dựng
  bằng đồ hoạ HTML — nhưng chúng nói về đúng những màn đã chụp rồi, nên thay vì vẽ thêm,
  hai chương «Nhịp hằng ngày & cuối tháng» và «Số liệu lệch thì sửa gốc» dùng lại ảnh
  `raw-attendance-2`, `first-payroll-3`, `attendance-modes-1`, `shifts-3` của video trước.
  Rẻ hơn, và người xem thấy lại đúng màn phải mở khi gặp sự cố.
- **Video 9 dài 4:42** — 17 cảnh, 6 bài, không cắt được bài nào mà không bỏ hẳn một module.
- **Bài `ai_assistant` nay đã thành video 10.** Lúc lập kế hoạch, QA không có khóa Gemini nên màn
  trợ lý báo «Chưa cấu hình». Ngày 14/11/2026 người dùng cấp khóa, khóa đã nạp vào DB `sbox_qa`
  (cửa hàng QA Restaurant) và trợ lý trả lời thật trong 3–8 giây, nên dựng được video riêng:
  mở trợ lý, hỏi số liệu, ra lệnh và thẻ chờ xác nhận, hỏi cách dùng, quản trị và nhật ký.

Video 6 dài 4 phút — hơn khoảng 3 phút rưỡi của các video khác, vì nhóm «Lương & chính sách»
có 7 bài và 18 màn. Cắt bớt thì mất phần người dùng cần nhất (cách chấm công trong thiết lập
lương, điều kiện phụ cấp, hệ số bảo hiểm), nên giữ nguyên.

Khâu chụp ảnh màn — phần lo nhất khi lập kế hoạch — hoá ra **không phải do test hỏng**:
chế độ ảnh sạch `GUIDE_SHOT_PLAIN=1` bỏ luôn khung trang, mà khung đó mới render thanh nút
trên cùng của các màn HRM. Thêm chế độ `GUIDE_SHOT_VIDEO=1` (giữ khung, chỉ tắt vẽ số) là
21 lỗi biến mất; lần chụp cho video 4–5 thì 44/44 test qua sạch.

Hai việc nên làm, không nằm trong phạm vi bộ video:
- Trang trợ giúp còn ghi nút **«Tải hồ sơ NS»** trên thanh trên cùng của màn Nhân sự chấm công;
  giao diện thật nay là ô lớn **«Tải hồ sơ nhân sự xuống máy»** trong khung Đồng bộ.
- `dist/guide-fnb` và `dist/guide-trasua` còn lỗi **gần 2 giây màn trắng** trước cảnh liên hệ
  (đã sửa trong `guide-hrm`) — các video POS đã giao cho khách đều bị.
