#include "web_ui.h"

#include <stdlib.h>
#include <string.h>

#include "cJSON.h"
#include "esp_app_desc.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "light_config.h"
#include "poller.h"
#include "relay.h"
#include "wifi_link.h"

static const char *TAG = "web";

extern const char ui_html_start[] asm("_binary_ui_html_start");
extern const char ui_html_end[] asm("_binary_ui_html_end");

#define MAX_BODY 4096

static void restart_task(void *arg)
{
    (void)arg;
    vTaskDelay(pdMS_TO_TICKS(800));
    esp_restart();
}

static void schedule_restart(void)
{
    xTaskCreate(restart_task, "restart", 2048, NULL, 5, NULL);
}

static esp_err_t send_json(httpd_req_t *req, cJSON *obj)
{
    char *s = cJSON_PrintUnformatted(obj);
    cJSON_Delete(obj);
    if (s == NULL) {
        return httpd_resp_send_500(req);
    }
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    esp_err_t err = httpd_resp_sendstr(req, s);
    free(s);
    return err;
}

static esp_err_t send_err(httpd_req_t *req, const char *status, const char *msg)
{
    cJSON *o = cJSON_CreateObject();
    cJSON_AddBoolToObject(o, "ok", false);
    cJSON_AddStringToObject(o, "msg", msg);
    httpd_resp_set_status(req, status);
    return send_json(req, o);
}

static esp_err_t send_ok(httpd_req_t *req)
{
    cJSON *o = cJSON_CreateObject();
    cJSON_AddBoolToObject(o, "ok", true);
    return send_json(req, o);
}

/* Đặt mật khẩu quản lý thì mọi thao tác ghi phải gửi kèm header X-Pass. */
static bool authorized(httpd_req_t *req)
{
    const char *want = light_config_get()->admin_pass;
    if (want[0] == '\0') {
        return true;
    }
    char got[LC_STR_LEN] = {0};
    if (httpd_req_get_hdr_value_str(req, "X-Pass", got, sizeof(got)) != ESP_OK) {
        return false;
    }
    return strcmp(got, want) == 0;
}

static cJSON *read_body(httpd_req_t *req)
{
    if (req->content_len <= 0 || req->content_len > MAX_BODY) {
        return NULL;
    }
    char *buf = malloc(req->content_len + 1);
    if (buf == NULL) {
        return NULL;
    }
    int got = 0;
    while (got < req->content_len) {
        int r = httpd_req_recv(req, buf + got, req->content_len - got);
        if (r <= 0) {
            free(buf);
            return NULL;
        }
        got += r;
    }
    buf[got] = '\0';
    cJSON *o = cJSON_Parse(buf);
    free(buf);
    return o;
}

static void copy_str(cJSON *o, const char *key, char *dst, size_t cap)
{
    const char *v = cJSON_GetStringValue(cJSON_GetObjectItem(o, key));
    if (v != NULL) {
        strlcpy(dst, v, cap);
    }
}

static esp_err_t h_index(httpd_req_t *req)
{
    httpd_resp_set_type(req, "text/html; charset=utf-8");
    return httpd_resp_send(req, ui_html_start, ui_html_end - ui_html_start - 1);
}

static esp_err_t h_status(httpd_req_t *req)
{
    const light_config_t *cfg = light_config_get();
    poller_status_t st;
    poller_get_status(&st);
    uint16_t mask = relay_mask();

    cJSON *o = cJSON_CreateObject();
    cJSON_AddStringToObject(o, "fw", esp_app_get_description()->version);
    cJSON_AddStringToObject(o, "name", cfg->name);
    cJSON_AddStringToObject(o, "ip", wifi_link_ip());
    cJSON_AddBoolToObject(o, "wifi", wifi_link_connected());
    cJSON_AddNumberToObject(o, "rssi", wifi_link_rssi());
    cJSON_AddBoolToObject(o, "ap", wifi_link_ap_active());
    cJSON_AddStringToObject(o, "apSsid", wifi_link_ap_ssid());
    cJSON_AddNumberToObject(o, "uptime", (double)(esp_timer_get_time() / 1000000));
    cJSON_AddBoolToObject(o, "locked", cfg->admin_pass[0] != '\0');

    cJSON *srv = cJSON_AddObjectToObject(o, "server");
    cJSON_AddBoolToObject(srv, "ok", st.server_ok);
    cJSON_AddNumberToObject(srv, "http", st.http_status);
    cJSON_AddNumberToObject(srv, "okCount", st.ok_count);
    cJSON_AddNumberToObject(srv, "failCount", st.fail_count);
    cJSON_AddNumberToObject(srv, "agoSec", st.last_ok_ms > 0
        ? (double)((esp_timer_get_time() / 1000 - st.last_ok_ms) / 1000) : -1);
    cJSON_AddStringToObject(srv, "msg", st.message);

    cJSON *c = cJSON_AddObjectToObject(o, "cfg");
    cJSON_AddStringToObject(c, "wifiSsid", cfg->wifi_ssid);
    cJSON_AddStringToObject(c, "serverUrl", cfg->server_url);
    /* Không trả khóa đầy đủ — chỉ đủ nhận ra đang dùng khóa nào. */
    size_t kl = strlen(cfg->device_key);
    cJSON_AddStringToObject(c, "keyTail", kl > 6 ? cfg->device_key + kl - 6 : "");
    cJSON_AddBoolToObject(c, "hasKey", kl > 0);
    cJSON_AddBoolToObject(c, "activeLow", cfg->active_low);
    cJSON_AddNumberToObject(c, "pollMs", cfg->poll_ms);
    cJSON_AddNumberToObject(c, "offlineOffMin", cfg->offline_off_min);

    cJSON *chs = cJSON_AddArrayToObject(o, "channels");
    for (int i = 0; i < LC_MAX_CH; i++) {
        cJSON *ch = cJSON_CreateObject();
        cJSON_AddNumberToObject(ch, "gpio", cfg->ch[i].gpio);
        cJSON_AddStringToObject(ch, "code", cfg->ch[i].table_code);
        cJSON_AddNumberToObject(ch, "mode", cfg->ch[i].mode);
        cJSON_AddBoolToObject(ch, "on", (mask >> i) & 1);
        cJSON_AddBoolToObject(ch, "serverOn", (st.server_mask >> i) & 1);
        cJSON_AddBoolToObject(ch, "unknown", (st.unknown_mask >> i) & 1);
        cJSON_AddItemToArray(chs, ch);
    }
    return send_json(req, o);
}

