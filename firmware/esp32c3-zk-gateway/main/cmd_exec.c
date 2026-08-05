#include "cmd_exec.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#include "esp_log.h"
#include "gateway.h"
#include "zk_client.h"

static const char *TAG = "cmd";

/* Mã lỗi báo về server: dùng khoảng âm giống PUSH SDK. */
#define RET_OK             0
#define RET_UNSUPPORTED   -1
#define RET_DEVICE_ERROR  -2
#define RET_BAD_ARGUMENT  -3
#define RET_TIMEOUT       -4

/* Thời gian giữ giao diện đăng ký vân tay mở trên máy để người dùng quét.
 * Cả vòng poll của gateway dừng trong lúc này, nên đừng đặt quá dài. */
#define ENROLL_WAIT_MS    45000

static bool starts_with(const char *s, const char *prefix)
{
    return strncasecmp(s, prefix, strlen(prefix)) == 0;
}

bool cmd_field(const char *text, const char *key, char *out, size_t cap)
{
    out[0] = '\0';
    size_t key_len = strlen(key);
    const char *p = text;

    while ((p = strstr(p, key)) != NULL) {
        bool at_boundary = (p == text) || p[-1] == '\t' || p[-1] == ' ';
        if (at_boundary && p[key_len] == '=') {
            const char *v = p + key_len + 1;
            size_t n = 0;
            while (v[n] != '\0' && v[n] != '\t' && v[n] != '\r' && v[n] != '\n' && n + 1 < cap) {
                n++;
            }
            memcpy(out, v, n);
            out[n] = '\0';
            return true;
        }
        p += key_len;
    }
    return false;
}

bool cmd_parse_line(const char *line, size_t line_len, adms_cmd_t *out)
{
    memset(out, 0, sizeof(*out));

    if (line_len < 5 || line[0] != 'C' || line[1] != ':') {
        return false;
    }

    const char *id_start = line + 2;
    const char *colon = memchr(id_start, ':', line_len - 2);
    if (colon == NULL) {
        return false;
    }

    size_t id_len = (size_t)(colon - id_start);
    if (id_len == 0 || id_len >= ADMS_CMD_ID_LEN) {
        return false;
    }
    memcpy(out->id, id_start, id_len);
    out->id[id_len] = '\0';

    const char *text = colon + 1;
    size_t text_len = line_len - (size_t)(text - line);
    while (text_len > 0 && (text[text_len - 1] == '\r' || text[text_len - 1] == '\n')) {
        text_len--;
    }
    if (text_len >= ADMS_CMD_TEXT_LEN) {
        text_len = ADMS_CMD_TEXT_LEN - 1;
    }
    memcpy(out->text, text, text_len);
    out->text[text_len] = '\0';

    return out->text[0] != '\0';
}

static void first_word(const char *text, char *out, size_t cap)
{
    size_t n = 0;
    while (text[n] != '\0' && !isspace((unsigned char)text[n]) && n + 1 < cap) {
        n++;
    }
    memcpy(out, text, n);
    out[n] = '\0';
}

static int exec_update_userinfo(zk_conn_t *c, const char *text)
{
    zk_user_rec_t user = {0};
    char buf[64];

    if (!cmd_field(text, "PIN", user.user_id, sizeof(user.user_id))) {
        ESP_LOGE(TAG, "lenh them nhan vien thieu PIN");
        return RET_BAD_ARGUMENT;
    }
    if (cmd_field(text, "Name", buf, sizeof(buf))) {
        strlcpy(user.name, buf, sizeof(user.name));
    }
    if (cmd_field(text, "Passwd", buf, sizeof(buf))) {
        strlcpy(user.password, buf, sizeof(user.password));
    }
    if (cmd_field(text, "Card", buf, sizeof(buf))) {
        user.card = (uint32_t)strtoul(buf, NULL, 10);
    }
    if (cmd_field(text, "Pri", buf, sizeof(buf))) {
        user.privilege = (uint8_t)atoi(buf);
    }
    if (cmd_field(text, "Grp", buf, sizeof(buf))) {
        user.group_id = (uint8_t)atoi(buf);
    }

    return zk_write_user(c, &user) == ESP_OK ? RET_OK : RET_DEVICE_ERROR;
}

static int exec_delete_userinfo(zk_conn_t *c, const char *text)
{
    char pin[ZK_USERID_LEN];
    if (!cmd_field(text, "PIN", pin, sizeof(pin))) {
        /* Không có PIN nghĩa là xoá toàn bộ nhân viên. */
        return zk_clear_all_data(c) == ESP_OK ? RET_OK : RET_DEVICE_ERROR;
    }

    esp_err_t err = zk_delete_user_by_pin(c, pin);
    if (err == ESP_ERR_NOT_FOUND) {
        return RET_OK; /* đã không còn trên máy, coi như xong */
    }
    return err == ESP_OK ? RET_OK : RET_DEVICE_ERROR;
}

