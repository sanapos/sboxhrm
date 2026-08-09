#include "device_api.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cJSON.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "gateway.h"
#include "app_config.h"
#include "portal_auth.h"
#include "zk_client.h"

static const char *TAG = "devapi";

#define MAX_USERS_JSON  300
#define MAX_ATT_JSON    800

#define REQUIRE_AUTH(req) do { if (portal_auth_guard(req) != ESP_OK) return ESP_FAIL; } while (0)

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
/* Danh sách nhân viên                                                 */
/* ------------------------------------------------------------------ */

typedef struct {
    cJSON *arr;
    int count;
} users_json_t;

static esp_err_t users_collect(void *ctx, const zk_user_rec_t *rec)
{
    users_json_t *u = ctx;
    if (u->count >= MAX_USERS_JSON) {
        return ESP_OK;
    }
    cJSON *item = cJSON_CreateObject();
    if (item == NULL) {
        return ESP_ERR_NO_MEM;
    }
    cJSON_AddStringToObject(item, "pin", rec->user_id);
    cJSON_AddStringToObject(item, "name", rec->name);
    cJSON_AddNumberToObject(item, "privilege", rec->privilege);
    cJSON_AddNumberToObject(item, "card", rec->card);
    cJSON_AddItemToArray(u->arr, item);
    u->count++;
    return ESP_OK;
}

static esp_err_t users_read_fn(zk_conn_t *c, void *ctx)
{
    return zk_read_users(c, users_collect, ctx);
}

static esp_err_t device_users_get(httpd_req_t *req)
{
    REQUIRE_AUTH(req);
    users_json_t u = {.arr = cJSON_CreateArray(), .count = 0};
    if (u.arr == NULL) {
        return httpd_resp_send_500(req);
    }

    esp_err_t err = gateway_run_on_device(users_read_fn, &u);
    char *json = cJSON_PrintUnformatted(u.arr);
    cJSON_Delete(u.arr);

    if (json == NULL) {
        return httpd_resp_send_500(req);
    }

    if (err != ESP_OK) {
        free(json);
        httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "khong ket noi duoc may cham cong");
        return ESP_FAIL;
    }

    esp_err_t out = send_json(req, json);
    free(json);
    return out;
}

typedef struct {
    zk_user_rec_t user;
} user_save_ctx_t;

static esp_err_t user_save_fn(zk_conn_t *c, void *ctx)
{
    user_save_ctx_t *u = ctx;
    return zk_write_user(c, &u->user);
}

static esp_err_t device_users_post(httpd_req_t *req)
{
    REQUIRE_AUTH(req);
    char *body = read_body(req, 1024);
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

    cJSON *pin = cJSON_GetObjectItemCaseSensitive(root, "pin");
    if (!cJSON_IsString(pin) || pin->valuestring == NULL || pin->valuestring[0] == '\0') {
        cJSON_Delete(root);
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "thieu ma PIN");
        return ESP_FAIL;
    }

    user_save_ctx_t ctx = {0};
    strlcpy(ctx.user.user_id, pin->valuestring, sizeof(ctx.user.user_id));

    cJSON *name = cJSON_GetObjectItemCaseSensitive(root, "name");
    if (cJSON_IsString(name) && name->valuestring != NULL) {
        strlcpy(ctx.user.name, name->valuestring, sizeof(ctx.user.name));
    } else {
        strlcpy(ctx.user.name, ctx.user.user_id, sizeof(ctx.user.name));
    }

    cJSON *priv = cJSON_GetObjectItemCaseSensitive(root, "privilege");
    if (cJSON_IsNumber(priv)) {
        ctx.user.privilege = (uint8_t)priv->valueint;
    }

    cJSON *card = cJSON_GetObjectItemCaseSensitive(root, "card");
    if (cJSON_IsNumber(card)) {
        ctx.user.card = (uint32_t)card->valuedouble;
    }

    cJSON_Delete(root);

    esp_err_t err = gateway_run_on_device(user_save_fn, &ctx);
    if (err != ESP_OK) {
        httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "khong ket noi duoc may cham cong");
        return ESP_FAIL;
    }

    return send_json(req, "{\"ok\":true}");
}

