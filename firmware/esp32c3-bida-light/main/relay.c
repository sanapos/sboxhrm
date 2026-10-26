#include "relay.h"

#include <stdint.h>
#include <strings.h>

#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "light_config.h"

static const char *TAG = "relay";

static uint16_t s_mask;
static SemaphoreHandle_t s_lock;
static esp_timer_handle_t s_test_timer;

/* Chân ra của ESP32-C3 trừ 2/8/9 (strapping) và 18/19 (USB). */
#define USABLE_PINS ((1u << 0) | (1u << 1) | (1u << 3) | (1u << 4) | (1u << 5) | (1u << 6) | \
                     (1u << 7) | (1u << 10) | (1u << 20) | (1u << 21))

static int level_for(bool on)
{
    return (on ^ light_config_get()->active_low) ? 1 : 0;
}

static void lock(void)
{
    if (s_lock == NULL) {
        s_lock = xSemaphoreCreateMutex();
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
}

static void unlock(void)
{
    xSemaphoreGive(s_lock);
}

/* Ghi lại mức cho mọi chân theo s_mask (gọi khi đang giữ khóa). */
static void write_all_locked(void)
{
    const light_config_t *cfg = light_config_get();
    for (int i = 0; i < LC_MAX_CH; i++) {
        int pin = cfg->ch[i].gpio;
        if (pin >= 0 && (USABLE_PINS >> pin & 1)) {
            gpio_set_level(pin, level_for((s_mask >> i) & 1));
        }
    }
}

static void setup_pin(int pin, bool on)
{
    /* Đặt mức trước rồi mới bật output — relay không nháy. */
    gpio_reset_pin(pin);
    gpio_set_level(pin, level_for(on));
    gpio_set_direction(pin, GPIO_MODE_OUTPUT);
    gpio_set_level(pin, level_for(on));
}

void relay_init(uint16_t initial_mask)
{
    const light_config_t *cfg = light_config_get();
    lock();
    for (int i = 0; i < LC_MAX_CH; i++) {
        int pin = cfg->ch[i].gpio;
        if (pin >= 0 && (USABLE_PINS >> pin & 1)) {
            setup_pin(pin, (initial_mask >> i) & 1);
        }
    }
    s_mask = initial_mask;
    unlock();
    ESP_LOGI(TAG, "khoi tao relay, mask=0x%03x", initial_mask);
}

bool relay_apply(uint16_t mask)
{
    lock();
    if (mask == s_mask) {
        unlock();
        return false;
    }
    const light_config_t *cfg = light_config_get();
    for (int i = 0; i < LC_MAX_CH; i++) {
        int pin = cfg->ch[i].gpio;
        bool on = (mask >> i) & 1;
        if (pin < 0 || !(USABLE_PINS >> pin & 1) || on == (bool)((s_mask >> i) & 1)) {
            continue;
        }
        gpio_set_level(pin, level_for(on));
        ESP_LOGW(TAG, "kenh %d (%s) -> %s", i + 1,
                 cfg->ch[i].table_code[0] ? cfg->ch[i].table_code : "-", on ? "SANG" : "TAT");
    }
    s_mask = mask;
    unlock();
    return true;
}

uint16_t relay_mask(void)
{
    return s_mask;
}

void relay_reconfigure(const light_config_t *old_cfg)
{
    const light_config_t *cfg = light_config_get();
    lock();
    uint16_t mask = 0;
    for (int i = 0; i < LC_MAX_CH; i++) {
        int pin = old_cfg->ch[i].gpio;
        bool still_used = false;
        for (int j = 0; j < LC_MAX_CH; j++) {
            still_used = still_used || cfg->ch[j].gpio == pin;
        }
        if (pin >= 0 && (USABLE_PINS >> pin & 1) && !still_used) {
            /* Chân bỏ dùng: về mức tắt rồi thả nổi — relay module có điện trở kéo về tắt. */
            gpio_set_level(pin, (false ^ old_cfg->active_low) ? 1 : 0);
            gpio_reset_pin(pin);
        }
    }
    for (int i = 0; i < LC_MAX_CH; i++) {
        /* Cùng mã bàn thì giữ trạng thái đang sáng; kênh mới bắt đầu tắt, lượt hỏi kế tiếp sẽ sửa. */
        bool on = false;
        for (int j = 0; j < LC_MAX_CH; j++) {
            if (cfg->ch[i].table_code[0] && strcasecmp(cfg->ch[i].table_code, old_cfg->ch[j].table_code) == 0) {
                on = (s_mask >> j) & 1;
            }
        }
        int pin = cfg->ch[i].gpio;
        if (pin >= 0 && (USABLE_PINS >> pin & 1)) {
            setup_pin(pin, on);
            if (on) {
                mask |= 1u << i;
            }
        }
    }
    s_mask = mask;
    unlock();
    ESP_LOGW(TAG, "doi chan relay xong, mask=0x%03x", mask);
}

static void test_done(void *arg)
{
    int pin = (int)(intptr_t)arg;
    lock();
    bool used = false;
    const light_config_t *cfg = light_config_get();
    for (int i = 0; i < LC_MAX_CH; i++) {
        used = used || cfg->ch[i].gpio == pin;
    }
    if (used) {
        write_all_locked();
    } else {
        gpio_set_level(pin, level_for(false));
        gpio_reset_pin(pin);
    }
    unlock();
}

bool relay_test_pin(int gpio, uint32_t ms)
{
    if (gpio < 0 || gpio > 21 || !(USABLE_PINS >> gpio & 1)) {
        return false;
    }
    if (s_test_timer != NULL) {
        esp_timer_stop(s_test_timer);
        esp_timer_delete(s_test_timer);
        s_test_timer = NULL;
    }
    lock();
    /* Thử chân khác trong lúc chân trước chưa hết giờ → trả chân trước về đúng trạng thái. */
    write_all_locked();
    bool used = false;
    const light_config_t *cfg = light_config_get();
    for (int i = 0; i < LC_MAX_CH; i++) {
        used = used || cfg->ch[i].gpio == gpio;
    }
    if (used) {
        gpio_set_level(gpio, level_for(true));
    } else {
        setup_pin(gpio, true);
    }
    unlock();
    ESP_LOGW(TAG, "thu den GPIO%d trong %u ms", gpio, (unsigned)ms);

    const esp_timer_create_args_t args = {
        .callback = test_done,
        .arg = (void *)(intptr_t)gpio,
        .name = "relay_test",
    };
    if (esp_timer_create(&args, &s_test_timer) == ESP_OK) {
        esp_timer_start_once(s_test_timer, (uint64_t)ms * 1000);
    }
    return true;
}

uint32_t relay_usable_pins(void)
{
    return USABLE_PINS;
}
