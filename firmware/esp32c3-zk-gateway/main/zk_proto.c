#include "zk_proto.h"

#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>

#include "esp_log.h"
#include "lwip/netdb.h"
#include "lwip/sockets.h"

static const char *TAG = "zk";

#define ZK_MAGIC_0 0x5050
#define ZK_MAGIC_1 0x7d82
#define ZK_HDR_LEN 8
#define ZK_TOP_LEN 8

/* Mảnh lớn nhất xin từ máy trong một lần READ_BUFFER, giống pyzk. */
#define ZK_MAX_CHUNK 0xFFC0

static void put_u16(uint8_t *p, uint16_t v)
{
    p[0] = (uint8_t)(v & 0xFF);
    p[1] = (uint8_t)(v >> 8);
}

static void put_u32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v & 0xFF);
    p[1] = (uint8_t)((v >> 8) & 0xFF);
    p[2] = (uint8_t)((v >> 16) & 0xFF);
    p[3] = (uint8_t)((v >> 24) & 0xFF);
}

static uint16_t get_u16(const uint8_t *p)
{
    return (uint16_t)(p[0] | (p[1] << 8));
}

static uint32_t get_u32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint16_t zk_checksum(const uint8_t *p, size_t len)
{
    uint32_t chk = 0;
    size_t i = 0;

    while (i + 1 < len) {
        chk += (uint32_t)get_u16(p + i);
        if (chk > 0xFFFF) {
            chk -= 0xFFFF;
        }
        i += 2;
    }
    if (i < len) {
        chk += p[i];
    }
    while (chk > 0xFFFF) {
        chk -= 0xFFFF;
    }

    /* Máy kiểm tra tổng mọi từ 16-bit của gói (kể cả ô checksum) phải bằng
     * 0xFFFF, nên phần bù phải là 0xFFFF - chk. Dùng ~chk sẽ lệch đúng 1 đơn
     * vị và máy lặng lẽ bỏ qua gói, không trả lời gì. */
    return (uint16_t)(0xFFFF - chk);
}

/* Khoá phiên cho CMD_AUTH khi máy bật Comm Key. */
static void make_commkey(uint32_t key, uint16_t session_id, uint8_t ticks, uint8_t out[4])
{
    uint32_t k = 0;
    for (int i = 0; i < 32; i++) {
        k = (k << 1) | ((key >> i) & 1u);
    }
    k += session_id;

    uint8_t b[4] = {
        (uint8_t)(k & 0xFF),
        (uint8_t)((k >> 8) & 0xFF),
        (uint8_t)((k >> 16) & 0xFF),
        (uint8_t)((k >> 24) & 0xFF),
    };
    b[0] ^= 'Z';
    b[1] ^= 'K';
    b[2] ^= 'S';
    b[3] ^= 'O';

    /* hoán đổi hai nửa 16 bit */
    uint8_t sw[4] = {b[2], b[3], b[0], b[1]};

    /* Trộn với "ticks": byte 2 là ticks thô, byte 3 là sw[3]^ticks. Thứ tự
     * này phải khớp đúng SDK gốc (pyzk make_commkey), nếu lệch máy trả
     * CMD_ACK_UNAUTH dù khóa đúng. */
    out[0] = sw[0] ^ ticks;
    out[1] = sw[1] ^ ticks;
    out[2] = ticks;
    out[3] = sw[3] ^ ticks;
}

static esp_err_t sock_send_all(int sock, const uint8_t *buf, size_t len)
{
    size_t sent = 0;
    while (sent < len) {
        int n = send(sock, buf + sent, len - sent, 0);
        if (n <= 0) {
            ESP_LOGE(TAG, "send loi errno=%d", errno);
            return ESP_FAIL;
        }
        sent += (size_t)n;
    }
    return ESP_OK;
}

static esp_err_t sock_recv_all(int sock, uint8_t *buf, size_t len)
{
    size_t got = 0;
    while (got < len) {
        int n = recv(sock, buf + got, len - got, 0);
        if (n <= 0) {
            ESP_LOGE(TAG, "recv loi n=%d errno=%d (can %u, duoc %u)",
                     n, errno, (unsigned)len, (unsigned)got);
            return ESP_FAIL;
        }
        got += (size_t)n;
    }
    return ESP_OK;
}

