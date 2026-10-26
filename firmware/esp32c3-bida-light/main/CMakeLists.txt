idf_component_register(
    SRCS
        "main.c"
        "light_config.c"
        "relay.c"
        "wifi_link.c"
        "poller.c"
        "web_ui.c"
        "ble_link.c"
    INCLUDE_DIRS "."
    EMBED_TXTFILES "ui.html"
    REQUIRES
        nvs_flash
        esp_wifi
        esp_netif
        esp_event
        esp_http_client
        esp_http_server
        esp_timer
        esp-tls
        esp_driver_gpio
        esp_app_format
        mbedtls
        json
        bt
)
