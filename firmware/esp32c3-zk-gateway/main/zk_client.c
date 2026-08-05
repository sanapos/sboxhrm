#include "zk_client.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "esp_log.h"
#include "esp_timer.h"

static const char *TAG = "zkcli";

static uint16_t le16(const uint8_t *p)
{
    return (uint16_t)(p[0] | (p[1] << 8));
}

static uint32_t le32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void put_le16(uint8_t *p, uint16_t v)
{
    p[0] = (uint8_t)(v & 0xFF);
    p[1] = (uint8_t)(v >> 8);
}

static void put_le32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v & 0xFF);
    p[1] = (uint8_t)((v >> 8) & 0xFF);
    p[2] = (uint8_t)((v >> 16) & 0xFF);
    p[3] = (uint8_t)((v >> 24) & 0xFF);
}

/* Sao chép trường cố định có thể không kết thúc bằng NUL. */
static void copy_fixed(char *dst, size_t dst_cap, const uint8_t *src, size_t src_len)
{
    size_t n = src_len < dst_cap - 1 ? src_len : dst_cap - 1;
    size_t i = 0;
    for (; i < n; i++) {
        if (src[i] == 0) {
            break;
        }
        dst[i] = (char)src[i];
    }
    dst[i] = '\0';
    /* bỏ khoảng trắng thừa ở cuối */
    while (i > 0 && (dst[i - 1] == ' ' || dst[i - 1] == '\t')) {
        dst[--i] = '\0';
    }
}

esp_err_t zk_get_option(zk_conn_t *c, const char *name, char *out, size_t cap)
{
    out[0] = '\0';

    char req[64];
    size_t len = strlcpy(req, name, sizeof(req));
    if (len >= sizeof(req)) {
        return ESP_ERR_INVALID_ARG;
    }

    esp_err_t err = zk_cmd(c, ZK_CMD_OPTIONS_RRQ, req, len + 1);
    if (err != ESP_OK) {
        return err;
    }
    if (c->resp_cmd != ZK_CMD_ACK_OK || c->reply_len == 0) {
        return ESP_ERR_NOT_FOUND;
    }

    c->reply[c->reply_len < ZK_REPLY_BUF_MAX ? c->reply_len : ZK_REPLY_BUF_MAX - 1] = '\0';
    char *raw = (char *)c->reply;
    char *eq = strchr(raw, '=');
    strlcpy(out, eq != NULL ? eq + 1 : raw, cap);

    /* cắt các ký tự điều khiển ở cuối */
    for (size_t i = 0; out[i] != '\0'; i++) {
        if ((unsigned char)out[i] < 0x20) {
            out[i] = '\0';
            break;
        }
    }
    return ESP_OK;
}

esp_err_t zk_get_serial(zk_conn_t *c, char *out, size_t cap)
{
    return zk_get_option(c, "~SerialNumber", out, cap);
}

esp_err_t zk_get_firmware(zk_conn_t *c, char *out, size_t cap)
{
    out[0] = '\0';
    esp_err_t err = zk_cmd(c, ZK_CMD_GET_VERSION, NULL, 0);
    if (err != ESP_OK || c->resp_cmd != ZK_CMD_ACK_OK) {
        return ESP_ERR_NOT_FOUND;
    }
    copy_fixed(out, cap, c->reply, c->reply_len);
    return ESP_OK;
}

esp_err_t zk_get_sizes(zk_conn_t *c, zk_sizes_t *out)
{
    memset(out, 0, sizeof(*out));

    esp_err_t err = zk_cmd(c, ZK_CMD_GET_FREE_SIZES, NULL, 0);
    if (err != ESP_OK || c->resp_cmd != ZK_CMD_ACK_OK) {
        return ESP_ERR_INVALID_RESPONSE;
    }
    if (c->reply_len < 80) {
        ESP_LOGE(TAG, "GET_FREE_SIZES tra ve %u byte, can >= 80", (unsigned)c->reply_len);
        return ESP_ERR_INVALID_RESPONSE;
    }

    out->users = le32(c->reply + 4 * 4);
    out->fingers = le32(c->reply + 6 * 4);
    out->records = le32(c->reply + 8 * 4);
    out->cards = le32(c->reply + 12 * 4);
    out->users_cap = le32(c->reply + 15 * 4);
    out->rec_cap = le32(c->reply + 16 * 4);

    ESP_LOGI(TAG, "may co %u nhan vien, %u van tay, %u ban ghi cham cong",
             (unsigned)out->users, (unsigned)out->fingers, (unsigned)out->records);
    return ESP_OK;
}