static esp_err_t h_tables(httpd_req_t *req)
{
    char *buf = malloc(12288);
    if (buf == NULL) {
        return httpd_resp_send_500(req);
    }
    size_t n = poller_copy_tables(buf, 12288);
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    esp_err_t err = n > 0 ? httpd_resp_send(req, buf, n) : httpd_resp_sendstr(req, "[]");
    free(buf);
    return err;
}

static bool gpio_ok(int pin)
{
    /* Chân ra hợp lệ của ESP32-C3, trừ 18/19 (USB nạp/nhật ký). */
    return pin == -1 || (pin >= 0 && pin <= 10) || pin == 20 || pin == 21;
}

static esp_err_t h_config(httpd_req_t *req)
{
    if (!authorized(req)) {
        return send_err(req, "401 Unauthorized", "Sai mat khau quan ly");
    }
    cJSON *in = read_body(req);
    if (in == NULL) {
        return send_err(req, "400 Bad Request", "Du lieu khong hop le");
    }

    light_config_t *c = malloc(sizeof(light_config_t));
    if (c == NULL) {
        cJSON_Delete(in);
        return httpd_resp_send_500(req);
    }
    *c = *light_config_get();

    copy_str(in, "name", c->name, sizeof(c->name));
    copy_str(in, "wifiSsid", c->wifi_ssid, sizeof(c->wifi_ssid));
    /* Ô mật khẩu / khóa để trống = giữ giá trị cũ. */
    const char *pw = cJSON_GetStringValue(cJSON_GetObjectItem(in, "wifiPass"));
    if (pw != NULL && pw[0]) {
        strlcpy(c->wifi_pass, pw, sizeof(c->wifi_pass));
    }
    copy_str(in, "serverUrl", c->server_url, sizeof(c->server_url));
    const char *key = cJSON_GetStringValue(cJSON_GetObjectItem(in, "deviceKey"));
    if (key != NULL && key[0]) {
        strlcpy(c->device_key, key, sizeof(c->device_key));
    }
    const char *ap = cJSON_GetStringValue(cJSON_GetObjectItem(in, "adminPass"));
    if (ap != NULL && ap[0]) {
        strlcpy(c->admin_pass, ap, sizeof(c->admin_pass));
    }
    if (cJSON_IsTrue(cJSON_GetObjectItem(in, "clearAdminPass"))) {
        c->admin_pass[0] = '\0';
    }
    cJSON *v;
    if (cJSON_IsBool(v = cJSON_GetObjectItem(in, "activeLow"))) {
        c->active_low = cJSON_IsTrue(v);
    }
    if (cJSON_IsNumber(v = cJSON_GetObjectItem(in, "pollMs"))) {
        c->poll_ms = v->valueint < 1000 ? 1000 : v->valueint > 60000 ? 60000 : v->valueint;
    }
    if (cJSON_IsNumber(v = cJSON_GetObjectItem(in, "offlineOffMin"))) {
        c->offline_off_min = v->valueint < 0 ? 0 : v->valueint > 1440 ? 1440 : v->valueint;
    }

    const char *bad = NULL;
    for (char *p = c->device_key; *p; p++) {
        bool okc = (*p >= '0' && *p <= '9') || (*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z')
                   || *p == '-';
        if (!okc) {
            bad = "Khoa thiet bi chi gom chu, so va dau '-'";
            break;
        }
    }
    if (strncmp(c->server_url, "http://", 7) != 0 && strncmp(c->server_url, "https://", 8) != 0) {
        bad = "Dia chi may chu phai bat dau bang https://";
    }

    cJSON *chs = cJSON_GetObjectItem(in, "channels");
    if (bad == NULL && cJSON_IsArray(chs)) {
        uint32_t used = 0;
        for (int i = 0; i < LC_MAX_CH; i++) {
            cJSON *ch = cJSON_GetArrayItem(chs, i);
            if (ch == NULL) {
                break;
            }
            if (cJSON_IsNumber(v = cJSON_GetObjectItem(ch, "gpio"))) {
                int pin = v->valueint;
                if (!gpio_ok(pin)) {
                    bad = "Chan GPIO khong dung duoc (chi 0-10, 20, 21)";
                    break;
                }
                if (pin >= 0 && (used >> pin & 1)) {
                    bad = "Hai kenh trung mot chan GPIO";
                    break;
                }
                if (pin >= 0) {
                    used |= 1u << pin;
                }
                c->ch[i].gpio = (int8_t)pin;
            }
            copy_str(ch, "code", c->ch[i].table_code, sizeof(c->ch[i].table_code));
        }
    }
    cJSON_Delete(in);

    if (bad != NULL) {
        free(c);
        return send_err(req, "400 Bad Request", bad);
    }
    esp_err_t err = light_config_save(c);
    free(c);
    if (err != ESP_OK) {
        return send_err(req, "500 Internal Server Error", "Khong luu duoc cau hinh");
    }
    ESP_LOGW(TAG, "da luu cau hinh - khoi dong lai");
    send_ok(req);
    /* Đổi chân relay / WiFi cần khởi tạo lại từ đầu. */
    schedule_restart();
    return ESP_OK;
}

static esp_err_t h_mode(httpd_req_t *req)
{
    if (!authorized(req)) {
        return send_err(req, "401 Unauthorized", "Sai mat khau quan ly");
    }
    cJSON *in = read_body(req);
    cJSON *ch = in ? cJSON_GetObjectItem(in, "ch") : NULL;
    cJSON *mode = in ? cJSON_GetObjectItem(in, "mode") : NULL;
    if (!cJSON_IsNumber(ch) || !cJSON_IsNumber(mode)
        || ch->valueint < 0 || ch->valueint >= LC_MAX_CH
        || mode->valueint < CH_AUTO || mode->valueint > CH_FORCE_OFF) {
        cJSON_Delete(in);
        return send_err(req, "400 Bad Request", "Du lieu khong hop le");
    }
    light_config_t *c = malloc(sizeof(light_config_t));
    if (c == NULL) {
        cJSON_Delete(in);
        return httpd_resp_send_500(req);
    }
    *c = *light_config_get();
    c->ch[ch->valueint].mode = (uint8_t)mode->valueint;
    cJSON_Delete(in);
    esp_err_t err = light_config_save(c);
    free(c);
    if (err != ESP_OK) {
        return send_err(req, "500 Internal Server Error", "Khong luu duoc");
    }
    poller_kick();
    return send_ok(req);
}

static esp_err_t h_reboot(httpd_req_t *req)
{
    if (!authorized(req)) {
        return send_err(req, "401 Unauthorized", "Sai mat khau quan ly");
    }
    send_ok(req);
    schedule_restart();
    return ESP_OK;
}

static esp_err_t h_factory(httpd_req_t *req)
{
    if (!authorized(req)) {
        return send_err(req, "401 Unauthorized", "Sai mat khau quan ly");
    }
    light_config_erase();
    send_ok(req);
    schedule_restart();
    return ESP_OK;
}

esp_err_t web_ui_start(void)
{
    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.max_uri_handlers = 12;
    config.stack_size = 6144;
    config.lru_purge_enable = true;

    httpd_handle_t server = NULL;
    esp_err_t err = httpd_start(&server, &config);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "khong mo duoc cong 80: %s", esp_err_to_name(err));
        return err;
    }
    const httpd_uri_t routes[] = {
        {.uri = "/", .method = HTTP_GET, .handler = h_index},
        {.uri = "/api/status", .method = HTTP_GET, .handler = h_status},
        {.uri = "/api/tables", .method = HTTP_GET, .handler = h_tables},
        {.uri = "/api/config", .method = HTTP_POST, .handler = h_config},
        {.uri = "/api/mode", .method = HTTP_POST, .handler = h_mode},
        {.uri = "/api/reboot", .method = HTTP_POST, .handler = h_reboot},
        {.uri = "/api/factory-reset", .method = HTTP_POST, .handler = h_factory},
    };
    for (size_t i = 0; i < sizeof(routes) / sizeof(routes[0]); i++) {
        httpd_register_uri_handler(server, &routes[i]);
    }
    return ESP_OK;
}
