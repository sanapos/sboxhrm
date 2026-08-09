#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#define CFG_STR_LEN 64
#define CFG_URL_LEN 128

/* Khóa cứng máy chủ ADMS — không cho đổi qua portal/NVS/app.
 * Firmware bị sao chép vẫn phải nối dịch vụ sboxhrm.com. */
#define APP_FIXED_SERVER_URL "https://sboxhrm.com"

typedef struct {
    char gw_name[CFG_STR_LEN];     /* tên gợi nhớ do người dùng đặt, ví dụ "Cửa trước" */

    char wifi_ssid[CFG_STR_LEN];
    char wifi_pass[CFG_STR_LEN];

    char device_ip[CFG_STR_LEN];   /* IP LAN của máy chấm công */
    uint16_t device_port;          /* mặc định 4370 */
    uint32_t comm_key;             /* Comm Key của máy, 0 = không đặt */

    char server_url[CFG_URL_LEN];  /* luôn = APP_FIXED_SERVER_URL (giữ field cho JSON tương thích) */
    char sn_override[CFG_STR_LEN]; /* để trống = dùng SN đọc từ máy */

    uint16_t poll_interval_s;      /* chu kỳ gọi getrequest */
    uint16_t attlog_interval_s;    /* chu kỳ kiểm tra có bản ghi mới */
    uint16_t backfill_days;        /* lần đầu chỉ lấy log trong N ngày gần nhất, 0 = lấy hết */
    int8_t tz_offset_h;            /* múi giờ của máy chấm công, VN = 7 */
    bool sync_device_clock;        /* đồng bộ giờ máy chấm công theo NTP */

    /* Xóa toàn bộ log trên máy theo lịch hàng tháng (máy ZK không xóa theo khoảng ngày).
     * An toàn: chỉ xóa sau khi đã đẩy log lên server thành công trong cùng vòng. */
    bool auto_clear_attlog;        /* mặc định tắt */
    uint8_t auto_clear_day;        /* ngày trong tháng 1..28 */
    uint8_t auto_clear_hour;       /* 0..23 theo giờ địa phương (tzOffset) */
    uint8_t auto_clear_min;        /* 0..59 */
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

/* YYYYMM lần gần nhất đã xóa log định kỳ thành công (0 = chưa bao giờ). */
uint32_t app_config_last_auto_clear_ym(void);
esp_err_t app_config_save_last_auto_clear_ym(uint32_t yyyymm);

/* SN đã phát hiện từ máy chấm công, lưu lại để dùng khi máy tạm mất kết nối. */
esp_err_t app_config_save_serial(const char *serial);
const char *app_config_effective_serial(void);
const char *app_config_detected_serial(void);

/* Xoá SN đã đọc từ máy cũ — gọi khi đổi IP/cổng/Comm Key máy chấm công. */
esp_err_t app_config_clear_detected_serial(void);

/* true nếu thông số kết nối tới máy chấm công khác bản trước đó. */
bool app_config_device_target_changed(const app_config_t *before, const app_config_t *after);

/* Hash SHA-256 hex (64 ký tự) của mật khẩu portal; rỗng = không khóa. */
const char *app_config_portal_pass_hash(void);
esp_err_t app_config_save_portal_pass_hash(const char *hash_hex);