esp_err_t zk_set_enabled(zk_conn_t *c, bool enabled)
{
    if (enabled) {
        esp_err_t err = zk_cmd(c, ZK_CMD_ENABLEDEVICE, NULL, 0);
        return err != ESP_OK ? err : (zk_reply_ok(c) ? ESP_OK : ESP_FAIL);
    }
    uint8_t arg[4] = {0};
    esp_err_t err = zk_cmd(c, ZK_CMD_DISABLEDEVICE, arg, sizeof(arg));
    return err != ESP_OK ? err : (zk_reply_ok(c) ? ESP_OK : ESP_FAIL);
}

esp_err_t zk_refresh_data(zk_conn_t *c)
{
    esp_err_t err = zk_cmd(c, ZK_CMD_REFRESHDATA, NULL, 0);
    return err != ESP_OK ? err : (zk_reply_ok(c) ? ESP_OK : ESP_FAIL);
}

esp_err_t zk_set_time(zk_conn_t *c, const struct tm *tm_local)
{
    uint32_t enc = zk_encode_time(tm_local->tm_year + 1900, tm_local->tm_mon + 1, tm_local->tm_mday,
                                  tm_local->tm_hour, tm_local->tm_min, tm_local->tm_sec);
    uint8_t arg[4];
    put_le32(arg, enc);

    esp_err_t err = zk_cmd(c, ZK_CMD_SET_TIME, arg, sizeof(arg));
    return err != ESP_OK ? err : (zk_reply_ok(c) ? ESP_OK : ESP_FAIL);
}

esp_err_t zk_unlock(zk_conn_t *c, int seconds)
{
    if (seconds <= 0) {
        seconds = 3;
    }
    uint8_t arg[4];
    put_le32(arg, (uint32_t)seconds * 10u);

    esp_err_t err = zk_cmd(c, ZK_CMD_UNLOCK, arg, sizeof(arg));
    return err != ESP_OK ? err : (zk_reply_ok(c) ? ESP_OK : ESP_FAIL);
}

esp_err_t zk_clear_attlog(zk_conn_t *c)
{
    esp_err_t err = zk_cmd(c, ZK_CMD_CLEAR_ATTLOG, NULL, 0);
    return err != ESP_OK ? err : (zk_reply_ok(c) ? ESP_OK : ESP_FAIL);
}

esp_err_t zk_clear_all_data(zk_conn_t *c)
{
    esp_err_t err = zk_cmd(c, ZK_CMD_CLEAR_DATA, NULL, 0);
    return err != ESP_OK ? err : (zk_reply_ok(c) ? ESP_OK : ESP_FAIL);
}

esp_err_t zk_restart(zk_conn_t *c)
{
    esp_err_t err = zk_cmd(c, ZK_CMD_RESTART, NULL, 0);
    if (err != ESP_OK) {
        return err;
    }
    c->session_id = 0; /* máy khởi động lại, phiên không còn giá trị */
    return ESP_OK;
}

/* ------------------------------------------------------------------ */
/* Bộ ráp bản ghi từ luồng byte                                        */
/* ------------------------------------------------------------------ */

typedef esp_err_t (*rec_emit_fn)(void *ctx, const uint8_t *rec, size_t len);

typedef struct {
    uint8_t hdr[4];
    size_t hdr_seen;
    uint32_t total;
    uint32_t expect_count;
    size_t rec_size;
    uint8_t rec[80];
    size_t rec_seen;
    uint32_t emitted;
    rec_emit_fn emit;
    void *ctx;
    bool sizing_failed;
} rec_stream_t;

