#include "gateway.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "adms_client.h"
#include "app_config.h"
#include "cmd_exec.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "wifi_mgr.h"
#include "zk_client.h"

static const char *TAG = "gw";

/* Mỗi lô ATTLOG khoảng 6 KB (~90 bản ghi) — đủ lớn để ít lượt HTTP,
 * vẫn thừa RAM cho phiên TLS trên ESP32-C3. */
#define BATCH_CAP        6144
#define BATCH_FLUSH_AT   (BATCH_CAP - 160)
#define SERVER_RESP_CAP  4096
#define REGISTER_EVERY_MS (30 * 60 * 1000)
#define ZK_TIMEOUT_MS    8000

static gw_status_t s_status;
static SemaphoreHandle_t s_lock;
static SemaphoreHandle_t s_device_lock;

static volatile bool s_req_full;
static volatile bool s_req_users;
static volatile bool s_req_clock;
static volatile bool s_req_identify;

static uint32_t s_last_seen_records = UINT32_MAX; /* ép quét ngay lần đầu */
static attlog_mark_t s_mark;
static char *s_batch;
static char s_att_stamp[24] = "9999";

/* ------------------------------------------------------------------ */
/* Trạng thái                                                          */
/* ------------------------------------------------------------------ */

static void status_lock(void)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
}

static void status_unlock(void)
{
    xSemaphoreGive(s_lock);
}

static void status_error(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    status_lock();
    vsnprintf(s_status.last_error, sizeof(s_status.last_error), fmt, ap);
    status_unlock();
    va_end(ap);
    ESP_LOGE(TAG, "%s", s_status.last_error);
}

static void status_clear_error(void)
{
    status_lock();
    s_status.last_error[0] = '\0';
    status_unlock();
}

void gateway_status_snapshot(gw_status_t *out)
{
    status_lock();
    *out = s_status;
    status_unlock();
}

void gateway_request_full_resync(void)
{
    ESP_LOGW(TAG, "yeu cau dong bo lai toan bo log cham cong");
    s_req_full = true;
}

void gateway_request_user_sync(void)
{
    s_req_users = true;
}

void gateway_request_clock_sync(void)
{
    s_req_clock = true;
}

void gateway_request_identify(void)
{
    s_req_identify = true;
}

void gateway_clear_device_identity(void)
{
    status_lock();
    s_status.serial[0] = '\0';
    s_status.firmware[0] = '\0';
    s_status.platform[0] = '\0';
    s_status.dev_users = 0;
    s_status.dev_fingers = 0;
    s_status.dev_records = 0;
    status_unlock();
}

/* ------------------------------------------------------------------ */
/* Phiên làm việc với máy chấm công                                    */
/* ------------------------------------------------------------------ */

static esp_err_t zk_session_open(zk_conn_t *c)
{
    const app_config_t *cfg = app_config_get();
    esp_err_t err = zk_open(c, cfg->device_ip, cfg->device_port, cfg->comm_key, ZK_TIMEOUT_MS);

    status_lock();
    s_status.device_online = (err == ESP_OK);
    status_unlock();

    if (err != ESP_OK) {
        status_error("khong ket noi duoc may cham cong %s:%u", cfg->device_ip, cfg->device_port);
    }
    return err;
}

static void zk_session_close(zk_conn_t *c)
{
    /* session_id = 0 nghĩa là máy vừa nhận lệnh khởi động lại — đừng gửi thêm gì. */
    if (c->session_id != 0) {
        zk_set_enabled(c, true);
    }
    zk_close(c);
}

static bool device_session_begin(zk_conn_t *c, TickType_t wait)
{
    if (s_device_lock == NULL || xSemaphoreTake(s_device_lock, wait) != pdTRUE) {
        return false;
    }
    if (zk_session_open(c) != ESP_OK) {
        xSemaphoreGive(s_device_lock);
        return false;
    }
    return true;
}

static void device_session_end(zk_conn_t *c)
{
    zk_session_close(c);
    xSemaphoreGive(s_device_lock);
}

