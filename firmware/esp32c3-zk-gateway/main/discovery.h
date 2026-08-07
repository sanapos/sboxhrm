#pragma once

#include "esp_err.h"

/* Giúp app điện thoại tìm thấy gateway trong mạng LAN mà không cần biết IP.
 *
 * Hai kênh song song vì mỗi kênh hỏng theo cách khác nhau:
 *  - mDNS: tên sboxadms.local và dịch vụ _sboxgw._tcp. Gọn nhưng
 *    nhiều router/AP chặn multicast giữa các client.
 *  - Quảng bá UDP: app gửi "SBOX_DISCOVER" tới địa chỉ broadcast, thiết bị
 *    trả lời một dòng JSON. Chạy được cả khi mDNS bị chặn.
 */
esp_err_t discovery_start(void);

/* Cổng UDP dùng cho dò tìm; app phải gửi quảng bá vào đúng cổng này. */
#define DISCOVERY_UDP_PORT 51820

/* Chuỗi app gửi lên để hỏi "có gateway nào không". */
#define DISCOVERY_PROBE "SBOX_DISCOVER"
