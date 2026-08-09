#pragma once

#include <stdbool.h>

#include "esp_err.h"
#include "esp_http_server.h"

bool portal_password_enabled(void);
bool portal_password_matches(const char *plain);
esp_err_t portal_password_set(const char *plain);
esp_err_t portal_password_clear(void);

/* ESP_OK nếu được phép; nếu không thì đã gửi 401. */
esp_err_t portal_auth_guard(httpd_req_t *req);

/* Cho phép đặt/xóa mật khẩu (đã qua guard nếu cần). */
esp_err_t portal_auth_register(httpd_handle_t server);
