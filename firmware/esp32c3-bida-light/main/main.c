#include "ble_link.h"
#include "driver/gpio.h"
#include "esp_app_desc.h"
#include "esp_log.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "light_config.h"
#include "poller.h"
#include "relay.h"
#include "web_ui.h"
#include "wifi_link.h"

static const char *TAG = "main";

/* Nút BOOT trên đa số bo ESP32-C3 (GPIO9, kéo lên, nhấn = 0). */
#define BOOT_BUTTON_GPIO   9
#define FACTORY_HOLD_MS    5000
#define BLE_WINDOW_MS      (10 * 60 * 1000)

/* Nhấn nhanh nút BOOT → bật Bluetooth cài đặt 10 phút.
 * Giữ 5 giây → xóa cấu hình, phát lại WiFi cấu hình. */
static void button_task(void *arg)
{
    (void)arg;
    gpio_config_t io = {
        .pin_bit_mask = 1ULL << BOOT_BUTTON_GPIO,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    gpio_config(&io);
    int held_ms = 0;
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(100));
        if (gpio_get_level(BOOT_BUTTON_GPIO) == 0) {
            held_ms += 100;
        } else {
            /* Nhấn nhanh → mở lại Bluetooth để cài / gán kênh bằng app. */
            if (held_ms >= 100 && held_ms < 2000) {
                ble_link_open_window(BLE_WINDOW_MS);
            }
            held_ms = 0;
        }
        if (held_ms >= FACTORY_HOLD_MS) {
            ESP_LOGW(TAG, "giu nut BOOT %d giay - xoa cau hinh va khoi dong lai",
                     FACTORY_HOLD_MS / 1000);
            light_config_erase();
            vTaskDelay(pdMS_TO_TICKS(300));
            esp_restart();
        }
    }
}

void app_main(void)
{
    ESP_LOGW(TAG, "SBOX Den ban bida %s - mo ban sang den, thanh toan tat den",
             esp_app_get_description()->version);

    ESP_ERROR_CHECK(light_config_init());
    relay_init(light_config_get()->device_key[0] ? light_config_load_last_mask() : 0);

    ESP_ERROR_CHECK(wifi_link_init());
    web_ui_start();
    poller_start();
    if (ble_link_start() != ESP_OK) {
        ESP_LOGE(TAG, "khong bat duoc Bluetooth - van cai dat duoc qua WiFi SBOX-Den");
    }
    xTaskCreate(button_task, "btn", 2048, NULL, 4, NULL);

    if (!light_config_is_provisioned()) {
        ESP_LOGW(TAG, "chua cau hinh - dung app SBOX qua Bluetooth, hoac noi WiFi '%s' (sbox12345) "
                 "roi mo http://192.168.4.1", wifi_link_ap_ssid());
    }
}
