// FWFFmpeg — the small C surface the app uses to run FFmpeg in-process.
// Built by scripts/build-ffmpeg.sh into FWFFmpeg.framework (dynamic, LGPL-2.1-or-later).
#ifndef FWFFMPEG_H
#define FWFFMPEG_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Receives every log line FFmpeg prints at or above the active -loglevel. `level` is an AV_LOG_* value
/// (8 = fatal, 16 = error, 24 = warning, 32 = info). Called on FFmpeg's own threads.
typedef void (*fw_log_callback)(void *_Nullable context, int level, const char *_Nonnull line);

/// Runs the `ffmpeg` command line tool in-process. argv[0] should be "ffmpeg".
/// Blocks until the run finishes; at most one run at a time (others wait on an internal lock).
/// Returns the tool's exit code (0 = success, 255 = cancelled). Never calls exit().
int fw_ffmpeg_execute(int argc, char *_Nonnull *_Nonnull argv, fw_log_callback _Nullable log, void *_Nullable context);

/// Asks the running ffmpeg (if any) to stop as if it got SIGINT. Safe to call from any thread.
void fw_ffmpeg_cancel(void);

/// Basic container facts, read with libavformat (replaces the ffprobe calls of the macOS app).
typedef struct fw_probe_result {
    double duration;        // seconds, 0 when unknown
    int64_t bit_rate;       // container bit rate in bit/s, 0 when unknown
    int64_t video_bit_rate; // first video stream bit rate, 0 when unknown
    int sample_rate;        // first audio stream sample rate, 0 when unknown
    int channels;           // first audio stream channel count, 0 when unknown
    int has_video;
    int has_audio;
} fw_probe_result;

/// Probes a media file. Container and stream tags are written into `tags` as "key=value\n" lines
/// (format tags first, then stream tags), truncated to `tags_size`. Returns 0 on success, a negative
/// AVERROR code otherwise.
int fw_probe(const char *_Nonnull path, fw_probe_result *_Nonnull result, char *_Nullable tags, size_t tags_size);

/// "9.0.2" etc.
const char *_Nonnull fw_ffmpeg_version(void);
/// Human readable list of the bundled libraries and their versions, one per line.
const char *_Nonnull fw_component_versions(void);
/// The FFmpeg configure line this framework was built with (to verify it is LGPL, no --enable-gpl).
const char *_Nonnull fw_ffmpeg_configuration(void);
/// "LGPL version 2.1 or later" for this build.
const char *_Nonnull fw_ffmpeg_license(void);
/// 1 when the named encoder (e.g. "libmp3lame", "h264_videotoolbox") is compiled in.
int fw_has_encoder(const char *_Nonnull name);
/// 1 when the named filter (e.g. "loudnorm") is compiled in.
int fw_has_filter(const char *_Nonnull name);

#ifdef __cplusplus
}
#endif

#endif