/* "ENROLL_FP PIN=123<tab>FID=0<tab>RETRY=3<tab>OVERWRITE=1" */
static int exec_enroll_fp(zk_conn_t *c, const char *text)
{
    char pin[ZK_USERID_LEN];
    if (!cmd_field(text, "PIN", pin, sizeof(pin))) {
        ESP_LOGE(TAG, "lenh dang ky van tay thieu PIN");
        return RET_BAD_ARGUMENT;
    }

    char buf[16];
    int fid = cmd_field(text, "FID", buf, sizeof(buf)) ? atoi(buf) : 0;

    /* Máy chủ gửi OVERWRITE=1 khi người dùng chủ ý thay mẫu cũ của ngón đó. */
    bool overwrite = cmd_field(text, "OVERWRITE", buf, sizeof(buf)) && atoi(buf) != 0;

    esp_err_t err = zk_enroll_finger(c, pin, fid, overwrite, ENROLL_WAIT_MS);
    if (err == ESP_ERR_NOT_SUPPORTED) {
        return RET_UNSUPPORTED;
    }
    if (err == ESP_ERR_TIMEOUT) {
        /* Đã mở được giao diện trên máy nhưng không ai quét — không phải lỗi
         * thiết bị, nên báo mã riêng để người dùng biết cần thử lại. */
        ESP_LOGW(TAG, "khong ai quet van tay trong thoi gian cho");
        return RET_TIMEOUT;
    }
    return err == ESP_OK ? RET_OK : RET_DEVICE_ERROR;
}

/* "DATA DELETE FINGERTMP PIN=123<tab>FID=0" — FID trống nghĩa là xoá hết. */
static int exec_delete_fingertmp(zk_conn_t *c, const char *text)
{
    char pin[ZK_USERID_LEN];
    if (!cmd_field(text, "PIN", pin, sizeof(pin))) {
        return RET_BAD_ARGUMENT;
    }

    char buf[16];
    int fid = cmd_field(text, "FID", buf, sizeof(buf)) ? atoi(buf) : -1;

    esp_err_t err = zk_delete_finger(c, pin, fid);
    if (err == ESP_ERR_NOT_FOUND) {
        /* Trên máy vốn không có mẫu đó — kết quả mong muốn đã đạt, coi là xong. */
        return RET_OK;
    }
    if (err == ESP_ERR_NOT_SUPPORTED) {
        return RET_UNSUPPORTED;
    }
    return err == ESP_OK ? RET_OK : RET_DEVICE_ERROR;
}

/* "CONTROL DEVICE 01<door>01<duration>" — hai ký tự cuối là thời gian mở, hex. */
static int exec_control_device(zk_conn_t *c, const char *text)
{
    const char *hex = strrchr(text, ' ');
    if (hex == NULL || strlen(hex + 1) < 8) {
        return RET_BAD_ARGUMENT;
    }
    hex++;

    char dur_hex[3] = {hex[6], hex[7], '\0'};
    int duration = (int)strtol(dur_hex, NULL, 16);

    if (duration == 0) {
        /* Lệnh đóng cửa: máy standalone tự đóng sau thời gian mở, không có lệnh riêng. */
        ESP_LOGI(TAG, "bo qua lenh dong cua (may tu dong dong)");
        return RET_OK;
    }
    return zk_unlock(c, duration) == ESP_OK ? RET_OK : RET_DEVICE_ERROR;
}

int cmd_exec_run(zk_conn_t *c, const adms_cmd_t *cmd, char *cmd_name, size_t cmd_name_cap)
{
    const char *t = cmd->text;
    first_word(t, cmd_name, cmd_name_cap);

    ESP_LOGI(TAG, "thuc thi lenh %s: %s", cmd->id, t);

    if (starts_with(t, "DATA UPDATE USERINFO")) {
        return exec_update_userinfo(c, t);
    }
    if (starts_with(t, "DATA DELETE USERINFO")) {
        return exec_delete_userinfo(c, t);
    }
    if (starts_with(t, "DATA QUERY USERINFO")) {
        return gateway_upload_users(c) == ESP_OK ? RET_OK : RET_DEVICE_ERROR;
    }
    if (starts_with(t, "DATA QUERY ATTLOG")) {
        return gateway_upload_attendance(c, true) == ESP_OK ? RET_OK : RET_DEVICE_ERROR;
    }
    if (starts_with(t, "AC_UNLOCK")) {
        return zk_unlock(c, 5) == ESP_OK ? RET_OK : RET_DEVICE_ERROR;
    }
    if (starts_with(t, "CONTROL DEVICE")) {
        return exec_control_device(c, t);
    }
    if (starts_with(t, "CLEAR LOG")) {
        return zk_clear_attlog(c) == ESP_OK ? RET_OK : RET_DEVICE_ERROR;
    }
    if (starts_with(t, "CLEAR ALL USERINFO") || starts_with(t, "CLEAR DATA")) {
        return zk_clear_all_data(c) == ESP_OK ? RET_OK : RET_DEVICE_ERROR;
    }
    if (starts_with(t, "REBOOT")) {
        return zk_restart(c) == ESP_OK ? RET_OK : RET_DEVICE_ERROR;
    }
    if (starts_with(t, "INFO") || starts_with(t, "CHECK")) {
        /* Thông tin máy đã được đẩy lên trong mỗi vòng poll. */
        return RET_OK;
    }
    if (starts_with(t, "SET OPTION") || starts_with(t, "SET TIME")) {
        gateway_request_clock_sync();
        return RET_OK;
    }

    if (starts_with(t, "ENROLL_FP")) {
        return exec_enroll_fp(c, t);
    }
    if (starts_with(t, "DATA DELETE FINGERTMP")) {
        return exec_delete_fingertmp(c, t);
    }

    /* Khuôn mặt và tải mẫu vân tay lên server cần firmware PUSH của ZKTeco;
     * máy standalone chỉ cho mở đăng ký tại chỗ, không xuất được mẫu ra ngoài. */
    if (starts_with(t, "ENROLL_BIO") || starts_with(t, "DATA QUERY FINGERTMP") ||
        starts_with(t, "DATA DELETE FACE")) {
        ESP_LOGW(TAG, "may standalone khong ho tro lenh nay: %s", t);
        return RET_UNSUPPORTED;
    }

    ESP_LOGW(TAG, "lenh chua ho tro: %s", t);
    return RET_UNSUPPORTED;
}
