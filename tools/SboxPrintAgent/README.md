# SBOX — Máy in cửa hàng (Windows) v1.3.6

## Chạy

`tools/SboxPrintAgent/dist/v1.3.6/SboxPrintAgent.exe`

## UI tối giản

1. Đăng nhập cửa hàng  
2. Thêm máy in **LAN** (quét :9100) hoặc **USB** (driver Windows)  
3. Đặt tên / đổi tên / in thử / xóa  
4. Xem **Online / Offline** (probe mỗi 15s)  
5. Agent tự nhận lệnh in từ server (không cấu hình route phức tạp trên tool)

Gán loại phiếu chi tiết để trên **POS / server**. Tool chỉ gắn mặc định hóa đơn + bếp + tem khi thêm máy mới.

## Build

```powershell
cd tools/SboxPrintAgent/SboxPrintAgent
dotnet publish -c Release -o ..\dist\v1.3.6
Copy-Item ..\dist\v1.3.6\SboxPrintAgent.exe ..\dist\SboxPrintAgent.exe -Force
```
