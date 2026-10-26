#include "ble_link.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "cJSON.h"
#include "esp_app_desc.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "light_config.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "poller.h"
#include "relay.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"
#include "wifi_link.h"

static const char *TAG = "ble";

#define WINDOW_MS        (10 * 60 * 1000)
#define TEST_MS          3000
#define MAX_CMD_LEN      512

/* UUID 128-bit (LSB-first cho NimBLE): a6b10002-0a7c-4b8e-9f21-5b0c9000000x
 * — khác service gateway (a6b10001) để app không lẫn hai loại thiết bị. */
#define SBOX_UUID(last) BLE_UUID128_INIT((last), 0x00, 0x00, 0x90, 0x0c, 0x5b, 0x21, 0x9f, \
                                         0x8e, 0x4b, 0x7c, 0x0a, 0x02, 0x00, 0xb1, 0xa6)
static const ble_uuid128_t SVC_UUID = SBOX_UUID(0x01);
static const ble_uuid128_t CHR_CMD_UUID = SBOX_UUID(0x02);
static const ble_uuid128_t CHR_STATUS_UUID = SBOX_UUID(0x03);
static const ble_uuid128_t CHR_INFO_UUID = SBOX_UUID(0x04);

static uint16_t s_conn = BLE_HS_CONN_HANDLE_NONE;
static uint16_t s_status_handle;
static uint8_t s_addr_type;
static bool s_synced;
static bool s_advertising;
static char s_name[24];
static char s_status[200];
static SemaphoreHandle_t s_status_mu;
static QueueHandle_t s_cmd_q;
static volatile int64_t s_window_until_ms;

static int64_t now_ms(void)
{
    return esp_timer_get_time() / 1000;
}

static void set_status(const char *state, const char *msg)
{
    poller_status_t ps;
    poller_get_status(&ps);
    const char *ip = wifi_link_connected() ? wifi_link_ip() : "";

    char buf[sizeof(s_status)];
    snprintf(buf, sizeof(buf),
             "{\"state\":\"%s\",\"msg\":\"%s\",\"ip\":\"%s\",\"wifi\":%s,\"server\":%s,\"provisioned\":%s}",
             state, msg ? msg : "", ip,
             wifi_link_connected() ? "true" : "false",
             ps.server_ok ? "true" : "false",
             light_config_is_provisioned() ? "true" : "false");

    xSemaphoreTake(s_status_mu, portMAX_DELAY);
    strlcpy(s_status, buf, sizeof(s_status));
    xSemaphoreGive(s_status_mu);

    if (s_conn != BLE_HS_CONN_HANDLE_NONE && s_status_handle != 0) {
        struct os_mbuf *om = ble_hs_mbuf_from_flat(buf, strlen(buf));
        if (om != NULL) {
            ble_gatts_notify_custom(s_conn, s_status_handle, om);
        }
    }
}

/* ── Quảng cáo ─────────────────────────────────────────────────────────── */

static int gap_event(struct ble_gap_event *event, void *arg);

static bool should_advertise(void)
{
    return !light_config_is_provisioned() || wifi_link_ap_active() || now_ms() < s_window_until_ms;
}

static void start_advertise(void)
{
    if (!s_synced || s_advertising || s_conn != BLE_HS_CONN_HANDLE_NONE || !should_advertise()) {
        return;
    }
    struct ble_hs_adv_fields fields = {0};
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.name = (uint8_t *)s_name;
    fields.name_len = strlen(s_name);
    fields.name_is_complete = 1;
    int rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "adv fields rc=%d", rc);
        return;
    }
    /* Tên + UUID 128-bit vượt 31 byte — UUID để ở gói scan response. */
    struct ble_hs_adv_fields rsp = {0};
    rsp.uuids128 = (ble_uuid128_t *)&SVC_UUID;
    rsp.num_uuids128 = 1;
    rsp.uuids128_is_complete = 1;
    ble_gap_adv_rsp_set_fields(&rsp);

    struct ble_gap_adv_params adv = {
        .conn_mode = BLE_GAP_CONN_MODE_UND,
        .disc_mode = BLE_GAP_DISC_MODE_GEN,
    };
    rc = ble_gap_adv_start(s_addr_type, NULL, BLE_HS_FOREVER, &adv, gap_event, NULL);
    if (rc != 0) {
        ESP_LOGE(TAG, "adv start rc=%d", rc);
        return;
    }
    s_advertising = true;
    ESP_LOGW(TAG, "Bluetooth dang quang cao '%s' - mo app SBOX de cai dat", s_name);
}

static void stop_advertise(void)
{
    if (s_advertising) {
        ble_gap_adv_stop();
        s_advertising = false;
        ESP_LOGW(TAG, "het thoi gian cai dat - tat quang cao Bluetooth");
    }
}

