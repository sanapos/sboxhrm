#include "poller.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "cJSON.h"
#include "esp_crt_bundle.h"
#include "esp_http_client.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "light_config.h"
#include "relay.h"
#include "wifi_link.h"

static const char *TAG = "poll";

#define BODY_CAP       12288
#define HTTP_TIMEOUT   8000
#define USER_AGENT     "SBOX-BidaLight/1.0"

static SemaphoreHandle_t s_lock;
static TaskHandle_t s_task;
static poller_status_t s_st;
static char *s_tables;      /* JSON mảng bàn lần cuối */
static size_t s_tables_len;

typedef struct {
    char *buf;
    size_t len;
    bool overflow;
} body_t;

static esp_err_t on_http(esp_http_client_event_t *ev)
{
    body_t *b = ev->user_data;
    if (ev->event_id == HTTP_EVENT_ON_DATA && b != NULL) {
        if (b->len + ev->data_len >= BODY_CAP) {
            b->overflow = true;
        } else {
            memcpy(b->buf + b->len, ev->data, ev->data_len);
            b->len += ev->data_len;
            b->buf[b->len] = '\0';
        }
    }
    return ESP_OK;
}

static void set_msg(const char *msg)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    strlcpy(s_st.message, msg, sizeof(s_st.message));
    xSemaphoreGive(s_lock);
}

/* Hỏi máy chủ một lần. Thành công → cập nhật server_mask/unknown_mask. */
static bool fetch_once(esp_http_client_handle_t *client, body_t *body)
{
    const light_config_t *cfg = light_config_get();
    char base[LC_URL_LEN];
    char url[LC_URL_LEN + LC_KEY_LEN + 48];
    char msg[96];

    strlcpy(base, cfg->server_url, sizeof(base));
    size_t bl = strlen(base);
    while (bl > 0 && base[bl - 1] == '/') {
        base[--bl] = '\0';
    }
    snprintf(url, sizeof(url), "%s/api/pos/bida-light/state?key=%s", base, cfg->device_key);

    if (*client == NULL) {
        esp_http_client_config_t hc = {
            .url = url,
            .timeout_ms = HTTP_TIMEOUT,
            .crt_bundle_attach = esp_crt_bundle_attach,
            .user_agent = USER_AGENT,
            .keep_alive_enable = true,
            .event_handler = on_http,
            .user_data = body,
            .buffer_size = 2048,
        };
        *client = esp_http_client_init(&hc);
        if (*client == NULL) {
            set_msg("Khong tao duoc ket noi HTTP");
            return false;
        }
    } else {
        esp_http_client_set_url(*client, url);
    }

    body->len = 0;
    body->overflow = false;
    body->buf[0] = '\0';
    esp_err_t err = esp_http_client_perform(*client);
    int status = err == ESP_OK ? esp_http_client_get_status_code(*client) : 0;

    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_st.http_status = status;
    xSemaphoreGive(s_lock);

    if (err != ESP_OK) {
        ESP_LOGW(TAG, "khong goi duoc may chu: %s", esp_err_to_name(err));
        snprintf(msg, sizeof(msg), "Khong ket noi duoc may chu (%s)", esp_err_to_name(err));
        set_msg(msg);
        /* Kết nối có thể đã hỏng — dựng lại ở lần sau. */
        esp_http_client_cleanup(*client);
        *client = NULL;
        return false;
    }
    if (status == 401) {
        set_msg("May chu tu choi khoa thiet bi - lay lai khoa trong app");
        return false;
    }
    if (status != 200 || body->overflow) {
        snprintf(msg, sizeof(msg), body->overflow ? "Phan hoi qua lon (HTTP %d)"
                                                  : "May chu tra loi HTTP %d", status);
        set_msg(msg);
        return false;
    }

    cJSON *root = cJSON_Parse(body->buf);
    cJSON *tables = root ? cJSON_GetObjectItem(root, "t") : NULL;
    if (!cJSON_IsTrue(cJSON_GetObjectItem(root, "ok")) || !cJSON_IsArray(tables)) {
        set_msg("Du lieu may chu khong hop le");
        cJSON_Delete(root);
        return false;
    }

    uint16_t on_mask = 0;
    uint16_t found_mask = 0;
    uint16_t mapped = 0;
    for (int i = 0; i < LC_MAX_CH; i++) {
        if (cfg->ch[i].table_code[0] && cfg->ch[i].gpio >= 0) {
            mapped |= 1u << i;
        }
    }

    cJSON *t;
    cJSON_ArrayForEach(t, tables) {
        const char *code = cJSON_GetStringValue(cJSON_GetObjectItem(t, "c"));
        cJSON *on = cJSON_GetObjectItem(t, "on");
        if (code == NULL) {
            continue;
        }
        for (int i = 0; i < LC_MAX_CH; i++) {
            if ((mapped >> i & 1) && strcasecmp(cfg->ch[i].table_code, code) == 0) {
                found_mask |= 1u << i;
                if (cJSON_IsNumber(on) && on->valueint) {
                    on_mask |= 1u << i;
                }
            }
        }
    }

    char *compact = cJSON_PrintUnformatted(tables);
    cJSON_Delete(root);

    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_st.server_mask = on_mask;
    s_st.unknown_mask = mapped & ~found_mask;
    if (compact != NULL) {
        free(s_tables);
        s_tables = compact;
        s_tables_len = strlen(compact);
    }
    strlcpy(s_st.message, "OK", sizeof(s_st.message));
    xSemaphoreGive(s_lock);
    return true;
}

