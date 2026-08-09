#include "portal_auth.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "app_config.h"
#include "cJSON.h"
#include "esp_log.h"
#include "mbedtls/sha256.h"
#include "wifi_mgr.h"

static const char *TAG = "auth";

static void hash_password(const char *plain, char out_hex[65])
{
    unsigned char dig[32];
    mbedtls_sha256((const unsigned char *)plain, strlen(plain), dig, 0);
    for (int i = 0; i < 32; i++) {
        snprintf(out_hex + i * 2, 3, "%02x", dig[i]);
    }
    out_hex[64] = '\0';
}

bool portal_password_enabled(void)
{
    const char *h = app_config_portal_pass_hash();
    return h != NULL && h[0] != '\0';
}

bool portal_password_matches(const char *plain)
{
    if (plain == NULL) {
        return false;
    }
    const char *stored = app_config_portal_pass_hash();
    if (stored == NULL || stored[0] == '\0') {
        return true;
    }
    char got[65];
    hash_password(plain, got);
    return strcmp(got, stored) == 0;
}

esp_err_t portal_password_set(const char *plain)
{
    if (plain == NULL || strlen(plain) < 4 || strlen(plain) > 64) {
        return ESP_ERR_INVALID_ARG;
    }
    char hex[65];
    hash_password(plain, hex);
    return app_config_save_portal_pass_hash(hex);
}

esp_err_t portal_password_clear(void)
{
    return app_config_save_portal_pass_hash("");
}

static bool extract_basic_password(httpd_req_t *req, char *out, size_t cap)
{
    out[0] = '\0';
    char auth[192];
    if (httpd_req_get_hdr_value_str(req, "Authorization", auth, sizeof(auth)) != ESP_OK) {
        return false;
    }
    if (strncmp(auth, "Basic ", 6) != 0) {
        return false;
    }

    /* Base64 decode tối giản cho "admin:password". */
    static const char b64[] =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const char *src = auth + 6;
    while (*src == ' ') {
        src++;
    }

    unsigned char buf[128];
    size_t n = 0;
    int val = 0, valb = -8;
    for (; *src && *src != ' ' && n + 1 < sizeof(buf); src++) {
        if (*src == '=') {
            break;
        }
        const char *p = strchr(b64, *src);
        if (p == NULL) {
            continue;
        }
        val = (val << 6) | (int)(p - b64);
        valb += 6;
        if (valb >= 0) {
            buf[n++] = (unsigned char)((val >> valb) & 0xFF);
            valb -= 8;
        }
    }
    buf[n] = '\0';

    /* Kỳ vọng "admin:...." hoặc ":pass" hoặc chỉ pass. */
    char *colon = strchr((char *)buf, ':');
    const char *pass = colon != NULL ? colon + 1 : (const char *)buf;
    strlcpy(out, pass, cap);
    return out[0] != '\0';
}

static void send_unauthorized(httpd_req_t *req)
{
    httpd_resp_set_status(req, "401 Unauthorized");
    httpd_resp_set_hdr(req, "WWW-Authenticate", "Basic realm=\"SBOX Gateway\"");
    httpd_resp_set_type(req, "application/json");
    httpd_resp_sendstr(req, "{\"error\":\"unauthorized\",\"locked\":true}");
}

esp_err_t portal_auth_guard(httpd_req_t *req)
{
    if (!portal_password_enabled()) {
        return ESP_OK;
    }
    char pass[80];
    if (extract_basic_password(req, pass, sizeof(pass)) && portal_password_matches(pass)) {
        return ESP_OK;
    }
    send_unauthorized(req);
    return ESP_FAIL;
}

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

static esp_err_t auth_status_get(httpd_req_t *req)
{
    char json[160];
    snprintf(json, sizeof(json),
             "{\"locked\":%s,\"apMode\":%s,\"canResetWithoutPass\":%s}",
             portal_password_enabled() ? "true" : "false",
             wifi_mgr_ap_active() ? "true" : "false",
             wifi_mgr_ap_active() ? "true" : "false");
    return send_json(req, json);
}

static esp_err_t auth_check_get(httpd_req_t *req)
{
    if (portal_auth_guard(req) != ESP_OK) {
        return ESP_FAIL;
    }
    return send_json(req, "{\"ok\":true}");
}

static esp_err_t auth_set_post(httpd_req_t *req)
{
    /* Đặt mật khẩu lần đầu: không cần auth. Đổi mật khẩu: cần mật khẩu cũ. */
    char *body = read_body(req, 512);
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

    cJSON *pass = cJSON_GetObjectItemCaseSensitive(root, "password");
    cJSON *old = cJSON_GetObjectItemCaseSensitive(root, "oldPassword");
    const char *new_pass = cJSON_IsString(pass) ? pass->valuestring : NULL;
    const char *old_pass = cJSON_IsString(old) ? old->valuestring : "";

    if (portal_password_enabled()) {
        if (!portal_password_matches(old_pass)) {
            cJSON_Delete(root);
            send_unauthorized(req);
            return ESP_FAIL;
        }
    }

    esp_err_t err = portal_password_set(new_pass);
    cJSON_Delete(root);
    if (err != ESP_OK) {
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "mat khau phai 4-64 ky tu");
        return ESP_FAIL;
    }
    ESP_LOGW(TAG, "da dat mat khau portal");
    return send_json(req, "{\"ok\":true,\"locked\":true}");
}

static esp_err_t auth_clear_post(httpd_req_t *req)
{
    /* Quên mật khẩu: chỉ khi đang ở chế độ AP cấu hình. Còn lại cần mật khẩu hiện tại. */
    if (wifi_mgr_ap_active()) {
        portal_password_clear();
        ESP_LOGW(TAG, "da xoa mat khau portal (che do AP)");
        return send_json(req, "{\"ok\":true,\"locked\":false,\"reset\":true}");
    }

    if (portal_auth_guard(req) != ESP_OK) {
        return ESP_FAIL;
    }
    portal_password_clear();
    ESP_LOGW(TAG, "da xoa mat khau portal");
    return send_json(req, "{\"ok\":true,\"locked\":false}");
}

esp_err_t portal_auth_register(httpd_handle_t server)
{
    const httpd_uri_t routes[] = {
        {.uri = "/api/auth/status", .method = HTTP_GET, .handler = auth_status_get},
        {.uri = "/api/auth/check", .method = HTTP_GET, .handler = auth_check_get},
        {.uri = "/api/auth/set", .method = HTTP_POST, .handler = auth_set_post},
        {.uri = "/api/auth/clear", .method = HTTP_POST, .handler = auth_clear_post},
    };
    for (size_t i = 0; i < sizeof(routes) / sizeof(routes[0]); i++) {
        esp_err_t err = httpd_register_uri_handler(server, &routes[i]);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "khong dang ky duoc %s", routes[i].uri);
            return err;
        }
    }
    return ESP_OK;
}
