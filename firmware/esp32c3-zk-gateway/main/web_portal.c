#include "web_portal.h"

#include <stdlib.h>
#include <string.h>

#include "app_config.h"
#include "cJSON.h"
#include "esp_app_desc.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_ota_ops.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "gateway.h"
#include "wifi_mgr.h"

static const char *TAG = "web";

extern const char portal_html_start[] asm("_binary_portal_html_start");

static esp_err_t send_json(httpd_req_t *req, const char *json)
{
    httpd_resp_set_type(req, "application/json; charset=utf-8");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    return httpd_resp_sendstr(req, json);
}

static char *read_body(httpd_req_t *req, size_t max)
{
    if (req->content_len == 0 || req->content_len > max) {
        return NULL;
    }
    char *buf = malloc(req->content_len + 1);
    if (buf == NULL) {
        return NULL;
    }

    size_t got = 0;
    while (got < req->content_len) {
        int n = httpd_req_recv(req, buf + got, req->content_len - got);
        if (n <= 0) {
            free(buf);
            return NULL;
        }
        got += (size_t)n;
    }
    buf[got] = '\0';
    return buf;
}

/* ------------------------------------------------------------------ */

static esp_err_t root_get(httpd_req_t *req)
{
    httpd_resp_set_type(req, "text/html; charset=utf-8");
    return httpd_resp_sendstr(req, portal_html_start);
}

/* Vì sao mạch khởi động lại lần gần nhất. Phân biệt được ba nhóm nguyên nhân
 * rất khác nhau: mất nguồn (dây/nguồn yếu), phần mềm sập, hay bị treo. */
static const char *reset_reason_text(void)
{
    switch (esp_reset_reason()) {
    case ESP_RST_POWERON:  return "bat nguon";
    case ESP_RST_EXT:      return "nut reset";
    case ESP_RST_SW:       return "phan mem yeu cau";
    case ESP_RST_PANIC:    return "phan mem sap";
    case ESP_RST_INT_WDT:  return "treo ngat";
    case ESP_RST_TASK_WDT: return "treo tac vu";
    case ESP_RST_WDT:      return "treo chung";
    case ESP_RST_BROWNOUT: return "sut dien ap";
    case ESP_RST_DEEPSLEEP:return "thuc sau ngu sau";
    case ESP_RST_SDIO:     return "sdio";
    default:               return "khong ro";
    }
}

static esp_err_t status_get(httpd_req_t *req)
{
    gw_status_t st;
    gateway_status_snapshot(&st);

    const esp_app_desc_t *app = esp_app_get_description();
    int64_t uptime_s = esp_timer_get_time() / 1000000;

    char *json = malloc(1024);
    if (json == NULL) {
        return httpd_resp_send_500(req);
    }

    snprintf(json, 1024,
             "{\"wifi\":{\"connected\":%s,\"ip\":\"%s\",\"rssi\":%d,\"ap\":%s,\"apSsid\":\"%s\"},"
             "\"device\":{\"online\":%s,\"serial\":\"%s\",\"firmware\":\"%s\",\"platform\":\"%s\","
             "\"users\":%u,\"fingers\":%u,\"records\":%u},"
             "\"server\":{\"online\":%s},"
             "\"sync\":{\"uploadedTotal\":%u,\"uploadedLast\":%u,\"commands\":%u,"
             "\"lastCycleMs\":%lld,\"lastUploadMs\":%lld},"
             "\"error\":\"%s\",\"uptime\":%lld,\"heap\":%u,\"heapMin\":%u,"
             "\"resetReason\":\"%s\",\"version\":\"%s\"}",
             wifi_mgr_is_connected() ? "true" : "false", wifi_mgr_sta_ip(),
             wifi_mgr_rssi(), wifi_mgr_ap_active() ? "true" : "false", wifi_mgr_ap_ssid(),
             st.device_online ? "true" : "false", st.serial, st.firmware, st.platform,
             (unsigned)st.dev_users, (unsigned)st.dev_fingers, (unsigned)st.dev_records,
             st.server_online ? "true" : "false",
             (unsigned)st.uploaded_total, (unsigned)st.uploaded_last, (unsigned)st.commands_done,
             (long long)st.last_cycle_ms, (long long)st.last_upload_ms,
             st.last_error, (long long)uptime_s, (unsigned)esp_get_free_heap_size(),
             (unsigned)esp_get_minimum_free_heap_size(), reset_reason_text(),
             app != NULL ? app->version : "?");

    esp_err_t err = send_json(req, json);
    free(json);
    return err;
}

