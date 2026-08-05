#include "wifi_mgr.h"

#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "app_config.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"

static const char *TAG = "wifi";

#define AP_PASSWORD      "sbox12345"
#define AP_FALLBACK_MS   60000

static bool s_connected;
static bool s_ap_active;
static volatile bool s_diag_scanning;
static char s_ip[16] = "0.0.0.0";
static char s_ap_ssid[32];
static int64_t s_disconnected_since;
static esp_netif_t *s_netif_ap;

static void start_ap_if_needed(void);

static const char *disconnect_reason_text(uint8_t reason)
{
    switch (reason) {
    case WIFI_REASON_AUTH_EXPIRE:       return "het han xac thuc";
    case WIFI_REASON_AUTH_FAIL:         return "sai mat khau / xac thuc that bai";
    case WIFI_REASON_HANDSHAKE_TIMEOUT: return "sai mat khau (handshake timeout)";
    case WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT: return "sai mat khau (4-way handshake)";
    case WIFI_REASON_NO_AP_FOUND:       return "khong tim thay SSID (co the la WiFi 5GHz hoac sai ten)";
    case WIFI_REASON_ASSOC_FAIL:        return "khong lien ket duoc voi AP";
    case WIFI_REASON_CONNECTION_FAIL:   return "ket noi that bai";
    case WIFI_REASON_BEACON_TIMEOUT:    return "mat song (beacon timeout)";
    case WIFI_REASON_ASSOC_LEAVE:       return "chu dong ngat";
    default:                            return "khac";
    }
}

static void on_wifi_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        ESP_LOGI(TAG, "STA khoi dong, dang thu ket noi...");
        esp_wifi_connect();
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        wifi_event_sta_disconnected_t *ev = data;
        ESP_LOGW(TAG, "chua vao duoc WiFi (ly do %u: %s), thu lai sau 2s",
                 ev->reason, disconnect_reason_text(ev->reason));
        s_connected = false;
        strlcpy(s_ip, "0.0.0.0", sizeof(s_ip));
        if (s_disconnected_since == 0) {
            s_disconnected_since = esp_timer_get_time() / 1000;
        }
        if (s_diag_scanning) {
            return; /* đang quét chẩn đoán, đừng nối lại để khỏi chặn quét */
        }
        vTaskDelay(pdMS_TO_TICKS(2000));
        esp_wifi_connect();
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *event = data;
        snprintf(s_ip, sizeof(s_ip), IPSTR, IP2STR(&event->ip_info.ip));
        s_connected = true;
        s_disconnected_since = 0;
        ESP_LOGI(TAG, "da vao mang WiFi, IP = %s", s_ip);
    }
}

/* Quét một lần lúc khởi động, in ra các WiFi 2.4GHz nhìn thấy được. Giúp phân
 * biệt "SSID sai/ẩn" với "mạng đang phát ở 5GHz" (ESP32-C3 chỉ bắt 2.4GHz). */