/* Đọc và bỏ đi n byte khi không quan tâm nội dung. */
static esp_err_t sock_skip(int sock, size_t len)
{
    uint8_t tmp[256];
    while (len > 0) {
        size_t want = len > sizeof(tmp) ? sizeof(tmp) : len;
        if (sock_recv_all(sock, tmp, want) != ESP_OK) {
            return ESP_FAIL;
        }
        len -= want;
    }
    return ESP_OK;
}

static esp_err_t zk_send(zk_conn_t *c, uint16_t cmd, const void *data, size_t len)
{
    size_t payload_len = ZK_HDR_LEN + len;
    uint8_t *pkt = malloc(ZK_TOP_LEN + payload_len);
    if (pkt == NULL) {
        return ESP_ERR_NO_MEM;
    }

    put_u16(pkt, ZK_MAGIC_0);
    put_u16(pkt + 2, ZK_MAGIC_1);
    put_u32(pkt + 4, (uint32_t)payload_len);

    uint8_t *payload = pkt + ZK_TOP_LEN;
    put_u16(payload, cmd);
    put_u16(payload + 2, 0);
    put_u16(payload + 4, c->session_id);
    put_u16(payload + 6, c->reply_id);
    if (len > 0) {
        memcpy(payload + ZK_HDR_LEN, data, len);
    }
    put_u16(payload + 2, zk_checksum(payload, payload_len));

    esp_err_t err = sock_send_all(c->sock, pkt, ZK_TOP_LEN + payload_len);
    free(pkt);
    return err;
}

esp_err_t zk_recv(zk_conn_t *c, zk_sink_fn sink, void *ctx)
{
    uint8_t top[ZK_TOP_LEN];
    if (sock_recv_all(c->sock, top, ZK_TOP_LEN) != ESP_OK) {
        return ESP_FAIL;
    }
    if (get_u16(top) != ZK_MAGIC_0 || get_u16(top + 2) != ZK_MAGIC_1) {
        ESP_LOGE(TAG, "sai magic goi TCP");
        return ESP_ERR_INVALID_RESPONSE;
    }

    uint32_t tcp_len = get_u32(top + 4);
    if (tcp_len < ZK_HDR_LEN) {
        ESP_LOGE(TAG, "goi qua ngan: %u", (unsigned)tcp_len);
        return ESP_ERR_INVALID_RESPONSE;
    }

    uint8_t hdr[ZK_HDR_LEN];
    if (sock_recv_all(c->sock, hdr, ZK_HDR_LEN) != ESP_OK) {
        return ESP_FAIL;
    }

    c->resp_cmd = get_u16(hdr);
    c->reply_id = get_u16(hdr + 6);
    c->reply_len = 0;

    /* Phiên chỉ được cấp một lần lúc CONNECT; các gói dữ liệu về sau có thể
     * mang session_id = 0 và sẽ làm hỏng mọi lệnh tiếp theo nếu ghi đè. */
    if (c->session_id == 0) {
        c->session_id = get_u16(hdr + 4);
    }

    size_t data_len = tcp_len - ZK_HDR_LEN;

    /* Chỉ khối CMD_DATA mới được đẩy thẳng sang sink; các gói điều khiển
     * (PREPARE_DATA, ACK_*) phải nằm trong c->reply để bên gọi đọc được. */
    if (sink != NULL && c->resp_cmd == ZK_CMD_DATA) {
        uint8_t buf[512];
        while (data_len > 0) {
            size_t want = data_len > sizeof(buf) ? sizeof(buf) : data_len;
            if (sock_recv_all(c->sock, buf, want) != ESP_OK) {
                return ESP_FAIL;
            }
            esp_err_t err = sink(ctx, buf, want);
            if (err != ESP_OK) {
                return err;
            }
            data_len -= want;
        }
        return ESP_OK;
    }

    size_t keep = data_len > ZK_REPLY_BUF_MAX ? ZK_REPLY_BUF_MAX : data_len;
    if (keep > 0 && sock_recv_all(c->sock, c->reply, keep) != ESP_OK) {
        return ESP_FAIL;
    }
    c->reply_len = keep;

    if (data_len > keep) {
        ESP_LOGW(TAG, "cat bot %u byte cua goi 0x%04x", (unsigned)(data_len - keep), c->resp_cmd);
        if (sock_skip(c->sock, data_len - keep) != ESP_OK) {
            return ESP_FAIL;
        }
    }
    return ESP_OK;
}