typedef struct {
    char pin[ZK_USERID_LEN];
} user_del_ctx_t;

static esp_err_t user_del_fn(zk_conn_t *c, void *ctx)
{
    user_del_ctx_t *u = ctx;
    return zk_delete_user_by_pin(c, u->pin);
}

static esp_err_t device_users_delete(httpd_req_t *req)
{
    REQUIRE_AUTH(req);
    char query[64] = {0};
    char pin[ZK_USERID_LEN] = {0};
    if (httpd_req_get_url_query_str(req, query, sizeof(query)) != ESP_OK ||
        httpd_query_key_value(query, "pin", pin, sizeof(pin)) != ESP_OK || pin[0] == '\0') {
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "thieu tham so pin");
        return ESP_FAIL;
    }

    user_del_ctx_t ctx;
    strlcpy(ctx.pin, pin, sizeof(ctx.pin));

    esp_err_t err = gateway_run_on_device(user_del_fn, &ctx);
    if (err != ESP_OK) {
        httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "khong ket noi duoc may cham cong");
        return ESP_FAIL;
    }

    return send_json(req, "{\"ok\":true}");
}

/* ------------------------------------------------------------------ */
/* Chấm công — JSON xem nhanh, CSV tải về                             */
/* ------------------------------------------------------------------ */

typedef struct {
    cJSON *arr;
    int count;
} att_json_t;

static const char *verify_text(uint8_t v)
{
    switch (v) {
    case 0:  return "Mật khẩu";
    case 1:  return "Vân tay";
    case 2:  return "Thẻ";
    case 15: return "Khuôn mặt";
    default: return "Khác";
    }
}

static const char *state_text(uint8_t s)
{
    return s == 0 ? "Vào" : (s == 1 ? "Ra" : "Khác");
}

static esp_err_t att_collect(void *ctx, const zk_att_rec_t *rec)
{
    att_json_t *a = ctx;
    if (a->count >= MAX_ATT_JSON) {
        return ESP_OK;
    }
    cJSON *item = cJSON_CreateObject();
    if (item == NULL) {
        return ESP_ERR_NO_MEM;
    }
    char time[24];
    snprintf(time, sizeof(time), "%04d-%02d-%02d %02d:%02d:%02d",
             rec->year, rec->mon, rec->day, rec->hour, rec->min, rec->sec);
    cJSON_AddStringToObject(item, "pin", rec->user_id);
    cJSON_AddStringToObject(item, "time", time);
    cJSON_AddStringToObject(item, "verify", verify_text(rec->verify));
    cJSON_AddStringToObject(item, "state", state_text(rec->state));
    cJSON_AddItemToArray(a->arr, item);
    a->count++;
    return ESP_OK;
}

static esp_err_t att_read_fn(zk_conn_t *c, void *ctx)
{
    return zk_read_attlog(c, att_collect, ctx);
}

static esp_err_t device_attlog_get(httpd_req_t *req)
{
    REQUIRE_AUTH(req);
    att_json_t a = {.arr = cJSON_CreateArray(), .count = 0};
    if (a.arr == NULL) {
        return httpd_resp_send_500(req);
    }

    esp_err_t err = gateway_run_on_device(att_read_fn, &a);
    cJSON *root = cJSON_CreateObject();
    if (root == NULL) {
        cJSON_Delete(a.arr);
        return httpd_resp_send_500(req);
    }
    cJSON_AddItemToObject(root, "items", a.arr);
    cJSON_AddNumberToObject(root, "count", a.count);
    cJSON_AddBoolToObject(root, "truncated", a.count >= MAX_ATT_JSON);

    char *json = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);

    if (json == NULL || err != ESP_OK) {
        free(json);
        httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "khong doc duoc du lieu cham cong");
        return ESP_FAIL;
    }

    esp_err_t out = send_json(req, json);
    free(json);
    return out;
}

typedef struct {
    char pin[ZK_USERID_LEN];
    char name[ZK_NAME_LEN];
} csv_name_ent_t;

