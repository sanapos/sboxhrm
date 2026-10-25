# BÀN GIAO — Trang chủ sboxhrm/sboxpos, link tải, deploy còn dở (04/10/2026)

Trả lời người dùng bằng **tiếng Việt**. Repo: `E:\SBOX CURSOR\ZKTecoADMS-master`, nhánh `fix/tingee-agent-scope-deploy`
(đã push, HEAD = `23b7271d`). Có **một phiên Claude khác cùng làm trong repo** → trước khi commit luôn `git status`,
chỉ `git add` đúng file mình sửa; không commit rác (`.tmp-*`, apk, log, `docs/shots`, firmware, `test/_shots`).

## 1. Đã làm xong

| Commit | Nội dung | Trạng thái |
|---|---|---|
| `46a20e2e` | Cuộn & phân trang (SboxScrollBehavior kéo chuột, AppTableScroll giữ vị trí + 2 thanh cuộn, sbox_table…) | Đã push, web sboxhrm đã deploy |
| `a0baf0ee` | Trang chủ: khối «Mô hình áp dụng» `#mo-hinh` (HRM), mobile gọn (băng chuyền vuốt + chấm, tính năng 2 cột), SEO title/desc/keywords thống nhất `render-site-home.py` ↔ `site-seo.js`, +4 FAQ; trang con SEO (`SeoPages.cs`, `SeoPages.Landing.cs`): menu chip vuốt ngang + thanh Gọi/Dùng thử trên mobile, H1/keywords /tinh-nang, /bang-gia | Đã push. **Phần trang chủ đã lên web; phần trang con cần deploy API** |
| `23b7271d` | Sửa link tải trong `flutter_client/web/home.html` (xem mục 3) | Đã push, web sboxhrm đã deploy; **sboxpos chưa deploy** |

Web sboxhrm.com đang chạy build `1791110123` (v1.0.713), đã kiểm tra live: có `#mo-hinh`, `site-solutions`, FAQPage,
nút APK HRM đúng, mobile không tràn ngang.

## 2. CÒN PHẢI LÀM (bị chặn quyền ở phiên trước — cần người dùng cho phép SSH/SCP)

1. **Deploy API sboxhrm** (103.133.224.176) để trang con có giao diện mobile mới:
   ```bash
   K="/c/Users/TH DECOR/.ssh/sbox_deploy_ed25519"; S=root@103.133.224.176
   git archive --format=tar.gz -o "$TEMP/api_src.tar.gz" HEAD:src
   tr -d '\r' < _deploy_api.sh > "$TEMP/_deploy_api.sh"
   ssh -i "$K" $S "docker tag zktecoadms-api:latest zktecoadms-api:rollback-20261004b"   # bản dự phòng
   scp -i "$K" "$TEMP/api_src.tar.gz" $S:/root/api_src.tar.gz
   scp -i "$K" "$TEMP/_deploy_api.sh" $S:/root/_deploy_api.sh
   ssh -i "$K" $S "chmod +x /root/_deploy_api.sh && /root/_deploy_api.sh"
   ```
   Kiểm tra: `curl -s https://sboxhrm.com/tinh-nang | grep -c 'class="mbar"'` ≥ 1.
2. **Deploy web sboxpos.com** (103.133.225.67) — để sửa link «Google Play» đang trỏ app HRM và Print Agent 404.
   Dùng `scripts/deploy-flutter-web-only.ps1 -Target sboxpos` (đã gồm `render-site-home.py --site pos` + patch) hoặc
   làm tay như sboxhrm (worktree sạch → `flutter build web --release --dart-define=API_BASE_URL=https://sboxpos.com --no-wasm-dry-run`
   → `patch-flutter-web-build.ps1` → **`render-site-home.py --site pos`** → tar → scp → `_deploy_flutter_web_only.sh`).
   Phiên trước SSH tới 103.133.225.67 bị chặn — hỏi người dùng / kiểm tra key có vào được server này không.
