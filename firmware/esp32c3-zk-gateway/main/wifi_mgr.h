#pragma once

#include <stdbool.h>

#include "esp_err.h"
#include "esp_wifi.h"

esp_err_t wifi_mgr_init(void);

bool wifi_mgr_is_connected(void);
const char *wifi_mgr_sta_ip(void);
bool wifi_mgr_ap_active(void);
const char *wifi_mgr_ap_ssid(void);
int wifi_mgr_rssi(void);

/* Áp dụng lại thông tin WiFi vừa lưu trong cấu hình. */
esp_err_t wifi_mgr_apply_config(void);

/* Quét WiFi xung quanh cho trang cấu hình. */
int wifi_mgr_scan(wifi_ap_record_t *out, int max);