static esp_err_t config_get(httpd_req_t *req)
{
    const app_config_t *cfg = app_config_get();

    char json[832];
    snprintf(json, sizeof(json),
             "{\"gwName\":\"%s\",\"wifiSsid\":\"%s\",\"hasWifiPass\":%s,\"deviceIp\":\"%s\","
             "\"devicePort\":%u,"
             "\"commKey\":%u,\"serverUrl\":\"%s\",\"snOverride\":\"%s\",\"pollInterval\":%u,"
             "\"attlogInterval\":%u,\"backfillDays\":%u,\"tzOffset\":%d,\"syncClock\":%s}",
             cfg->gw_name, cfg->wifi_ssid, cfg->wifi_pass[0] != '\0' ? "true" : "false",
             cfg->device_ip, cfg->device_port, (unsigned)cfg->comm_key, cfg->server_url,
             cfg->sn_override, cfg->poll_interval_s, cfg->attlog_interval_s,
             cfg->backfill_days, cfg->tz_offset_h, cfg->sync_device_clock ? "true" : "false");

    return send_json(req, json);
}

/* Endpoint rất nhẹ để app xác nhận "đầu bên kia đúng là gateway SBOX" ngay khi
 * vừa dò được IP, không phải tải cả khối trạng thái. */
static esp_err_t info_get(httpd_req_t *req)
{
    gw_status_t st;
    gateway_status_snapshot(&st);

    const app_config_t *cfg = app_config_get();
    const esp_app_desc_t *app = esp_app_get_description();

    /* Chuỗi version lấy từ `git describe` nên không đổi khi sửa code chưa commit.
     * Mã băm ELF thì đổi theo từng bản build, nên đây là cách duy nhất để biết
     * mạch đang chạy đúng bản vừa nạp hay không. */
    char sha[17] = "?";
    if (app != NULL) {
        for (int i = 0; i < 8; i++) {
            snprintf(sha + i * 2, 3, "%02x", app->app_elf_sha256[i]);
        }
    }

    char json[640];
    snprintf(json, sizeof(json),
             "{\"product\":\"sbox-zk-gateway\",\"version\":\"%s\",\"build\":\"%s %s\","
             "\"appSha\":\"%s\",\"name\":\"%s\","
             "\"serial\":\"%s\",\"ip\":\"%s\",\"apSsid\":\"%s\",\"provisioned\":%s,"
             "\"wifiConnected\":%s,\"deviceOnline\":%s,\"serverOnline\":%s}",
             app != NULL ? app->version : "?",
             app != NULL ? app->date : "?", app != NULL ? app->time : "?",
             sha, cfg->gw_name,
             app_config_effective_serial(), wifi_mgr_sta_ip(), wifi_mgr_ap_ssid(),
             app_config_is_provisioned() ? "true" : "false",
             wifi_mgr_is_connected() ? "true" : "false",
             st.device_online ? "true" : "false",
             st.server_online ? "true" : "false");

    return send_json(req, json);
}

static void json_copy_str(cJSON *root, const char *key, char *dst, size_t cap)
{
    cJSON *item = cJSON_GetObjectItemCaseSensitive(root, key);
    if (cJSON_IsString(item) && item->valuestring != NULL) {
        strlcpy(dst, item->valuestring, cap);
    }
}

static void json_copy_int(cJSON *root, const char *key, long *dst)
{
    cJSON *item = cJSON_GetObjectItemCaseSensitive(root, key);
    if (cJSON_IsNumber(item)) {
        *dst = (long)item->valuedouble;
    }
}

