#pragma once

#include <stdbool.h>

#include "esp_err.h"

/* Vào WiFi theo cấu hình; chưa cấu hình hoặc mất WiFi quá 60 giây → phát điểm cấu hình
 * "SBOX-Den-XXXX" (mật khẩu sbox12345), trang web ở http://192.168.4.1. */
esp_err_t wifi_link_init(void);

bool wifi_link_connected(void);
const char *wifi_link_ip(void);
bool wifi_link_ap_active(void);
const char *wifi_link_ap_ssid(void);
int wifi_link_rssi(void);

/* Nối lại WiFi theo cấu hình vừa lưu (cài qua Bluetooth, không khởi động lại). */
esp_err_t wifi_link_apply(void);
