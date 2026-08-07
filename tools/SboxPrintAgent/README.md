# SBOX — Kết nối máy in (Windows) v1.3

## Chạy

`tools/SboxPrintAgent/dist/v1.3/SboxPrintAgent.exe`

## Tính năng

- Logo / icon SBOX HRM
- Đăng nhập (mặc định https://sboxhrm.com), hiện/ẩn mật khẩu
- Máy in mạng (LAN :9100) và máy in USB (driver Windows)
- Gán phiếu in bằng tên dễ hiểu (hóa đơn, báo bếp, tem…)
- Bật nhận lệnh in từ phần mềm bán hàng

## Build

```powershell
cd tools/SboxPrintAgent/SboxPrintAgent
dotnet publish -c Release -o ..\dist\v1.3
```
