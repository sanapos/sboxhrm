#pragma once

/*
 * Bên client của giao thức ADMS push (ZKTeco PUSH SDK 2.4.1).
 * Gateway đóng vai một máy chấm công có ADMS đối với server sboxhrm.com.
 */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"

typedef struct {
    int status;      /* mã HTTP */
    size_t len;      /* số byte thân phản hồi đã lấy được */
} adms_result_t;

/* GET /iclock/cdata?SN=..&options=all -> khối "GET OPTION FROM: .." hoặc "FAIL" */
esp_err_t adms_get_options(const char *sn, char *resp, size_t resp_cap, adms_result_t *out);

/* POST /iclock/cdata?SN=..&table=options — khai báo firmware, số nhân viên, IP... */
esp_err_t adms_post_options(const char *sn, const char *body);

/* POST /iclock/cdata?SN=..&table=ATTLOG&Stamp=.. — mỗi dòng một lần chấm công */
esp_err_t adms_post_attlog(const char *sn, const char *body, const char *stamp);

/* POST /iclock/cdata?SN=..&table=OPERLOG — danh sách nhân viên đọc từ máy */
esp_err_t adms_post_operlog(const char *sn, const char *body);

/* POST /iclock/cdata?SN=..&table=ERRORLOG — cảnh báo sức khỏe gateway */
esp_err_t adms_post_errorlog(const char *sn, const char *body);

/* GET /iclock/getrequest?SN=..&INFO=.. -> "OK" hoặc các dòng "C:<id>:<lenh>" */
esp_err_t adms_get_request(const char *sn, const char *info, char *resp, size_t resp_cap,
                           adms_result_t *out);

/* POST /iclock/devicecmd?SN=.. body "ID=..&Return=..&CMD=.." */
esp_err_t adms_ack_command(const char *sn, const char *cmd_id, int ret_code, const char *cmd_name);

/* Đọc một khoá trong khối "GET OPTION FROM:" (ví dụ ATTLOGStamp). */
bool adms_parse_option(const char *block, const char *key, char *out, size_t cap);

/* Bỏ kết nối HTTPS đang giữ lại (dùng khi đổi cấu hình server hoặc mất WiFi). */
void adms_client_reset(void);