/* Gộp trạng thái máy chủ với chế độ tay của từng kênh rồi đóng/ngắt relay. */
static void apply_outputs(void)
{
    const light_config_t *cfg = light_config_get();
    xSemaphoreTake(s_lock, portMAX_DELAY);
    uint16_t server = s_st.server_mask;
    int64_t last_ok = s_st.last_ok_ms;
    xSemaphoreGive(s_lock);

    /* Mất máy chủ quá lâu (và được phép) → tắt; mặc định giữ nguyên để không tắt đèn giữa trận. */
    if (cfg->offline_off_min > 0
        && esp_timer_get_time() / 1000 - last_ok > (int64_t)cfg->offline_off_min * 60000) {
        server = 0;
    }

    uint16_t mask = 0;
    for (int i = 0; i < LC_MAX_CH; i++) {
        if (cfg->ch[i].gpio < 0) {
            continue;
        }
        switch (cfg->ch[i].mode) {
        case CH_FORCE_ON:
            mask |= 1u << i;
            break;
        case CH_FORCE_OFF:
            break;
        default:
            mask |= server & (1u << i);
            break;
        }
    }
    if (relay_apply(mask)) {
        light_config_save_last_mask(mask);
    }
}

static void poll_task(void *arg)
{
    (void)arg;
    body_t body = {.buf = malloc(BODY_CAP)};
    esp_http_client_handle_t client = NULL;
    char msg[96];
    if (body.buf == NULL) {
        ESP_LOGE(TAG, "het RAM");
        vTaskDelete(NULL);
        return;
    }

    for (;;) {
        const light_config_t *cfg = light_config_get();
        uint32_t wait_ms = cfg->poll_ms < 1000 ? 1000 : cfg->poll_ms;

        if (!light_config_is_provisioned()) {
            set_msg("Chua cau hinh WiFi / khoa thiet bi");
        } else if (!wifi_link_connected()) {
            snprintf(msg, sizeof(msg), "Dang vao WiFi '%s'", cfg->wifi_ssid);
            set_msg(msg);
        } else {
            bool ok = fetch_once(&client, &body);
            xSemaphoreTake(s_lock, portMAX_DELAY);
            s_st.server_ok = ok;
            if (ok) {
                s_st.ok_count++;
                s_st.last_ok_ms = esp_timer_get_time() / 1000;
            } else {
                s_st.fail_count++;
            }
            xSemaphoreGive(s_lock);
            if (!ok && wait_ms < 5000) {
                wait_ms = 5000; /* lỗi → giãn nhịp hỏi */
            }
        }
        apply_outputs();
        /* Ngủ tới lượt sau, hoặc dậy sớm khi trang web đổi chế độ tay. */
        ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(wait_ms));
    }
}

void poller_start(void)
{
    s_lock = xSemaphoreCreateMutex();
    /* Trước lần hỏi đầu tiên: giữ trạng thái đã lưu (mất điện chập chờn giữa trận không tắt đèn). */
    s_st.server_mask = relay_mask();
    xTaskCreate(poll_task, "poll", 8192, NULL, 5, &s_task);
}

void poller_get_status(poller_status_t *out)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    *out = s_st;
    xSemaphoreGive(s_lock);
}

void poller_kick(void)
{
    if (s_task != NULL) {
        xTaskNotifyGive(s_task);
    }
}

size_t poller_copy_tables(char *buf, size_t cap)
{
    size_t n = 0;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    if (s_tables != NULL && s_tables_len < cap) {
        memcpy(buf, s_tables, s_tables_len + 1);
        n = s_tables_len;
    }
    xSemaphoreGive(s_lock);
    return n;
}