static esp_err_t rec_stream_sink(void *ctx, const uint8_t *data, size_t len)
{
    rec_stream_t *s = ctx;

    while (len > 0) {
        if (s->hdr_seen < 4) {
            size_t want = 4 - s->hdr_seen;
            if (want > len) {
                want = len;
            }
            memcpy(s->hdr + s->hdr_seen, data, want);
            s->hdr_seen += want;
            data += want;
            len -= want;

            if (s->hdr_seen == 4) {
                s->total = le32(s->hdr);
                if (s->expect_count == 0) {
                    s->sizing_failed = true;
                    return ESP_OK;
                }
                s->rec_size = s->total / s->expect_count;
                if (s->rec_size == 0 || s->rec_size > sizeof(s->rec)) {
                    ESP_LOGE(TAG, "co ban ghi bat thuong: %u byte (tong %u / %u ban ghi)",
                             (unsigned)s->rec_size, (unsigned)s->total, (unsigned)s->expect_count);
                    s->sizing_failed = true;
                    return ESP_ERR_INVALID_SIZE;
                }
            }
            continue;
        }

        if (s->sizing_failed) {
            return ESP_ERR_INVALID_SIZE;
        }

        size_t want = s->rec_size - s->rec_seen;
        if (want > len) {
            want = len;
        }
        memcpy(s->rec + s->rec_seen, data, want);
        s->rec_seen += want;
        data += want;
        len -= want;

        if (s->rec_seen == s->rec_size) {
            s->rec_seen = 0;
            s->emitted++;
            esp_err_t err = s->emit(s->ctx, s->rec, s->rec_size);
            if (err != ESP_OK) {
                return err;
            }
        }
    }
    return ESP_OK;
}

/* ------------------------------------------------------------------ */
/* Log chấm công                                                       */
/* ------------------------------------------------------------------ */

typedef struct {
    zk_att_cb_t cb;
    void *ctx;
} att_ctx_t;

static esp_err_t att_emit(void *ctx, const uint8_t *rec, size_t len)
{
    att_ctx_t *a = ctx;
    zk_att_rec_t out = {0};

    if (len >= 40) {
        out.uid = le16(rec);
        copy_fixed(out.user_id, sizeof(out.user_id), rec + 2, 24);
        out.verify = rec[26];
        out.enc_time = le32(rec + 27);
        out.state = rec[31];
    } else if (len >= 16) {
        snprintf(out.user_id, sizeof(out.user_id), "%u", (unsigned)le32(rec));
        out.enc_time = le32(rec + 4);
        out.verify = rec[8];
        out.state = rec[9];
    } else if (len >= 8) {
        out.uid = le16(rec);
        snprintf(out.user_id, sizeof(out.user_id), "%u", (unsigned)out.uid);
        out.verify = rec[2];
        out.enc_time = le32(rec + 3);
        out.state = rec[7];
    } else {
        return ESP_ERR_INVALID_SIZE;
    }

    if (out.user_id[0] == '\0' || out.enc_time == 0) {
        return ESP_OK; /* bản ghi rỗng, bỏ qua */
    }

    zk_decode_time(out.enc_time, &out.year, &out.mon, &out.day, &out.hour, &out.min, &out.sec);
    if (out.year < 2000 || out.year > 2099 || out.mon < 1 || out.mon > 12 || out.day < 1 || out.day > 31) {
        ESP_LOGW(TAG, "bo qua ban ghi co thoi gian la: %u", (unsigned)out.enc_time);
        return ESP_OK;
    }

    return a->cb(a->ctx, &out);
}

esp_err_t zk_read_attlog(zk_conn_t *c, zk_att_cb_t cb, void *ctx)
{
    zk_sizes_t sizes;
    esp_err_t err = zk_get_sizes(c, &sizes);
    if (err != ESP_OK) {
        return err;
    }
    if (sizes.records == 0) {
        ESP_LOGI(TAG, "may khong co ban ghi cham cong nao");
        return ESP_OK;
    }

    att_ctx_t actx = {.cb = cb, .ctx = ctx};
    rec_stream_t stream = {
        .expect_count = sizes.records,
        .emit = att_emit,
        .ctx = &actx,
    };

    err = zk_read_buffered(c, ZK_CMD_ATTLOG_RRQ, 0, rec_stream_sink, &stream, NULL);
    if (err != ESP_OK) {
        return err;
    }

    ESP_LOGI(TAG, "da doc %u/%u ban ghi cham cong (co ban ghi %u byte)",
             (unsigned)stream.emitted, (unsigned)sizes.records, (unsigned)stream.rec_size);
    return ESP_OK;
}

/* ------------------------------------------------------------------ */
/* Danh sách nhân viên                                                 */
/* ------------------------------------------------------------------ */