typedef struct {
    csv_name_ent_t *items;
    int count;
    int cap;
} csv_name_map_t;

typedef struct {
    httpd_req_t *req;
    bool failed;
    int stt;
    csv_name_map_t names;
} att_csv_t;

static const char *weekday_vn(int year, int mon, int day)
{
    /* Sakamoto — 0=CN … 6=T7 */
    static const char *const names[] = {"CN", "T2", "T3", "T4", "T5", "T6", "T7"};
    static const int t[] = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4};
    int y = year;
    if (mon < 3) {
        y -= 1;
    }
    int w = (y + y / 4 - y / 100 + y / 400 + t[mon - 1] + day) % 7;
    if (w < 0) {
        w += 7;
    }
    return names[w];
}

static const char *csv_lookup_name(const csv_name_map_t *map, const char *pin)
{
    if (map == NULL || pin == NULL) {
        return "";
    }
    for (int i = 0; i < map->count; i++) {
        if (strcmp(map->items[i].pin, pin) == 0) {
            return map->items[i].name;
        }
    }
    return "";
}

static esp_err_t csv_name_collect(void *ctx, const zk_user_rec_t *rec)
{
    csv_name_map_t *m = ctx;
    if (m->count >= m->cap) {
        return ESP_OK;
    }
    csv_name_ent_t *e = &m->items[m->count++];
    strlcpy(e->pin, rec->user_id, sizeof(e->pin));
    strlcpy(e->name, rec->name, sizeof(e->name));
    return ESP_OK;
}

/* Escape CSV field: quote when có dấu phẩy / quote / xuống dòng. */
static int csv_write_field(char *dst, size_t cap, const char *raw)
{
    if (raw == NULL) {
        raw = "";
    }
    bool need_quote = false;
    for (const char *p = raw; *p; p++) {
        if (*p == ',' || *p == '"' || *p == '\r' || *p == '\n') {
            need_quote = true;
            break;
        }
    }
    if (!need_quote) {
        return snprintf(dst, cap, "%s", raw);
    }
    size_t o = 0;
    if (o + 1 >= cap) {
        return -1;
    }
    dst[o++] = '"';
    for (const char *p = raw; *p && o + 2 < cap; p++) {
        if (*p == '"') {
            dst[o++] = '"';
            if (o + 1 >= cap) {
                break;
            }
        }
        dst[o++] = *p;
    }
    if (o + 1 >= cap) {
        return -1;
    }
    dst[o++] = '"';
    dst[o] = '\0';
    return (int)o;
}

static esp_err_t att_csv_line(void *ctx, const zk_att_rec_t *rec)
{
    att_csv_t *u = ctx;
    u->stt++;

    char name_field[80];
    char pin_field[64];
    char verify_field[48];
    const char *name = csv_lookup_name(&u->names, rec->user_id);
    if (csv_write_field(pin_field, sizeof(pin_field), rec->user_id) < 0 ||
        csv_write_field(name_field, sizeof(name_field), name) < 0 ||
        csv_write_field(verify_field, sizeof(verify_field), verify_text(rec->verify)) < 0) {
        return ESP_OK;
    }

    char line[320];
    int n = snprintf(line, sizeof(line),
                     "%d,%s,%s,%s,%02d/%02d/%04d,%02d:%02d:%02d,%s,%s\r\n",
                     u->stt,
                     pin_field,
                     name_field,
                     weekday_vn(rec->year, rec->mon, rec->day),
                     rec->day, rec->mon, rec->year,
                     rec->hour, rec->min, rec->sec,
                     state_text(rec->state),
                     verify_field);
    if (n <= 0) {
        return ESP_OK;
    }
    if (httpd_resp_send_chunk(u->req, line, (size_t)n) != ESP_OK) {
        u->failed = true;
        return ESP_FAIL;
    }
    return ESP_OK;
}

static esp_err_t att_csv_fn(zk_conn_t *c, void *ctx)
{
    att_csv_t *u = ctx;
    /* Nạp tên NV trước — CSV cần cột Tên nhân viên. */
    (void)zk_read_users(c, csv_name_collect, &u->names);
    return zk_read_attlog(c, att_csv_line, ctx);
}