esp_err_t zk_send_ack(zk_conn_t *c)
{
    c->reply_id++;
    return zk_send(c, ZK_CMD_ACK_OK, NULL, 0);
}

void zk_set_recv_timeout(zk_conn_t *c, int timeout_ms)
{
    if (c->sock < 0) {
        return;
    }
    struct timeval tv = {.tv_sec = timeout_ms / 1000, .tv_usec = (timeout_ms % 1000) * 1000};
    setsockopt(c->sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
}

esp_err_t zk_cmd_stream(zk_conn_t *c, uint16_t cmd, const void *data, size_t len,
                        zk_sink_fn sink, void *ctx)
{
    c->reply_id++;
    esp_err_t err = zk_send(c, cmd, data, len);
    if (err != ESP_OK) {
        return err;
    }
    return zk_recv(c, sink, ctx);
}

esp_err_t zk_cmd(zk_conn_t *c, uint16_t cmd, const void *data, size_t len)
{
    return zk_cmd_stream(c, cmd, data, len, NULL, NULL);
}

bool zk_reply_ok(const zk_conn_t *c)
{
    return c->resp_cmd == ZK_CMD_ACK_OK || c->resp_cmd == ZK_CMD_ACK_DATA ||
           c->resp_cmd == ZK_CMD_DATA || c->resp_cmd == ZK_CMD_PREPARE_DATA;
}

static esp_err_t connect_with_timeout(const char *ip, uint16_t port, int timeout_ms, int *out_sock)
{
    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    if (inet_pton(AF_INET, ip, &addr.sin_addr) != 1) {
        ESP_LOGE(TAG, "dia chi IP khong hop le: %s", ip);
        return ESP_ERR_INVALID_ARG;
    }

    int sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (sock < 0) {
        return ESP_FAIL;
    }

    int flags = fcntl(sock, F_GETFL, 0);
    fcntl(sock, F_SETFL, flags | O_NONBLOCK);

    int rc = connect(sock, (struct sockaddr *)&addr, sizeof(addr));
    if (rc != 0 && errno != EINPROGRESS) {
        ESP_LOGE(TAG, "connect %s:%u loi errno=%d", ip, port, errno);
        close(sock);
        return ESP_FAIL;
    }

    if (rc != 0) {
        fd_set wset;
        FD_ZERO(&wset);
        FD_SET(sock, &wset);
        struct timeval tv = {.tv_sec = timeout_ms / 1000, .tv_usec = (timeout_ms % 1000) * 1000};
        if (select(sock + 1, NULL, &wset, NULL, &tv) <= 0) {
            ESP_LOGE(TAG, "connect %s:%u qua han", ip, port);
            close(sock);
            return ESP_ERR_TIMEOUT;
        }
        int soerr = 0;
        socklen_t slen = sizeof(soerr);
        getsockopt(sock, SOL_SOCKET, SO_ERROR, &soerr, &slen);
        if (soerr != 0) {
            ESP_LOGE(TAG, "connect %s:%u bi tu choi (%d)", ip, port, soerr);
            close(sock);
            return ESP_FAIL;
        }
    }

    fcntl(sock, F_SETFL, flags);

    struct timeval tv = {.tv_sec = timeout_ms / 1000, .tv_usec = (timeout_ms % 1000) * 1000};
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    int one = 1;
    setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));

    *out_sock = sock;
    return ESP_OK;
}