esp_err_t gateway_run_on_device(gateway_device_fn fn, void *ctx)
{
    if (fn == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    zk_conn_t c;
    if (!device_session_begin(&c, pdMS_TO_TICKS(90000))) {
        return ESP_ERR_TIMEOUT;
    }

    esp_err_t err = fn(&c, ctx);
    device_session_end(&c);
    return err;
}

/* ------------------------------------------------------------------ */
/* Nhận diện máy                                                       */
/* ------------------------------------------------------------------ */

static void sanitize_for_query(char *s)
{
    for (; *s != '\0'; s++) {
        if (*s == ',' || *s == '&' || *s == '#' || *s == '+' || *s == '%') {
            *s = '-';
        } else if (*s == ' ') {
            *s = '_';
        }
    }
}

static esp_err_t identify_device(void)
{
    zk_conn_t c;
    if (!device_session_begin(&c, pdMS_TO_TICKS(8000))) {
        return ESP_FAIL;
    }

    char serial[CFG_STR_LEN] = {0};
    char firmware[64] = {0};
    char platform[48] = {0};
    zk_sizes_t sizes = {0};

    zk_get_serial(&c, serial, sizeof(serial));
    zk_get_firmware(&c, firmware, sizeof(firmware));
    zk_get_option(&c, "~Platform", platform, sizeof(platform));
    zk_get_sizes(&c, &sizes);

    device_session_end(&c);

    if (serial[0] == '\0') {
        status_error("khong doc duoc so seri cua may cham cong");
        return ESP_FAIL;
    }

    app_config_save_serial(serial);

    status_lock();
    strlcpy(s_status.serial, serial, sizeof(s_status.serial));
    strlcpy(s_status.firmware, firmware, sizeof(s_status.firmware));
    strlcpy(s_status.platform, platform, sizeof(s_status.platform));
    s_status.dev_users = sizes.users;
    s_status.dev_fingers = sizes.fingers;
    s_status.dev_records = sizes.records;
    status_unlock();

    ESP_LOGI(TAG, "may cham cong: SN=%s firmware=%s nen=%s", serial, firmware, platform);
    return ESP_OK;
}

/* ------------------------------------------------------------------ */
/* Đẩy log chấm công lên server                                        */
/* ------------------------------------------------------------------ */

typedef struct {
    const char *sn;
    size_t len;
    uint32_t sent;
    uint32_t skipped;

    uint32_t cur_time;       /* thời điểm của bản ghi đang xét */
    uint32_t cur_time_count; /* số bản ghi mang đúng thời điểm đó, tính cả bản đã bỏ qua */

    uint32_t mark_time;
    uint32_t mark_count;
    uint32_t seen_at_mark;

    uint32_t min_time;       /* mốc chặn lấy log cũ, 0 = không chặn */
    bool full;
} att_upload_t;

static esp_err_t flush_batch(att_upload_t *u)
{
    if (u->len == 0) {
        return ESP_OK;
    }
    s_batch[u->len] = '\0';

    esp_err_t err = adms_post_attlog(u->sn, s_batch, s_att_stamp);
    if (err != ESP_OK) {
        status_error("gui lo cham cong that bai: %s", esp_err_to_name(err));
        return err;
    }

    u->len = 0;
    return ESP_OK;
}

static esp_err_t att_record_cb(void *ctx, const zk_att_rec_t *rec)
{
    att_upload_t *u = ctx;

    if (rec->enc_time == u->cur_time) {
        u->cur_time_count++;
    } else {
        u->cur_time = rec->enc_time;
        u->cur_time_count = 1;
    }

    bool skip = false;
    if (u->min_time != 0 && rec->enc_time < u->min_time) {
        skip = true;
    } else if (!u->full) {
        if (rec->enc_time < u->mark_time) {
            skip = true;
        } else if (rec->enc_time == u->mark_time && u->seen_at_mark < u->mark_count) {
            u->seen_at_mark++;
            skip = true;
        }
    }

    if (skip) {
        u->skipped++;
        return ESP_OK;
    }

    int n = snprintf(s_batch + u->len, BATCH_CAP - u->len,
                     "%s\t%04d-%02d-%02d %02d:%02d:%02d\t%u\t%u\t0\t0\t0\n",
                     rec->user_id, rec->year, rec->mon, rec->day, rec->hour, rec->min, rec->sec,
                     (unsigned)rec->state, (unsigned)rec->verify);
    if (n <= 0 || (size_t)n >= BATCH_CAP - u->len) {
        return ESP_ERR_NO_MEM;
    }
    u->len += (size_t)n;
    u->sent++;

    if (u->len >= BATCH_FLUSH_AT) {
        return flush_batch(u);
    }
    return ESP_OK;
}

/* Chỉ lấy log trong N ngày gần nhất ở lần đồng bộ đầu tiên. */
static uint32_t compute_min_time(void)
{
    const app_config_t *cfg = app_config_get();
    if (cfg->backfill_days == 0) {
        return 0;
    }

    time_t now = time(NULL);
    if (now < 1700000000) {
        return 0; /* chưa có giờ chuẩn, không dám cắt */
    }

    time_t cutoff = now + (time_t)cfg->tz_offset_h * 3600 - (time_t)cfg->backfill_days * 86400;
    struct tm tm_cut;
    gmtime_r(&cutoff, &tm_cut);

    return zk_encode_time(tm_cut.tm_year + 1900, tm_cut.tm_mon + 1, tm_cut.tm_mday, 0, 0, 0);
}

esp_err_t gateway_upload_attendance(zk_conn_t *c, bool full_resync)
{
    const char *sn = app_config_effective_serial();
    if (sn[0] == '\0') {
        return ESP_ERR_INVALID_STATE;
    }

    att_upload_t u = {
        .sn = sn,
        .mark_time = s_mark.last_zk_time,
        .mark_count = s_mark.last_count,
        .full = full_resync,
        .min_time = full_resync ? 0 : compute_min_time(),
    };

    /* Tạm khoá bàn phím máy trong lúc kéo dữ liệu lớn, theo khuyến nghị của SDK. */
    zk_set_enabled(c, false);
    esp_err_t err = zk_read_attlog(c, att_record_cb, &u);
    zk_set_enabled(c, true);

    if (err != ESP_OK) {
        status_error("doc log cham cong that bai: %s", esp_err_to_name(err));
        return err;
    }

    err = flush_batch(&u);
    if (err != ESP_OK) {
        return err;
    }

    /* Chỉ dịch mốc nước cao khi toàn bộ các lô đã lên server thành công. */
    if (u.cur_time != 0) {
        s_mark.last_zk_time = u.cur_time;
        s_mark.last_count = u.cur_time_count;
        app_config_save_mark(&s_mark);
    }

    if (full_resync) {
        /* Thân rỗng là dấu hiệu kết thúc phiên đồng bộ của giao thức PUSH. */
        adms_post_attlog(sn, "", s_att_stamp);
    }

    status_lock();
    s_status.uploaded_last = u.sent;
    s_status.uploaded_total += u.sent;
    s_status.last_upload_ms = esp_timer_get_time() / 1000;
    status_unlock();

    if (u.sent > 0) {
        ESP_LOGW(TAG, "da day %u ban ghi cham cong len server (bo qua %u ban da gui truoc)",
                 (unsigned)u.sent, (unsigned)u.skipped);
    } else {
        ESP_LOGI(TAG, "khong co ban ghi moi (%u ban ghi cu)", (unsigned)u.skipped);
    }
    return ESP_OK;
}

/* ------------------------------------------------------------------ */
/* Đẩy danh sách nhân viên lên server                                  */
/* ------------------------------------------------------------------ */

typedef struct {
    const char *sn;
    size_t len;
    uint32_t sent;
} user_upload_t;

static esp_err_t flush_users(user_upload_t *u)
{
    if (u->len == 0) {
        return ESP_OK;
    }
    s_batch[u->len] = '\0';

    esp_err_t err = adms_post_operlog(u->sn, s_batch);
    if (err != ESP_OK) {
        status_error("gui danh sach nhan vien that bai: %s", esp_err_to_name(err));
        return err;
    }
    u->len = 0;
    return ESP_OK;
}

static esp_err_t user_record_cb(void *ctx, const zk_user_rec_t *rec)
{
    user_upload_t *u = ctx;

    int n = snprintf(s_batch + u->len, BATCH_CAP - u->len,
                     "USER PIN=%s\tName=%s\tPri=%u\tPasswd=%s\tCard=%u\tGrp=%u\tTZ=0000\tVerify=0\n",
                     rec->user_id, rec->name, (unsigned)rec->privilege, rec->password,
                     (unsigned)rec->card, (unsigned)rec->group_id);
    if (n <= 0 || (size_t)n >= BATCH_CAP - u->len) {
        return ESP_ERR_NO_MEM;
    }
    u->len += (size_t)n;
    u->sent++;

    if (u->len >= BATCH_FLUSH_AT) {
        return flush_users(u);
    }
    return ESP_OK;
}

esp_err_t gateway_upload_users(zk_conn_t *c)
{
    const char *sn = app_config_effective_serial();
    if (sn[0] == '\0') {
        return ESP_ERR_INVALID_STATE;
    }

    user_upload_t u = {.sn = sn};

    zk_set_enabled(c, false);
    esp_err_t err = zk_read_users(c, user_record_cb, &u);
    zk_set_enabled(c, true);

    if (err != ESP_OK) {
        status_error("doc danh sach nhan vien that bai: %s", esp_err_to_name(err));
        return err;
    }

    err = flush_users(&u);
    if (err != ESP_OK) {
        return err;
    }

    adms_post_operlog(sn, ""); /* kết thúc phiên đồng bộ nhân viên */
    ESP_LOGW(TAG, "da day %u nhan vien len server", (unsigned)u.sent);
    return ESP_OK;
}

/* ------------------------------------------------------------------ */
/* Xử lý phản hồi của server                                           */
/* ------------------------------------------------------------------ */

static void apply_server_options(const char *block)
{
    char val[32];

    if (adms_parse_option(block, "ATTLOGStamp", val, sizeof(val))) {
        if (strcmp(val, "0") == 0) {
            ESP_LOGW(TAG, "server dat ATTLOGStamp=0 - yeu cau gui lai toan bo cham cong");
            s_req_full = true;
        } else if (val[0] != '\0') {
            strlcpy(s_att_stamp, val, sizeof(s_att_stamp));
        }
    }

    if (adms_parse_option(block, "OPERLOGStamp", val, sizeof(val)) && strcmp(val, "0") == 0) {
        ESP_LOGW(TAG, "server dat OPERLOGStamp=0 - yeu cau gui lai danh sach nhan vien");
        s_req_users = true;
    }
}

/* Chạy tất cả các dòng "C:<id>:<lenh>" trong phản hồi, dùng chung một phiên ZK. */
static void run_commands(const char *resp)
{
    if (strstr(resp, "C:") == NULL) {
        return;
    }

    zk_conn_t c;
    bool opened = false;

    const char *p = resp;
    while (*p != '\0') {
        const char *nl = strchr(p, '\n');
        size_t line_len = nl != NULL ? (size_t)(nl - p) : strlen(p);

        adms_cmd_t cmd;
        if (line_len > 0 && cmd_parse_line(p, line_len, &cmd)) {
            if (!opened) {
                if (!device_session_begin(&c, pdMS_TO_TICKS(15000))) {
                    adms_ack_command(app_config_effective_serial(), cmd.id, -2, "DEVICE_OFFLINE");
                    return;
                }
                opened = true;
            }

            char cmd_name[32];
            int ret = cmd_exec_run(&c, &cmd, cmd_name, sizeof(cmd_name));
            adms_ack_command(app_config_effective_serial(), cmd.id, ret, cmd_name);

            status_lock();
            s_status.commands_done++;
            status_unlock();

            /* REBOOT làm mất phiên; dừng lô lệnh còn lại. */
            if (c.session_id == 0) {
                break;
            }
        }

        if (nl == NULL) {
            break;
        }
        p = nl + 1;
    }

    if (opened) {
        device_session_end(&c);
    }
}

static void handle_server_response(const char *resp)
{
    if (resp == NULL || resp[0] == '\0') {
        return;
    }
    if (strncmp(resp, "OK", 2) == 0 && strlen(resp) <= 4) {
        return;
    }
    if (strncmp(resp, "FAIL", 4) == 0) {
        ESP_LOGW(TAG, "server tra ve FAIL - may co the chua duoc gan vao cua hang");
        return;
    }

    apply_server_options(resp);
    run_commands(resp);
}

/* ------------------------------------------------------------------ */
/* Các chu kỳ                                                          */
/* ------------------------------------------------------------------ */

static void build_info_string(char *out, size_t cap)
{
    const app_config_t *cfg = app_config_get();

    gw_status_t st;
    gateway_status_snapshot(&st);

    char fw[64];
    strlcpy(fw, st.firmware[0] != '\0' ? st.firmware : "ZK-Gateway", sizeof(fw));
    sanitize_for_query(fw);

    snprintf(out, cap, "%s,%u,%u,%u,%s,,,,ESP32C3_ADMS_Gateway",
             fw, (unsigned)st.dev_users, (unsigned)st.dev_fingers, (unsigned)st.dev_records,
             cfg->device_ip);
}

static void do_register(const char *sn)
{
    char *resp = malloc(SERVER_RESP_CAP);
    if (resp == NULL) {
        return;
    }

    adms_result_t res;
    esp_err_t err = adms_get_options(sn, resp, SERVER_RESP_CAP, &res);

    status_lock();
    s_status.server_online = (err == ESP_OK);
    status_unlock();

    if (err != ESP_OK) {
        status_error("khong lien lac duoc server ADMS: %s", esp_err_to_name(err));
        free(resp);
        return;
    }

    status_clear_error();
    handle_server_response(resp);
    free(resp);

    gw_status_t st;
    gateway_status_snapshot(&st);

    char body[384];
    snprintf(body, sizeof(body),
             "~DeviceName=%s,~SerialNumber=%s,FirmwareVersion=%s,~UserCount=%u,~FPCount=%u,"
             "~AttCount=%u,IPAddress=%s,~Platform=%s,~OEMVendor=ZKTeco,PushVersion=2.4.1,LockCount=1",
             st.platform[0] != '\0' ? st.platform : "ZKTeco", sn,
             st.firmware[0] != '\0' ? st.firmware : "ZK-Gateway",
             (unsigned)st.dev_users, (unsigned)st.dev_fingers, (unsigned)st.dev_records,
             app_config_get()->device_ip,
             st.platform[0] != '\0' ? st.platform : "Standalone");

    adms_post_options(sn, body);
}

static void do_poll(const char *sn)
{
    char info[192];
    build_info_string(info, sizeof(info));

    char *resp = malloc(SERVER_RESP_CAP);
    if (resp == NULL) {
        return;
    }

    adms_result_t res;
    esp_err_t err = adms_get_request(sn, info, resp, SERVER_RESP_CAP, &res);

    status_lock();
    s_status.server_online = (err == ESP_OK);
    s_status.last_cycle_ms = esp_timer_get_time() / 1000;
    status_unlock();

    if (err == ESP_OK) {
        status_clear_error();
        handle_server_response(resp);
    } else {
        status_error("poll that bai: %s", esp_err_to_name(err));
    }

    free(resp);
}

static void do_attendance_cycle(void)
{
    bool full = s_req_full;

    /* Lần đồng bộ đầu tiên cần giờ chuẩn để tính mốc chặn log cũ; nếu đẩy sớm
     * hơn NTP thì cả nhiều năm lịch sử sẽ tràn lên server. */
    if (!full && s_mark.last_zk_time == 0 && app_config_get()->backfill_days > 0 &&
        time(NULL) < 1700000000) {
        ESP_LOGI(TAG, "cho dong bo gio NTP truoc khi day log lan dau");
        return;
    }

    zk_conn_t c;
    if (!device_session_begin(&c, 0)) {
        return;
    }

    zk_sizes_t sizes;
    if (zk_get_sizes(&c, &sizes) == ESP_OK) {
        status_lock();
        s_status.dev_users = sizes.users;
        s_status.dev_fingers = sizes.fingers;
        s_status.dev_records = sizes.records;
        status_unlock();

        /* Không có bản ghi mới thì bỏ qua — tránh kéo cả log mỗi vòng. */
        if (!full && sizes.records == s_last_seen_records) {
            device_session_end(&c);
            return;
        }
    }

    if (gateway_upload_attendance(&c, full) == ESP_OK) {
        s_last_seen_records = sizes.records;
        if (full) {
            s_req_full = false;
        }
    }

    device_session_end(&c);
}

static void do_user_cycle(void)
{
    zk_conn_t c;
    if (!device_session_begin(&c, 0)) {
        return;
    }
    if (gateway_upload_users(&c) == ESP_OK) {
        s_req_users = false;
    }
    device_session_end(&c);
}

static void do_clock_sync(void)
{
    const app_config_t *cfg = app_config_get();
    if (!cfg->sync_device_clock) {
        s_req_clock = false;
        return;
    }

    time_t now = time(NULL);
    if (now < 1700000000) {
        return; /* chờ NTP */
    }

    time_t local = now + (time_t)cfg->tz_offset_h * 3600;
    struct tm tm_local;
    gmtime_r(&local, &tm_local);

    zk_conn_t c;
    if (!device_session_begin(&c, 0)) {
        return;
    }
    if (zk_set_time(&c, &tm_local) == ESP_OK) {
        ESP_LOGI(TAG, "da chinh gio may cham cong theo NTP: %04d-%02d-%02d %02d:%02d:%02d",
                 tm_local.tm_year + 1900, tm_local.tm_mon + 1, tm_local.tm_mday,
                 tm_local.tm_hour, tm_local.tm_min, tm_local.tm_sec);
        s_req_clock = false;
    }
    device_session_end(&c);
}

/* ------------------------------------------------------------------ */
/* Vòng lặp chính                                                      */
/* ------------------------------------------------------------------ */

static void gateway_task(void *arg)
{
    (void)arg;

    s_batch = malloc(BATCH_CAP);
    if (s_batch == NULL) {
        ESP_LOGE(TAG, "khong du RAM cho bo dem gui du lieu");
        vTaskDelete(NULL);
        return;
    }

    app_config_load_mark(&s_mark);
    ESP_LOGI(TAG, "moc dong bo da luu: time=%u count=%u",
             (unsigned)s_mark.last_zk_time, (unsigned)s_mark.last_count);

    int64_t last_poll = 0;
    int64_t last_scan = 0;
    int64_t last_register = 0;
    int64_t last_identify = 0;
    int64_t last_clock = 0;
    bool identified_this_boot = false;

    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(500));

        if (!wifi_mgr_is_connected() || !app_config_is_provisioned()) {
            continue;
        }

        const app_config_t *cfg = app_config_get();
        int64_t now = esp_timer_get_time() / 1000;

        /* Chạy nhận diện khi chưa biết SN, sau khi đổi máy chấm công, và thêm một
         * lần mỗi lần khởi động: firmware/nền tảng không lưu NVS nên phải đọc lại. */
        if (s_req_identify || app_config_effective_serial()[0] == '\0' || !identified_this_boot) {
            if (now - last_identify < 15000 && last_identify != 0 && !s_req_identify) {
                continue;
            }
            last_identify = now;
            if (identify_device() != ESP_OK) {
                continue;
            }
            identified_this_boot = true;
            s_req_identify = false;
            last_register = 0; /* đăng ký lại ngay khi vừa biết SN */
            s_last_seen_records = 0;
        }

        const char *sn = app_config_effective_serial();

        if (last_register == 0 || now - last_register >= REGISTER_EVERY_MS) {
            last_register = now;
            do_register(sn);
        }

        if (now - last_poll >= (int64_t)cfg->poll_interval_s * 1000) {
            last_poll = now;
            do_poll(sn);
        }

        if (s_req_full || now - last_scan >= (int64_t)cfg->attlog_interval_s * 1000) {
            last_scan = now;
            do_attendance_cycle();
        }

        if (s_req_users) {
            do_user_cycle();
        }

        /* Đồng hồ máy chấm công trôi vài giây mỗi ngày — chỉnh lại mỗi 12 tiếng. */
        if (s_req_clock || last_clock == 0 || now - last_clock >= 12 * 3600 * 1000) {
            last_clock = now;
            do_clock_sync();
        }
    }
}

void gateway_start(void)
{
    s_lock = xSemaphoreCreateMutex();
    s_device_lock = xSemaphoreCreateMutex();
    strlcpy(s_status.serial, app_config_effective_serial(), sizeof(s_status.serial));
    xTaskCreate(gateway_task, "gateway", 8192, NULL, 5, NULL);
}
