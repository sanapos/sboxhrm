#include "app_config.h"

#include <string.h>

#include "esp_log.h"
#include "nvs.h"
#include "nvs_flash.h"

static const char *TAG = "cfg";
static const char *NS = "zkgw";

static app_config_t s_cfg;
static char s_detected_sn[CFG_STR_LEN];

static void load_str(nvs_handle_t h, const char *key, char *dst, size_t cap, const char *def)
{
    size_t len = cap;
    if (nvs_get_str(h, key, dst, &len) != ESP_OK) {
        strlcpy(dst, def, cap);
    }
}

static void apply_defaults(app_config_t *cfg)
{
    memset(cfg, 0, sizeof(*cfg));
    cfg->device_port = 4370;
    cfg->poll_interval_s = 10;
    cfg->attlog_interval_s = 30;
    cfg->backfill_days = 30;
    cfg->tz_offset_h = 7;
    cfg->sync_device_clock = true;
    strlcpy(cfg->server_url, "https://sboxhrm.com", sizeof(cfg->server_url));
}

esp_err_t app_config_init(void)
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    if (err != ESP_OK) {
        return err;
    }

    apply_defaults(&s_cfg);

    nvs_handle_t h;
    if (nvs_open(NS, NVS_READONLY, &h) != ESP_OK) {
        ESP_LOGW(TAG, "chua co cau hinh trong NVS, dung mac dinh");
        return ESP_OK;
    }

    load_str(h, "gwname", s_cfg.gw_name, sizeof(s_cfg.gw_name), "");
    load_str(h, "ssid", s_cfg.wifi_ssid, sizeof(s_cfg.wifi_ssid), "");
    load_str(h, "pass", s_cfg.wifi_pass, sizeof(s_cfg.wifi_pass), "");
    load_str(h, "devip", s_cfg.device_ip, sizeof(s_cfg.device_ip), "");
    load_str(h, "url", s_cfg.server_url, sizeof(s_cfg.server_url), s_cfg.server_url);
    load_str(h, "sn", s_cfg.sn_override, sizeof(s_cfg.sn_override), "");
    load_str(h, "dsn", s_detected_sn, sizeof(s_detected_sn), "");

    nvs_get_u16(h, "devport", &s_cfg.device_port);
    nvs_get_u32(h, "ckey", &s_cfg.comm_key);
    nvs_get_u16(h, "poll", &s_cfg.poll_interval_s);
    nvs_get_u16(h, "attint", &s_cfg.attlog_interval_s);
    nvs_get_u16(h, "backfill", &s_cfg.backfill_days);
    nvs_get_i8(h, "tz", &s_cfg.tz_offset_h);

    uint8_t sync_clock = s_cfg.sync_device_clock ? 1 : 0;
    nvs_get_u8(h, "syncclk", &sync_clock);
    s_cfg.sync_device_clock = sync_clock != 0;

    nvs_close(h);

    ESP_LOGI(TAG, "cau hinh: ssid=%s may=%s:%u server=%s",
             s_cfg.wifi_ssid, s_cfg.device_ip, s_cfg.device_port, s_cfg.server_url);
    return ESP_OK;
}

const app_config_t *app_config_get(void)
{
    return &s_cfg;
}

bool app_config_is_provisioned(void)
{
    return s_cfg.wifi_ssid[0] != '\0' && s_cfg.device_ip[0] != '\0' && s_cfg.server_url[0] != '\0';
}

esp_err_t app_config_save(const app_config_t *cfg)
{
    nvs_handle_t h;
    esp_err_t err = nvs_open(NS, NVS_READWRITE, &h);
    if (err != ESP_OK) {
        return err;
    }

    nvs_set_str(h, "gwname", cfg->gw_name);
    nvs_set_str(h, "ssid", cfg->wifi_ssid);
    nvs_set_str(h, "pass", cfg->wifi_pass);
    nvs_set_str(h, "devip", cfg->device_ip);
    nvs_set_str(h, "url", cfg->server_url);
    nvs_set_str(h, "sn", cfg->sn_override);
    nvs_set_u16(h, "devport", cfg->device_port);
    nvs_set_u32(h, "ckey", cfg->comm_key);
    nvs_set_u16(h, "poll", cfg->poll_interval_s);
    nvs_set_u16(h, "attint", cfg->attlog_interval_s);
    nvs_set_u16(h, "backfill", cfg->backfill_days);
    nvs_set_i8(h, "tz", cfg->tz_offset_h);
    nvs_set_u8(h, "syncclk", cfg->sync_device_clock ? 1 : 0);

    err = nvs_commit(h);
    nvs_close(h);

    if (err == ESP_OK) {
        s_cfg = *cfg;
    }
    return err;
}

esp_err_t app_config_load_mark(attlog_mark_t *out)
{
    out->last_zk_time = 0;
    out->last_count = 0;

    nvs_handle_t h;
    if (nvs_open(NS, NVS_READONLY, &h) != ESP_OK) {
        return ESP_OK;
    }
    nvs_get_u32(h, "mark_t", &out->last_zk_time);
    nvs_get_u32(h, "mark_n", &out->last_count);
    nvs_close(h);
    return ESP_OK;
}

esp_err_t app_config_save_mark(const attlog_mark_t *mark)
{
    nvs_handle_t h;
    esp_err_t err = nvs_open(NS, NVS_READWRITE, &h);
    if (err != ESP_OK) {
        return err;
    }
    nvs_set_u32(h, "mark_t", mark->last_zk_time);
    nvs_set_u32(h, "mark_n", mark->last_count);
    err = nvs_commit(h);
    nvs_close(h);
    return err;
}

esp_err_t app_config_reset_mark(void)
{
    attlog_mark_t zero = {0};
    return app_config_save_mark(&zero);
}

esp_err_t app_config_save_serial(const char *serial)
{
    if (serial == NULL || serial[0] == '\0') {
        return ESP_ERR_INVALID_ARG;
    }
    if (strcmp(s_detected_sn, serial) == 0) {
        return ESP_OK;
    }
    strlcpy(s_detected_sn, serial, sizeof(s_detected_sn));

    nvs_handle_t h;
    esp_err_t err = nvs_open(NS, NVS_READWRITE, &h);
    if (err != ESP_OK) {
        return err;
    }
    nvs_set_str(h, "dsn", s_detected_sn);
    err = nvs_commit(h);
    nvs_close(h);
    return err;
}

const char *app_config_effective_serial(void)
{
    if (s_cfg.sn_override[0] != '\0') {
        return s_cfg.sn_override;
    }
    return s_detected_sn;
}

const char *app_config_detected_serial(void)
{
    return s_detected_sn;
}

esp_err_t app_config_clear_detected_serial(void)
{
    if (s_detected_sn[0] == '\0') {
        return ESP_OK;
    }
    s_detected_sn[0] = '\0';

    nvs_handle_t h;
    esp_err_t err = nvs_open(NS, NVS_READWRITE, &h);
    if (err != ESP_OK) {
        return err;
    }
    nvs_erase_key(h, "dsn");
    err = nvs_commit(h);
    nvs_close(h);
    ESP_LOGW(TAG, "da xoa SN cu, se doc lai tu may cham cong moi");
    return err;
}

bool app_config_device_target_changed(const app_config_t *before, const app_config_t *after)
{
    if (before == NULL || after == NULL) {
        return false;
    }
    return strcmp(before->device_ip, after->device_ip) != 0 ||
           before->device_port != after->device_port ||
           before->comm_key != after->comm_key;
}