3. **Print Agent trên sboxpos.com**: `/downloads/sbox-print-agent.exe` và `/api/app/print-agent-release` trả 404 ở sboxpos.
   Trang chủ đã tạm trỏ sang `https://sboxhrm.com/api/app/print-agent-windows` (chạy được). Muốn tải tại chỗ: chép
   `sbox-print-agent.exe` + `sbox-print-agent-release.json` từ wwwroot/downloads của sboxhrm sang sboxpos (cần đồng ý người dùng).
4. **APK cũ trên server**: `sbox-hrm.apk` = 1.0.556 (04/09) trong khi code 1.0.713; `sbox-pos.apk` = 1.0.409 (sboxhrm) /
   1.0.410 (sboxpos) trong khi `flutter_pos` = 1.0.449. Máy này **không có `android/key.properties`** → không build APK ký đúng
   được tại chỗ. Hỏi người dùng APK trước đây build ở đâu (Codemagic workflow Android?). Upload qua Super Admin → Server Ops
   (`ServerOpsService.cs` nhận `sbox-hrm.apk`, `sbox-hrm-release.json`) hoặc `scripts/deploy-pos-apk.ps1`.

## 3. Hiện trạng link tải (đã kiểm tra live 04/10)

| URL | sboxhrm.com | sboxpos.com |
|---|---|---|
| `/downloads/sbox-hrm.apk` (+ `sbox-hrm-release.json`) | 200 (85 MB, v1.0.556) | 404 |
| `/downloads/sbox-pos.apk`, `/api/app/pos-android-apk` | 200 | 200 |
| `/downloads/sbox-print-agent.exe`, `/api/app/print-agent-windows` | 200 (v1.4.5) | **404** |
| `/tai-lieu/tai/<slug>` (6 file Excel) | 200 | 200 |
| Google Play `sbox.sana.vn` (HRM) | có | — (POS `sbox.sana.vn.pos.flutter` **không** có trên Play) |

Code trong `home.html` sau `23b7271d`: `enrichHrmAndroidDownload()` (HRM, đọc `sbox-hrm-release.json`, gắn `#pf-apk`),
`wirePosAndroidLinks()` (POS: `#pf-apk`, `#footer-android` → `/api/app/pos-android-apk`), hằng `PRINT_AGENT_URL`,
`renderDownloads()` ghi «Liên hệ nhận file» cho link `#...`.

## 4. Quy tắc bắt buộc

- SSH chỉ bằng key `/c/Users/TH DECOR/.ssh/sbox_deploy_ed25519`; **không** dùng mật khẩu người dùng đưa; không in token Codemagic / API key.
- DB production: chỉ đọc (schema/count).
- Chỉ deploy/push khi người dùng yêu cầu; mặc định chỉ sboxhrm. Người dùng đã nói «LÀM TẤT CẢ HOÀN THIỆN» (gồm sboxpos, APK) nhưng phiên trước bị chặn quyền → xác nhận lại trước khi đụng sboxpos.
- **Deploy web luôn chạy `render-site-home.py --site hrm|pos`** (bỏ qua là mất khối SEO trang chủ). Build từ worktree sạch: `git worktree add --detach $TEMP/hrm_web_wt HEAD`, xong `git worktree remove --force`.
- Codemagic iOS: `$env:CODEMAGIC_APP_ID="69e0e613c1f93e9ae6f71a2f"; .\scripts\trigger-codemagic-ios.ps1 -Workflow ios-release -Branch fix/tingee-agent-scope-deploy`.
- Commit kết thúc bằng `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## 5. Việc treo khác (chờ người dùng)

- Super Admin AI: sau deploy API, người dùng cần chuyển model sang `gemini-flash-latest` và thử lại.
- Đề xuất giọng đọc Gemini TTS tự nhiên — chờ quyết định.
- Câu FAQ «miễn phí» trong `render-site-home.py` viết thận trọng (không nêu thời hạn dùng thử) — nhờ người dùng duyệt nội dung.
- Thanh nav desktop trang chủ hơi chật (thêm Bài viết/Tài liệu) — có thể gọn lại.
