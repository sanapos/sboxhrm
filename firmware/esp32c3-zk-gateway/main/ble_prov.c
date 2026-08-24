#include "ble_prov.h"

#include <stdio.h>
#include <string.h>

#include "app_config.h"
#include "cJSON.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"
#include "wifi_mgr.h"

static const char *TAG = "ble_prov";

/* UUID 128-bit (LSB-first cho NimBLE):
 * Service  a6b10001-0a7c-4b8e-9f21-5b0c90000001
 * Config   a6b10001-0a7c-4b8e-9f21-5b0c90000002  (write)
 * Status   a6b10001-0a7c-4b8e-9f21-5b0c90000003  (read/notify)
 * Info     a6b10001-0a7c-4b8e-9f21-5b0c90000004  (read)
 */
static const ble_uuid128_t SVC_UUID =
    BLE_UUID128_INIT(0x01, 0x00, 0x00, 0x90, 0x0c, 0x5b, 0x21, 0x9f,
                     0x8e, 0x4b, 0x7c, 0x0a, 0x01, 0x00, 0xb1, 0xa6);
static const ble_uuid128_t CHR_CONFIG_UUID =
    BLE_UUID128_INIT(0x02, 0x00, 0x00, 0x90, 0x0c, 0x5b, 0x21, 0x9f,
                     0x8e, 0x4b, 0x7c, 0x0a, 0x01, 0x00, 0xb1, 0xa6);
static const ble_uuid128_t CHR_STATUS_UUID =
    BLE_UUID128_INIT(0x03, 0x00, 0x00, 0x90, 0x0c, 0x5b, 0x21, 0x9f,
                     0x8e, 0x4b, 0x7c, 0x0a, 0x01, 0x00, 0xb1, 0xa6);
static const ble_uuid128_t CHR_INFO_UUID =
    BLE_UUID128_INIT(0x04, 0x00, 0x00, 0x90, 0x0c, 0x5b, 0x21, 0x9f,
                     0x8e, 0x4b, 0x7c, 0x0a, 0x01, 0x00, 0xb1, 0xa6);

static uint16_t s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
static uint16_t s_status_val_handle;
static uint8_t s_own_addr_type;
static bool s_active;
static bool s_nimble_ready;
static bool s_advertising;
static char s_adv_name[24];
static char s_status[192];
static SemaphoreHandle_t s_status_mu;
static TaskHandle_t s_apply_task;

static void set_status(const char *state, const char *msg)
{
    char ip[16] = {0};
    strlcpy(ip, wifi_mgr_sta_ip(), sizeof(ip));
    if (ip[0] == '\0' || strcmp(ip, "0.0.0.0") == 0) {
        ip[0] = '\0';
    }

    char buf[192];
    snprintf(buf, sizeof(buf),
             "{\"state\":\"%s\",\"ip\":\"%s\",\"msg\":\"%s\",\"wifi\":%s,\"provisioned\":%s}",
             state ? state : "idle",
             ip,
             msg ? msg : "",
             wifi_mgr_is_connected() ? "true" : "false",
             app_config_is_provisioned() ? "true" : "false");

    if (s_status_mu && xSemaphoreTake(s_status_mu, pdMS_TO_TICKS(200)) == pdTRUE) {
        strlcpy(s_status, buf, sizeof(s_status));
        xSemaphoreGive(s_status_mu);
    } else {
        strlcpy(s_status, buf, sizeof(s_status));
    }

    if (s_conn_handle != BLE_HS_CONN_HANDLE_NONE && s_status_val_handle != 0) {
        struct os_mbuf *om = ble_hs_mbuf_from_flat(s_status, strlen(s_status));
        if (om != NULL) {
            ble_gatts_notify_custom(s_conn_handle, s_status_val_handle, om);
        }
    }
}

static void build_adv_name(void)
{
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP);
    snprintf(s_adv_name, sizeof(s_adv_name), "SBOX-Gateway-%02X%02X", mac[4], mac[5]);
}

static int gap_event(struct ble_gap_event *event, void *arg);

