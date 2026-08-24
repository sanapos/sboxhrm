#include "discovery.h"

#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>

#include "app_config.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "gateway.h"
#include "mdns.h"
#include "portal_auth.h"
#include "wifi_mgr.h"

static const char *TAG = "disco";

static char s_host[32];
static char s_suffix[8];

static void build_host(void)
{
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP);
    snprintf(s_suffix, sizeof(s_suffix), "%02X%02X", mac[4], mac[5]);
    /* Hostname riêng từng mạch — nhiều gateway cùng LAN không còn tranh sboxadms.local */
    snprintf(s_host, sizeof(s_host), "sboxgw-%s", s_suffix);
    /* Chuẩn hoá chữ thường cho mDNS (RFC khuyến nghị). */
    for (char *p = s_host; *p; p++) {
        if (*p >= 'A' && *p <= 'Z') {
            *p = (char)(*p - 'A' + 'a');
        }
    }
}

const char *discovery_hostname(void)
{
    return s_host[0] ? s_host : "sboxgw";
}

/* Một dòng JSON đủ để app dựng thẻ thiết bị mà chưa cần gọi /api/status. */
static int build_announce(char *out, size_t cap)
{
    gw_status_t st;
    gateway_status_snapshot(&st);
    const app_config_t *cfg = app_config_get();

    return snprintf(out, cap,
                    "{\"product\":\"sbox-zk-gateway\",\"host\":\"%s\",\"ip\":\"%s\","
                    "\"name\":\"%s\",\"serial\":\"%s\",\"deviceIp\":\"%s\",\"apSsid\":\"%s\","
                    "\"deviceOnline\":%s,\"serverOnline\":%s,\"provisioned\":%s,\"locked\":%s}",
                    s_host, wifi_mgr_sta_ip(), cfg->gw_name,
                    app_config_effective_serial(), cfg->device_ip, wifi_mgr_ap_ssid(),
                    st.device_online ? "true" : "false",
                    st.server_online ? "true" : "false",
                    app_config_is_provisioned() ? "true" : "false",
                    portal_password_enabled() ? "true" : "false");
}

/* Nhiều router chặn multicast giữa các client nên mDNS một mình là không đủ.
 * Kênh UDP này chỉ trả lời khi được hỏi đúng chuỗi, nên không gây ồn mạng. */
static void udp_responder_task(void *arg)
{
    (void)arg;

    int sock = -1;
    char rx[64];
    char tx[640];

    for (;;) {
        if (sock < 0) {
            sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
            if (sock < 0) {
                vTaskDelay(pdMS_TO_TICKS(5000));
                continue;
            }

            struct sockaddr_in addr = {
                .sin_family = AF_INET,
                .sin_port = htons(DISCOVERY_UDP_PORT),
                .sin_addr.s_addr = htonl(INADDR_ANY),
            };
            if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
                ESP_LOGW(TAG, "khong bind duoc cong UDP %d", DISCOVERY_UDP_PORT);
                close(sock);
                sock = -1;
                vTaskDelay(pdMS_TO_TICKS(5000));
                continue;
            }
            ESP_LOGI(TAG, "dang lang nghe do tim tai cong UDP %d", DISCOVERY_UDP_PORT);
        }

        struct sockaddr_in from;
        socklen_t from_len = sizeof(from);
        int n = recvfrom(sock, rx, sizeof(rx) - 1, 0, (struct sockaddr *)&from, &from_len);
        if (n < 0) {
            close(sock);
            sock = -1;
            continue;
        }
        rx[n] = '\0';

        if (strncmp(rx, DISCOVERY_PROBE, strlen(DISCOVERY_PROBE)) != 0) {
            continue;
        }

        int len = build_announce(tx, sizeof(tx));
        if (len > 0) {
            sendto(sock, tx, (size_t)len, 0, (struct sockaddr *)&from, from_len);
        }
    }
}

static void start_mdns(void)
{
    if (mdns_init() != ESP_OK) {
        ESP_LOGW(TAG, "khong khoi dong duoc mDNS");
        return;
    }

    mdns_hostname_set(s_host);

    char instance[40];
    const char *gw = app_config_get()->gw_name;
    if (gw != NULL && gw[0] != '\0') {
        strlcpy(instance, gw, sizeof(instance));
    } else {
        snprintf(instance, sizeof(instance), "SBOX-GW-%s", s_suffix);
    }
    mdns_instance_name_set(instance);

    static char txt_host[32];
    static char txt_ap[32];
    strlcpy(txt_host, s_host, sizeof(txt_host));
    strlcpy(txt_ap, wifi_mgr_ap_ssid(), sizeof(txt_ap));

    mdns_txt_item_t txt[] = {
        {"product", "sbox-zk-gateway"},
        {"path", "/"},
        {"host", txt_host},
        {"ap", txt_ap},
    };
    mdns_service_add(instance, "_sboxgw", "_tcp", 80, txt, sizeof(txt) / sizeof(txt[0]));
    mdns_service_add(instance, "_http", "_tcp", 80, NULL, 0);

    ESP_LOGI(TAG, "mDNS: http://%s.local (instance=%s)", s_host, instance);
}

esp_err_t discovery_start(void)
{
    build_host();
    start_mdns();

    if (xTaskCreate(udp_responder_task, "disco_udp", 4096, NULL, 3, NULL) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    return ESP_OK;
}