static void diag_scan_task(void *arg)
{
    (void)arg;
    vTaskDelay(pdMS_TO_TICKS(1500));

    /* Tạm ngừng nối lại rồi ngắt để cửa sổ quét được thông thoáng. */
    s_diag_scanning = true;
    esp_wifi_disconnect();
    vTaskDelay(pdMS_TO_TICKS(300));

    /* Các cấu trúc WiFi khá lớn (wifi_ap_record_t hơn 100 byte) nên phải để
     * trên heap, đặt trên stack tác vụ sẽ tràn. */
    const uint16_t cap = 16;
    wifi_ap_record_t *records = calloc(cap, sizeof(wifi_ap_record_t));
    if (records == NULL) {
        s_diag_scanning = false;
        esp_wifi_connect();
        vTaskDelete(NULL);
        return;
    }

    wifi_scan_config_t scan = {.show_hidden = true};
    esp_err_t serr = esp_wifi_scan_start(&scan, true);
    if (serr != ESP_OK) {
        ESP_LOGW(TAG, "quet WiFi that bai: %s", esp_err_to_name(serr));
        free(records);
        s_diag_scanning = false;
        esp_wifi_connect();
        vTaskDelete(NULL);
        return;
    }
    uint16_t found = cap;
    if (esp_wifi_scan_get_ap_records(&found, records) != ESP_OK) {
        free(records);
        s_diag_scanning = false;
        esp_wifi_connect();
        vTaskDelete(NULL);
        return;
    }

    const char *want = app_config_get()->wifi_ssid;
    bool matched = false;
    const char *nearly = NULL; /* khớp nếu bỏ qua hoa/thường */

    ESP_LOGW(TAG, "=== thay %u mang 2.4GHz (ESP chi bat duoc 2.4GHz) ===", found);
    for (int i = 0; i < found; i++) {
        const char *ssid = (const char *)records[i].ssid;
        bool hit = want[0] && strcmp(ssid, want) == 0;
        matched = matched || hit;
        if (want[0] && !hit && strcasecmp(ssid, want) == 0) {
            nearly = ssid;
        }
        ESP_LOGW(TAG, "  %2d) '%s'  rssi=%d ch=%d%s",
                 i + 1, ssid[0] ? ssid : "(an)", records[i].rssi,
                 records[i].primary, hit ? "  <== SSID ban da cau hinh" : "");
    }

    if (want[0] && !matched && nearly != NULL) {
        /* Tên WiFi phân biệt hoa/thường nên chỉ lệch một chữ là báo
         * "khong tim thay SSID". Lấy đúng tên vừa quét được và lưu lại. */
        ESP_LOGW(TAG, "SSID luu la '%s' nhung mang that ten '%s' - tu sua lai",
                 want, nearly);
        app_config_t *fixed = malloc(sizeof(app_config_t));
        wifi_config_t *sta = calloc(1, sizeof(wifi_config_t));
        if (fixed != NULL && sta != NULL) {
            *fixed = *app_config_get();
            strlcpy(fixed->wifi_ssid, nearly, sizeof(fixed->wifi_ssid));
            if (app_config_save(fixed) == ESP_OK) {
                const app_config_t *cfg = app_config_get();
                strlcpy((char *)sta->sta.ssid, cfg->wifi_ssid, sizeof(sta->sta.ssid));
                strlcpy((char *)sta->sta.password, cfg->wifi_pass, sizeof(sta->sta.password));
                esp_wifi_set_config(WIFI_IF_STA, sta);
            }
        }
        free(fixed);
        free(sta);
    } else if (want[0] && !matched) {
        ESP_LOGE(TAG, "KHONG thay '%s' trong danh sach 2.4GHz. Rat co the mang nay",
                 want);
        ESP_LOGE(TAG, "dang phat 5GHz. Hay tao/tach mot SSID 2.4GHz rieng cho ESP.");
    }

    free(records);
    s_diag_scanning = false;
    esp_wifi_connect();
    vTaskDelete(NULL);
}

static void ap_watchdog_task(void *arg)
{
    (void)arg;
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(5000));
        if (s_connected || s_ap_active) {
            continue;
        }
        int64_t now = esp_timer_get_time() / 1000;
        if (s_disconnected_since != 0 && now - s_disconnected_since > AP_FALLBACK_MS) {
            ESP_LOGW(TAG, "khong vao duoc WiFi sau %d giay - bat diem phat cau hinh",
                     AP_FALLBACK_MS / 1000);
            start_ap_if_needed();
        }
    }
}

static void build_ap_ssid(void)
{
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP);
    snprintf(s_ap_ssid, sizeof(s_ap_ssid), "SBOX-Gateway-%02X%02X", mac[4], mac[5]);
}

