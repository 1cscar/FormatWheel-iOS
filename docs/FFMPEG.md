# FFmpeg on iOS

上游 macOS 版用 `Process` 呼叫 Homebrew 的 `ffmpeg` / `ffprobe` / `cwebp`。iOS 不能執行外部程式，
而 FFmpegKit 已在 2025 年停止維護，所以本專案**自己從原始碼編譯 FFmpeg**，在 App 行程內呼叫。

## 方案評估

| 方案 | 優點 | 缺點 | 結論 |
|---|---|---|---|
| FFmpegKit（arthenica） | 現成 API、文件多 | 2025 年停止維護、二進位下架；最後版本是 FFmpeg 6.0；預設套件含 GPL 元件 | ✗ |
| kingslay/FFmpegKit（SwiftPM，FFmpeg 7/8） | 持續更新、有 iOS xcframework | 預設含 GPL 元件（需自己裁剪）、以 Swift Package plugin 建置，依賴上游 repo 節奏；fftools 入口要另外處理 | 參考其 configure 參數 |
| kewlbear/FFmpeg-iOS | 腳本簡單 | 只出靜態函式庫、沒有 fftools 入口、維護慢 | 參考 |
| 直接呼叫 libav* API 自寫轉檔 | 最乾淨 | 要重寫上游所有 ffmpeg 參數（濾鏡圖、palettegen、loudnorm…）的行為，風險高 | ✗ |
| **自建腳本：FFmpeg 靜態庫 + fftools 編進一個動態 framework，暴露極小 C API** | 參數字串沿用上游、LGPL 合規（動態）、完全掌控版本與元件、一個 framework 好嵌入 | 要自己處理 fftools 的 `exit()`、全域狀態、signal | **✓ 採用** |

## 產物

`scripts/build-ffmpeg.sh` 產生 `Vendor/FFmpeg/`：

| 檔案 | 內容 | 授權 | 連結方式 |
|---|---|---|---|
| `FWFFmpeg.xcframework` | FFmpeg 9.0.2（avcodec/avformat/avfilter/swscale/swresample/avutil）+ LAME 3.100 + Opus 1.6.1 + libvpx 1.17.0 + SVT-AV1 4.3.0 + libwebp 1.6.0 + fftools（ffmpeg 主程式）+ 膠水碼 | LGPL-2.1-or-later | **動態 framework**（可替換） |
| `WebP.xcframework` | libwebp + libwebpmux + libwebpdemux + libsharpyuv | BSD-3-Clause | 靜態（App 的 WebP 編碼器，取代 `cwebp`） |

Slice：`ios-arm64`（iphoneos）、`ios-arm64_x86_64-simulator`。最低 iOS 17.0。

### configure 重點

```
--disable-autodetect --disable-programs --enable-ffmpeg --disable-ffplay --disable-ffprobe
--disable-avdevice --disable-network --enable-pthreads --enable-zlib --enable-bzlib --enable-iconv
--enable-videotoolbox --enable-audiotoolbox
--enable-libmp3lame --enable-libopus --enable-libvpx --enable-libwebp --enable-libsvtav1
```

- **沒有** `--enable-gpl`、`--enable-nonfree`；腳本在 configure 後檢查 `config.h`（`CONFIG_GPL 0`、
  `CONFIG_NONFREE 0`），並確認必要的編碼器（libmp3lame、libopus、libvpx_vp9、libwebp、libsvtav1、
  h264/hevc_videotoolbox、aac、flac、alac、pcm_s16le）與濾鏡（loudnorm、palettegen、paletteuse、atempo、
  setpts、scale、fps、split、pad、format）都在，否則失敗。
- `PKG_CONFIG_LIBDIR` 指向每個 slice 自己的 prefix，避免抓到 Homebrew 的 macOS 函式庫。
- x86_64 模擬器 slice 關閉 x86 組語（只給模擬器用）。
- AV1 用 SVT-AV1 而不是 libaom：上游 AVIF 參數就是 `libsvtav1 -crf … -preset 6`，可以一字不改。

## in-process 執行（`scripts/ffmpeg/`）

