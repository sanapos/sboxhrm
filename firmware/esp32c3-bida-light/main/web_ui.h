#pragma once

#include "esp_err.h"

/* Trang quản lý trên cổng 80: trạng thái, gắn kênh relay ↔ mã bàn, bật/tắt tay. */
esp_err_t web_ui_start(void);
