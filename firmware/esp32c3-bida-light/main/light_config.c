#include "light_config.h"

#include <stdlib.h>
#include <string.h>

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "nvs.h"
#include "nvs_flash.h"

static const char *TAG = "cfg";

#define NVS_NS        "bidalight"
#define KEY_CFG       "cfg"
#define KEY_MASK      "mask"
#define CFG_VERSION   1

typedef struct {
    uint32_t version;
    light_config_t cfg;
} stored_t;

static light_config_t s_cfg;
static SemaphoreHandle_t s_lock;

/* Chân an toàn trên ESP32-C3: bỏ GPIO2/8/9 (chân strapping lúc khởi động) và 18/19 (USB).
 * Console qua USB Serial/JTAG nên GPIO20/21 (UART0) dùng được. */
static const int8_t DEFAULT_PINS[LC_MAX_CH] = {0, 1, 3, 4, 5, 6, 7, 10, 20, 21};

static void set_defaults(light_config_t *c)
{
    memset(c, 0, sizeof(*c));
    strlcpy(c->name, "Den ban bida", sizeof(c->name));
    strlcpy(c->server_url, LC_DEFAULT_SERVER, sizeof(c->server_url));
    c->active_low = true;
    c->poll_ms = 2000;
    c->offline_off_min = 0;
    for (int i = 0; i < LC_MAX_CH; i++) {
        c->ch[i].gpio = i < 8 ? DEFAULT_PINS[i] : -1;
        c->ch[i].mode = CH_AUTO;
    }
}

esp_err_t light_config_init(void)
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    if (err != ESP_OK) {
        return err;
    }
    s_lock = xSemaphoreCreateMutex();
    set_defaults(&s_cfg);

    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READONLY, &h) != ESP_OK) {
        return ESP_OK;
    }
    stored_t *st = calloc(1, sizeof(stored_t));
    size_t len = sizeof(stored_t);
    if (st != NULL && nvs_get_blob(h, KEY_CFG, st, &len) == ESP_OK
        && len == sizeof(stored_t) && st->version == CFG_VERSION) {
        s_cfg = st->cfg;
        s_cfg.name[LC_STR_LEN - 1] = '\0';
        s_cfg.wifi_ssid[LC_STR_LEN - 1] = '\0';
        s_cfg.wifi_pass[LC_STR_LEN - 1] = '\0';
        s_cfg.server_url[LC_URL_LEN - 1] = '\0';
        s_cfg.device_key[LC_KEY_LEN - 1] = '\0';
        s_cfg.admin_pass[LC_STR_LEN - 1] = '\0';
        for (int i = 0; i < LC_MAX_CH; i++) {
            s_cfg.ch[i].table_code[LC_CODE_LEN - 1] = '\0';
        }
    } else {
        ESP_LOGW(TAG, "chua co cau hinh (hoac khac phien ban) - dung mac dinh");
    }
    free(st);
    nvs_close(h);
    return ESP_OK;
}

const light_config_t *light_config_get(void)
{
    return &s_cfg;
}

esp_err_t light_config_save(const light_config_t *cfg)
{
    stored_t *st = calloc(1, sizeof(stored_t));
    if (st == NULL) {
        return ESP_ERR_NO_MEM;
    }
    st->version = CFG_VERSION;
    st->cfg = *cfg;

    nvs_handle_t h;
    esp_err_t err = nvs_open(NVS_NS, NVS_READWRITE, &h);
    if (err == ESP_OK) {
        err = nvs_set_blob(h, KEY_CFG, st, sizeof(stored_t));
        if (err == ESP_OK) {
            err = nvs_commit(h);
        }
        nvs_close(h);
    }
    if (err == ESP_OK) {
        xSemaphoreTake(s_lock, portMAX_DELAY);
        s_cfg = *cfg;
        xSemaphoreGive(s_lock);
    }
    free(st);
    return err;
}

esp_err_t light_config_erase(void)
{
    nvs_handle_t h;
    esp_err_t err = nvs_open(NVS_NS, NVS_READWRITE, &h);
    if (err != ESP_OK) {
        return err;
    }
    err = nvs_erase_all(h);
    if (err == ESP_OK) {
        err = nvs_commit(h);
    }
    nvs_close(h);
    return err;
}

bool light_config_is_provisioned(void)
{
    return s_cfg.wifi_ssid[0] != '\0' && s_cfg.device_key[0] != '\0';
}

uint16_t light_config_load_last_mask(void)
{
    nvs_handle_t h;
    uint16_t mask = 0;
    if (nvs_open(NVS_NS, NVS_READONLY, &h) == ESP_OK) {
        nvs_get_u16(h, KEY_MASK, &mask);
        nvs_close(h);
    }
    return mask;
}

void light_config_save_last_mask(uint16_t mask)
{
    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READWRITE, &h) != ESP_OK) {
        return;
    }
    uint16_t old = 0xFFFF;
    /* Chỉ ghi khi đổi — mỗi lần mở/đóng bàn một lần ghi, flash dư sức chịu. */
    if (nvs_get_u16(h, KEY_MASK, &old) != ESP_OK || old != mask) {
        nvs_set_u16(h, KEY_MASK, mask);
        nvs_commit(h);
    }
    nvs_close(h);
}
