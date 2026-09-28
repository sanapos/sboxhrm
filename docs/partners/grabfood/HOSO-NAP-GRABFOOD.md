# Hồ sơ đăng ký đối tác POS — GrabFood (Vietnam)

Dùng để nộp **GrabFood Partner API** (không phải đăng ký quán bán hàng).  
Docs: https://developer.grab.com/docs/grabfood/  
Portal: https://developer.grab.com/

Điền các chỗ `[...]` trước khi gửi. In PDF kèm GPKD + CCCD người đại diện.

---

## 1. Cách nộp (thứ tự)

1. Người phụ trách kỹ thuật cài **Grab App**, đăng ký SĐT công ty (không dùng SĐT cá nhân nếu có thể).
2. Đăng nhập https://developer.grab.com/ bằng SĐT đó.
3. Nộp **interest form**, chọn category **Food** (POS / merchant integration).
4. Gửi email hồ sơ này tới:
   - `grabfood.vn@grabtaxi.com` (Grab Vietnam — nhà hàng / đối tác)
   - CC: PIC Grab (nếu đã có AM)
5. Chờ Grab duyệt công ty → mời **Staging project** → dev webhook → test → 1 quán pilot production.

---

## 2. Thông tin công ty (điền form)

| Trường | Giá trị |
|--------|---------|
| Legal company name | **[ĐIỀN TÊN PHÁP NHÂN — GPKD]** |
| Trade / product name | SBOX POS (cùng hệ sinh thái SBOX HRM) |
| Country | Vietnam |
| Category | **Food** — POS / SaaS partner |
| Integration type | GrabFood Partner API (order + menu + store) |
| Website | https://sboxhrm.com |
| Product URL | https://sbox.sana.vn |
| Play Store (HRM) | `sbox.sana.vn` |
| Play Store (POS APK) | `sbox.sana.vn.pos.flutter` |
| Office address | 184 Nam Cao, Hòa Khánh, Đà Nẵng, Việt Nam |
| Phone / Zalo | 0973 024 042 |
| Company email | support@sboxhrm.com |
| Tax code (MST) | **[ĐIỀN MST]** |
| Business license | **[ĐÍNH KÈM GPKD PDF]** |
| Year founded | **[ĐIỀN]** |
| Number of employees | **[ĐIỀN]** |
| Number of restaurant / F&B merchants on SBOX POS | **[ĐIỀN SỐ QUÁN ĐANG DÙNG]** |
| Pilot store (GrabFood merchant ID / name) | **[ĐIỀN 1 QUÁN PILOT ĐÃ CÓ GRABFOOD]** |
| Markets | Vietnam (Đà Nẵng, mở rộng toàn quốc) |

### Người liên hệ (PIC)

| Vai trò | Họ tên | SĐT | Email | Grab App SĐT |
|---------|--------|-----|-------|----------------|
| Business / legal | **[ĐIỀN]** | 0973 024 042 | support@sboxhrm.com | **[ĐIỀN]** |
| Technical lead | **[ĐIỀN]** | **[ĐIỀN]** | **[ĐIỀN @sboxhrm.com]** | **[ĐIỀN — dùng login developer portal]** |
| Support 24/7 (sau go-live) | **[ĐIỀN]** | 0973 024 042 | support@sboxhrm.com | — |

---

## 3. Tóm tắt sản phẩm (paste vào form / email)

**SBOX POS** is a cloud POS for Vietnamese F&B and retail, running on Android cashier terminals (Sunmi T1 / A6), handheld / HRM POS (C20Lite / A7), web, and iOS. It already handles dine-in, takeaway, QR online orders, kitchen printing, inventory, e-invoice, and last-mile shipping (e.g. GHTK).

We request to become a **GrabFood POS Partner** so merchants using SBOX POS can:

- Receive GrabFood orders on the same cashier / kitchen printer (no second tablet)
- Sync menu, OOS, and prices from SBOX → GrabFood
- Pause / unpause store and mark orders ready from POS
- Reconcile GrabFood sales in SBOX reports

We will implement the **essential Partner endpoints and GrabFood endpoints** in [GrabFood API v1.1.3](https://developer.grab.com/docs/grabfood/api/v1-1-3), with HTTPS webhooks on our production API (`sbox.sana.vn` / dedicated partner host), OAuth, and a low-traffic **pilot store in Vietnam** before phased rollout.

---

## 4. Phạm vi kỹ thuật (cam kết giai đoạn 1)

Theo bảng *Essential* trên docs GrabFood.

**Partner webhooks (SBOX host, Grab gọi vào):**

| Nhóm | Endpoint |
|------|----------|
| Auth | Get partner access token |
| Onboarding | Push Grab menu; Push integration status |
| Menu | Get menu; Menu sync state |
| Order | Submit orders; Push order state |

**GrabFood APIs (SBOX gọi Grab):**

| Nhóm | Endpoint |
|------|----------|
| Auth | Get GrabFood access token |
| Onboarding | Create self-serve journey |
| Menu | Update menu notification; Update menu record |
| Order | List orders; Edit orders; Mark orders ready; Cancel order |
| Store | Temporarily pause store; Get store status |

**Giai đoạn 2 (sau pilot):** campaign, batch menu, delivery-by-partner, loyalty — nếu Grab yêu cầu.

**SLA kỹ thuật (theo docs):** webhook trả lời trong **10 giây**; HTTPS + TLS; IP whitelist production Grab nếu Grab cấp danh sách.

**Môi trường dự kiến:**

- Staging webhook: `https://[host]/api/grabfood/...` (sau khi Grab cấp project)
- Production: cùng pattern, host production SBOX
- Auth: OAuth2 client credentials, scope `food.partner_api`

---

## 5. Kế hoạch triển khai

| Mốc | Nội dung | Thời gian ước lượng |
|-----|----------|---------------------|
| T0 | Nộp form + email hồ sơ | Ngày gửi |
| T0 + duyệt | Grab mời Staging project | Theo Grab |
| Dev | Webhook + OAuth + map menu/order sang SBOX POS | 3–6 tuần sau khi có staging |
| Staging test | Chạy test case trên developer portal | 1–2 tuần |
| Pilot | 1 quán GrabFood lưu lượng thấp | 1–2 tuần |
| Rollout | Từng cụm quán SBOX đã có GrabFood | Theo Grab |

---

## 6. Tài liệu đính kèm khi gửi

- [ ] GPKD (bản scan màu)
- [ ] CCCD người đại diện (mặt trước/sau)
- [ ] File này (PDF)
- [ ] 3–5 ảnh màn hình SBOX POS: bán hàng, bếp/KDS, đơn online, báo cáo
- [ ] Link website / Play Store
- [ ] Danh sách 1 quán pilot (tên quán GrabFood, địa chỉ, SĐT merchant)

---

## 7. Lưu ý

- Hồ sơ này **không** thay form trên developer.grab.com — vẫn phải nộp form Food.
- Không đăng ký nhầm **GrabPay POS API** (thanh toán tại quầy). Đúng loại: **GrabFood Partner API**.
- 1 quán GrabFood chỉ nên gắn **một** POS partner tại một thời điểm.
- Không scrape GrabMerchant; chỉ dùng API sau khi được cấp credential.
