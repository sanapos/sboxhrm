#pragma once

#include <stdbool.h>
#include <stddef.h>

#include "zk_proto.h"

#define ADMS_CMD_ID_LEN 32

typedef struct {
    char id[ADMS_CMD_ID_LEN]; /* phần <id> trong "C:<id>:<lenh>" */
    const char *text;         /* lệnh, NUL-terminated; TMP có thể dài hàng KB */
} adms_cmd_t;

/* Tách một dòng "C:<id>:<lenh>" đã kết thúc bằng NUL. */
bool cmd_parse_line(const char *line, size_t line_len, adms_cmd_t *out);

/* Thực thi lệnh trên máy chấm công.
 * Trả về mã Return để báo lại server: 0 = thành công, khác 0 = lỗi.
 * cmd_name nhận từ khoá đầu của lệnh để đưa vào trường CMD khi ACK. */
int cmd_exec_run(zk_conn_t *c, const adms_cmd_t *cmd, char *cmd_name, size_t cmd_name_cap);

/* Đọc giá trị của một trường "key=value" trong chuỗi lệnh. */
bool cmd_field(const char *text, const char *key, char *out, size_t cap);

/* Như cmd_field nhưng không copy — val trỏ vào text gốc (đến TAB/cuối). */
bool cmd_field_span(const char *text, const char *key, const char **val, size_t *len);
