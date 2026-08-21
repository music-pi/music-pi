#define _GNU_SOURCE

#include "wifi.h"

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static bool split_escaped_fields(const char* line, char fields[][WIFI_SSID_MAX],
                                 size_t field_count)
{
    size_t field = 0;
    size_t offset = 0;
    bool escaped = false;
    memset(fields, 0, field_count * WIFI_SSID_MAX);
    for (const unsigned char* p = (const unsigned char*)line; *p; ++p) {
        if (!escaped && (*p == '\n' || *p == '\r')) break;
        if (!escaped && *p == ':') {
            if (++field >= field_count) return false;
            offset = 0;
            continue;
        }
        if (!escaped && *p == '\\') {
            escaped = true;
            continue;
        }
        if (offset + 1 < WIFI_SSID_MAX) fields[field][offset++] = (char)*p;
        escaped = false;
    }
    return field + 1 == field_count;
}

bool wifi_parse_nmcli_line(const char* line, wifi_network_t* network)
{
    if (!line || !network) return false;
    char fields[4][WIFI_SSID_MAX];
    if (!split_escaped_fields(line, fields, 4) || !fields[1][0]) return false;
    char* end = NULL;
    long signal = strtol(fields[2], &end, 10);
    if (!end || *end != '\0') return false;
    if (signal < 0) signal = 0;
    if (signal > 100) signal = 100;

    memset(network, 0, sizeof *network);
    snprintf(network->ssid, sizeof network->ssid, "%s", fields[1]);
    snprintf(network->security, sizeof network->security, "%.63s", fields[3]);
    network->signal = (int)signal;
    network->active = strcmp(fields[0], "*") == 0 || strcmp(fields[0], "yes") == 0;
    network->secured = fields[3][0] != '\0' && strcmp(fields[3], "--") != 0;
    network->enterprise = strstr(fields[3], "802.1X") != NULL ||
                          strstr(fields[3], "EAP") != NULL;
    return true;
}