static esp_err_t config_post(httpd_req_t *req)
{
    char *body = read_body(req, 2048);
    if (body == NULL) {
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "than yeu cau khong hop le");
        return ESP_FAIL;
    }

    cJSON *root = cJSON_Parse(body);
    free(body);
    if (root == NULL) {
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "JSON khong hop le");
        return ESP_FAIL;
    }

    app_config_t cfg = *app_config_get();
    char old_ssid[CFG_STR_LEN];
    char old_pass[CFG_STR_LEN];
    strlcpy(old_ssid, cfg.wifi_ssid, sizeof(old_ssid));
    strlcpy(old_pass, cfg.wifi_pass, sizeof(old_pass));

    json_copy_str(root, "gwName", cfg.gw_name, sizeof(cfg.gw_name));
    json_copy_str(root, "wifiSsid", cfg.wifi_ssid, sizeof(cfg.wifi_ssid));
    json_copy_str(root, "deviceIp", cfg.device_ip, sizeof(cfg.device_ip));
    json_copy_str(root, "serverUrl", cfg.server_url, sizeof(cfg.server_url));
    json_copy_str(root, "snOverride", cfg.sn_override, sizeof(cfg.sn_override));

    /* Mật khẩu chỉ ghi đè khi người dùng thực sự nhập giá trị mới. */
    cJSON *pass = cJSON_GetObjectItemCaseSensitive(root, "wifiPass");
    if (cJSON_IsString(pass) && pass->valuestring != NULL && pass->valuestring[0] != '\0') {
        strlcpy(cfg.wifi_pass, pass->valuestring, sizeof(cfg.wifi_pass));
    }

    long v;
    v = cfg.device_port;      json_copy_int(root, "devicePort", &v);     cfg.device_port = (uint16_t)v;
    v = cfg.comm_key;         json_copy_int(root, "commKey", &v);        cfg.comm_key = (uint32_t)v;
    v = cfg.poll_interval_s;  json_copy_int(root, "pollInterval", &v);   cfg.poll_interval_s = (uint16_t)v;
    v = cfg.attlog_interval_s;json_copy_int(root, "attlogInterval", &v); cfg.attlog_interval_s = (uint16_t)v;
    v = cfg.backfill_days;    json_copy_int(root, "backfillDays", &v);   cfg.backfill_days = (uint16_t)v;
    v = cfg.tz_offset_h;      json_copy_int(root, "tzOffset", &v);       cfg.tz_offset_h = (int8_t)v;

    cJSON *sync_clock = cJSON_GetObjectItemCaseSensitive(root, "syncClock");
    if (cJSON_IsBool(sync_clock)) {
        cfg.sync_device_clock = cJSON_IsTrue(sync_clock);
    }
    cJSON_Delete(root);

    if (cfg.device_port == 0) {
        cfg.device_port = 4370;
    }
    if (cfg.poll_interval_s < 5) {
        cfg.poll_interval_s = 5;
    }
    if (cfg.attlog_interval_s < 10) {
        cfg.attlog_interval_s = 10;
    }

    esp_err_t err = app_config_save(&cfg);
    if (err != ESP_OK) {
        httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "khong luu duoc cau hinh");
        return ESP_FAIL;
    }

    bool wifi_changed = strcmp(old_ssid, cfg.wifi_ssid) != 0 || strcmp(old_pass, cfg.wifi_pass) != 0;
    if (wifi_changed) {
        ESP_LOGW(TAG, "thong tin WiFi thay doi, ket noi lai");
        wifi_mgr_apply_config();
    }

    return send_json(req, "{\"ok\":true}");
}

static esp_err_t scan_get(httpd_req_t *req)
{
    const int max = 16;
    wifi_ap_record_t *aps = calloc(max, sizeof(wifi_ap_record_t));
    if (aps == NULL) {
        return httpd_resp_send_500(req);
    }

    int found = wifi_mgr_scan(aps, max);

    char *json = malloc(1536);
    if (json == NULL) {
        free(aps);
        return httpd_resp_send_500(req);
    }

    size_t len = strlcpy(json, "[", 1536);
    for (int i = 0; i < found && len < 1400; i++) {
        len += snprintf(json + len, 1536 - len, "%s{\"ssid\":\"%s\",\"rssi\":%d,\"secure\":%s}",
                        i > 0 ? "," : "", (char *)aps[i].ssid, aps[i].rssi,
                        aps[i].authmode == WIFI_AUTH_OPEN ? "false" : "true");
    }
    strlcat(json, "]", 1536);

    esp_err_t err = send_json(req, json);
    free(json);
    free(aps);
    return err;
}