typedef struct {
    zk_user_cb_t cb;
    void *ctx;
} user_ctx_t;

static void parse_user(const uint8_t *rec, size_t len, zk_user_rec_t *out)
{
    memset(out, 0, sizeof(*out));

    if (len >= 72) {
        out->uid = le16(rec);
        out->privilege = rec[2];
        copy_fixed(out->password, sizeof(out->password), rec + 3, 8);
        copy_fixed(out->name, sizeof(out->name), rec + 11, 24);
        out->card = le32(rec + 35);
        char grp[8];
        copy_fixed(grp, sizeof(grp), rec + 40, 7);
        out->group_id = (uint8_t)atoi(grp);
        copy_fixed(out->user_id, sizeof(out->user_id), rec + 48, 24);
    } else {
        out->uid = le16(rec);
        out->privilege = rec[2];
        copy_fixed(out->password, sizeof(out->password), rec + 3, 5);
        copy_fixed(out->name, sizeof(out->name), rec + 8, 8);
        out->card = le32(rec + 16);
        out->group_id = rec[21];
        snprintf(out->user_id, sizeof(out->user_id), "%u", (unsigned)le32(rec + 24));
    }

    if (out->user_id[0] == '\0') {
        snprintf(out->user_id, sizeof(out->user_id), "%u", (unsigned)out->uid);
    }
    if (out->name[0] == '\0') {
        strlcpy(out->name, out->user_id, sizeof(out->name));
    }
}

static esp_err_t user_emit(void *ctx, const uint8_t *rec, size_t len)
{
    user_ctx_t *u = ctx;
    zk_user_rec_t out;
    parse_user(rec, len, &out);
    return u->cb(u->ctx, &out);
}

esp_err_t zk_read_users(zk_conn_t *c, zk_user_cb_t cb, void *ctx)
{
    zk_sizes_t sizes;
    esp_err_t err = zk_get_sizes(c, &sizes);
    if (err != ESP_OK) {
        return err;
    }
    if (sizes.users == 0) {
        ESP_LOGI(TAG, "may chua co nhan vien nao");
        return ESP_OK;
    }

    user_ctx_t uctx = {.cb = cb, .ctx = ctx};
    rec_stream_t stream = {
        .expect_count = sizes.users,
        .emit = user_emit,
        .ctx = &uctx,
    };

    err = zk_read_buffered(c, ZK_CMD_USERTEMP_RRQ, ZK_FCT_USER, rec_stream_sink, &stream, NULL);
    if (err != ESP_OK) {
        return err;
    }

    ESP_LOGI(TAG, "da doc %u/%u nhan vien (co ban ghi %u byte)",
             (unsigned)stream.emitted, (unsigned)sizes.users, (unsigned)stream.rec_size);
    return ESP_OK;
}

esp_err_t zk_probe_user_packet_size(zk_conn_t *c, size_t *out_size)
{
    *out_size = 72;

    zk_sizes_t sizes;
    if (zk_get_sizes(c, &sizes) != ESP_OK || sizes.users == 0) {
        return ESP_OK; /* không đoán được, giữ mặc định của dòng máy mới */
    }

    uint8_t req[11] = {0};
    req[0] = 1;
    put_le16(req + 1, ZK_CMD_USERTEMP_RRQ);
    put_le32(req + 3, ZK_FCT_USER);

    esp_err_t err = zk_cmd(c, ZK_CMD_DATA_WRRQ, req, sizeof(req));
    if (err != ESP_OK) {
        return err;
    }

    if (c->resp_cmd != ZK_CMD_DATA && c->reply_len >= 5) {
        uint32_t buffered = le32(c->reply + 1);
        if (buffered > 4) {
            size_t guess = (buffered - 4) / sizes.users;
            if (guess == 28 || guess == 72) {
                *out_size = guess;
            } else {
                ESP_LOGW(TAG, "co goi nhan vien la (%u byte), dung 72", (unsigned)guess);
            }
        }
    }

    zk_cmd(c, ZK_CMD_FREE_DATA, NULL, 0);
    ESP_LOGI(TAG, "co goi nhan vien cua may: %u byte", (unsigned)*out_size);
    return ESP_OK;
}

/* ------------------------------------------------------------------ */
/* Ghi / xoá nhân viên                                                 */
/* ------------------------------------------------------------------ */

