#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#define CFG_STR_LEN 64
#define CFG_URL_LEN 128

typedef struct {
    char gw_name[CFG_STR_LEN];     /* tên gợi nhớ do người dùng đặt, ví dụ "Cửa trước" */

    char wifi_ssid[CFG_STR_LEN];
    char wifi_pass[CFG_STR_LEN];

    char device_ip[CFG_STR_LEN];   /* IP LAN của máy chấm công */
    uint16_t device_port;          /* mặc định 4370 */
    uint32_t comm_key;             /* Comm Key của máy, 0 = không đặt */

    char server_url[CFG_URL_LEN];  /* ví dụ https://sboxhrm.com */
    char sn_override[CFG_STR_LEN]; /* để trống = dùng SN đọc từ máy */

    uint16_t poll_interval_s;      /* chu kỳ gọi getrequest */
    uint16_t attlog_interval_s;    /* chu kỳ kiểm tra có bản ghi mới */
    uint16_t backfill_days;        /* lần đầu chỉ lấy log trong N ngày gần nhất, 0 = lấy hết */
    int8_t tz_offset_h;            /* múi giờ của máy chấm công, VN = 7 */
    bool sync_device_clock;        /* đồng bộ giờ máy chấm công theo NTP */
} app_config_t;

/* Mốc nước cao: bản ghi mới nhất đã đẩy thành công lên server. */
typedef struct {
    uint32_t last_zk_time;  /* timestamp ZK đã mã hoá của bản ghi cuối */
    uint32_t last_count;    /* số bản ghi mang đúng last_zk_time đã gửi */
} attlog_mark_t;

esp_err_t app_config_init(void);
const app_config_t *app_config_get(void);
esp_err_t app_config_save(const app_config_t *cfg);
bool app_config_is_provisioned(void);

esp_err_t app_config_load_mark(attlog_mark_t *out);
esp_err_t app_config_save_mark(const attlog_mark_t *mark);
esp_err_t app_config_reset_mark(void);

/* SN đã phát hiện từ máy chấm công, lưu lại để dùng khi máy tạm mất kết nối. */
esp_err_t app_config_save_serial(const char *serial);
const char *app_config_effective_serial(void);
