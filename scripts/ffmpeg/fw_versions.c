// Versions of everything inside FWFFmpeg.framework, for the app's "弹药状态" row.
#include <stdio.h>
#include "lame/lame.h"
#include "opus/opus.h"
#include "vpx/vpx_codec.h"
#include "svt-av1/EbSvtAv1Enc.h"
#include "webp/encode.h"
#include "libavutil/ffversion.h"
#include "FWFFmpeg.h"

const char *fw_component_versions(void) {
    static char text[512];
    if (!text[0]) {
        int webp = WebPGetEncoderVersion();
        snprintf(text, sizeof(text),
                 "FFmpeg %s\nLAME %s\n%s\nlibvpx %s\nSVT-AV1 %s\nlibwebp %d.%d.%d",
                 FFMPEG_VERSION, get_lame_version(), opus_get_version_string(), vpx_codec_version_str(),
                 svt_av1_get_version(), (webp >> 16) & 0xff, (webp >> 8) & 0xff, webp & 0xff);
    }
    return text;
}
