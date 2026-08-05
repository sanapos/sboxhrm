#pragma once

/* Các thao tác mức cao với máy chấm công ZKTeco, dựng trên zk_proto. */

#include <stdbool.h>
#include <stdint.h>
#include <time.h>

#include "esp_err.h"
#include "zk_proto.h"

#define ZK_USERID_LEN 25
#define ZK_NAME_LEN   25

typedef struct {
    uint32_t users;
    uint32_t fingers;
    uint32_t records;
    uint32_t cards;
    uint32_t users_cap;
    uint32_t rec_cap;
} zk_sizes_t;

typedef struct {
    uint16_t uid;
    char user_id[ZK_USERID_LEN];
    uint32_t enc_time;
    int year, mon, day, hour, min, sec;
    uint8_t verify; /* 0=mat khau 1=van tay 2=the 15=khuon mat */
    uint8_t state;  /* 0=vao 1=ra 2..5=ra/vao giai lao, an com */
} zk_att_rec_t;

typedef struct {
    uint16_t uid;
    char user_id[ZK_USERID_LEN];
    char name[ZK_NAME_LEN];
    char password[16];
    uint32_t card;
    uint8_t privilege;
    uint8_t group_id;
} zk_user_rec_t;

typedef esp_err_t (*zk_att_cb_t)(void *ctx, const zk_att_rec_t *rec);
typedef esp_err_t (*zk_user_cb_t)(void *ctx, const zk_user_rec_t *rec);

esp_err_t zk_get_option(zk_conn_t *c, const char *name, char *out, size_t cap);
esp_err_t zk_get_serial(zk_conn_t *c, char *out, size_t cap);
esp_err_t zk_get_firmware(zk_conn_t *c, char *out, size_t cap);
esp_err_t zk_get_sizes(zk_conn_t *c, zk_sizes_t *out);

esp_err_t zk_set_enabled(zk_conn_t *c, bool enabled);
esp_err_t zk_refresh_data(zk_conn_t *c);
esp_err_t zk_set_time(zk_conn_t *c, const struct tm *tm_local);
esp_err_t zk_unlock(zk_conn_t *c, int seconds);
esp_err_t zk_clear_attlog(zk_conn_t *c);
esp_err_t zk_clear_all_data(zk_conn_t *c);
esp_err_t zk_restart(zk_conn_t *c);

/* Duyệt toàn bộ log chấm công trên máy, gọi cb theo từng bản ghi.
 * Chỉ giữ đúng một bản ghi trong RAM tại một thời điểm. */
esp_err_t zk_read_attlog(zk_conn_t *c, zk_att_cb_t cb, void *ctx);
esp_err_t zk_read_users(zk_conn_t *c, zk_user_cb_t cb, void *ctx);

/* Ghi/xoá nhân viên. uid = 0 nghĩa là tự chọn theo user_id sẵn có hoặc cấp mới. */
esp_err_t zk_write_user(zk_conn_t *c, const zk_user_rec_t *user);
esp_err_t zk_delete_user_by_pin(zk_conn_t *c, const char *user_id);

/* Cỡ gói nhân viên máy đang dùng (28 hoặc 72); cần biết trước khi ghi. */
esp_err_t zk_probe_user_packet_size(zk_conn_t *c, size_t *out_size);

/* Kết thúc mọi phiên lấy mẫu đang treo trên máy. */
esp_err_t zk_cancel_capture(zk_conn_t *c);

/* Mở đăng ký vân tay ngay trên máy: máy hiện "đặt ngón tay" và chờ người dùng.
 *
 * Hàm giữ kết nối trong tối đa wait_ms để người đứng tại máy quét xong, vì máy
 * huỷ phiên đăng ký nếu socket đóng giữa đường.
 *
 * overwrite = true thì mẫu cũ của đúng ngón đó bị xoá trước khi mở đăng ký.
 * Đánh đổi cần biết: nhờ vậy mới biết chắc kết quả (số mẫu phải tăng 1), nhưng
 * nếu người dùng quét không thành công thì ngón đó mất mẫu và phải đăng ký lại.
 * overwrite = false giữ nguyên mẫu cũ, đổi lại việc đăng ký lại một ngón đã có
 * sẽ báo ESP_ERR_TIMEOUT vì tổng số mẫu không đổi.
 *
 * Trả về:
 *  - ESP_OK              đăng ký xong, đã có mẫu mới
 *  - ESP_ERR_TIMEOUT     đã mở được nhưng không lấy được nét vân tay
 *  - ESP_ERR_NOT_SUPPORTED  máy từ chối lệnh (firmware không có chức năng này)
 */
esp_err_t zk_enroll_finger(zk_conn_t *c, const char *user_id, int finger_index,
                           bool overwrite, int wait_ms);

/* Xoá mẫu vân tay. finger_index < 0 nghĩa là xoá toàn bộ mẫu của nhân viên.
 * Trả ESP_ERR_NOT_FOUND khi trên máy vốn không có mẫu nào để xoá. */
esp_err_t zk_delete_finger(zk_conn_t *c, const char *user_id, int finger_index);
