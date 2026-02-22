#include <stdint.h>
#include <sys/stat.h>
#include <errno.h>

#undef errno
extern int errno;

#define UART_ADDR ((volatile uint32_t*)0x100)

// Heap management for malloc/printf
extern char _end;
extern char __heap_start;
static char *heap_ptr = NULL;

void *_sbrk(int incr) {
    char *prev_heap;
    
    // Initialize heap pointer on first call
    if (heap_ptr == NULL) {
        heap_ptr = &_end;
    }
    
    prev_heap = heap_ptr;
    heap_ptr += incr;
    
    return (void *)prev_heap;
}

// UART write
int _write(int file, const char *ptr, int len) {
    for (int i = 0; i < len; i++)
        *UART_ADDR = ptr[i];
    return len;
}

// File operations
int _close(int file) { 
    errno = EBADF;
    return -1; 
}

int _lseek(int file, int ptr, int dir) { 
    return 0; 
}

int _read(int file, char *ptr, int len) { 
    return 0; 
}

int _fstat(int file, struct stat *st) { 
    st->st_mode = S_IFCHR;
    return 0; 
}

int _isatty(int file) { 
    return 1; 
}

// Process operations (needed by exit/abort)
void _exit(int status) {
    while (1);  // Hang forever
}

int _kill(int pid, int sig) {
    errno = EINVAL;
    return -1;
}

int _getpid(void) {
    return 1;
}

// Link (not supported)
int _link(const char *old, const char *new) {
    errno = EMLINK;
    return -1;
}

// Unlink (not supported)
int _unlink(const char *name) {
    errno = ENOENT;
    return -1;
}

// Environment (empty)
char **environ = NULL;