static esp_err_t device_attlog_csv_get(httpd_req_t *req)
{
    REQUIRE_AUTH(req);
    httpd_resp_set_type(req, "text/csv; charset=utf-8");
    httpd_resp_set_hdr(req, "Content-Disposition",
                       "attachment; filename=\"cham-cong.csv\"");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");

    static const char bom[] = "\xEF\xBB\xBF";
    /* Cột: STT, Pin, Tên nhân viên, Thứ, Ngày, Giờ, Kiểu chấm, Loại xác thực */
    static const char header[] =
        "STT,Pin,Tên nhân viên,Thứ,Ngày,Giờ,Kiểu chấm,Loại xác thực\r\n";
    if (httpd_resp_send_chunk(req, bom, 3) != ESP_OK ||
        httpd_resp_send_chunk(req, header, sizeof(header) - 1) != ESP_OK) {
        httpd_resp_send_chunk(req, NULL, 0);
        return ESP_FAIL;
    }

    att_csv_t ctx = {0};
    ctx.req = req;
    ctx.names.cap = MAX_USERS_JSON;
    ctx.names.items = calloc((size_t)ctx.names.cap, sizeof(csv_name_ent_t));
    if (ctx.names.items == NULL) {
        httpd_resp_send_chunk(req, NULL, 0);
        return httpd_resp_send_500(req);
    }

    esp_err_t err = gateway_run_on_device(att_csv_fn, &ctx);
    free(ctx.names.items);
    httpd_resp_send_chunk(req, NULL, 0);

    if (err != ESP_OK || ctx.failed) {
        return ESP_FAIL;
    }
    return ESP_OK;
}

/* ------------------------------------------------------------------ */
/* Đăng ký vân tay — chạy nền, trang web hỏi trạng thái               */
/* ------------------------------------------------------------------ */

typedef struct {
    char pin[ZK_USERID_LEN];
    int fid;
    bool overwrite;
} enroll_args_t;

static volatile bool s_enroll_running;
static volatile int s_enroll_result;
static char s_enroll_msg[96];
static uint32_t s_fingers_before;
static uint32_t s_fingers_after;

static esp_err_t enroll_run_fn(zk_conn_t *c, void *ctx)
{
    enroll_args_t *a = ctx;

    zk_sizes_t before = {0};
    if (zk_get_sizes(c, &before) == ESP_OK) {
        s_fingers_before = before.fingers;
    }

    esp_err_t err = zk_enroll_finger(c, a->pin, a->fid, a->overwrite, 45000);

    zk_sizes_t after = {0};
    if (zk_get_sizes(c, &after) == ESP_OK) {
        s_fingers_after = after.fingers;
    }

    if (err == ESP_OK) {
        s_enroll_result = 1;
        snprintf(s_enroll_msg, sizeof(s_enroll_msg), "Da dang ky van tay (mau %u -> %u)",
                 (unsigned)s_fingers_before, (unsigned)s_fingers_after);
    } else if (err == ESP_ERR_TIMEOUT) {
        s_enroll_result = -2;
        snprintf(s_enroll_msg, sizeof(s_enroll_msg),
                 "Het thoi gian cho quet (mau van tay van %u)", (unsigned)s_fingers_after);
    } else {
        s_enroll_result = -1;
        snprintf(s_enroll_msg, sizeof(s_enroll_msg), "Dang ky that bai");
    }
    return err;
}

static void enroll_task(void *arg)
{
    enroll_args_t *a = arg;
    gateway_run_on_device(enroll_run_fn, a);
    free(a);
    s_enroll_running = false;
    vTaskDelete(NULL);
}