| 檔案 | 作用 |
|---|---|
| `FWFFmpeg.h` | 對 Swift 暴露的 C API：`fw_ffmpeg_execute`、`fw_ffmpeg_cancel`、`fw_probe`、版本與能力查詢 |
| `fw_ffmpeg.c` | 直接 `#include "fftools/ffmpeg.c"`：把 `main` 改名為 `fw_ffmpeg_main_impl`；`exit()` 改成 `fw_tool_exit()`；`signal()` 改成 no-op（不碰 App 的 signal 設定）。每次執行前重設 ffmpeg.c 的檔案內 static（`received_sigterm`、`received_nb_signals`、`transcode_init_done`、`ffmpeg_exited`、`copy_ts_first_pts`）與會殘留的 CLI 全域選項 |
| `fw_exit.c` | `fw_tool_exit()`：在 session 執行緒上就 `longjmp` 回入口並回傳錯誤碼；在 ffmpeg 自己的工作執行緒上只結束該執行緒——**絕不讓 App 閃退** |
| `fw_probe.c` | 用 libavformat 讀時長、位元率、取樣率、聲道、容器與串流標籤（取代 `ffprobe`） |
| `fw_versions.c` | 各函式庫版本字串（設定頁「弹药状态」） |
| `exports.txt` | 只匯出 `fw_*` 符號 |

其他 fftools 物件（ffmpeg_dec/demux/enc/filter/mux/opt/sched…、cmdutils、opt_common、textformat、資源檔）
直接取自 FFmpeg 自己的 `make` 產出，原始碼不修改。

### Swift 端：`FFmpegRunner`（FormatWheelCore）

- `run(_ arguments:duration:progress:)`：參數字串與上游相同（不含程式名）。在 16 MB stack 的專用執行緒上呼叫
  `fw_ffmpeg_execute`。
- **一次一個 session**：Swift actor 依提交順序排隊，C 端另有互斥鎖。
- **進度**：上游的 `-progress pipe:1` 會被換成暫存檔，每 150 ms 讀最後一個 `out_time_us=`，除以時長得 0…1。
- **取消**：取消呼叫端的 Task → `fw_ffmpeg_cancel()`（等同 SIGINT）→ 拋出 `FWError.cancelled`（「已取消」）。
  半成品由呼叫端刪除（上游 `MediaOps.ff` 本來就在錯誤時刪除輸出）。
- **錯誤**：收集 `av_log` 中 error 等級以上的行，轉成上游風格的 `FWError("ffmpeg 出错：<最後一行>")`。
- `probe(_:)`：回傳 `Probe`（duration、bitRate、videoBitRate、sampleRate、channels、tags）。

測試：`Tests/CoreTests/FFmpegRunnerTests.swift`（`-version`、LGPL 與必要元件檢查、正弦波 → MP3 並讀回長度與聲道、
錯誤轉換、取消後可再次執行、三個並行請求依序完成）。

## 建置與快取

- 本機：`brew install cmake pkgconf nasm && scripts/build-ffmpeg.sh`（Apple Silicon 約 15–25 分鐘）。
  只要模擬器：`scripts/build-ffmpeg.sh --slices iphonesimulator-arm64`（本機建置時再加 `ARCHS=arm64`）。
- CI：`.github/workflows/ffmpeg.yml`（手動 `workflow_dispatch`）在 macOS runner 建置三個 slice，打包成
  `FWFFmpeg.xcframework.zip`、`WebP.xcframework.zip`、`SHA256SUMS`，發布到 Release **`ffmpeg-v9.0.2`**
  （prerelease，不會變成「最新版本」）。
- 平常的 CI 與開發者：`scripts/fetch-ffmpeg.sh` 下載該 Release 並驗證 SHA-256。
- 升級：改 `scripts/ffmpeg-versions.env` → 執行 ffmpeg workflow → CI 會自動抓新 tag。

## 替換 FFmpeg（LGPL §6）

使用者可以用 `scripts/build-ffmpeg.sh`（或修改過的版本）重新產生 `FWFFmpeg.framework`，再重新建置 App，
或直接替換 `.ipa` 內 `Payload/FormatWheel.app/Frameworks/FWFFmpeg.framework` 後重新簽章。詳見
`THIRD_PARTY_NOTICES.md`。
