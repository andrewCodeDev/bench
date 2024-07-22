
#include <asm/unistd.h>
#include <linux/perf_event.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <inttypes.h>
#include <sys/types.h>

#include "hw_counter.h"

static long perf_event_open(
    struct perf_event_attr *hw_event,
    pid_t pid,
    int cpu, 
    int group_fd, 
    unsigned long flags
) {
    return syscall(__NR_perf_event_open, hw_event, pid, cpu, group_fd, flags);
}

long counter_start(unsigned long long COUNT_TYPE)
{
    struct perf_event_attr pe;
    memset(&pe, 0, sizeof(struct perf_event_attr));

    pe.type = PERF_TYPE_HARDWARE;
    pe.size = sizeof(struct perf_event_attr);
    pe.config = COUNT_TYPE;
    pe.disabled = 1;
    pe.exclude_kernel = 1;
    pe.exclude_hv = 1;

    long fd = perf_event_open(&pe, 0, -1, -1, 0);

    if (fd == -1) {
        fprintf(stderr, "Error opening leader %llx\n", pe.config);
        exit(EXIT_FAILURE);
    }

    ioctl(fd, PERF_EVENT_IOC_RESET, 0);
    ioctl(fd, PERF_EVENT_IOC_ENABLE, 0);

    return fd;
}

long long count_read(long fd) {
    long long count;
    ioctl(fd, PERF_EVENT_IOC_DISABLE, 0);
    read(fd, &count, sizeof(long long));
    close(fd);
    return count;
}

long instruction_start() {
    return counter_start(PERF_COUNT_HW_INSTRUCTIONS);
}
long branch_start() {
    return counter_start(PERF_COUNT_HW_BRANCH_INSTRUCTIONS);
}
long branch_miss_start() {
    return counter_start(PERF_COUNT_HW_BRANCH_MISSES);
}
long cache_reference_start() {
    return counter_start(PERF_COUNT_HW_CACHE_REFERENCES);
}
long cache_miss_start() {
    return counter_start(PERF_COUNT_HW_CACHE_MISSES);
}

Descriptors all_start() {
    Descriptors desc;
    desc.fds[0] = instruction_start();
    desc.fds[1] = branch_start();
    desc.fds[2] = branch_miss_start();
    desc.fds[3] = cache_reference_start();
    desc.fds[4] = cache_miss_start();
    return desc;
}

Counts all_read(Descriptors desc) {
    Counts counts;
    counts.data[0] = count_read(desc.fds[0]);
    counts.data[1] = count_read(desc.fds[1]);
    counts.data[2] = count_read(desc.fds[2]);
    counts.data[3] = count_read(desc.fds[3]);
    counts.data[4] = count_read(desc.fds[4]);
    return counts;
}
