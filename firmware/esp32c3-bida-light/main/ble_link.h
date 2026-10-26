#pragma once

#include <stdint.h>

#include "esp_err.h"

/*
 * Cài đặt qua Bluetooth LE bằng app SBOX (như gateway chấm công):
 * WiFi + khóa thiết bị, rồi gán lần lượt từng kênh relay cho bàn, có lệnh bật thử đèn.
 *
 * Quảng cáo tên "SBOX-Den-XXXX". GATT service (UUID phía app):
 *   a6b10002-0a7c-4b8e-9f21-5b0c90000001
 *     ...0002  lệnh (write JSON)   {"op":"wifi"|"channels"|"test", ...}
 *     ...0003  trạng thái (read/notify)
 *     ...0004  thông tin + kênh hiện tại (read)
 *
 * Chưa cài đặt: luôn quảng cáo. Đã cài: chỉ trong 10 phút sau khi cấp điện / nhấn nút BOOT,
 * hoặc khi mất WiFi — người ngoài quán không dò được để đổi cấu hình.
 */
esp_err_t ble_link_start(void);

/* Mở lại cửa sổ quảng cáo thêm window_ms (nhấn nhanh nút BOOT). */
void ble_link_open_window(uint32_t window_ms);