typedef struct {
    const char *want_user_id;
    uint16_t found_uid;
    uint16_t max_uid;
    bool found;
} uid_lookup_t;

static esp_err_t uid_lookup_cb(void *ctx, const zk_user_rec_t *rec)
{
    uid_lookup_t *l = ctx;
    if (rec->uid > l->max_uid) {
        l->max_uid = rec->uid;
    }
    if (!l->found && strcmp(rec->user_id, l->want_user_id) == 0) {
        l->found_uid = rec->uid;
        l->found = true;
    }
    return ESP_OK;
}

static esp_err_t resolve_uid(zk_conn_t *c, const char *user_id, uint16_t *out_uid, bool *out_exists)
{
    uid_lookup_t lookup = {.want_user_id = user_id};
    esp_err_t err = zk_read_users(c, uid_lookup_cb, &lookup);
    if (err != ESP_OK) {
        return err;
    }

    *out_exists = lookup.found;
    *out_uid = lookup.found ? lookup.found_uid : (uint16_t)(lookup.max_uid + 1);
    if (*out_uid == 0) {
        *out_uid = 1;
    }
    return ESP_OK;
}

esp_err_t zk_write_user(zk_conn_t *c, const zk_user_rec_t *user)
{
    if (user->user_id[0] == '\0') {
        return ESP_ERR_INVALID_ARG;
    }

    uint16_t uid = user->uid;
    if (uid == 0) {
        bool exists = false;
        esp_err_t err = resolve_uid(c, user->user_id, &uid, &exists);
        if (err != ESP_OK) {
            return err;
        }
    }

    size_t packet_size = 72;
    esp_err_t err = zk_probe_user_packet_size(c, &packet_size);
    if (err != ESP_OK) {
        return err;
    }

    uint8_t buf[72] = {0};
    if (packet_size == 28) {
        put_le16(buf, uid);
        buf[2] = user->privilege;
        memcpy(buf + 3, user->password, strnlen(user->password, 5));
        memcpy(buf + 8, user->name, strnlen(user->name, 8));
        put_le32(buf + 16, user->card);
        buf[21] = user->group_id != 0 ? user->group_id : 1;
        put_le16(buf + 22, 0);
        put_le32(buf + 24, (uint32_t)strtoul(user->user_id, NULL, 10));
    } else {
        packet_size = 72;
        put_le16(buf, uid);
        buf[2] = user->privilege;
        memcpy(buf + 3, user->password, strnlen(user->password, 8));
        memcpy(buf + 11, user->name, strnlen(user->name, 24));
        put_le32(buf + 35, user->card);
        char grp[8];
        snprintf(grp, sizeof(grp), "%u", user->group_id != 0 ? user->group_id : 1);
        memcpy(buf + 40, grp, strnlen(grp, 7));
        memcpy(buf + 48, user->user_id, strnlen(user->user_id, 24));
    }

    err = zk_cmd(c, ZK_CMD_USER_WRQ, buf, packet_size);
    if (err != ESP_OK) {
        return err;
    }
    if (!zk_reply_ok(c)) {
        ESP_LOGE(TAG, "may tu choi ghi nhan vien %s (ma %u)", user->user_id, c->resp_cmd);
        return ESP_FAIL;
    }

    zk_refresh_data(c);
    ESP_LOGI(TAG, "da ghi nhan vien PIN=%s uid=%u ten=%s", user->user_id, uid, user->name);
    return ESP_OK;
}

esp_err_t zk_delete_user_by_pin(zk_conn_t *c, const char *user_id)
{
    uint16_t uid = 0;
    bool exists = false;
    esp_err_t err = resolve_uid(c, user_id, &uid, &exists);
    if (err != ESP_OK) {
        return err;
    }
    if (!exists) {
        ESP_LOGW(TAG, "khong tim thay nhan vien PIN=%s tren may", user_id);
        return ESP_ERR_NOT_FOUND;
    }

    uint8_t arg[2];
    put_le16(arg, uid);
    err = zk_cmd(c, ZK_CMD_DELETE_USER, arg, sizeof(arg));
    if (err != ESP_OK) {
        return err;
    }
    if (!zk_reply_ok(c)) {
        return ESP_FAIL;
    }

    zk_refresh_data(c);
    ESP_LOGI(TAG, "da xoa nhan vien PIN=%s uid=%u", user_id, uid);
    return ESP_OK;
}

