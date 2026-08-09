#include "discovery.h"

#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>

#include "app_config.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "gateway.h"
#include "mdns.h"
#include "portal_auth.h"
#include "wifi_mgr.h"

static const char *TAG = "disco";

static char s_host[32];

static void build_host(void)
{
    strlcpy(s_host, "sboxadms", sizeof(s_host));
}

/* Một dòng JSON đủ để app dựng thẻ thiết bị mà chưa cần gọi /api/status. */
static int build_announce(char *out, size_t cap)
{
    gw_status_t st;
    gateway_status_snapshot(&st);
    const app_config_t *cfg = app_config_get();

    return snprintf(out, cap,
                    "{\"product\":\"sbox-zk-gateway\",\"host\":\"%s\",\"ip\":\"%s\","
                    "\"name\":\"%s\",\"serial\":\"%s\",\"deviceIp\":\"%s\","
                    "\"deviceOnline\":%s,\"serverOnline\":%s,\"provisioned\":%s,\"locked\":%s}",
                    s_host, wifi_mgr_sta_ip(), cfg->gw_name,
                    app_config_effective_serial(), cfg->device_ip,
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
    char tx[512];

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
    mdns_instance_name_set("SBOX ZK Gateway");

    /* Cho app biết cổng web và vài thuộc tính để lọc trước khi gọi HTTP. */
    mdns_txt_item_t txt[] = {
        {"product", "sbox-zk-gateway"},
        {"path", "/"},
    };
    mdns_service_add(NULL, "_sboxgw", "_tcp", 80, txt, sizeof(txt) / sizeof(txt[0]));
    mdns_service_add(NULL, "_http", "_tcp", 80, NULL, 0);

    ESP_LOGI(TAG, "mDNS: http://%s.local", s_host);
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
