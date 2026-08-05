#include "adms_client.h"

#include <stdio.h>
#include <string.h>

#include "app_config.h"
#include "esp_crt_bundle.h"
#include "esp_http_client.h"
#include "esp_log.h"

static const char *TAG = "adms";

/* Máy ZKTeco thật gửi chuỗi này; giữ nguyên để server/log không phân biệt. */
#define ADMS_USER_AGENT "iClock Proxy/1.09"
#define ADMS_TIMEOUT_MS 15000

static void build_url(char *dst, size_t cap, const char *path_and_query)
{
    const app_config_t *cfg = app_config_get();
    size_t len = strlcpy(dst, cfg->server_url, cap);

    /* bỏ dấu / thừa ở cuối server_url */
    while (len > 0 && dst[len - 1] == '/') {
        dst[--len] = '\0';
    }
    strlcat(dst, path_and_query, cap);
}

/* Bắt tay TLS tốn vài giây trên C3, nên giữ lại một kết nối dùng chung
 * cho mọi lượt gọi — quan trọng khi đẩy hàng nghìn bản ghi theo nhiều lô. */
static esp_http_client_handle_t s_client;

static void client_destroy(void)
{
    if (s_client != NULL) {
        esp_http_client_cleanup(s_client);
        s_client = NULL;
    }
}

void adms_client_reset(void)
{
    client_destroy();
}

static esp_err_t client_ensure(const char *url)
{
    if (s_client != NULL) {
        return esp_http_client_set_url(s_client, url);
    }

    esp_http_client_config_t cfg = {
        .url = url,
        .timeout_ms = ADMS_TIMEOUT_MS,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .user_agent = ADMS_USER_AGENT,
        .keep_alive_enable = true,
    };
    s_client = esp_http_client_init(&cfg);
    return s_client != NULL ? ESP_OK : ESP_FAIL;
}

static esp_err_t http_once(const char *url, esp_http_client_method_t method,
                           const char *body, size_t body_len,
                           char *resp, size_t resp_cap, adms_result_t *out)
{
    esp_err_t err = client_ensure(url);
    if (err != ESP_OK) {
        return err;
    }

    esp_http_client_set_method(s_client, method);
    esp_http_client_set_header(s_client, "Content-Type", "text/plain");
    esp_http_client_set_header(s_client, "Accept", "text/plain");

    err = esp_http_client_open(s_client, body_len);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "khong mo duoc ket noi toi %s: %s", url, esp_err_to_name(err));
        return err;
    }

    if (body_len > 0) {
        size_t written = 0;
        while (written < body_len) {
            int n = esp_http_client_write(s_client, body + written, body_len - written);
            if (n < 0) {
                esp_http_client_close(s_client);
                return ESP_FAIL;
            }
            written += (size_t)n;
        }
    }

    if (esp_http_client_fetch_headers(s_client) < 0) {
        esp_http_client_close(s_client);
        return ESP_FAIL;
    }

    int status = esp_http_client_get_status_code(s_client);
    if (out != NULL) {
        out->status = status;
    }

    if (resp != NULL && resp_cap > 1) {
        size_t total = 0;
        while (total + 1 < resp_cap) {
            int n = esp_http_client_read(s_client, resp + total, resp_cap - 1 - total);
            if (n <= 0) {
                break;
            }
            total += (size_t)n;
        }
        resp[total] = '\0';
        if (out != NULL) {
            out->len = total;
        }
    }

    esp_http_client_close(s_client);

    if (status < 200 || status >= 300) {
        ESP_LOGW(TAG, "HTTP %d tu %s", status, url);
        return ESP_ERR_INVALID_RESPONSE;
    }
    return ESP_OK;
}

static esp_err_t http_do(const char *url, esp_http_client_method_t method,
                         const char *body, size_t body_len,
                         char *resp, size_t resp_cap, adms_result_t *out)
{
    if (resp != NULL && resp_cap > 0) {
        resp[0] = '\0';
    }
    if (out != NULL) {
        out->status = 0;
        out->len = 0;
    }

    esp_err_t err = http_once(url, method, body, body_len, resp, resp_cap, out);
    if (err == ESP_OK || err == ESP_ERR_INVALID_RESPONSE) {
        return err;
    }

    /* Kết nối giữ lại nhiều khả năng đã bị server đóng — dựng lại rồi thử một lần nữa. */
    client_destroy();
    return http_once(url, method, body, body_len, resp, resp_cap, out);
}

