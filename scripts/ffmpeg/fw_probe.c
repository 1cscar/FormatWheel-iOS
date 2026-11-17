// libavformat probe used instead of the ffprobe executable (duration, bit rate, sample rate, tags).
#include <stdio.h>
#include <string.h>
#include "libavformat/avformat.h"
#include "libavutil/dict.h"
#include "FWFFmpeg.h"

static size_t append_tags(AVDictionary *dict, char *out, size_t used, size_t size) {
    const AVDictionaryEntry *e = NULL;
    while (out && (e = av_dict_iterate(dict, e))) {
        if (used + 1 >= size) break;
        int n = snprintf(out + used, size - used, "%s=%s\n", e->key, e->value ? e->value : "");
        if (n < 0) break;
        used += (size_t)n < size - used ? (size_t)n : size - used - 1;
    }
    return used;
}

int fw_probe(const char *path, fw_probe_result *result, char *tags, size_t tags_size) {
    memset(result, 0, sizeof(*result));
    if (tags && tags_size) tags[0] = 0;
    AVFormatContext *fmt = NULL;
    int ret = avformat_open_input(&fmt, path, NULL, NULL);
    if (ret < 0) return ret;
    ret = avformat_find_stream_info(fmt, NULL);
    if (ret < 0) { avformat_close_input(&fmt); return ret; }

    if (fmt->duration != AV_NOPTS_VALUE && fmt->duration > 0) result->duration = fmt->duration / (double)AV_TIME_BASE;
    result->bit_rate = fmt->bit_rate > 0 ? fmt->bit_rate : 0;
    size_t used = append_tags(fmt->metadata, tags, 0, tags_size);
    for (unsigned i = 0; i < fmt->nb_streams; i++) {
        AVStream *st = fmt->streams[i];
        AVCodecParameters *par = st->codecpar;
        if (par->codec_type == AVMEDIA_TYPE_VIDEO && !(st->disposition & AV_DISPOSITION_ATTACHED_PIC)) {
            if (!result->has_video) result->video_bit_rate = par->bit_rate > 0 ? par->bit_rate : 0;
            result->has_video = 1;
        } else if (par->codec_type == AVMEDIA_TYPE_AUDIO) {
            if (!result->has_audio) {
                result->sample_rate = par->sample_rate;
                result->channels = par->ch_layout.nb_channels;
            }
            result->has_audio = 1;
        }
        used = append_tags(st->metadata, tags, used, tags_size);
    }
    avformat_close_input(&fmt);
    return 0;
}