esp_err_t zk_open(zk_conn_t *c, const char *ip, uint16_t port, uint32_t comm_key, int timeout_ms)
{
    memset(c, 0, sizeof(*c));
    c->sock = -1;
    c->comm_key = comm_key;
    c->timeout_ms = timeout_ms;
    c->port = port;
    snprintf(c->ip, sizeof(c->ip), "%s", ip != NULL ? ip : "");

    esp_err_t err = connect_with_timeout(ip, port, timeout_ms, &c->sock);
    if (err != ESP_OK) {
        return err;
    }

    c->session_id = 0;
    c->reply_id = 0xFFFE; /* USHRT_MAX - 1, giống SDK gốc */

    err = zk_cmd(c, ZK_CMD_CONNECT, NULL, 0);
    if (err != ESP_OK) {
        zk_close(c);
        return err;
    }

    if (c->resp_cmd == ZK_CMD_ACK_UNAUTH) {
        uint8_t key[4];
        make_commkey(comm_key, c->session_id, 50, key);
        err = zk_cmd(c, ZK_CMD_AUTH, key, sizeof(key));
        if (err != ESP_OK || c->resp_cmd != ZK_CMD_ACK_OK) {
            ESP_LOGE(TAG, "xac thuc that bai - kiem tra Comm Key (dang dung %u)", (unsigned)comm_key);
            zk_close(c);
            return ESP_ERR_INVALID_STATE;
        }
    } else if (c->resp_cmd != ZK_CMD_ACK_OK) {
        ESP_LOGE(TAG, "may tu choi ket noi, ma tra ve %u", c->resp_cmd);
        zk_close(c);
        return ESP_ERR_INVALID_RESPONSE;
    }

    ESP_LOGI(TAG, "da ket noi %s:%u, session=%u", ip, port, c->session_id);
    return ESP_OK;
}

void zk_close(zk_conn_t *c)
{
    if (c->sock >= 0) {
        if (c->session_id != 0) {
            zk_cmd(c, ZK_CMD_EXIT, NULL, 0);
        }
        close(c->sock);
        c->sock = -1;
    }
    c->session_id = 0;
}

esp_err_t zk_reopen(zk_conn_t *c)
{
    char ip[sizeof(c->ip)];
    snprintf(ip, sizeof(ip), "%s", c->ip);
    uint16_t port = c->port;
    uint32_t comm_key = c->comm_key;
    int timeout_ms = c->timeout_ms;

    /* Xoá session_id để zk_close khỏi gửi EXIT: phía kia đã im nên gói đó chỉ
     * ngồi chờ hết thời gian chờ rồi thôi. */
    c->session_id = 0;
    zk_close(c);

    return zk_open(c, ip, port, comm_key, timeout_ms);
}

typedef struct {
    zk_sink_fn sink;
    void *ctx;
    uint32_t seen;
} counting_sink_t;

static esp_err_t counting_sink(void *ctx, const uint8_t *data, size_t len)
{
    counting_sink_t *cs = ctx;
    cs->seen += (uint32_t)len;
    if (cs->sink == NULL) {
        return ESP_OK;
    }
    return cs->sink(cs->ctx, data, len);
}

/* Nhận chuỗi PREPARE_DATA -> nhiều CMD_DATA -> ACK_OK. */
static esp_err_t drain_prepared(zk_conn_t *c, uint32_t expect, zk_sink_fn sink, void *ctx)
{
    counting_sink_t cs = {.sink = sink, .ctx = ctx, .seen = 0};

    while (cs.seen < expect) {
        uint32_t before = cs.seen;

        esp_err_t err = zk_recv(c, counting_sink, &cs);
        if (err != ESP_OK) {
            return err;
        }
        if (c->resp_cmd == ZK_CMD_ACK_OK) {
            return ESP_OK;
        }
        if (c->resp_cmd != ZK_CMD_DATA) {
            ESP_LOGE(TAG, "goi la giua luong du lieu: %u", c->resp_cmd);
            return ESP_ERR_INVALID_RESPONSE;
        }
        if (cs.seen == before) {
            ESP_LOGE(TAG, "luong du lieu dung lai o %u/%u", (unsigned)cs.seen, (unsigned)expect);
            return ESP_ERR_INVALID_RESPONSE;
        }
    }

    /* nuốt gói ACK_OK kết thúc luồng */
    return zk_recv(c, NULL, NULL);
}

