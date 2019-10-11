
#include <sys/time.h>

double current_time() {
    struct timeval v;
    gettimeofday(&v, NULL);
    return v.tv_sec + v.tv_usec / 1000000.0;
}
