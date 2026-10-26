#include "wifi_link.h"

#include <stdio.h>
#include <string.h>

#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "light_config.h"

static const char *TAG = "wifi";

#define AP_PASSWORD     "sbox12345"
#define AP_FALLBACK_MS  60000

static volatile bool s_connected;
static volatile bool s_ap_active;
static char s_ip[16] = "0.0.0.0";
static char s_ap_ssid[32];
static volatile int64_t s_disconnected_since;
static esp_netif_t *s_netif_ap;

static void start_ap(void)
{
    if (s_ap_active) {
        return;
    }
    if (s_netif_ap == NULL) {
        s_netif_ap = esp_netif_create_default_wifi_ap();
    }
    wifi_config_t ap = {0};
    strlcpy((char *)ap.ap.ssid, s_ap_ssid, sizeof(ap.ap.ssid));
    ap.ap.ssid_len = strlen(s_ap_ssid);
    strlcpy((char *)ap.ap.password, AP_PASSWORD, sizeof(ap.ap.password));
    ap.ap.max_connection = 3;
    ap.ap.authmode = WIFI_AUTH_WPA2_PSK;
    ap.ap.channel = 1;
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_APSTA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &ap));
    s_ap_active = true;
    ESP_LOGW(TAG, "diem phat cau hinh: SSID=%s mat khau=%s, vao http://192.168.4.1",
             s_ap_ssid, AP_PASSWORD);
}

static void stop_ap(void)
{
    if (!s_ap_active) {
        return;
    }
    if (esp_wifi_set_mode(WIFI_MODE_STA) == ESP_OK) {
        s_ap_active = false;
        ESP_LOGW(TAG, "tat diem phat cau hinh (da vao WiFi)");
    }
}

static void on_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        if (light_config_get()->wifi_ssid[0]) {
            esp_wifi_connect();
        }
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        wifi_event_sta_disconnected_t *ev = data;
        if (s_connected) {
            ESP_LOGW(TAG, "mat WiFi (ly do %u)", ev->reason);
        }
        s_connected = false;
        strlcpy(s_ip, "0.0.0.0", sizeof(s_ip));
        if (s_disconnected_since == 0) {
            s_disconnected_since = esp_timer_get_time() / 1000;
        }
        if (light_config_get()->wifi_ssid[0]) {
            vTaskDelay(pdMS_TO_TICKS(2000));
            esp_wifi_connect();
        }
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *ev = data;
        snprintf(s_ip, sizeof(s_ip), IPSTR, IP2STR(&ev->ip_info.ip));
        s_connected = true;
        s_disconnected_since = 0;
        ESP_LOGW(TAG, "da vao WiFi, IP = %s (trang quan ly http://%s)", s_ip, s_ip);
        stop_ap();
    }
}

static void ap_watchdog_task(void *arg)
{
    (void)arg;
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(5000));
        if (s_connected || s_ap_active || s_disconnected_since == 0) {
            continue;
        }
        if (esp_timer_get_time() / 1000 - s_disconnected_since > AP_FALLBACK_MS) {
            ESP_LOGW(TAG, "khong vao duoc WiFi sau %d giay - bat diem phat cau hinh",
                     AP_FALLBACK_MS / 1000);
            start_ap();
        }
    }
}

esp_err_t wifi_link_init(void)
{
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&init));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID,
                                                        on_event, NULL, NULL));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_GOT_IP,
                                                        on_event, NULL, NULL));

    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP);
    snprintf(s_ap_ssid, sizeof(s_ap_ssid), "SBOX-Den-%02X%02X", mac[4], mac[5]);

    const light_config_t *cfg = light_config_get();
    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    if (cfg->wifi_ssid[0]) {
        wifi_config_t sta = {0};
        strlcpy((char *)sta.sta.ssid, cfg->wifi_ssid, sizeof(sta.sta.ssid));
        strlcpy((char *)sta.sta.password, cfg->wifi_pass, sizeof(sta.sta.password));
        ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &sta));
        s_disconnected_since = esp_timer_get_time() / 1000;
    }
    ESP_ERROR_CHECK(esp_wifi_start());
    /* Relay bật/tắt gây nhiễu nguồn — tắt tiết kiệm điện để WiFi ổn định hơn. */
    esp_wifi_set_ps(WIFI_PS_NONE);

    if (!cfg->wifi_ssid[0]) {
        start_ap();
    }
    xTaskCreate(ap_watchdog_task, "ap_wd", 3072, NULL, 3, NULL);
    return ESP_OK;
}

bool wifi_link_connected(void)
{
    return s_connected;
}

const char *wifi_link_ip(void)
{
    return s_ip;
}

bool wifi_link_ap_active(void)
{
    return s_ap_active;
}

const char *wifi_link_ap_ssid(void)
{
    return s_ap_ssid;
}

int wifi_link_rssi(void)
{
    wifi_ap_record_t ap;
    return esp_wifi_sta_get_ap_info(&ap) == ESP_OK ? ap.rssi : 0;
}

esp_err_t wifi_link_apply(void)
{
    const light_config_t *cfg = light_config_get();
    if (cfg->wifi_ssid[0] == '\0') {
        return ESP_ERR_INVALID_STATE;
    }
    wifi_config_t sta = {0};
    strlcpy((char *)sta.sta.ssid, cfg->wifi_ssid, sizeof(sta.sta.ssid));
    strlcpy((char *)sta.sta.password, cfg->wifi_pass, sizeof(sta.sta.password));
    esp_err_t err = esp_wifi_set_config(WIFI_IF_STA, &sta);
    if (err != ESP_OK) {
        return err;
    }
    s_disconnected_since = esp_timer_get_time() / 1000;
    esp_wifi_disconnect();
    return esp_wifi_connect();
}