static int gap_event(struct ble_gap_event *event, void *arg)
{
    (void)arg;
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        s_advertising = false;
        if (event->connect.status == 0) {
            s_conn = event->connect.conn_handle;
            ESP_LOGW(TAG, "app da ket noi Bluetooth");
            set_status("ready", "Da ket noi");
        } else {
            start_advertise();
        }
        return 0;
    case BLE_GAP_EVENT_DISCONNECT:
        s_conn = BLE_HS_CONN_HANDLE_NONE;
        ESP_LOGW(TAG, "app ngat Bluetooth (ly do %d)", event->disconnect.reason);
        start_advertise();
        return 0;
    case BLE_GAP_EVENT_ADV_COMPLETE:
        s_advertising = false;
        start_advertise();
        return 0;
    default:
        return 0;
    }
}

/* ── Lệnh từ app ───────────────────────────────────────────────────────── */

static bool pass_ok(cJSON *in)
{
    const light_config_t *cfg = light_config_get();
    if (!light_config_is_provisioned() || cfg->admin_pass[0] == '\0') {
        return true;
    }
    const char *p = cJSON_GetStringValue(cJSON_GetObjectItem(in, "pass"));
    return p != NULL && strcmp(p, cfg->admin_pass) == 0;
}

static void copy_str(cJSON *o, const char *key, char *dst, size_t cap)
{
    const char *v = cJSON_GetStringValue(cJSON_GetObjectItem(o, key));
    if (v != NULL) {
        strlcpy(dst, v, cap);
    }
}