static esp_err_t device_enroll_post(httpd_req_t *req)
{
    REQUIRE_AUTH(req);
    if (s_enroll_running) {
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "dang co phien dang ky van tay");
        return ESP_FAIL;
    }

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

    enroll_args_t *args = calloc(1, sizeof(*args));
    if (args == NULL) {
        cJSON_Delete(root);
        return httpd_resp_send_500(req);
    }

    cJSON *pin = cJSON_GetObjectItemCaseSensitive(root, "pin");
    if (!cJSON_IsString(pin) || pin->valuestring == NULL || pin->valuestring[0] == '\0') {
        cJSON_Delete(root);
        free(args);
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "thieu ma PIN");
        return ESP_FAIL;
    }
    strlcpy(args->pin, pin->valuestring, sizeof(args->pin));

    cJSON *fid = cJSON_GetObjectItemCaseSensitive(root, "fid");
    args->fid = cJSON_IsNumber(fid) ? fid->valueint : 0;

    cJSON *ow = cJSON_GetObjectItemCaseSensitive(root, "overwrite");
    args->overwrite = cJSON_IsBool(ow) ? cJSON_IsTrue(ow) : true;

    cJSON_Delete(root);

    s_enroll_running = true;
    s_enroll_result = 0;
    s_enroll_msg[0] = '\0';
    s_fingers_before = 0;
    s_fingers_after = 0;

    if (xTaskCreate(enroll_task, "enroll", 8192, args, 4, NULL) != pdPASS) {
        s_enroll_running = false;
        free(args);
        return httpd_resp_send_500(req);
    }

    return send_json(req, "{\"ok\":true,\"running\":true}");
}

static esp_err_t device_enroll_get(httpd_req_t *req)
{
    REQUIRE_AUTH(req);
    char json[320];
    snprintf(json, sizeof(json),
             "{\"running\":%s,\"result\":%d,\"message\":\"%s\","
             "\"fingersBefore\":%u,\"fingersAfter\":%u}",
             s_enroll_running ? "true" : "false", s_enroll_result, s_enroll_msg,
             (unsigned)s_fingers_before, (unsigned)s_fingers_after);
    return send_json(req, json);
}

typedef struct {
    char pin[ZK_USERID_LEN];
    int fid;
} finger_del_ctx_t;

static esp_err_t finger_del_fn(zk_conn_t *c, void *ctx)
{
    finger_del_ctx_t *d = ctx;
    esp_err_t err = zk_delete_finger(c, d->pin, d->fid);
    return (err == ESP_ERR_NOT_FOUND) ? ESP_OK : err;
}

static esp_err_t device_finger_delete(httpd_req_t *req)
{
    REQUIRE_AUTH(req);
    char query[64] = {0};
    char pin[ZK_USERID_LEN] = {0};
    char fid_buf[8] = {0};
    if (httpd_req_get_url_query_str(req, query, sizeof(query)) != ESP_OK ||
        httpd_query_key_value(query, "pin", pin, sizeof(pin)) != ESP_OK || pin[0] == '\0') {
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "thieu tham so pin");
        return ESP_FAIL;
    }
    httpd_query_key_value(query, "fid", fid_buf, sizeof(fid_buf));

    finger_del_ctx_t ctx;
    strlcpy(ctx.pin, pin, sizeof(ctx.pin));
    ctx.fid = fid_buf[0] != '\0' ? atoi(fid_buf) : -1;

    esp_err_t err = gateway_run_on_device(finger_del_fn, &ctx);
    if (err != ESP_OK) {
        httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "khong xoa duoc mau van tay");
        return ESP_FAIL;
    }
    return send_json(req, "{\"ok\":true}");
}

/* ------------------------------------------------------------------ */
/* Lệnh điều khiển máy: mở cửa, reset, v.v.                          */
/* ------------------------------------------------------------------ */

typedef struct {
    char action_buf[32];
    const char *action;
    int seconds;
    char message[96];
} control_ctx_t;

