#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    bool server_ok;          /* lần hỏi gần nhất thành công */
    int http_status;         /* mã HTTP lần gần nhất (0 = không tới được máy chủ) */
    uint32_t ok_count;
    uint32_t fail_count;
    int64_t last_ok_ms;      /* thời điểm (esp_timer) hỏi thành công gần nhất, 0 = chưa */
    uint16_t server_mask;    /* bàn đang mở theo máy chủ (bit i = kênh i) */
    uint16_t unknown_mask;   /* kênh đã gắn mã bàn nhưng máy chủ không có bàn đó */
    char message[96];
} poller_status_t;

void poller_start(void);
void poller_get_status(poller_status_t *out);

/* Tính lại relay ngay (sau khi đổi chế độ tay trên trang web). */
void poller_kick(void);

/* Danh sách bàn từ lần hỏi gần nhất, dạng JSON [{"c":"B01","n":"Bàn 1","on":1},...].
 * Ghi vào buf, trả về độ dài (0 nếu chưa có hoặc không vừa). */
size_t poller_copy_tables(char *buf, size_t cap);
