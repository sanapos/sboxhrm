# Bảo mật sản xuất ESP32-C3 Gateway

Phương án đã chốt khi triển khai nhiều cửa hàng:

1. **Server ADMS cố định** `https://sboxhrm.com` trong firmware (không đổi qua NVS/portal/app).
2. **Flash Encryption + Secure Boot** khi nạp hàng loạt (khó dump ROM chạy được).
3. **OTA dual-bank** để cập nhật nhanh sau lần nạp đầu (USB).

## Server URL khóa cứng

- Macro: `APP_FIXED_SERVER_URL` trong `main/app_config.h`
- `adms_client` luôn nối URL này
- Portal hiển thị read-only; API bỏ qua `serverUrl` client gửi

Lưu ý: chỉ khóa URL **không đủ** chống patch binary. Cần Flash Encryption + Secure Boot.

## Flash Encryption + Secure Boot (sản xuất)

Làm **một lần** trên dây chuyền / máy nạp — không bật nhầm trên bản đang phát triển.

### Chuẩn bị key (giữ offline, backup an toàn)

```powershell
cd E:\zkgw
espsecure.py generate_signing_key --version 2 secure_boot_signing_key.pem
# Key này KHÔNG commit vào git. Lưu khoá cứng / vault.
```

### Nạp lần đầu có mã hóa (Release)

1. Sao chép `sdkconfig.defaults.prod` → merge vào `sdkconfig` (hoặc `idf.py -D SDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfig.defaults.prod"`).
2. Build và flash **có serial** lần đầu để ESP tự mã hóa flash.
3. Sau đó chỉ cập nhật bằng **OTA đã ký** (hoặc `idf.py encrypted-flash`).

Cảnh báo:

- Bật **Release** flash encryption gần như không đảo ngược trên chip.
- Mất signing key = không phát hành OTA mới được.
- Bản dev tiếp tục dùng `sdkconfig.defaults` thường (không encrypt).

## OTA nhiều điểm

Sau khi thiết bị đã ở hiện trường:

1. Build `zk_gateway.bin` (và ký nếu Secure Boot bật).
2. Đưa lên kho firmware sboxhrm (bước server/app — triển khai tiếp).
3. App cùng LAN với gateway → `POST /api/ota`.
4. Dual-bank giữ bản cũ nếu bản mới không boot.

## Checklist sản xuất

- [ ] Signing key backup
- [ ] Flash Encryption Release + Secure Boot v2
- [ ] NVS cấu hình WiFi/IP máy (server đã cố định)
- [ ] Kiểm tra `/api/info` → `server` luôn sboxhrm
- [ ] Thử OTA một máy trước khi roll-out