static void reboot_task(void *arg)
{
    (void)arg;
    vTaskDelay(pdMS_TO_TICKS(800));
    esp_restart();
}

static esp_err_t action_post(httpd_req_t *req)
{
    char query[64] = {0};
    char what[32] = {0};
    if (httpd_req_get_url_query_str(req, query, sizeof(query)) == ESP_OK) {
        httpd_query_key_value(query, "do", what, sizeof(what));
    }

    if (strcmp(what, "resync") == 0) {
        gateway_request_full_resync();
    } else if (strcmp(what, "users") == 0) {
        gateway_request_user_sync();
    } else if (strcmp(what, "clock") == 0) {
        gateway_request_clock_sync();
    } else if (strcmp(what, "resetmark") == 0) {
        app_config_reset_mark();
        gateway_request_full_resync();
    } else if (strcmp(what, "reboot") == 0) {
        xTaskCreate(reboot_task, "reboot", 2048, NULL, 5, NULL);
    } else {
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "thao tac khong hop le");
        return ESP_FAIL;
    }

    return send_json(req, "{\"ok\":true}");
}

static esp_err_t ota_post(httpd_req_t *req)
{
    const esp_partition_t *target = esp_ota_get_next_update_partition(NULL);
    if (target == NULL) {
        httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "khong co phan vung OTA");
        return ESP_FAIL;
    }

    ESP_LOGW(TAG, "bat dau nap firmware moi vao %s (%d byte)", target->label, req->content_len);

    esp_ota_handle_t handle = 0;
    if (esp_ota_begin(target, OTA_WITH_SEQUENTIAL_WRITES, &handle) != ESP_OK) {
        httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "khong mo duoc OTA");
        return ESP_FAIL;
    }

    char *buf = malloc(2048);
    if (buf == NULL) {
        esp_ota_abort(handle);
        return httpd_resp_send_500(req);
    }

    int remaining = req->content_len;
    while (remaining > 0) {
        int n = httpd_req_recv(req, buf, remaining > 2048 ? 2048 : remaining);
        if (n <= 0) {
            free(buf);
            esp_ota_abort(handle);
            httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "mat ket noi khi nap");
            return ESP_FAIL;
        }
        if (esp_ota_write(handle, buf, n) != ESP_OK) {
            free(buf);
            esp_ota_abort(handle);
            httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "ghi firmware that bai");
            return ESP_FAIL;
        }
        remaining -= n;
    }
    free(buf);

    if (esp_ota_end(handle) != ESP_OK || esp_ota_set_boot_partition(target) != ESP_OK) {
        httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "firmware khong hop le");
        return ESP_FAIL;
    }

    send_json(req, "{\"ok\":true,\"reboot\":true}");
    xTaskCreate(reboot_task, "reboot", 2048, NULL, 5, NULL);
    return ESP_OK;
}

esp_err_t web_portal_start(void)
{
    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.max_uri_handlers = 12;
    config.stack_size = 6144;
    config.lru_purge_enable = true;
    config.recv_wait_timeout = 20;
    config.send_wait_timeout = 20;

    httpd_handle_t server = NULL;
    esp_err_t err = httpd_start(&server, &config);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "khong khoi dong duoc web server: %s", esp_err_to_name(err));
        return err;
    }

    const httpd_uri_t routes[] = {
        {.uri = "/", .method = HTTP_GET, .handler = root_get},
        {.uri = "/api/info", .method = HTTP_GET, .handler = info_get},
        {.uri = "/api/status", .method = HTTP_GET, .handler = status_get},
        {.uri = "/api/config", .method = HTTP_GET, .handler = config_get},
        {.uri = "/api/config", .method = HTTP_POST, .handler = config_post},
        {.uri = "/api/scan", .method = HTTP_GET, .handler = scan_get},
        {.uri = "/api/action", .method = HTTP_POST, .handler = action_post},
        {.uri = "/api/ota", .method = HTTP_POST, .handler = ota_post},
    };

    for (size_t i = 0; i < sizeof(routes) / sizeof(routes[0]); i++) {
        httpd_register_uri_handler(server, &routes[i]);
    }

    ESP_LOGI(TAG, "trang cau hinh da san sang");
    return ESP_OK;
}
