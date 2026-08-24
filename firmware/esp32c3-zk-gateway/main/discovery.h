#pragma once

#include "esp_err.h"

/* Giúp app điện thoại tìm thấy gateway trong mạng LAN mà không cần biết IP.
 *
 * Hai kênh song song vì mỗi kênh hỏng theo cách khác nhau:
 *  - mDNS: hostname riêng theo MAC `sboxgw-XXXX.local` + dịch vụ `_sboxgw._tcp`
 *    (tránh trùng khi nhiều mạch cùng LAN).
 *  - Quảng bá UDP: app gửi "SBOX_DISCOVER" tới địa chỉ broadcast, thiết bị
 *    trả lời một dòng JSON. Chạy được cả khi mDNS bị chặn.
 */
esp_err_t discovery_start(void);

/** Hostname mDNS hiện tại (không gồm `.local`), ví dụ `sboxgw-9781`. */
const char *discovery_hostname(void);

/* Cổng UDP dùng cho dò tìm; app phải gửi quảng bá vào đúng cổng này. */
#define DISCOVERY_UDP_PORT 51820

/* Chuỗi app gửi lên để hỏi "có gateway nào không". */
#define DISCOVERY_PROBE "SBOX_DISCOVER"
