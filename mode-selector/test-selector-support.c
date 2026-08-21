#include "t9-input.h"
#include "wifi.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void test_t9_multitap(void)
{
    t9_input_t input;
    char text[80];
    t9_input_reset(&input);
    assert(t9_input_press(&input, 14, 100) == T9_EVENT_CHANGED);
    assert(t9_input_press(&input, 14, 200) == T9_EVENT_CHANGED);
    assert(t9_input_press(&input, 15, 300) == T9_EVENT_CHANGED);
    t9_input_text(&input, text, sizeof text);
    assert(strcmp(text, "bd") == 0);
    assert(t9_input_tick(&input, 1200) == T9_EVENT_CHANGED);
    assert(t9_input_press(&input, 4, 1300) == T9_EVENT_SUBMIT);
    t9_input_text(&input, text, sizeof text);
    assert(strcmp(text, "bd") == 0);
}

static void test_t9_layers_and_editing(void)
{
    t9_input_t input;
    char text[80];
    t9_input_reset(&input);
    (void)t9_input_press(&input, 8, 100);
    assert(strcmp(t9_input_layer_name(&input), "UPPER") == 0);
    (void)t9_input_press(&input, 14, 200);
    (void)t9_input_tick(&input, 1100);
    (void)t9_input_press(&input, 8, 1200);
    assert(strcmp(t9_input_layer_name(&input), "SYMBOLS") == 0);
    (void)t9_input_press(&input, 15, 1300);
    (void)t9_input_press(&input, 15, 1400);
    (void)t9_input_press(&input, 16, 1500);
    t9_input_text(&input, text, sizeof text);
    assert(strcmp(text, "A") == 0);
    assert(t9_input_press(&input, 12, 1600) == T9_EVENT_CANCEL);
    assert(t9_input_length(&input) == 0);
}

static void test_t9_digit_one_and_password_reveal(void)
{
    t9_input_t input;
    char text[80];
    t9_input_reset(&input);
    assert(strcmp(t9_input_layer_name(&input), "LOWER") == 0);

    (void)t9_input_press(&input, 1, 100);
    (void)t9_input_press(&input, 1, 200);
    (void)t9_input_press(&input, 14, 1000);
    (void)t9_input_press(&input, 8, 1900);
    (void)t9_input_press(&input, 14, 2000);
    (void)t9_input_press(&input, 8, 2900);
    (void)t9_input_press(&input, 15, 3000);

    t9_input_display(&input, false, text, sizeof text);
    assert(strcmp(text, "XXXX") == 0);
    t9_input_display(&input, true, text, sizeof text);
    assert(strcmp(text, "1aA@") == 0);
}

static void test_nmcli_parser(void)
{
    wifi_network_t network;
    assert(wifi_parse_nmcli_line("*:Studio\\:Main:87:WPA2\n", &network));
    assert(network.active);
    assert(network.secured);
    assert(!network.enterprise);
    assert(network.signal == 87);
    assert(strcmp(network.ssid, "Studio:Main") == 0);
    assert(wifi_parse_nmcli_line(" :Open Cafe:101:--\n", &network));
    assert(!network.active);
    assert(!network.secured);
    assert(network.signal == 100);
    assert(wifi_parse_nmcli_line(" :Corp:54:WPA2 802.1X\n", &network));
    assert(network.enterprise);
    assert(!wifi_parse_nmcli_line("broken", &network));
}

static void read_file(const char* path, char* output, size_t output_size)
{
    FILE* file = fopen(path, "r");
    assert(file);
    size_t length = fread(output, 1, output_size - 1, file);
    output[length] = '\0';
    fclose(file);
}

static void test_wifi_secret_pipe_and_hidden_flag(void)
{
    char directory[] = "/tmp/selector-support.XXXXXX";
    assert(mkdtemp(directory));
    char script[256];
    char args_file[256];
    char stdin_file[256];
    snprintf(script, sizeof script, "%s/nmcli", directory);
    snprintf(args_file, sizeof args_file, "%s/args", directory);
    snprintf(stdin_file, sizeof stdin_file, "%s/stdin", directory);
    FILE* file = fopen(script, "w");
    assert(file);
    fputs("#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$FAKE_ARGS_FILE\"\n"
          "IFS= read -r secret\nprintf '%s' \"$secret\" > \"$FAKE_STDIN_FILE\"\n", file);
    fclose(file);
    assert(chmod(script, 0700) == 0);
    assert(setenv("FAKE_ARGS_FILE", args_file, 1) == 0);
    assert(setenv("FAKE_STDIN_FILE", stdin_file, 1) == 0);

    wifi_network_t network = {0};
    snprintf(network.ssid, sizeof network.ssid, "Hidden Lab");
    network.secured = true;
    network.hidden = true;
    assert(wifi_connect(script, &network, "TopSecret9") == 0);

    char contents[1024];
    read_file(args_file, contents, sizeof contents);
    assert(strstr(contents, "TopSecret9") == NULL);
    assert(strstr(contents, "hidden\nyes\n") != NULL);
    assert(strstr(contents, "private\nno\n") != NULL);
    read_file(stdin_file, contents, sizeof contents);
    assert(strcmp(contents, "TopSecret9") == 0);

    unlink(stdin_file);
    unlink(args_file);
    unlink(script);
    rmdir(directory);
}

int main(void)
{
    test_t9_multitap();
    test_t9_layers_and_editing();
    test_t9_digit_one_and_password_reveal();
    test_nmcli_parser();
    test_wifi_secret_pipe_and_hidden_flag();
    puts("selector support tests: PASS");
    return 0;
}
