# Tingee — hướng dẫn test

## Mô hình nghiệp vụ Sbox

1. **SuperAdmin** mua gói Tingee → **nạp kho platform** (vd: 10.000 lượt × 200đ)
2. **SuperAdmin bán lại** cửa hàng → trừ kho platform, cộng credit cửa hàng (vd: 1.000 lượt × 300đ)
3. **Cửa hàng** bán hàng Tingee QR → mỗi webhook CK thành công **trừ 1 lượt** credit cửa hàng
4. **Hết lượt** → cửa hàng **mua gói** trong app (CK → webhook → trừ kho platform + cộng cửa hàng)
5. Mỗi cửa hàng có **số VA riêng** (cấu hình tại Cổng thanh toán POS)

## Môi trường

| | Production | UAT (test) |
|---|------------|------------|
| Portal | https://baas.tingee.vn | https://uat-baas-portal.tingee.vn |
| Open API | https://open-api.tingee.vn/v1 | https://uat-open-api.tingee.vn/v1 |
| Webhook Sbox | https://sboxhrm.com/api/webhooks/payment/tingee | (cùng URL, credentials UAT trên platform) |

Tài liệu Tingee: https://developers.tingee.vn/docs/

## SuperAdmin

Tab **Lượt CK Tingee** trong System Admin:

- Nạp kho (mua gói Tingee)
- Cấu hình Client ID / Secret / Webhook Secret (master)
- Chọn **UAT** hoặc **Production**
- Bán lượt cho cửa hàng (trừ kho)

UAT: Tingee đã cấu hình **tài khoản test BIDV** (BIN `970418`) cho SBOX. Gắn STK / tạo VA trên UAT dùng BIDV, không dùng VCB (cổng VCB UAT từng 404).

## Cửa hàng (demopos)

Portal Tingee **Liên kết ngân hàng** (UAT, 25/08/2026):

| | |
|---|---|
| Ngân hàng | BIDV |
| STK thanh toán (settlement) | `8600237579` |
| **Số VA** (khách CK / QR) | `96499085BOX` |
| Chủ TK | SBOX |
| Loại | Doanh nghiệp |
| Cửa hàng Tingee | SBOX demopos |

**Thiết lập → Cổng thanh toán:**

- Bật Tingee
- Số VA trên SBOX = **`96499085BOX`** (không dùng STK `8600237579` cho QR)
- Bank account POS phải có **STK BIDV số** `8600237579` để ra VietQR (VA `96499085BOX` là TK thu hộ — quét VietQR thường BIDV báo **025 không có hóa đơn**)
- Số VA trên SBOX (webhook) = **`96499085BOX`** hoặc STK `8600237579` (cả hai đều khớp cửa hàng)
- Không nhập token — do SuperAdmin quản lý

## Test webhook thủ công

```bash
python scripts/test-tingee-webhook.py \
  --secret "WEBHOOK_SECRET" \
  --client-id "CLIENT_ID" \
  --va "96499085BOX" \
  --amount 50000 \
  --order "TMP999"
```

Kỳ vọng: `{"code":"00","message":"Success"}`

## Checklist E2E

- [ ] SuperAdmin: nạp kho ≥ số lượt sẽ bán
- [ ] SuperAdmin: credentials + UAT/Prod
- [ ] Tingee portal: webhook → sboxhrm.com, Connection Test OK
- [ ] Cửa hàng: VA + bật Tingee
- [ ] SuperAdmin: cấp credit hoặc cửa hàng mua gói
- [ ] POS: bán → Tingee QR → CK → loa + tab Xác nhận CK
- [ ] Credit cửa hàng giảm 1; kho platform giảm khi bán gói
