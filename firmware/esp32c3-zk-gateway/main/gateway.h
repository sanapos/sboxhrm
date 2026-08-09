#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "app_config.h"
#include "esp_err.h"
#include "zk_proto.h"

typedef struct {
    bool device_online;
    bool server_online;
    char serial[CFG_STR_LEN];
    char firmware[64];
    char platform[48];
    uint32_t dev_users;
    uint32_t dev_fingers;
    uint32_t dev_records;
    uint32_t uploaded_total;
    uint32_t uploaded_last;
    uint32_t commands_done;
    int64_t last_cycle_ms;
    int64_t last_upload_ms;
    uint32_t last_auto_clear_ym; /* YYYYMM lần xóa định kỳ gần nhất, 0 = chưa */
    char last_error[128];
} gw_status_t;

void gateway_start(void);
void gateway_status_snapshot(gw_status_t *out);

/* Yêu cầu từ web portal hoặc từ lệnh của server. */
void gateway_request_full_resync(void);
void gateway_request_user_sync(void);
void gateway_request_clock_sync(void);
void gateway_request_identify(void);
void gateway_clear_device_identity(void);

/* Được cmd_exec gọi khi server yêu cầu kéo dữ liệu; dùng lại phiên ZK đang mở. */
esp_err_t gateway_upload_attendance(zk_conn_t *c, bool full_resync);
esp_err_t gateway_upload_users(zk_conn_t *c);

/* Gửi cảnh báo ERRORLOG lên server (debounce theo mã). */
void gateway_report_alert(const char *code, const char *msg, uint32_t records, int64_t duration_ms);

/* Máy ZK chỉ cho một phiên TCP. Web portal và vòng đồng bộ dùng chung khoá này. */
typedef esp_err_t (*gateway_device_fn)(zk_conn_t *c, void *ctx);
esp_err_t gateway_run_on_device(gateway_device_fn fn, void *ctx);
