#pragma once

#include <stdbool.h>
#include <stddef.h>

#define WIFI_NETWORK_MAX 32
#define WIFI_SSID_MAX 128

typedef struct {
    char ssid[WIFI_SSID_MAX];
    char security[64];
    int signal;
    bool active;
    bool secured;
    bool enterprise;
    bool hidden;
} wifi_network_t;

bool wifi_parse_nmcli_line(const char* line, wifi_network_t* network);
int wifi_scan(const char* nmcli, wifi_network_t* networks, size_t capacity);
int wifi_connect(const char* nmcli, const wifi_network_t* network,
                 const char* password);
