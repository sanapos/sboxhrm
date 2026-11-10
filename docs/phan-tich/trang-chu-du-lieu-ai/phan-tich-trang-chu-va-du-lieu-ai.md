# Phân tích trang chủ web và dữ liệu trợ lý AI (04/11/2026, commit 22a47aca)

Chỉ phân tích, chưa sửa mã. Các file liên quan không có thay đổi chưa commit, HEAD đúng commit đang chạy.

## Cách đo

Chạy đúng `AiAssistantHelpCorpus.SearchScored` + `AiAssistantIntent.IsGuideQuestion` trong project tạm ngoài repo
(link file nguồn + nhúng landing-guide.json). Đây là kiểm ở mức hàm tìm kiếm và định tuyến.
Chưa gọi trợ lý thật end-to-end, chưa thử phản hồi của Gemini.

- `[THẲNG]`: khớp IsGuideQuestion, máy chủ trả nguyên bài, không gọi Gemini.
- `[AI]`: đi tiếp theo luồng thường.

## Kết quả tuyến trả lời cho câu «cách / làm sao»

| Câu hỏi | Tuyến | Bài đứng đầu : điểm ; bài 2 : điểm | Nhận xét |
|---|---|---|---|
| cách kết nối máy chấm công | THẲNG | device_connect:246 ; gateway_wifi:226 | đúng |
| hướng dẫn kết nối máy zkteco | THẲNG | device_connect:163 ; pos_scale:89 | đúng |
| máy chấm công mất kết nối phải làm sao | THẲNG | gateway_wifi:235 ; device_connect:221 | sai bài đầu |
| máy chấm công offline lỗi gì | THẲNG | gateway_wifi:208 ; raw_attendance:164 | sai |
| cách khắc phục máy chấm công bị sai giờ | THẲNG | gateway_wifi:211 ; raw_attendance:167 | sai |
| máy chấm công không đẩy dữ liệu được | THẲNG | gateway_wifi:225 ; raw_attendance:164 | sai |
| cách chọn máy chấm công | THẲNG | gateway_wifi:214 ; raw_attendance:167 | sai, thiếu bài |
| làm sao đóng bhxh cho nhân viên | THẲNG | sys_roles_accounts:112 ; zalo_bot:111 | sai, có insurance_tax |
| cách tính bhxh | AI | pos_services:44 ; overtime:36 | sai |
| cách tính lương tăng ca | THẲNG | overtime:165 ; shifts:98 | đúng bài, không có % luật |
| cách tính thuế tncn | THẲNG | insurance_tax:87 ; pos_sell_vat:57 | đúng bài, không có số |
| cách tính giá vốn món ăn | THẲNG | pos_services:79 ; pos_sale_edit:69 | sai, thiếu kiến thức |
| cách xếp ca xoay | THẲNG | shifts:68 ; work_schedule_basic:64 | tạm được |
| làm sao chống chấm công hộ | THẲNG | gateway_wifi:130 ; raw_attendance:127 | sai |
| hướng dẫn chấm công trên macbook | THẲNG | gateway_wifi:130 ; raw_attendance:124 | sai, corpus 0 lần «MacBook» |
| cách đăng ký chấm công bằng qr | THẲNG | mobile_attendance:154 ; gateway_wifi:136 | thiếu kiến thức QR |
| cách tải mẫu bảng lương excel | THẲNG | sys_excel_import_export:103 ; first_payroll:89 | sai, không biết /tai-lieu |
| máy chấm công đời cũ dùng được không | AI | gateway_wifi:280 ; raw_attendance:164 | đúng |

## Kết quả tìm kiếm cho câu không có dấu hiệu hỏi cách

