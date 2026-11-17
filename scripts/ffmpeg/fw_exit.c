// exit() replacement for the fftools sources, compiled WITHOUT the exit macro.
#include <pthread.h>
#include <setjmp.h>
#include <stddef.h>

static __thread jmp_buf *fw_jump;
static __thread int fw_code;

void fw_exit_set_jump(jmp_buf *jump) { fw_jump = jump; }
int fw_exit_code(void) { return fw_code; }

__attribute__((noreturn)) void fw_tool_exit(int code) {
    if (fw_jump) {
        fw_code = code;
        longjmp(*fw_jump, 1);
    }
    // exit() from one of ffmpeg's worker threads: end only that thread, never the app.
    pthread_exit(NULL);
}
