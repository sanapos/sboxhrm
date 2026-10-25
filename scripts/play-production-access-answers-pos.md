# SBOX POS — Câu trả lời Production Access (Google Play)

> **App:** SBOX POS (`sbox.sana.vn.pos`) · Alpha khép kín · Feedback: sanapos.vn@gmail.com  
> **Không** dán bản HRM. Lần HRM bị trả vì “cần thử nghiệm thêm” — form POS phải nêu **cập nhật trong kỳ test + feedback cụ thể**.  
> Form Console thường **tiếng Anh** — dán khối English.

**Không làm trước khi Apply:** không upload AAB mới, không xóa tester, không tạm dừng kênh Alpha (tránh rớt dưới 12 opted-in).

---

## Checklist

- [ ] Dashboard: ≥12 opted-in **liên tục 14 ngày** (không đếm list 21 email)
- [ ] Nút **Đăng ký phát hành công khai** đã bật
- [ ] Alpha đang phát hành **1.0.604 (14604)** (không còn nháp treo)
- [ ] Privacy: https://sboxpos.com/privacy-policy.html ghi **SBOX POS** (không phải HRM)
- [ ] Tester vẫn opted-in trên https://play.google.com/apps/testing/sbox.sana.vn.pos

---

## How did you recruit testers?

```
We recruited 21 closed testers from cashiers, store owners, and partners already using SBOX POS in real shops in Vietnam (F&B and retail). They were added to the Play Console email list "Kiểm thử SBOX" and asked to opt in with their personal Gmail accounts via https://play.google.com/apps/testing/sbox.sana.vn.pos . We invited more than 12 testers so the count stays above Google's minimum if someone leaves the test.
```

---

## Describe tester engagement during closed testing

```
During closed testing on the Alpha track, testers used SBOX POS on real Android phones in production-like shop conditions. Core flows: store-code login (sboxpos.com), selling (cart, VAT, cash/transfer/QR), receipts, kitchen/bar tickets, product catalog and stock, shifts / end of day, and online/table QR orders where the shop uses them.

Cashiers open the app throughout the shift the same way we expect production users to work. Feedback went to sanapos.vn@gmail.com, Zalo/hotline 0973 024 042, and Play Console pre-launch reports. We watched Android vitals for crashes on login and sell.
```

---

## Who is your target audience?

```
SBOX POS targets small and medium restaurants and retail shops in Vietnam that need a cloud cash register: cashiers taking orders and payments, and store managers handling products, inventory, shifts, and reports. The app is not a consumer social app. Access is limited to staff provisioned by the merchant on https://sboxpos.com .
```

---

## How does your app provide value to users?

```
SBOX POS replaces a standalone cash register plus paper kitchen tickets with one app: checkout, receipts, kitchen printing, stock, customers, and daily reports on the merchant's SBOX POS server. Staff do not need a separate HR app to sell. Data stays on the merchant's store account; we do not sell user data or show ads.
```

---

## Summarize feedback from testers and how you collected it

```
Channels: (1) sanapos.vn@gmail.com in Play Console closed-test feedback, (2) Zalo/hotline 0973 024 042, (3) Play pre-launch / vitals.

Main themes:
1. Screens opened from the POS hub hid the title and back button, so cashiers could not return to sell.
2. Drink sizes (M/L) took too much space on the item picker; milk-tea shops could not change size quickly.
3. Early builds still pointed some testers at the wrong API host; shops on sboxpos.com needed the app to talk only to https://sboxpos.com .
4. Testers could not find the app by searching Play until they opened the closed-test opt-in link (expected for closed testing; we resent https://play.google.com/apps/testing/sbox.sana.vn.pos ).

Each report included shop, device, app version, and steps.
```

---

## What changes did you make based on tester feedback?

```
We shipped multiple Alpha updates during closed testing (updates do not reset the 14-day opted-in clock):

• 1.0.2 (versionCode 14555) — 3 Sep 2026: first closed-test release, API https://sboxpos.com , restored page title and back button on POS/settings screens.
• 1.0.558 (versionCode 14558) — follow-up Alpha: same host, production-like package for Play testers.
• 1.0.604 (versionCode 14604) — 9 Sep 2026: compact unit picker (M/L on the row instead of large chips) and milk-tea size selection fixes, plus sell/print/kitchen updates from cashier feedback.

We asked the same testers to update from the closed-test Play listing and keep the app installed so they stayed opted in.
```

---

## Crashes / ANRs

```
Pre-launch did not show a crash cluster that blocked login or selling. Isolated device issues were reviewed; main cashier flows stayed usable on the devices testers used. If Console vitals list a specific crash, we will name the version that addressed it.
```

---

## Overall summary / production readiness

```
SBOX POS completed closed testing on Alpha with 21 invited testers (buffer above 12). Testers are real cashiers and shop managers in Vietnam using checkout, receipts, kitchen tickets, and inventory on https://sboxpos.com . We collected feedback by email and support chat, shipped 1.0.2 → 1.0.558 → 1.0.604 with specific UX and size-picker fixes, and kept testers opted in via https://play.google.com/apps/testing/sbox.sana.vn.pos . Privacy policy and Data safety are published. The app is employer/merchant provisioned, not a general-consumer social app. We believe it is stable and ready for production on Google Play.
```

---

## Nếu Google trả “cần thử nghiệm thêm” (bài học HRM 3/6/2026)

Đơn **không** làm mất 14 ngày nếu tester vẫn opted-in. Nộp lại ngay, nhấn:

1. Đã có **3 bản** trong kỳ test (1.0.2 / 1.0.558 / 1.0.604).
2. Feedback cụ thể (nút Back, size M/L, host sboxpos.com) + bản sửa.
3. Tester là **thu ngân thật**, không phải tài khoản ảo.
4. Không opt-out trong 14 ngày.

Không upload AAB mới chỉ để “có bản khác” trước khi nộp lại.
