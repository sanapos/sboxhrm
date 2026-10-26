#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#define LC_MAX_CH      10
#define LC_STR_LEN     64
#define LC_URL_LEN     128
#define LC_KEY_LEN     80
#define LC_CODE_LEN    24

#define LC_DEFAULT_SERVER "https://sboxhrm.com"

/* Chế độ từng kênh: theo máy chủ, ép bật, ép tắt (bảo trì / dọn bàn). */
typedef enum {
    CH_AUTO = 0,
    CH_FORCE_ON = 1,
    CH_FORCE_OFF = 2,
} ch_mode_t;

typedef struct {
    int8_t gpio;                  /* -1 = kênh không dùng */
    char table_code[LC_CODE_LEN]; /* mã bàn trên POS (ví dụ "B01"), rỗng = không gắn bàn */
    uint8_t mode;                 /* ch_mode_t */
} lc_channel_t;

typedef struct {
    char name[LC_STR_LEN];        /* tên gợi nhớ, ví dụ "Tủ điện tầng 1" */
    char wifi_ssid[LC_STR_LEN];
    char wifi_pass[LC_STR_LEN];
    char server_url[LC_URL_LEN];
    char device_key[LC_KEY_LEN];  /* lấy trong app: Bán hàng → Đèn bàn bi-a */
    char admin_pass[LC_STR_LEN];  /* rỗng = trang web không khóa */

    bool active_low;              /* module relay kích mức thấp (đa số module 5V) */
    uint16_t poll_ms;             /* chu kỳ hỏi máy chủ */
    uint16_t offline_off_min;     /* mất máy chủ quá N phút thì tắt hết, 0 = giữ nguyên */

    lc_channel_t ch[LC_MAX_CH];
} light_config_t;

esp_err_t light_config_init(void);
const light_config_t *light_config_get(void);
esp_err_t light_config_save(const light_config_t *cfg);
esp_err_t light_config_erase(void);
bool light_config_is_provisioned(void);

/* Trạng thái relay lần cuối (bit i = kênh i) — khôi phục khi mất điện chập chờn giữa trận. */
uint16_t light_config_load_last_mask(void);
void light_config_save_last_mask(uint16_t mask);
