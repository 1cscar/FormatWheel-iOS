// In-process ffmpeg entry point. Includes fftools/ffmpeg.c directly so its file-static state
// (signal counters, init flags) can be reset between runs and so main() can be renamed.
#include <pthread.h>
#include <setjmp.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>

// Never touch the host app's signal dispositions; cancellation goes through fw_ffmpeg_cancel().
#define signal(sig, handler) ((void)(sig), (void)(handler), SIG_DFL)
// Never terminate the host app.
__attribute__((noreturn)) void fw_tool_exit(int code);
#define exit(code) fw_tool_exit(code)
#define main fw_ffmpeg_main_impl

#include "fftools/ffmpeg.c"

#undef main
#undef exit
#undef signal

#include "libavutil/ffversion.h"
#include "FWFFmpeg.h"

void fw_exit_set_jump(jmp_buf *jump);
int fw_exit_code(void);

static pthread_mutex_t fw_run_lock = PTHREAD_MUTEX_INITIALIZER;
static fw_log_callback fw_log_fn;
static void *fw_log_ctx;
static volatile int fw_running;

static void fw_log(void *avcl, int level, const char *fmt, va_list vl) {
    if (level > av_log_get_level() || !fw_log_fn) return;
    char line[2048];
    int print_prefix = 1;
    av_log_format_line2(avcl, level, fmt, vl, line, sizeof(line), &print_prefix);
    size_t n = strlen(line);
    while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r')) line[--n] = 0;
    if (n > 0) fw_log_fn(fw_log_ctx, level, line);
}

int fw_ffmpeg_execute(int argc, char **argv, fw_log_callback log, void *context) {
    pthread_mutex_lock(&fw_run_lock);
    received_sigterm = 0;
    received_nb_signals = 0;
    atomic_store(&transcode_init_done, 0);
    ffmpeg_exited = 0;
    copy_ts_first_pts = AV_NOPTS_VALUE;
    // Options that are process globals in the CLI and would otherwise leak into the next run.
    stdin_interaction = 1;
    print_stats = -1;
    do_benchmark = 0;
    do_benchmark_all = 0;
    copy_ts = 0;
    start_at_zero = 0;
    exit_on_error = 0;

    fw_log_fn = log;
    fw_log_ctx = context;
    av_log_set_level(AV_LOG_INFO);
    av_log_set_flags(0);
    av_log_set_callback(fw_log);
    fw_running = 1;

    jmp_buf jump;
    int ret;
    fw_exit_set_jump(&jump);
    if (setjmp(jump) == 0) {
        ret = fw_ffmpeg_main_impl(argc, argv);
    } else {
        ret = fw_exit_code();
    }
    fw_exit_set_jump(NULL);

    fw_running = 0;
    // -version / -h install cmdutils' stdout printer; always restore ours with no sink.
    fw_log_fn = NULL;
    fw_log_ctx = NULL;
    av_log_set_callback(fw_log);
    pthread_mutex_unlock(&fw_run_lock);
    return ret;
}

void fw_ffmpeg_cancel(void) {
    if (fw_running && received_nb_signals == 0) {
        received_sigterm = SIGINT;
        received_nb_signals = 1;
    }
}

const char *fw_ffmpeg_version(void) { return FFMPEG_VERSION; }
const char *fw_ffmpeg_configuration(void) { return avcodec_configuration(); }
const char *fw_ffmpeg_license(void) { return avcodec_license(); }

int fw_has_encoder(const char *name) { return avcodec_find_encoder_by_name(name) != NULL; }
int fw_has_filter(const char *name) { return avfilter_get_by_name(name) != NULL; }