/* ------------------------------------------------------------------ */
/* Vân tay                                                             */
/* ------------------------------------------------------------------ */

esp_err_t zk_cancel_capture(zk_conn_t *c)
{
    esp_err_t err = zk_cmd(c, ZK_CMD_CANCELCAPTURE, NULL, 0);
    return err != ESP_OK ? err : (zk_reply_ok(c) ? ESP_OK : ESP_FAIL);
}

/* Mỗi lần chờ một gói sự kiện. Ngắn hơn tổng thời gian chờ để khi máy đăng ký
 * xong và im lặng, gateway thoát ra sớm thay vì treo hết cửa sổ chờ. */
#define ENROLL_EVENT_SLICE_MS 8000

esp_err_t zk_enroll_finger(zk_conn_t *c, const char *user_id, int finger_index,
                           bool overwrite, int wait_ms)
{
    if (user_id == NULL || user_id[0] == '\0') {
        return ESP_ERR_INVALID_ARG;
    }
    if (finger_index < 0 || finger_index > 9) {
        finger_index = 0;
    }

    /* Dọn mẫu cũ của đúng ngón này để phép đếm bên dưới trở nên chính xác: ghi đè
     * mẫu cũ sẽ giữ nguyên tổng số mẫu và không còn cách nào biết kết quả. */
    if (overwrite) {
        zk_delete_finger(c, user_id, finger_index);
    }

    /* Số mẫu là thước đo duy nhất đáng tin. Mã trong gói sự kiện khác nhau theo
     * từng đời firmware, suy ra kết quả từ mã sẽ báo thành công sai. */
    zk_sizes_t before = {0};
    bool have_before = zk_get_sizes(c, &before) == ESP_OK;

    /* Người dùng phải bấm được trên máy, nên bàn phím bắt buộc đang mở. */
    zk_set_enabled(c, true);
    zk_cancel_capture(c);

    /* 24 byte user_id dạng chuỗi + số thứ tự ngón + cờ ghi đè, giống SDK gốc. */
    uint8_t arg[26] = {0};
    memcpy(arg, user_id, strnlen(user_id, 24));
    arg[24] = (uint8_t)finger_index;
    arg[25] = 1;

    esp_err_t err = zk_cmd(c, ZK_CMD_STARTENROLL, arg, sizeof(arg));
    if (err != ESP_OK) {
        return err;
    }
    if (!zk_reply_ok(c)) {
        ESP_LOGW(TAG, "may tu choi mo dang ky van tay (ma tra ve %u)", c->resp_cmd);
        return ESP_ERR_NOT_SUPPORTED;
    }

    ESP_LOGW(TAG, "da mo dang ky van tay tren may cho PIN=%s ngon=%d, cho toi %d giay",
             user_id, finger_index, wait_ms / 1000);

    /* Máy đòi quét vài lượt và gửi một gói sự kiện sau mỗi lượt. Mỗi gói phải
     * được ACK, nếu không máy dừng giữa đường. */
    zk_set_recv_timeout(c, ENROLL_EVENT_SLICE_MS);

    int64_t deadline = esp_timer_get_time() + (int64_t)wait_ms * 1000;
    int events = 0;
    int quiet_slices = 0;

    while (esp_timer_get_time() < deadline) {
        if (zk_recv(c, NULL, NULL) != ESP_OK) {
            /* Im lặng một lúc: có thể đã xong, hoặc chưa ai đặt ngón tay. Chỉ
             * bỏ cuộc sau vài lượt im để không cắt ngang người đang quét. */
            if (events > 0 && ++quiet_slices >= 2) {
                break;
            }
            continue;
        }
        zk_send_ack(c);
        quiet_slices = 0;
        events++;
        ESP_LOGI(TAG, "su kien dang ky %d: goi=%u", events, c->resp_cmd);
    }

    zk_set_recv_timeout(c, c->timeout_ms);

    /* Máy ngừng trả lời hẳn sau khi rời giao diện đăng ký: mọi lệnh gửi tiếp
     * trên phiên này đều hết thời gian chờ, kể cả phép đếm dùng để kết luận. Đó
     * là lý do một lượt quét thành công thật vẫn bị báo thất bại. Phải nối lại
     * trước khi đếm. */
    if (zk_reopen(c) != ESP_OK) {
        ESP_LOGE(TAG, "khong noi lai duoc may sau khi dang ky, khong the kiem chung ket qua");
        return ESP_FAIL;
    }

    zk_cancel_capture(c);
    zk_refresh_data(c);

    zk_sizes_t after = {0};
    bool have_after = zk_get_sizes(c, &after) == ESP_OK;

    if (have_before && have_after && after.fingers > before.fingers) {
        ESP_LOGW(TAG, "da dang ky xong van tay cho PIN=%s (so mau %u -> %u)",
                 user_id, (unsigned)before.fingers, (unsigned)after.fingers);
        return ESP_OK;
    }

    /* Không tăng số mẫu nghĩa là chưa lấy được nét vân tay nào, bất kể máy đã
     * gửi bao nhiêu gói sự kiện — các gói đó cũng phát ra khi quét lỗi. */
    ESP_LOGW(TAG, "khong co mau van tay moi cho PIN=%s (%d su kien, so mau %u)",
             user_id, events, (unsigned)after.fingers);
    return ESP_ERR_TIMEOUT;
}

