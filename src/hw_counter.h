typedef struct {
    long fds[5];
} Descriptors;

typedef struct {
    long long data[5];
} Counts;

// These functions return a file-descriptor that
// can be passed to the count_read function
long instruction_start();
long branch_start();
long branch_miss_start();
long cache_reference_start();
long cache_miss_start();

// expects a file descriptor that was created by
// one of the "foo_start" functions above
long long count_read(long);

// open each metric and return an array of descriptors
Descriptors all_start();

// read from descriptors returned by all_start
Counts all_read(Descriptors);