static int wait_for(pid_t child)
{
    int status = 0;
    while (waitpid(child, &status, 0) < 0) {
        if (errno != EINTR) return -1;
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static void silence_fd(int target)
{
    int null_fd = open("/dev/null", target == STDIN_FILENO ? O_RDONLY : O_WRONLY);
    if (null_fd >= 0) {
        (void)dup2(null_fd, target);
        if (null_fd != target) close(null_fd);
    }
}

static void radio_on(const char* nmcli)
{
    pid_t child = fork();
    if (child == 0) {
        silence_fd(STDIN_FILENO);
        silence_fd(STDOUT_FILENO);
        silence_fd(STDERR_FILENO);
        execl(nmcli, "nmcli", "radio", "wifi", "on", (char*)NULL);
        _exit(127);
    }
    if (child > 0) (void)wait_for(child);
}

int wifi_scan(const char* nmcli, wifi_network_t* networks, size_t capacity)
{
    if (!nmcli || !networks || capacity == 0) return -1;
    radio_on(nmcli);

    int output_pipe[2];
    if (pipe2(output_pipe, O_CLOEXEC) != 0) return -1;
    pid_t child = fork();
    if (child < 0) {
        close(output_pipe[0]);
        close(output_pipe[1]);
        return -1;
    }
    if (child == 0) {
        close(output_pipe[0]);
        (void)dup2(output_pipe[1], STDOUT_FILENO);
        close(output_pipe[1]);
        silence_fd(STDIN_FILENO);
        silence_fd(STDERR_FILENO);
        execl(nmcli, "nmcli", "-t", "--escape", "yes", "-f",
              "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list",
              "--rescan", "yes", (char*)NULL);
        _exit(127);
    }

    close(output_pipe[1]);
    FILE* stream = fdopen(output_pipe[0], "r");
    if (!stream) {
        close(output_pipe[0]);
        (void)wait_for(child);
        return -1;
    }
    size_t count = 0;
    char line[512];
    while (fgets(line, sizeof line, stream)) {
        wifi_network_t candidate;
        if (!wifi_parse_nmcli_line(line, &candidate)) continue;
        size_t duplicate = count;
        for (size_t i = 0; i < count; ++i) {
            if (strcmp(networks[i].ssid, candidate.ssid) == 0) {
                duplicate = i;
                break;
            }
        }
        if (duplicate < count) {
            if (candidate.active || candidate.signal > networks[duplicate].signal)
                networks[duplicate] = candidate;
        } else if (count < capacity) {
            networks[count++] = candidate;
        }
    }
    fclose(stream);
    int result = wait_for(child);
    if (result != 0) return -1;

    for (size_t i = 0; i < count; ++i) {
        for (size_t j = i + 1; j < count; ++j) {
            if ((!networks[i].active && networks[j].active) ||
                (networks[i].active == networks[j].active &&
                 networks[j].signal > networks[i].signal)) {
                wifi_network_t temporary = networks[i];
                networks[i] = networks[j];
                networks[j] = temporary;
            }
        }
    }
    return (int)count;
}

static void connection_name(const char* ssid, char* output, size_t output_size)
{
    size_t offset = 0;
    const char prefix[] = "mpi-";
    for (size_t i = 0; prefix[i] && offset + 1 < output_size; ++i)
        output[offset++] = prefix[i];
    for (const unsigned char* p = (const unsigned char*)ssid;
         *p && offset + 1 < output_size; ++p) {
        output[offset++] = (isalnum(*p) || *p == '-' || *p == '_') ? (char)*p : '-';
    }
    output[offset] = '\0';
}

static bool write_all(int fd, const char* data, size_t length)
{
    while (length > 0) {
        ssize_t written = write(fd, data, length);
        if (written < 0) {
            if (errno == EINTR) continue;
            return false;
        }
        data += written;
        length -= (size_t)written;
    }
    return true;
}

int wifi_connect(const char* nmcli, const wifi_network_t* network,
                 const char* password)
{
    if (!nmcli || !network || !network->ssid[0] || network->enterprise) return -1;
    if (network->secured && (!password || !password[0])) return -1;

    int input_pipe[2];
    if (pipe2(input_pipe, O_CLOEXEC) != 0) return -1;
    pid_t child = fork();
    if (child < 0) {
        close(input_pipe[0]);
        close(input_pipe[1]);
        return -1;
    }
    if (child == 0) {
        close(input_pipe[1]);
        (void)dup2(input_pipe[0], STDIN_FILENO);
        close(input_pipe[0]);
        silence_fd(STDOUT_FILENO);
        silence_fd(STDERR_FILENO);
        char name[96];
        connection_name(network->ssid, name, sizeof name);
        if (network->hidden)
            execl(nmcli, "nmcli", "--ask", "--wait", "45", "device", "wifi",
                  "connect", network->ssid, "name", name, "private", "no",
                  "hidden", "yes", (char*)NULL);
        else
            execl(nmcli, "nmcli", "--ask", "--wait", "45", "device", "wifi",
                  "connect", network->ssid, "name", name, "private", "no",
                  (char*)NULL);
        _exit(127);
    }

    close(input_pipe[0]);
    bool input_ok = true;
    if (network->secured) {
        struct sigaction ignored = {.sa_handler = SIG_IGN};
        struct sigaction previous;
        sigemptyset(&ignored.sa_mask);
        bool signal_changed = sigaction(SIGPIPE, &ignored, &previous) == 0;
        input_ok = write_all(input_pipe[1], password, strlen(password)) &&
                   write_all(input_pipe[1], "\n", 1);
        if (signal_changed) (void)sigaction(SIGPIPE, &previous, NULL);
    }
    close(input_pipe[1]);
    int child_status = wait_for(child);
    return input_ok && child_status == 0 ? 0 : -1;
}