esp_err_t zk_read_buffered(zk_conn_t *c, uint16_t data_cmd, uint32_t fct,
                           zk_sink_fn sink, void *ctx, uint32_t *out_size)
{
    uint8_t req[11];
    req[0] = 1;
    put_u16(req + 1, data_cmd);
    put_u32(req + 3, fct);
    put_u32(req + 7, 0);

    esp_err_t err = zk_cmd_stream(c, ZK_CMD_DATA_WRRQ, req, sizeof(req), sink, ctx);
    if (err != ESP_OK) {
        return err;
    }

    /* Dữ liệu nhỏ: máy trả thẳng trong gói CMD_DATA, sink đã nhận đủ. */
    if (c->resp_cmd == ZK_CMD_DATA) {
        if (out_size != NULL) {
            *out_size = 0; /* không biết trước, bên gọi tự đếm */
        }
        return ESP_OK;
    }

    if (c->resp_cmd == ZK_CMD_ACK_ERROR) {
        ESP_LOGW(TAG, "may khong ho tro DATA_WRRQ cho lenh %u", data_cmd);
        return ESP_ERR_NOT_SUPPORTED;
    }

    if (c->reply_len < 5) {
        ESP_LOGE(TAG, "tra loi DATA_WRRQ khong hop le (%u byte, cmd=%u)",
                 (unsigned)c->reply_len, c->resp_cmd);
        return ESP_ERR_INVALID_RESPONSE;
    }

    uint32_t total = get_u32(c->reply + 1);
    if (out_size != NULL) {
        *out_size = total;
    }
    ESP_LOGI(TAG, "khoi du lieu %u byte tu lenh %u", (unsigned)total, data_cmd);

    uint32_t start = 0;
    while (start < total) {
        uint32_t want = total - start;
        if (want > ZK_MAX_CHUNK) {
            want = ZK_MAX_CHUNK;
        }

        uint8_t chunk_req[8];
        put_u32(chunk_req, start);
        put_u32(chunk_req + 4, want);

        err = zk_cmd_stream(c, ZK_CMD_READ_BUFFER, chunk_req, sizeof(chunk_req), sink, ctx);
        if (err != ESP_OK) {
            return err;
        }

        if (c->resp_cmd == ZK_CMD_PREPARE_DATA) {
            uint32_t announced = c->reply_len >= 4 ? get_u32(c->reply) : want;
            err = drain_prepared(c, announced, sink, ctx);
            if (err != ESP_OK) {
                return err;
            }
        } else if (c->resp_cmd != ZK_CMD_DATA) {
            ESP_LOGE(TAG, "READ_BUFFER tra ve ma la: %u", c->resp_cmd);
            return ESP_ERR_INVALID_RESPONSE;
        }

        start += want;
    }

    zk_cmd(c, ZK_CMD_FREE_DATA, NULL, 0);
    return ESP_OK;
}

void zk_decode_time(uint32_t enc, int *year, int *mon, int *day, int *hour, int *min, int *sec)
{
    uint32_t t = enc;
    *sec = (int)(t % 60);
    t /= 60;
    *min = (int)(t % 60);
    t /= 60;
    *hour = (int)(t % 24);
    t /= 24;
    *day = (int)(t % 31) + 1;
    t /= 31;
    *mon = (int)(t % 12) + 1;
    t /= 12;
    *year = (int)t + 2000;
}

uint32_t zk_encode_time(int year, int mon, int day, int hour, int min, int sec)
{
    uint32_t days = (uint32_t)(((year % 100) * 12 * 31) + ((mon - 1) * 31) + (day - 1));
    return days * 24u * 60u * 60u + (uint32_t)((hour * 60 + min) * 60 + sec);
}