static esp_err_t control_fn(zk_conn_t *c, void *ctx)
{
    control_ctx_t *ctl = ctx;

    if (strcmp(ctl->action, "unlock") == 0) {
        esp_err_t err = zk_unlock(c, ctl->seconds > 0 ? ctl->seconds : 5);
        if (err == ESP_OK) {
            snprintf(ctl->message, sizeof(ctl->message), "Da mo cua %d giay",
                     ctl->seconds > 0 ? ctl->seconds : 5);
        }
        return err;
    }
    if (strcmp(ctl->action, "refresh") == 0) {
        esp_err_t err = zk_refresh_data(c);
        if (err == ESP_OK) {
            strlcpy(ctl->message, "Da lam moi du lieu tren may", sizeof(ctl->message));
        }
        return err;
    }
    if (strcmp(ctl->action, "restart") == 0) {
        esp_err_t err = zk_restart(c);
        if (err == ESP_OK) {
            strlcpy(ctl->message, "May cham cong dang khoi dong lai", sizeof(ctl->message));
        }
        return err;
    }
    if (strcmp(ctl->action, "clear_attlog") == 0) {
        esp_err_t err = zk_clear_attlog(c);
        if (err == ESP_OK) {
            strlcpy(ctl->message, "Da xoa log cham cong tren may", sizeof(ctl->message));
            gateway_clear_device_identity();
            gateway_request_identify();
        }
        return err;
    }
    if (strcmp(ctl->action, "factory_reset") == 0) {
        esp_err_t err = zk_clear_all_data(c);
        if (err == ESP_OK) {
            strlcpy(ctl->message, "Da khoi phuc cai dat goc may cham cong", sizeof(ctl->message));
            gateway_clear_device_identity();
            gateway_request_identify();
            app_config_reset_mark();
            gateway_request_full_resync();
        }
        return err;
    }

    return ESP_ERR_INVALID_ARG;
}

static esp_err_t device_control_post(httpd_req_t *req)
{
    REQUIRE_AUTH(req);
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

    cJSON *action = cJSON_GetObjectItemCaseSensitive(root, "action");
    if (!cJSON_IsString(action) || action->valuestring == NULL || action->valuestring[0] == '\0') {
        cJSON_Delete(root);
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "thieu tham so action");
        return ESP_FAIL;
    }

    control_ctx_t ctx = {0};
    strlcpy(ctx.action_buf, action->valuestring, sizeof(ctx.action_buf));
    ctx.action = ctx.action_buf;

    cJSON *sec = cJSON_GetObjectItemCaseSensitive(root, "seconds");
    if (cJSON_IsNumber(sec)) {
        ctx.seconds = sec->valueint;
    }

    cJSON_Delete(root);

    esp_err_t err = gateway_run_on_device(control_fn, &ctx);
    if (err == ESP_ERR_INVALID_ARG) {
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "lenh khong hop le");
        return ESP_FAIL;
    }
    if (err != ESP_OK) {
        httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "may cham cong khong phan hoi");
        return ESP_FAIL;
    }

    char json[160];
    snprintf(json, sizeof(json), "{\"ok\":true,\"message\":\"%s\"}", ctx.message[0] ? ctx.message : "OK");
    return send_json(req, json);
}

esp_err_t device_api_register(httpd_handle_t server)
{
    const httpd_uri_t routes[] = {
        {.uri = "/api/device/users", .method = HTTP_GET, .handler = device_users_get},
        {.uri = "/api/device/users", .method = HTTP_POST, .handler = device_users_post},
        {.uri = "/api/device/users", .method = HTTP_DELETE, .handler = device_users_delete},
        {.uri = "/api/device/attlog", .method = HTTP_GET, .handler = device_attlog_get},
        {.uri = "/api/device/attlog.csv", .method = HTTP_GET, .handler = device_attlog_csv_get},
        {.uri = "/api/device/enroll", .method = HTTP_GET, .handler = device_enroll_get},
        {.uri = "/api/device/enroll", .method = HTTP_POST, .handler = device_enroll_post},
        {.uri = "/api/device/finger", .method = HTTP_DELETE, .handler = device_finger_delete},
        {.uri = "/api/device/control", .method = HTTP_POST, .handler = device_control_post},
    };

    for (size_t i = 0; i < sizeof(routes) / sizeof(routes[0]); i++) {
        esp_err_t err = httpd_register_uri_handler(server, &routes[i]);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "khong dang ky duoc %s", routes[i].uri);
            return err;
        }
    }
    ESP_LOGI(TAG, "da dang ky API dieu khien may cham cong");
    return ESP_OK;
}