static void start_advertise(void)
{
    if (!s_active) {
        return;
    }

    struct ble_gap_adv_params adv = {0};
    adv.conn_mode = BLE_GAP_CONN_MODE_UND;
    adv.disc_mode = BLE_GAP_DISC_MODE_GEN;

    struct ble_hs_adv_fields fields = {0};
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.name = (uint8_t *)s_adv_name;
    fields.name_len = strlen(s_adv_name);
    fields.name_is_complete = 1;
    fields.uuids128 = (ble_uuid128_t *)&SVC_UUID;
    fields.num_uuids128 = 1;
    fields.uuids128_is_complete = 1;

    int rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) {
        /* Tên + UUID 128 có thể vượt 31 byte — bỏ UUID khỏi adv, để scan response. */
        memset(&fields, 0, sizeof(fields));
        fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
        fields.name = (uint8_t *)s_adv_name;
        fields.name_len = strlen(s_adv_name);
        fields.name_is_complete = 1;
        rc = ble_gap_adv_set_fields(&fields);
        if (rc != 0) {
            ESP_LOGE(TAG, "adv fields rc=%d", rc);
            return;
        }

        struct ble_hs_adv_fields rsp = {0};
        rsp.uuids128 = (ble_uuid128_t *)&SVC_UUID;
        rsp.num_uuids128 = 1;
        rsp.uuids128_is_complete = 1;
        ble_gap_adv_rsp_set_fields(&rsp);
    }

    rc = ble_gap_adv_start(s_own_addr_type, NULL, BLE_HS_FOREVER, &adv, gap_event, NULL);
    if (rc != 0) {
        ESP_LOGE(TAG, "adv start rc=%d", rc);
        s_advertising = false;
        return;
    }
    s_advertising = true;
    ESP_LOGW(TAG, "BLE dang quang cao: %s (giu WiFi nha, dung app HRM)", s_adv_name);
}

static int gap_event(struct ble_gap_event *event, void *arg)
{
    (void)arg;
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status == 0) {
            s_conn_handle = event->connect.conn_handle;
            s_advertising = false;
            ESP_LOGI(TAG, "BLE connected handle=%u", s_conn_handle);
            set_status("ready", "Da ket noi BLE");
        } else {
            start_advertise();
        }
        return 0;
    case BLE_GAP_EVENT_DISCONNECT:
        ESP_LOGI(TAG, "BLE disconnect reason=%d", event->disconnect.reason);
        s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
        if (s_active && !app_config_is_provisioned()) {
            start_advertise();
        } else if (s_active && app_config_is_provisioned() && !wifi_mgr_is_connected()) {
            start_advertise();
        }
        return 0;
    case BLE_GAP_EVENT_SUBSCRIBE:
        if (event->subscribe.attr_handle == s_status_val_handle &&
            event->subscribe.cur_notify) {
            set_status(wifi_mgr_is_connected() ? "connected" : "ready",
                       wifi_mgr_is_connected() ? "WiFi OK" : "Cho cau hinh");
        }
        return 0;
    case BLE_GAP_EVENT_MTU:
        ESP_LOGI(TAG, "MTU %u", event->mtu.value);
        return 0;
    default:
        return 0;
    }
}

static int chr_access(uint16_t conn_handle, uint16_t attr_handle,
                      struct ble_gatt_access_ctxt *ctxt, void *arg);

