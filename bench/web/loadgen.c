/* Closed-loop HTTP load generator: C threads, one keep-alive connection each, GET /item/<key> with skewed keys.
   Usage: loadgen <port> <connections> <seconds> [keys [requests per connection]]. Prints requests/s and latency percentiles. */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static int port, seconds, keys = 5000, per_connection = 0;
static volatile int stop;

typedef struct { uint64_t count, errors; uint32_t *latencies; uint64_t capacity; } stats_t;

static uint64_t now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (uint64_t)t.tv_sec * 1000000000ull + t.tv_nsec; }

static void *run(void *arg) {
    stats_t *stats = arg;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET; address.sin_port = htons(port); address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    int on = 1; setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &on, sizeof(on));
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) { stats->errors++; return NULL; }
    unsigned seed = (unsigned)(uintptr_t)arg ^ (unsigned)now_ns();
    char request[128], buffer[4096];
    int served = 0;
    while (!stop) {
        if (per_connection && served >= per_connection) {  /* a new connection every N requests */
            close(fd);
            fd = socket(AF_INET, SOCK_STREAM, 0);
            setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &on, sizeof(on));
            if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) { stats->errors++; return NULL; }
            served = 0;
        }
        served++;
        uint64_t u = (uint64_t)(rand_r(&seed) % keys), key = u * u / keys;
        int length = snprintf(request, sizeof(request), "GET /item/%llu HTTP/1.1\r\nHost: x\r\n\r\n", (unsigned long long)key);
        uint64_t start = now_ns();
        if (send(fd, request, length, MSG_NOSIGNAL) != length) { stats->errors++; break; }
        size_t have = 0; ssize_t want = -1; size_t head = 0;
        for (;;) {
            ssize_t got = recv(fd, buffer + have, sizeof(buffer) - have - 1, 0);
            if (got <= 0) { stats->errors++; close(fd); return NULL; }
            have += (size_t)got; buffer[have] = 0;
            char *end = strstr(buffer, "\r\n\r\n");
            if (end && want < 0) {
                head = (size_t)(end - buffer) + 4;
                char *cl = strcasestr(buffer, "content-length:");
                want = cl ? atoi(cl + 15) : 0;
            }
            if (want >= 0 && have >= head + (size_t)want) break;
        }
        if (strncmp(buffer, "HTTP/1.1 200", 12) != 0) stats->errors++;
        uint64_t elapsed = now_ns() - start;
        if (stats->count < stats->capacity) stats->latencies[stats->count] = (uint32_t)(elapsed / 1000);
        stats->count++;
    }
    close(fd);
    return NULL;
}

static int compare(const void *a, const void *b) { uint32_t x = *(const uint32_t *)a, y = *(const uint32_t *)b; return x < y ? -1 : x > y; }

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage: loadgen port connections seconds [keys]\n"); return 2; }
    port = atoi(argv[1]); int connections = atoi(argv[2]); seconds = atoi(argv[3]);
    if (argc > 4) keys = atoi(argv[4]);
    if (argc > 5) per_connection = atoi(argv[5]);
    pthread_t *threads = calloc(connections, sizeof(*threads));
    stats_t *stats = calloc(connections, sizeof(*stats));
    for (int i = 0; i < connections; ++i) { stats[i].capacity = 2000000; stats[i].latencies = malloc(stats[i].capacity * sizeof(uint32_t)); pthread_create(&threads[i], NULL, run, &stats[i]); }
    uint64_t start = now_ns();
    sleep((unsigned)seconds);
    stop = 1;
    for (int i = 0; i < connections; ++i) pthread_join(threads[i], NULL);
    double wall = (now_ns() - start) / 1e9;
    uint64_t total = 0, errors = 0, kept = 0;
    for (int i = 0; i < connections; ++i) { total += stats[i].count; errors += stats[i].errors; kept += stats[i].count < stats[i].capacity ? stats[i].count : stats[i].capacity; }
    uint32_t *all = malloc((kept ? kept : 1) * sizeof(uint32_t)); size_t at = 0;
    for (int i = 0; i < connections; ++i) { uint64_t n = stats[i].count < stats[i].capacity ? stats[i].count : stats[i].capacity; memcpy(all + at, stats[i].latencies, n * sizeof(uint32_t)); at += n; }
    qsort(all, kept, sizeof(uint32_t), compare);
    printf("requests %llu errors %llu  %.0f req/s  latency us p50 %u p99 %u max %u\n", (unsigned long long)total, (unsigned long long)errors,
           total / wall, kept ? all[kept / 2] : 0, kept ? all[kept * 99 / 100] : 0, kept ? all[kept - 1] : 0);
    return 0;
}
