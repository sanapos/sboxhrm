#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "light_config.h"

/* Cấu hình chân và đặt trạng thái ban đầu theo mask (bit i = kênh i sáng). */
void relay_init(uint16_t initial_mask);

/* Đặt toàn bộ kênh theo mask; trả về true nếu có kênh đổi trạng thái. */
bool relay_apply(uint16_t mask);

uint16_t relay_mask(void);

/* Sau khi lưu cấu hình kênh mới: nhả các chân cũ (đặt về mức tắt) rồi khởi tạo chân mới,
 * giữ trạng thái sáng/tắt theo kênh. Không cần khởi động lại. */
void relay_reconfigure(const light_config_t *old_cfg);

/* Bật thử relay trên một chân trong ms mili giây rồi trả lại đúng trạng thái kênh —
 * để người cài nhìn đèn nào sáng mà gán đúng bàn. false nếu chân không hợp lệ. */
bool relay_test_pin(int gpio, uint32_t ms);

/* Bit i = GPIO i dùng được làm chân relay. */
uint32_t relay_usable_pins(void);
