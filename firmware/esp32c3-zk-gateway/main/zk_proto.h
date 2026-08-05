#pragma once

/*
 * Khung truyền của giao thức ZKTeco standalone (cổng TCP 4370).
 *
 * Mỗi gói TCP:  [50 50 82 7d][uint32 le: do dai phan sau][payload]
 * payload:      [uint16 cmd][uint16 checksum][uint16 session_id][uint16 reply_id][data...]
 *
 * Checksum tính trên toàn bộ payload với truong checksum = 0.
 */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"

#define ZK_CMD_CONNECT        1000
#define ZK_CMD_EXIT           1001
#define ZK_CMD_ENABLEDEVICE   1002
#define ZK_CMD_DISABLEDEVICE  1003
#define ZK_CMD_RESTART        1004
#define ZK_CMD_POWEROFF       1005
#define ZK_CMD_REFRESHDATA    1013
#define ZK_CMD_REFRESHOPTION  1014
#define ZK_CMD_AUTH           1102
#define ZK_CMD_GET_VERSION    1100

#define ZK_CMD_PREPARE_DATA   1500
#define ZK_CMD_DATA           1501
#define ZK_CMD_FREE_DATA      1502
#define ZK_CMD_DATA_WRRQ      1503
#define ZK_CMD_READ_BUFFER    1504

#define ZK_CMD_ACK_OK         2000
#define ZK_CMD_ACK_ERROR      2001
#define ZK_CMD_ACK_DATA       2002
#define ZK_CMD_ACK_UNAUTH     2005

#define ZK_CMD_USER_WRQ       8
#define ZK_CMD_USERTEMP_RRQ   9
#define ZK_CMD_OPTIONS_RRQ    11
#define ZK_CMD_OPTIONS_WRQ    12
#define ZK_CMD_ATTLOG_RRQ     13
#define ZK_CMD_CLEAR_DATA     14
#define ZK_CMD_CLEAR_ATTLOG   15
#define ZK_CMD_DELETE_USER    18
#define ZK_CMD_DELETE_USERTEMP 19
#define ZK_CMD_CLEAR_ADMIN    20
#define ZK_CMD_UNLOCK         31
#define ZK_CMD_GET_FREE_SIZES 50
#define ZK_CMD_STARTVERIFY    60
#define ZK_CMD_STARTENROLL    61
#define ZK_CMD_CANCELCAPTURE  62
#define ZK_CMD_GET_TIME       201
#define ZK_CMD_SET_TIME       202

/* Xoá một mẫu vân tay theo user_id dạng chuỗi (bản TCP của DELETE_USERTEMP). */
#define ZK_CMD_DEL_FPTMP_STR  134

/* Máy chủ động gửi lên trong lúc đăng ký vân tay (không phải trả lời lệnh nào). */
#define ZK_CMD_REG_EVENT      500

#define ZK_FCT_USER           5

/* Payload trả về được giữ trong bộ đệm nội bộ; các lệnh điều khiển đều rất nhỏ. */
#define ZK_REPLY_BUF_MAX      2048

typedef struct {
    int sock;
    uint16_t session_id;
    uint16_t reply_id;
    uint32_t comm_key;
    int timeout_ms;                       /* thời gian chờ nhận mặc định của phiên */
    char ip[16];                          /* giữ lại để mở lại được phiên khi cần */
    uint16_t port;

    uint16_t resp_cmd;                    /* mã lệnh của gói trả lời gần nhất */
    uint8_t reply[ZK_REPLY_BUF_MAX];      /* phần data của gói trả lời gần nhất */
    size_t reply_len;
} zk_conn_t;

/* Nhận từng mảnh dữ liệu lớn mà không cần nạp hết vào RAM. */
typedef esp_err_t (*zk_sink_fn)(void *ctx, const uint8_t *data, size_t len);

esp_err_t zk_open(zk_conn_t *c, const char *ip, uint16_t port, uint32_t comm_key, int timeout_ms);
void zk_close(zk_conn_t *c);

/* Dựng lại phiên tới cùng máy. Máy ngừng trả lời sau vài thao tác (rõ nhất là
 * sau khi đóng giao diện đăng ký vân tay) và cách duy nhất để dùng tiếp là nối
 * lại từ đầu. */
esp_err_t zk_reopen(zk_conn_t *c);

/* Gửi một lệnh và đọc đúng một gói trả lời vào c->reply. */
esp_err_t zk_cmd(zk_conn_t *c, uint16_t cmd, const void *data, size_t len);

/* Như zk_cmd nhưng phần data của gói trả lời được đẩy dần sang sink. */
esp_err_t zk_cmd_stream(zk_conn_t *c, uint16_t cmd, const void *data, size_t len,
                        zk_sink_fn sink, void *ctx);

/* Đọc thêm một gói trả lời nữa (dùng cho chuỗi PREPARE_DATA -> DATA... -> ACK_OK). */
esp_err_t zk_recv(zk_conn_t *c, zk_sink_fn sink, void *ctx);

/* Gửi ACK_OK mà không chờ trả lời — máy đòi xác nhận từng gói sự kiện đăng ký. */
esp_err_t zk_send_ack(zk_conn_t *c);

/* Đổi thời gian chờ nhận của socket. Đăng ký vân tay phải chờ người dùng đặt
 * ngón tay nên cần lâu hơn nhiều so với các lệnh thường. */
void zk_set_recv_timeout(zk_conn_t *c, int timeout_ms);

bool zk_reply_ok(const zk_conn_t *c);

/* Đọc khối dữ liệu lớn (ATTLOG, USERINFO) theo kiểu chia mảnh, tiết kiệm RAM.
 * data_cmd: ZK_CMD_ATTLOG_RRQ hoặc ZK_CMD_USERTEMP_RRQ. */
esp_err_t zk_read_buffered(zk_conn_t *c, uint16_t data_cmd, uint32_t fct,
                           zk_sink_fn sink, void *ctx, uint32_t *out_size);

/* Chuyển đổi timestamp mã hoá của ZK. */
void zk_decode_time(uint32_t enc, int *year, int *mon, int *day, int *hour, int *min, int *sec);
uint32_t zk_encode_time(int year, int mon, int day, int hour, int min, int sec);