| Câu hỏi | Bài đứng đầu : điểm ; bài 2 : điểm |
|---|---|
| cách thêm nhân viên (đối chứng) | employees:152 ; sys_roles_accounts:121 |
| máy in không in (đối chứng) | pos_printers:93 ; pos_barcode_labels:69 |
| tạo khuyến mãi giờ vàng (đối chứng) | pos_promotions:207 |
| mức đóng bhxh 2026 là bao nhiêu phần trăm | pos_combo:75 ; pos_quotes:73 |
| lương tối thiểu vùng 2026 bao nhiêu | salary:73 ; pos_lots:63 |
| tăng ca ngày lễ tính bao nhiêu phần trăm | overtime:151 ; holidays:133 |
| phép năm được bao nhiêu ngày | leave:85 ; reports:67 |
| giảm trừ gia cảnh thuế tncn bao nhiêu | insurance_tax:211 |
| đi muộn có được phạt tiền không | penalty:49 ; penalty_ticket:47 |
| tính lương theo ngày công công thức thế nào | allowance:121 ; salary:116 |
| tạm ứng lương tối đa bao nhiêu | advance:140 ; business_trip:100 |
| quy trình onboarding nhân viên mới | ind_commission:131 ; sys_roles_accounts:118 |
| cách tính food cost giá vốn món ăn | pos_services:73 ; pos_sale_edit:69 |
| máy chấm công báo offline không đẩy dữ liệu | gateway_wifi:225 ; raw_attendance:164 |
| máy chấm công bị sai giờ | gateway_wifi:211 ; raw_attendance:167 |
| máy chấm công trùng mã nhân viên bộ nhớ đầy | gateway_wifi:234 ; raw_attendance:228 |
| máy zkteco model nào tương thích | device_connect:65 ; device_users:49 |
| nên mua máy khuôn mặt hay vân tay | device_users:154 ; raw_attendance:104 |
| chi phí lắp đặt máy chấm công bao nhiêu | gateway_wifi:214 ; raw_attendance:170 |
| có lắp máy chấm công ở đà nẵng không | gateway_wifi:220 ; raw_attendance:164 |
| chọn máy in 58 hay 80mm | pos_printers:103 ; pos_barcode_labels:81 |
| dùng macbook có chấm công được không | gateway_wifi:136 ; raw_attendance:124 |
| dữ liệu chấm công cloud có an toàn không | gateway_wifi:139 ; attendance_modes:132 |
| chấm công bằng mã qr được không | gateway_wifi:133 ; raw_attendance:127 |
| chuyển từ phần mềm cài máy tính sang online | pos_rules:74 ; device_connect:72 |
| mẫu bảng lương excel tải ở đâu | first_payroll:112 ; sys_excel_import_export:97 |
| giá phần mềm bao nhiêu tiền một năm | sys_service_package:109 ; pos_quotes:82 |
| gói máy chấm công gồm những gì | gateway_wifi:211 ; raw_attendance:177 |
| duyệt lịch làm việc ở đâu | work_schedule_basic:141 ; work_schedule:139 |
| sửa mẫu in báo giá ở đâu | pos_quotes:142 ; pos_printers:113 |
| quản trị hệ thống để làm gì | sys_system_params:70 ; zalo_bot:47 |
| thiết lập thông báo ở đâu | notifications:115 ; salary:114 |
| báo cáo chấm công xem ở đâu | hr_analytics:175 ; reports:173 |
| báo cáo đi trễ về sớm | penalty_ticket:176 ; hr_analytics:145 |
| báo phục vụ món đã xong trên màn hình bếp | pos_kds:211 ; pos_customer_display:110 |
| app nhân viên có những chức năng gì | sys_roles_accounts:126 ; employees:119 |

## Nguyên nhân lệch bài

`ScoreChunk` (AiAssistantHelpCorpus.cs:638) cộng điểm cho từng bullet chứa từ khóa, không giới hạn, và không hạ trọng số từ phổ biến.
Bài gateway_wifi có «máy chấm công» trong tiêu đề, từ khóa, tóm tắt và nhiều bullet, nên thắng mọi câu có cụm này.
`IsGuideQuestion` (AiAssistantIntent.cs:165) chỉ đòi điểm ≥ 45. Các câu trên đều đạt mức này, nên bài sai được trả thẳng, không qua Gemini.