esp_err_t adms_get_options(const char *sn, char *resp, size_t resp_cap, adms_result_t *out)
{
    char path[256];
    snprintf(path, sizeof(path),
             "/iclock/cdata?SN=%s&options=all&pushver=2.4.1&language=69&DeviceType=att&PushOptionsFlag=1",
             sn);

    char url[sizeof(path) + CFG_URL_LEN];
    build_url(url, sizeof(url), path);

    esp_err_t err = http_do(url, HTTP_METHOD_GET, NULL, 0, resp, resp_cap, out);
    if (err == ESP_OK) {
        ESP_LOGI(TAG, "dang ky voi server: %d byte cau hinh", (int)(out != NULL ? out->len : 0));
    }
    return err;
}

esp_err_t adms_post_options(const char *sn, const char *body)
{
    char path[128];
    snprintf(path, sizeof(path), "/iclock/cdata?SN=%s&table=options&Stamp=9999", sn);

    char url[sizeof(path) + CFG_URL_LEN];
    build_url(url, sizeof(url), path);

    char resp[32];
    return http_do(url, HTTP_METHOD_POST, body, strlen(body), resp, sizeof(resp), NULL);
}

esp_err_t adms_post_attlog(const char *sn, const char *body, const char *stamp)
{
    char path[160];
    snprintf(path, sizeof(path), "/iclock/cdata?SN=%s&table=ATTLOG&Stamp=%s",
             sn, stamp != NULL ? stamp : "9999");

    char url[sizeof(path) + CFG_URL_LEN];
    build_url(url, sizeof(url), path);

    char resp[32];
    esp_err_t err = http_do(url, HTTP_METHOD_POST, body, strlen(body), resp, sizeof(resp), NULL);
    if (err == ESP_OK && strncmp(resp, "OK", 2) != 0) {
        /* "FAIL" ở đây nghĩa là cả lô đều trùng bản ghi đã có — không phải lỗi truyền. */
        ESP_LOGW(TAG, "server tra ve '%s' cho lo ATTLOG (thuong la ban ghi trung)", resp);
    }
    return err;
}

esp_err_t adms_post_operlog(const char *sn, const char *body)
{
    char path[128];
    snprintf(path, sizeof(path), "/iclock/cdata?SN=%s&table=OPERLOG&Stamp=9999", sn);

    char url[sizeof(path) + CFG_URL_LEN];
    build_url(url, sizeof(url), path);

    char resp[32];
    return http_do(url, HTTP_METHOD_POST, body, strlen(body), resp, sizeof(resp), NULL);
}

esp_err_t adms_get_request(const char *sn, const char *info, char *resp, size_t resp_cap,
                           adms_result_t *out)
{
    char path[320];
    if (info != NULL && info[0] != '\0') {
        snprintf(path, sizeof(path), "/iclock/getrequest?SN=%s&INFO=%s", sn, info);
    } else {
        snprintf(path, sizeof(path), "/iclock/getrequest?SN=%s", sn);
    }

    char url[sizeof(path) + CFG_URL_LEN];
    build_url(url, sizeof(url), path);

    return http_do(url, HTTP_METHOD_GET, NULL, 0, resp, resp_cap, out);
}

esp_err_t adms_ack_command(const char *sn, const char *cmd_id, int ret_code, const char *cmd_name)
{
    char path[128];
    snprintf(path, sizeof(path), "/iclock/devicecmd?SN=%s", sn);

    char url[sizeof(path) + CFG_URL_LEN];
    build_url(url, sizeof(url), path);

    char body[192];
    snprintf(body, sizeof(body), "ID=%s&Return=%d&CMD=%s", cmd_id, ret_code,
             cmd_name != NULL ? cmd_name : "");

    char resp[32];
    ESP_LOGI(TAG, "bao ket qua lenh %s: Return=%d", cmd_id, ret_code);
    return http_do(url, HTTP_METHOD_POST, body, strlen(body), resp, sizeof(resp), NULL);
}

bool adms_parse_option(const char *block, const char *key, char *out, size_t cap)
{
    out[0] = '\0';
    if (block == NULL) {
        return false;
    }

    size_t key_len = strlen(key);
    const char *p = block;

    while (*p != '\0') {
        /* p đang ở đầu một dòng */
        if (strncmp(p, key, key_len) == 0 && p[key_len] == '=') {
            const char *v = p + key_len + 1;
            size_t n = 0;
            while (v[n] != '\0' && v[n] != '\r' && v[n] != '\n' && n + 1 < cap) {
                n++;
            }
            memcpy(out, v, n);
            out[n] = '\0';
            return true;
        }
        const char *nl = strchr(p, '\n');
        if (nl == NULL) {
            break;
        }
        p = nl + 1;
    }
    return false;
}
