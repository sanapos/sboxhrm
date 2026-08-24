#pragma once

#include <stdbool.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Cấu hình WiFi qua Bluetooth LE khi chưa provisioned.
 * Điện thoại giữ WiFi nhà / Internet; không cần nối SoftAP.
 *
 * Quảng cáo tên giống SoftAP: SBOX-Gateway-XXXX.
 * GATT service (UUID string phía app):
 *   a6b10001-0a7c-4b8e-9f21-5b0c90000001
 */
esp_err_t ble_prov_start(void);
void ble_prov_stop(void);
bool ble_prov_is_active(void);

/** Gọi khi STA đã có IP — cập nhật status notify và tắt quảng cáo nếu đã cấu hình. */
void ble_prov_on_wifi_connected(void);

#ifdef __cplusplus
}
#endif