static void do_wifi(cJSON *in)
{
    light_config_t *c = malloc(sizeof(light_config_t));
    if (c == NULL) {
        set_status("failed", "Het RAM");
        return;
    }
    *c = *light_config_get();
    copy_str(in, "name", c->name, sizeof(c->name));
    copy_str(in, "wifiSsid", c->wifi_ssid, sizeof(c->wifi_ssid));
    copy_str(in, "wifiPass", c->wifi_pass, sizeof(c->wifi_pass));
    copy_str(in, "deviceKey", c->device_key, sizeof(c->device_key));
    copy_str(in, "serverUrl", c->server_url, sizeof(c->server_url));
    copy_str(in, "adminPass", c->admin_pass, sizeof(c->admin_pass));

    if (c->wifi_ssid[0] == '\0' || c->device_key[0] == '\0') {
        free(c);
        set_status("failed", "Thieu ten WiFi hoac khoa thiet bi");
        return;
    }
    esp_err_t err = light_config_save(c);
    free(c);
    if (err != ESP_OK) {
        set_status("failed", "Khong luu duoc cau hinh");
        return;
    }

    set_status("connecting", "Dang vao WiFi");
    wifi_link_apply();
    for (int i = 0; i < 45 && !wifi_link_connected(); i++) {
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
    if (!wifi_link_connected()) {
        set_status("failed", "Khong vao duoc WiFi - kiem tra ten/mat khau, WiFi phai 2.4GHz");
        return;
    }

    set_status("checking", "Da vao WiFi, dang hoi may chu");
    poller_kick();
    poller_status_t ps = {0};
    for (int i = 0; i < 25; i++) {
        vTaskDelay(pdMS_TO_TICKS(1000));
        poller_get_status(&ps);
        if (ps.server_ok || ps.http_status == 401) {
            break;
        }
    }
    /* Cài xong vẫn giữ Bluetooth thêm để app gán kênh tiếp. */
    s_window_until_ms = now_ms() + WINDOW_MS;
    if (ps.server_ok) {
        set_status("online", "May chu OK");
    } else if (ps.http_status == 401) {
        set_status("failed", "May chu tu choi khoa thiet bi - bat lai Den ban bi-a trong app");
    } else {
        set_status("failed", ps.message);
    }
}

static void do_channels(cJSON *in)
{
    cJSON *list = cJSON_GetObjectItem(in, "ch");
    if (!cJSON_IsArray(list) || cJSON_GetArraySize(list) > LC_MAX_CH) {
        set_status("failed", "Danh sach kenh khong hop le");
        return;
    }
    light_config_t *old = malloc(sizeof(light_config_t));
    light_config_t *c = malloc(sizeof(light_config_t));
    if (old == NULL || c == NULL) {
        free(old);
        free(c);
        set_status("failed", "Het RAM");
        return;
    }
    *old = *light_config_get();
    *c = *old;

    cJSON *v = cJSON_GetObjectItem(in, "activeLow");
    if (cJSON_IsBool(v)) {
        c->active_low = cJSON_IsTrue(v);
    }
    const char *bad = NULL;
    uint32_t used = 0;
    int n = cJSON_GetArraySize(list);
    for (int i = 0; i < LC_MAX_CH; i++) {
        c->ch[i].gpio = -1;
        c->ch[i].table_code[0] = '\0';
        c->ch[i].mode = CH_AUTO;
        if (i >= n) {
            continue;
        }
        /* Mỗi kênh: [gpio, "mã bàn"] — gọn để vừa một lần ghi BLE. */
        cJSON *row = cJSON_GetArrayItem(list, i);
        cJSON *g = cJSON_GetArrayItem(row, 0);
        const char *code = cJSON_GetStringValue(cJSON_GetArrayItem(row, 1));
        int pin = cJSON_IsNumber(g) ? g->valueint : -1;
        if (pin >= 0 && (pin > 21 || !(relay_usable_pins() >> pin & 1))) {
            bad = "Chan GPIO khong dung duoc";
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
        if (code != NULL) {
            strlcpy(c->ch[i].table_code, code, sizeof(c->ch[i].table_code));
        }
        /* Giữ chế độ tay của kênh cùng bàn. */
        for (int j = 0; j < LC_MAX_CH; j++) {
            if (c->ch[i].table_code[0] && strcasecmp(c->ch[i].table_code, old->ch[j].table_code) == 0) {
                c->ch[i].mode = old->ch[j].mode;
            }
        }
    }

    if (bad != NULL) {
        set_status("failed", bad);
    } else if (light_config_save(c) != ESP_OK) {
        set_status("failed", "Khong luu duoc cau hinh");
    } else {
        relay_reconfigure(old);
        light_config_save_last_mask(relay_mask());
        poller_kick();
        set_status("saved", "Da luu kenh");
    }
    free(old);
    free(c);
}

static void cmd_task(void *arg)
{
    (void)arg;
    char *json;
    for (;;) {
        if (xQueueReceive(s_cmd_q, &json, portMAX_DELAY) != pdTRUE) {
            continue;
        }
        cJSON *in = cJSON_Parse(json);
        free(json);
        const char *op = cJSON_GetStringValue(cJSON_GetObjectItem(in, "op"));
        if (in == NULL || op == NULL) {
            set_status("failed", "Lenh khong hop le");
        } else if (!pass_ok(in)) {
            set_status("denied", "Sai mat khau quan ly");
        } else if (strcmp(op, "wifi") == 0) {
            do_wifi(in);
        } else if (strcmp(op, "channels") == 0) {
            do_channels(in);
        } else if (strcmp(op, "test") == 0) {
            cJSON *g = cJSON_GetObjectItem(in, "gpio");
            bool ok = cJSON_IsNumber(g) && relay_test_pin(g->valueint, TEST_MS);
            set_status(ok ? "testing" : "failed", ok ? "Dang bat thu" : "Chan GPIO khong dung duoc");
        } else {
            set_status("failed", "Lenh khong ho tro");
        }
        cJSON_Delete(in);
    }
}

/* ── GATT ──────────────────────────────────────────────────────────────── */

static char *build_info(void)
{
    const light_config_t *cfg = light_config_get();
    uint16_t mask = relay_mask();
    cJSON *o = cJSON_CreateObject();
    cJSON_AddStringToObject(o, "product", "sbox-bida-light");
    cJSON_AddStringToObject(o, "fw", esp_app_get_description()->version);
    cJSON_AddStringToObject(o, "name", cfg->name);
    cJSON_AddBoolToObject(o, "provisioned", light_config_is_provisioned());
    cJSON_AddBoolToObject(o, "wifi", wifi_link_connected());
    cJSON_AddStringToObject(o, "wifiSsid", cfg->wifi_ssid);
    cJSON_AddStringToObject(o, "ip", wifi_link_connected() ? wifi_link_ip() : "");
    cJSON_AddBoolToObject(o, "locked", light_config_is_provisioned() && cfg->admin_pass[0] != '\0');
    cJSON_AddBoolToObject(o, "activeLow", cfg->active_low);
    cJSON *pins = cJSON_AddArrayToObject(o, "pins");
    for (int p = 0; p <= 21; p++) {
        if (relay_usable_pins() >> p & 1) {
            cJSON_AddItemToArray(pins, cJSON_CreateNumber(p));
        }
    }
    cJSON *chs = cJSON_AddArrayToObject(o, "ch");
    for (int i = 0; i < LC_MAX_CH; i++) {
        cJSON *row = cJSON_CreateArray();
        cJSON_AddItemToArray(row, cJSON_CreateNumber(cfg->ch[i].gpio));
        cJSON_AddItemToArray(row, cJSON_CreateString(cfg->ch[i].table_code));
        cJSON_AddItemToArray(row, cJSON_CreateNumber((mask >> i) & 1));
        cJSON_AddItemToArray(chs, row);
    }
    char *s = cJSON_PrintUnformatted(o);
    cJSON_Delete(o);
    return s;
}

static int chr_access(uint16_t conn_handle, uint16_t attr_handle,
                      struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle;
    (void)attr_handle;
    (void)arg;
    const ble_uuid_t *uuid = ctxt->chr->uuid;

    if (ble_uuid_cmp(uuid, &CHR_INFO_UUID.u) == 0) {
        char *s = build_info();
        int rc = s ? os_mbuf_append(ctxt->om, s, strlen(s)) : BLE_HS_ENOMEM;
        free(s);
        return rc == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
    }
    if (ble_uuid_cmp(uuid, &CHR_STATUS_UUID.u) == 0) {
        xSemaphoreTake(s_status_mu, portMAX_DELAY);
        int rc = os_mbuf_append(ctxt->om, s_status, strlen(s_status));
        xSemaphoreGive(s_status_mu);
        return rc == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
    }
    if (ble_uuid_cmp(uuid, &CHR_CMD_UUID.u) == 0 && ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR) {
        uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
        if (len < 2 || len > MAX_CMD_LEN) {
            return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
        }
        char *json = malloc(len + 1);
        if (json == NULL || ble_hs_mbuf_to_flat(ctxt->om, json, len, NULL) != 0) {
            free(json);
            return BLE_ATT_ERR_INSUFFICIENT_RES;
        }
        json[len] = '\0';
        if (xQueueSend(s_cmd_q, &json, 0) != pdTRUE) {
            free(json);
            set_status("busy", "Dang xu ly lenh truoc");
            return BLE_ATT_ERR_UNLIKELY;
        }
        return 0;
    }
    return BLE_ATT_ERR_UNLIKELY;
}

static const struct ble_gatt_svc_def s_svcs[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &SVC_UUID.u,
        .characteristics = (struct ble_gatt_chr_def[]){
            {
                .uuid = &CHR_CMD_UUID.u,
                .access_cb = chr_access,
                .flags = BLE_GATT_CHR_F_WRITE,
            },
            {
                .uuid = &CHR_STATUS_UUID.u,
                .access_cb = chr_access,
                .val_handle = &s_status_handle,
                .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_NOTIFY,
            },
            {
                .uuid = &CHR_INFO_UUID.u,
                .access_cb = chr_access,
                .flags = BLE_GATT_CHR_F_READ,
            },
            {0},
        },
    },
    {0},
};

static void on_sync(void)
{
    if (ble_hs_util_ensure_addr(0) != 0 || ble_hs_id_infer_auto(0, &s_addr_type) != 0) {
        ESP_LOGE(TAG, "khong lay duoc dia chi Bluetooth");
        return;
    }
    s_synced = true;
    start_advertise();
}

static void host_task(void *param)
{
    (void)param;
    nimble_port_run();
    nimble_port_freertos_deinit();
}

/* Bật / tắt quảng cáo theo cửa sổ thời gian và tình trạng WiFi. */
static void window_task(void *arg)
{
    (void)arg;
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(3000));
        if (should_advertise()) {
            start_advertise();
        } else {
            stop_advertise();
        }
    }
}