## Số liệu kho nội dung

- landing-guide.json: 93 bước (basic 26, advanced 21, pos 37, industry 9); guide.html có 96 thẻ h3 và 221 ảnh.
- 23 bài chỉ có ở máy chủ (ServerChunks), chưa có trong app guide và guide.html: pos_ai_read_order, sys_ai_export, pos_promotions,
  pos_vouchers, pos_stock_transfer, pos_reorder_purchase, sys_service_package, pos_table_transfer_merge_split, pos_sell_vat, pos_scale,
  pos_barcode_labels, pos_offline_sale, sys_dashboard_overview, pos_branch_report, pos_gym_trainer_checkin, sys_excel_import_export,
  pos_cash_book, sys_change_forgot_password, sys_change_language, sys_roles_accounts, sys_system_params, sys_reset_trial_data,
  sys_multi_device_login.
- 12 bước chưa có ảnh: getting_started, daily_ops, common_hrm, ai_assistant, pos_devices, pos_customer_display, pos_booking, pos_quotes,
  pos_shipping, pos_stock_rules, pos_common, pos_rules.
- Seo/Seed: 82 file, 488 KB (64 bài viết, 18 trang tính năng; hrm 51, pos 31). Đã nhúng sẵn vào Api (Sbox.SeoSeed.*.md). Trợ lý không đọc.
- Số lần xuất hiện trong corpus (JSON / C#) so với số file Seed:
  150% 0/0 so với 8; 300% 0/0 so với 7; 10,5% 0/0 so với 3; 15,5 triệu 0/0 so với 2; bộ nhớ đầy 0/0 so với 1; tên model ZKTeco 0/0 so với 2; MacBook 0 trong JSON.
- Chuỗi không có trong JSON lẫn HelpCorpus.cs: «Quản trị hệ thống», «Thiết lập thông báo», «Phản ánh», «BOSS», «Nhân Viên» (viết hoa, tên app).
- AiAssistantMenuMap.cs còn khớp: chạy lại gen_ai_menu_map.py ra file ngoài repo, không có khác biệt so với bản hiện tại.

## Trang đang chạy

| Chỉ số | sboxhrm.com | sboxpos.com |
|---|---|---|
| Chiều cao trang | 18.358 px (cửa sổ 1024 px), 17.052 px (375 px) | 15.134 px (trong pane máy tính) |
| Chữ trong HTML gốc | 3.552 từ | 3.203 từ |
| #pricing trong HTML gốc | 41 từ (giá do JS nạp) | 41 từ |
| Hướng dẫn trên menu chính | có | không (lớp site-hrm-nav bị bỏ) |
| /llms.txt | 200, trả HTML index | 200, trả HTML index |
| Số URL trong sitemap | 97 | 38 |

- guide.html (HTML 309 KB, 26.039 từ): cao 230.417 px trên điện thoại, không có ô tìm kiếm, 96 h3 trên một URL.
- guide.html trên sboxpos có canonical trỏ về sboxhrm.com, nút quay lại ghi «Trang chủ SBOX HRM», và không có trong sitemap POS.
- HRM màn 375 px: articles 2.708 px, faq 2.562 px, platforms 1.425 px. Màn 1024 px: screenshots 4.679 px.
- Title POS: HTML gốc «Phần mềm bán hàng POS cho quán cafe, nhà hàng» (render-site-home.py:93), JS đổi thành
  «Phần mềm POS bán hàng, quản lý cửa hàng & kho» (site-seo.js:26). Script ghi chú phải giữ hai nơi khớp nhau.
- Màu: render-site-home.py:36 dùng #0C56D0, home.html dùng #158DC0. Khối chèn lúc deploy căn trái, không có nhãn nhỏ như các khối gốc.
- Chưa kiểm chứng: «500+ doanh nghiệp, 10.000+ nhân viên, 99.9% uptime» trên hero.
- Chưa kiểm tính đúng của số liệu luật trong các bài Seed.