static const struct ble_gatt_svc_def s_gatt_svcs[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &SVC_UUID.u,
        .characteristics =
            (struct ble_gatt_chr_def[]){
                {
                    .uuid = &CHR_CONFIG_UUID.u,
                    .access_cb = chr_access,
                    .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_NO_RSP,
                },
                {
                    .uuid = &CHR_STATUS_UUID.u,
                    .access_cb = chr_access,
                    .val_handle = &s_status_val_handle,
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

static void apply_config_task(void *arg)
{
    char *json = (char *)arg;
    set_status("saving", "Dang luu cau hinh");

    cJSON *root = cJSON_Parse(json);
    free(json);
    if (root == NULL) {
        set_status("failed", "JSON khong hop le");
        s_apply_task = NULL;
        vTaskDelete(NULL);
        return;
    }

    app_config_t cfg = *app_config_get();
    cJSON *item;

    item = cJSON_GetObjectItemCaseSensitive(root, "wifiSsid");
    if (cJSON_IsString(item) && item->valuestring) {
        strlcpy(cfg.wifi_ssid, item->valuestring, sizeof(cfg.wifi_ssid));
    }
    item = cJSON_GetObjectItemCaseSensitive(root, "wifiPass");
    if (cJSON_IsString(item) && item->valuestring) {
        strlcpy(cfg.wifi_pass, item->valuestring, sizeof(cfg.wifi_pass));
    }
    item = cJSON_GetObjectItemCaseSensitive(root, "deviceIp");
    if (cJSON_IsString(item) && item->valuestring) {
        strlcpy(cfg.device_ip, item->valuestring, sizeof(cfg.device_ip));
    }
    item = cJSON_GetObjectItemCaseSensitive(root, "gwName");
    if (cJSON_IsString(item) && item->valuestring) {
        strlcpy(cfg.gw_name, item->valuestring, sizeof(cfg.gw_name));
    }
    item = cJSON_GetObjectItemCaseSensitive(root, "commKey");
    if (cJSON_IsNumber(item)) {
        cfg.comm_key = (uint32_t)item->valuedouble;
    }
    item = cJSON_GetObjectItemCaseSensitive(root, "devicePort");
    if (cJSON_IsNumber(item) && item->valuedouble > 0) {
        cfg.device_port = (uint16_t)item->valuedouble;
    }

    cJSON_Delete(root);

    if (cfg.wifi_ssid[0] == '\0' || cfg.device_ip[0] == '\0') {
        set_status("failed", "Thieu wifiSsid hoac deviceIp");
        s_apply_task = NULL;
        vTaskDelete(NULL);
        return;
    }

    if (app_config_save(&cfg) != ESP_OK) {
        set_status("failed", "Luu NVS that bai");
        s_apply_task = NULL;
        vTaskDelete(NULL);
        return;
    }

    set_status("connecting", "Dang noi WiFi");
    if (wifi_mgr_apply_config() != ESP_OK) {
        set_status("failed", "Khong apply WiFi");
        s_apply_task = NULL;
        vTaskDelete(NULL);
        return;
    }

    for (int i = 0; i < 45; i++) {
        vTaskDelay(pdMS_TO_TICKS(1000));
        if (wifi_mgr_is_connected()) {
            set_status("connected", "WiFi OK");
            /* Giữ BLE thêm vài giây để app đọc IP rồi tắt. */
            vTaskDelay(pdMS_TO_TICKS(3000));
            if (app_config_is_provisioned()) {
                ble_prov_stop();
            }
            s_apply_task = NULL;
            vTaskDelete(NULL);
            return;
        }
        if ((i % 5) == 4) {
            set_status("connecting", "Dang cho WiFi...");
        }
    }

    set_status("failed", "WiFi timeout — kiem tra SSID/mat khau (2.4GHz)");
    s_apply_task = NULL;
    vTaskDelete(NULL);
}

static int chr_access(uint16_t conn_handle, uint16_t attr_handle,
                      struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle;
    (void)attr_handle;
    (void)arg;

    const ble_uuid_t *uuid = ctxt->chr->uuid;

    if (ble_uuid_cmp(uuid, &CHR_INFO_UUID.u) == 0) {
        if (ctxt->op != BLE_GATT_ACCESS_OP_READ_CHR) {
            return BLE_ATT_ERR_UNLIKELY;
        }
        char buf[240];
        snprintf(buf, sizeof(buf),
                 "{\"product\":\"sbox-zk-gateway\",\"name\":\"%s\",\"apSsid\":\"%s\","
                 "\"serial\":\"%s\",\"provisioned\":%s,\"wifi\":%s}",
                 app_config_get()->gw_name,
                 s_adv_name[0] ? s_adv_name : wifi_mgr_ap_ssid(),
                 app_config_effective_serial(),
                 app_config_is_provisioned() ? "true" : "false",
                 wifi_mgr_is_connected() ? "true" : "false");
        int rc = os_mbuf_append(ctxt->om, buf, strlen(buf));
        return rc == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
    }

    if (ble_uuid_cmp(uuid, &CHR_STATUS_UUID.u) == 0) {
        if (ctxt->op != BLE_GATT_ACCESS_OP_READ_CHR) {
            return BLE_ATT_ERR_UNLIKELY;
        }
        const char *p = s_status[0] ? s_status : "{\"state\":\"idle\",\"ip\":\"\",\"msg\":\"\",\"wifi\":false,\"provisioned\":false}";
        int rc = os_mbuf_append(ctxt->om, p, strlen(p));
        return rc == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
    }

    if (ble_uuid_cmp(uuid, &CHR_CONFIG_UUID.u) == 0) {
        if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR) {
            return BLE_ATT_ERR_UNLIKELY;
        }
        uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
        if (len < 2 || len > 480) {
            return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
        }
        if (s_apply_task != NULL) {
            set_status("busy", "Dang xu ly cau hinh truoc");
            return BLE_ATT_ERR_UNLIKELY;
        }
        char *json = malloc(len + 1);
        if (json == NULL) {
            return BLE_ATT_ERR_INSUFFICIENT_RES;
        }
        int rc = ble_hs_mbuf_to_flat(ctxt->om, json, len, NULL);
        if (rc != 0) {
            free(json);
            return BLE_ATT_ERR_UNLIKELY;
        }
        json[len] = '\0';
        ESP_LOGW(TAG, "BLE config (%u byte): %.80s...", (unsigned)len, json);
        if (xTaskCreate(apply_config_task, "ble_cfg", 6144, json, 5, &s_apply_task) != pdPASS) {
            free(json);
            s_apply_task = NULL;
            return BLE_ATT_ERR_INSUFFICIENT_RES;
        }
        return 0;
    }

    return BLE_ATT_ERR_UNLIKELY;
}

static void on_sync(void)
{
    int rc = ble_hs_util_ensure_addr(0);
    if (rc != 0) {
        ESP_LOGE(TAG, "ensure addr rc=%d", rc);
        return;
    }
    rc = ble_hs_id_infer_auto(0, &s_own_addr_type);
    if (rc != 0) {
        ESP_LOGE(TAG, "infer addr rc=%d", rc);
        return;
    }
    start_advertise();
}

static void on_reset(int reason)
{
    ESP_LOGW(TAG, "nimble reset reason=%d", reason);
}

static void nimble_host_task(void *param)
{
    (void)param;
    nimble_port_run();
    nimble_port_freertos_deinit();
}

esp_err_t ble_prov_start(void)
{
    if (s_active) {
        if (!s_advertising && s_conn_handle == BLE_HS_CONN_HANDLE_NONE && s_nimble_ready) {
            start_advertise();
        }
        return ESP_OK;
    }

    if (s_status_mu == NULL) {
        s_status_mu = xSemaphoreCreateMutex();
    }
    build_adv_name();
    strlcpy(s_status,
            "{\"state\":\"idle\",\"ip\":\"\",\"msg\":\"Cho app\",\"wifi\":false,\"provisioned\":false}",
            sizeof(s_status));

    if (s_nimble_ready) {
        s_active = true;
        start_advertise();
        ESP_LOGW(TAG, "BLE provision bat lai: %s", s_adv_name);
        return ESP_OK;
    }

    esp_err_t err = nimble_port_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "nimble_port_init: %s", esp_err_to_name(err));
        return err;
    }

    ble_hs_cfg.reset_cb = on_reset;
    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.gatts_register_cb = NULL;
    ble_hs_cfg.store_status_cb = NULL;

    ble_svc_gap_init();
    ble_svc_gatt_init();

    int rc = ble_gatts_count_cfg(s_gatt_svcs);
    if (rc != 0) {
        ESP_LOGE(TAG, "gatts_count_cfg rc=%d", rc);
        return ESP_FAIL;
    }
    rc = ble_gatts_add_svcs(s_gatt_svcs);
    if (rc != 0) {
        ESP_LOGE(TAG, "gatts_add_svcs rc=%d", rc);
        return ESP_FAIL;
    }

    rc = ble_svc_gap_device_name_set(s_adv_name);
    if (rc != 0) {
        ESP_LOGW(TAG, "gap name rc=%d", rc);
    }

    s_active = true;
    s_nimble_ready = true;
    nimble_port_freertos_init(nimble_host_task);
    ESP_LOGW(TAG, "BLE provision bat: %s", s_adv_name);
    return ESP_OK;
}

void ble_prov_stop(void)
{
    if (!s_active) {
        return;
    }
    ESP_LOGW(TAG, "tat quang cao BLE provision");
    if (s_advertising) {
        ble_gap_adv_stop();
        s_advertising = false;
    }
    if (s_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
        ble_gap_terminate(s_conn_handle, BLE_ERR_REM_USER_CONN_TERM);
        s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
    }
    s_active = false;
}
bool ble_prov_is_active(void)
{
    return s_active;
}

void ble_prov_on_wifi_connected(void)
{
    if (!s_active) {
        return;
    }
    set_status("connected", "WiFi OK");
}
