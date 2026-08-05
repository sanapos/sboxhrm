#include <stdio.h>

#include "app_config.h"
#include "discovery.h"
#include "esp_app_desc.h"
#include "esp_log.h"
#include "esp_netif_sntp.h"
#include "esp_ota_ops.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "gateway.h"
#include "web_portal.h"
#include "wifi_mgr.h"

static const char *TAG = "main";

static void start_time_sync(void)
{
    esp_sntp_config_t cfg = ESP_NETIF_SNTP_DEFAULT_CONFIG("pool.ntp.org");
    cfg.start = true;
    cfg.server_from_dhcp = true;
    cfg.renew_servers_after_new_IP = true;
    cfg.index_of_first_server = 1;
    esp_netif_sntp_init(&cfg);
}

void app_main(void)
{
    const esp_app_desc_t *app = esp_app_get_description();
    ESP_LOGW(TAG, "SBOX ZK Gateway %s - cau noi ZKTeco TCP 4370 <-> ADMS", app->version);

    ESP_ERROR_CHECK(app_config_init());
    ESP_ERROR_CHECK(wifi_mgr_init());

    start_time_sync();

    ESP_ERROR_CHECK(web_portal_start());
    gateway_start();
    discovery_start();

    if (!app_config_is_provisioned()) {
        ESP_LOGW(TAG, "chua cau hinh - noi WiFi '%s' (mat khau sbox12345) roi vao http://192.168.4.1",
                 wifi_mgr_ap_ssid());
    }

    /* Đánh dấu firmware chạy tốt để không bị quay về bản cũ sau khi nạp OTA. */
    vTaskDelay(pdMS_TO_TICKS(20000));
    esp_ota_mark_app_valid_cancel_rollback();
}