static void start_ap_if_needed(void)
{
    if (s_ap_active) {
        return;
    }

    if (s_netif_ap == NULL) {
        s_netif_ap = esp_netif_create_default_wifi_ap();
    }

    wifi_config_t ap_cfg = {0};
    strlcpy((char *)ap_cfg.ap.ssid, s_ap_ssid, sizeof(ap_cfg.ap.ssid));
    ap_cfg.ap.ssid_len = strlen(s_ap_ssid);
    strlcpy((char *)ap_cfg.ap.password, AP_PASSWORD, sizeof(ap_cfg.ap.password));
    ap_cfg.ap.max_connection = 3;
    ap_cfg.ap.authmode = WIFI_AUTH_WPA2_PSK;
    ap_cfg.ap.channel = 1;

    wifi_mode_t mode = WIFI_MODE_APSTA;
    ESP_ERROR_CHECK(esp_wifi_set_mode(mode));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &ap_cfg));

    s_ap_active = true;
    ESP_LOGW(TAG, "diem phat cau hinh: SSID=%s mat khau=%s, vao http://192.168.4.1",
             s_ap_ssid, AP_PASSWORD);
}

esp_err_t wifi_mgr_apply_config(void)
{
    const app_config_t *cfg = app_config_get();
    if (cfg->wifi_ssid[0] == '\0') {
        return ESP_ERR_INVALID_STATE;
    }

    wifi_config_t sta = {0};
    strlcpy((char *)sta.sta.ssid, cfg->wifi_ssid, sizeof(sta.sta.ssid));
    strlcpy((char *)sta.sta.password, cfg->wifi_pass, sizeof(sta.sta.password));
    sta.sta.threshold.authmode = cfg->wifi_pass[0] != '\0' ? WIFI_AUTH_WPA_PSK : WIFI_AUTH_OPEN;

    esp_err_t err = esp_wifi_set_config(WIFI_IF_STA, &sta);
    if (err != ESP_OK) {
        return err;
    }
    esp_wifi_disconnect();
    return esp_wifi_connect();
}

esp_err_t wifi_mgr_init(void)
{
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t init_cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&init_cfg));

    ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID,
                                                        on_wifi_event, NULL, NULL));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_GOT_IP,
                                                        on_wifi_event, NULL, NULL));

    build_ap_ssid();

    const app_config_t *cfg = app_config_get();
    bool have_wifi = cfg->wifi_ssid[0] != '\0';

    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));

    if (have_wifi) {
        wifi_config_t sta = {0};
        strlcpy((char *)sta.sta.ssid, cfg->wifi_ssid, sizeof(sta.sta.ssid));
        strlcpy((char *)sta.sta.password, cfg->wifi_pass, sizeof(sta.sta.password));
        ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &sta));
        s_disconnected_since = esp_timer_get_time() / 1000;
    }

    ESP_ERROR_CHECK(esp_wifi_start());

    if (!have_wifi) {
        start_ap_if_needed();
    }

    xTaskCreate(ap_watchdog_task, "ap_wd", 3072, NULL, 3, NULL);
    if (have_wifi) {
        xTaskCreate(diag_scan_task, "wifi_diag", 4096, NULL, 3, NULL);
    }
    return ESP_OK;
}

bool wifi_mgr_is_connected(void)
{
    return s_connected;
}

const char *wifi_mgr_sta_ip(void)
{
    return s_ip;
}

bool wifi_mgr_ap_active(void)
{
    return s_ap_active;
}

const char *wifi_mgr_ap_ssid(void)
{
    return s_ap_ssid;
}

int wifi_mgr_rssi(void)
{
    wifi_ap_record_t ap;
    if (esp_wifi_sta_get_ap_info(&ap) == ESP_OK) {
        return ap.rssi;
    }
    return 0;
}

int wifi_mgr_scan(wifi_ap_record_t *out, int max)
{
    wifi_scan_config_t scan = {.show_hidden = false};
    if (esp_wifi_scan_start(&scan, true) != ESP_OK) {
        return 0;
    }

    uint16_t found = (uint16_t)max;
    if (esp_wifi_scan_get_ap_records(&found, out) != ESP_OK) {
        return 0;
    }
    return (int)found;
}