/* Hai cách xoá mẫu vân tay tồn tại song song trong họ ZKTeco:
 *  - lệnh 134 nhận thẳng user_id dạng chuỗi (firmware mới),
 *  - lệnh 19 nhận uid dạng số (firmware cũ, ví dụ ZLM60 Ver 6.60).
 * Thử cách mới trước rồi lùi về cách cũ, vì không có cờ nào cho biết máy nào
 * hiểu lệnh nào. */
static bool try_delete_finger_once(zk_conn_t *c, const char *user_id, uint16_t uid, int finger)
{
    uint8_t str_arg[25] = {0};
    memcpy(str_arg, user_id, strnlen(user_id, 24));
    str_arg[24] = (uint8_t)finger;

    if (zk_cmd(c, ZK_CMD_DEL_FPTMP_STR, str_arg, sizeof(str_arg)) == ESP_OK && zk_reply_ok(c)) {
        return true;
    }

    uint8_t num_arg[3];
    put_le16(num_arg, uid);
    num_arg[2] = (uint8_t)finger;

    return zk_cmd(c, ZK_CMD_DELETE_USERTEMP, num_arg, sizeof(num_arg)) == ESP_OK && zk_reply_ok(c);
}

esp_err_t zk_delete_finger(zk_conn_t *c, const char *user_id, int finger_index)
{
    if (user_id == NULL || user_id[0] == '\0') {
        return ESP_ERR_INVALID_ARG;
    }

    uint16_t uid = 0;
    bool exists = false;
    esp_err_t err = resolve_uid(c, user_id, &uid, &exists);
    if (err != ESP_OK) {
        return err;
    }
    if (!exists) {
        ESP_LOGW(TAG, "khong tim thay nhan vien PIN=%s tren may", user_id);
        return ESP_ERR_NOT_FOUND;
    }

    zk_sizes_t before = {0};
    bool have_before = zk_get_sizes(c, &before) == ESP_OK;

    /* finger_index âm nghĩa là xoá hết: lặp qua toàn bộ 10 ngón. */
    int from = finger_index < 0 ? 0 : finger_index;
    int to = finger_index < 0 ? 9 : finger_index;

    for (int f = from; f <= to; f++) {
        try_delete_finger_once(c, user_id, uid, f);
    }

    zk_refresh_data(c);

    zk_sizes_t after = {0};
    bool have_after = zk_get_sizes(c, &after) == ESP_OK;

    /* Máy trả ACK OK cả khi ngón đó vốn không có mẫu, nên chỉ số mẫu giảm mới
     * chứng minh là đã xoá thật. */
    if (have_before && have_after && after.fingers < before.fingers) {
        ESP_LOGI(TAG, "da xoa mau van tay PIN=%s ngon=%d (so mau %u -> %u)",
                 user_id, finger_index, (unsigned)before.fingers, (unsigned)after.fingers);
        return ESP_OK;
    }

    ESP_LOGW(TAG, "khong co mau van tay nao bi xoa cho PIN=%s ngon=%d", user_id, finger_index);
    return ESP_ERR_NOT_FOUND;
}