void ble_link_open_window(uint32_t window_ms)
{
    s_window_until_ms = now_ms() + window_ms;
    ESP_LOGW(TAG, "mo Bluetooth cai dat trong %u phut", (unsigned)(window_ms / 60000));
    start_advertise();
}

esp_err_t ble_link_start(void)
{
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP);
    snprintf(s_name, sizeof(s_name), "SBOX-Den-%02X%02X", mac[4], mac[5]);

    s_status_mu = xSemaphoreCreateMutex();
    s_cmd_q = xQueueCreate(2, sizeof(char *));
    strlcpy(s_status, "{\"state\":\"idle\",\"msg\":\"\",\"ip\":\"\",\"wifi\":false,\"server\":false,\"provisioned\":false}",
            sizeof(s_status));
    s_window_until_ms = now_ms() + WINDOW_MS;

    esp_err_t err = nimble_port_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "nimble_port_init: %s", esp_err_to_name(err));
        return err;
    }
    ble_hs_cfg.sync_cb = on_sync;
    ble_svc_gap_init();
    ble_svc_gatt_init();
    if (ble_gatts_count_cfg(s_svcs) != 0 || ble_gatts_add_svcs(s_svcs) != 0) {
        ESP_LOGE(TAG, "khong dang ky duoc GATT");
        return ESP_FAIL;
    }
    ble_svc_gap_device_name_set(s_name);

    xTaskCreate(cmd_task, "ble_cmd", 6144, NULL, 5, NULL);
    xTaskCreate(window_task, "ble_win", 2560, NULL, 3, NULL);
    nimble_port_freertos_init(host_task);
    return ESP_OK;
}
