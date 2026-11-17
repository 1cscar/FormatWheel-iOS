# FormatWheel iOS 移植計畫

上游：[Elise616/FormatWheel](https://github.com/Elise616/FormatWheel) @ `1eb19a1`（MIT）。macOS 選單列 App，
Swift + AppKit，20 個 Swift 檔、約 6,200 行，`Catalog.allIDs` 共 **73 個動作 ID**。

最高原則：**保留完整功能**。不能照搬的功能一律做等效替代，並在 [PARITY.md](PARITY.md) 標 ⚠️。

---

## 1. 架構

```
┌──────────────────────────── App (iOS target) ─────────────────────────────┐
│ SwiftUI：首頁／匯入、設定、最近轉換、清單模式（VoiceOver）、App Intents    │
│ UIKit：WheelView / StatsPanel / WantedView / Banner / BusyHUD（CoreGraphics）│
│ 平台注入：UIPasteboard、WKWebView（舊 .doc）、UIPrintPageRenderer（doc→pdf）│
│          NSAttributedString RTF/HTML 編解碼、相簿、分享、在「檔案」中顯示    │
└───────────────┬──────────────────────────────────────┬────────────────────┘
                │                                      │
┌───────────────▼─────────── FormatWheelCore ──┐ ┌─────▼──── FormatWheelArt ─────┐
│ Catalog · Engine · Support(Out/Fmt/FWError)  │ │ Glyphs · Weapons · Drawing    │
│ ImageOps · PDFOps · MediaOps · DocOps        │ │ Theme(Crew/WheelSize/IconStyle│
│ Privacy · GenericOps · Zip · Output          │ │ /Fonts) · SFX(AVAudioEngine)  │
│ FFmpegRunner · Tools(能力偵測) · Platform 協定│ │ Icons(App 圖示)               │
│ 不得 import UIKit / AppKit / SwiftUI          │ │ CoreGraphics / CoreText 純繪圖 │
└───────┬───────────────────────┬──────────────┘ └───────────────────────────────┘
        │                       │
┌───────▼──────────┐   ┌────────▼────────┐   ┌──────────────┐
│ FWFFmpeg.xcfw     │   │ WebP.xcfw       │   │ ZIPFoundation│
│ 動態、LGPL         │   │ 靜態、BSD        │   │ MIT（P1 加入）│
└──────────────────┘   └─────────────────┘   └──────────────┘
```

- **FormatWheelCore**（本地 Swift Package，動態 library）：上游 `Catalog / Engine / Support / ImageOps / PDFOps /
  MediaOps / DocOps / Privacy` 的移植。所有需要 UI 框架的能力透過 `Platform` 協定由 App 注入：
  - `Clipboard`（UIPasteboard）
  - `LegacyDocReader`（離屏 WKWebView 讀舊版 .doc → HTML）
  - `RichTextCodec`（NSAttributedString ⇄ RTF / HTML；iOS 上 `DocumentType` 宣告在 UIKit）
  - `PDFTypesetter`（UIMarkupTextPrintFormatter + UIPrintPageRenderer，A4 分頁）
  - `OutputDestination`（Documents/FormatWheel、自選資料夾 bookmark、相簿）
- **Tools**：取代上游 `Shell.has(...)`。回報裝置能力：FFmpeg 是否可用、HEIC/AVIF 編碼器（ImageIO
  `CGImageDestinationCopyTypeIdentifiers()`）、FLAC 編碼器（AudioToolbox）。可在測試中覆寫，以驗證上游的
  「沒有 ffmpeg」備援路徑。
- **FFmpegRunner**：in-process 執行 `ffmpeg`，支援進度、取消、排隊；`probe()` 用 libavformat 取代 ffprobe。
- **FormatWheelArt**：上游 `Glyphs / Weapons / Drawing / Theme / SFX` 的移植，`NSColor/NSFont/NSImage` 改成
  `CGColor/CTFont/CGImage`，App、快照測試、圖示腳本共用。
- **App**：SwiftUI 外殼 + UIKit 輪盤（UIViewRepresentable 嵌入）。

### 執行流程（對應上游 Runner）

1. 取得檔案（選取器、PHPicker、拖放、貼上、分享／以…開啟）→ 複製到 App 的工作暫存區（安全範圍 URL 只在讀取時存取）。
2. `Catalog.context(for:)` 產生頁面與槽位；背景 `Privacy.scan` 顯示通緝星等。
3. 手勢選槽 → `Engine.run(id, files)`（`beginBackgroundTask`／iOS 26+ `BGContinuedProcessingTask`）。
4. 輸出寫入 `OutputDestination`（預設 `Documents/FormatWheel/`，`Out.unique` 命名與衝突處理沿用上游）。
5. HUD：上膛音 → 0.3 秒後 MISSION PASSED／甩掉警察；失敗 WASTED。橫幅提供分享、在「檔案」中顯示、存到相簿。
6. 加入「最近轉換」（8 筆，可重開或分享）。

---

## 2. macOS → iOS 對照表

| 上游 | iOS 替代 | PARITY |
|---|---|---|
| `Shell.run` / `Process` | 一律不用；改 `FFmpegRunner` 或 Swift/C 函式庫 | — |
| ffmpeg（AVIF、WebM、MP3、Opus、變速、響度、GIF 調色盤） | 自編 FFmpeg 9.0.2，參數字串沿用上游 | ✅ 目標 |
| ffmpeg `libx264`（vid.to.mp4/mov 備援、vid.compress、vid.720p 備援、vid.fast/slow） | x264 是 GPL，禁用 → `h264_videotoolbox`：`-crf` 換成 `-q:v`（crf 20→65、27→50），裝置不支援時依原片位元率換算 `-b:v`（規則見 PARITY.md 第 5 節） | ⚠️ |
| ffprobe（時長、位元率、影音標籤） | `FFmpegRunner.probe`（libavformat） | ✅ 目標 |
| cwebp `-q -mt -metadata icc` | libwebp：`WebPConfig.quality`、`thread_level=1`、ICC 以 WebPMux 寫入 | ✅ 目標 |
| AVIF：ffmpeg libsvtav1 | 有 `public.avif` 編碼器就用 ImageIO，否則 FFmpeg libsvtav1（同參數） | ✅ 目標 |
| textutil | DocxReader/Writer、ODTReader/Writer（ZIP+XML）；舊 .doc 讀取：WKWebView；.doc 寫出：RTF 內容 + .doc 副檔名；doc→pdf：UIMarkupTextPrintFormatter + UIPrintPageRenderer | ⚠️（.doc 寫出、排版細節） |
| NSPrintOperation + NSTextView（A4，邊界 56/60） | UIPrintPageRenderer，同樣 595×842、同邊界 | ✅ 目標 |
| afconvert | AVAssetReader/Writer、ExtAudioFile；FLAC 編碼器執行時偵測，不行就 FFmpeg `flac` | ✅ 目標 |
| ditto / zip / unzip | ZIPFoundation | ✅ 目標（無 AppleDouble 資源分支，iOS 檔案沒有） |
| QuartzFilter「Gray Tone」（pdf.mono） | 逐頁灰階點陣化（150／200／300 dpi，預設 200）＋隱形文字層（優先用原文字層，否則 Vision OCR），逐頁串流 | ⚠️ |
| NSPasteboard | UIPasteboard | ✅ 目標 |
| NSWorkspace 圖示／在 Finder 顯示 | QLThumbnailGenerator／在「檔案」顯示（`shareddocuments://`）／分享表單 | ⚠️ |
| 開機啟動（SMAppService） | 不適用 → 「觸覺回饋」開關 | ⚠️ |
| 輸出存在原檔旁（不可寫就到「下載」） | 預設 `Documents/FormatWheel/`；可選資料夾（security-scoped bookmark）；圖片／影片可自動存相簿；每次都可分享 | ⚠️ |
| 命令列模式 | App Intents：「列出可用動作」「對檔案執行動作」「掃描隱私資訊」；`--glyphs/--weapons/--sounds` → 隱藏開發者選單匯出 ZIP；`--snapshot/--banner` → XCTest 快照；`--icon` → 圖示腳本 | ⚠️ |
| DragWatcher（全域拖曳＋Shift） | 長按 0.25 秒；拖放懸停；iPad 實體鍵盤 Shift | ⚠️ |
| NSPanel 全螢幕覆蓋＋NSVisualEffectView | App 內全螢幕 UIView＋UIVisualEffectView | ✅ 目標 |
| 長時間任務 | `beginBackgroundTask`；iOS 26+ `BGContinuedProcessingTask` | — |
| Vision 去背／OCR | 相同 API（iOS 17+） | ✅ 目標 |
| `gen.path` 複製 POSIX 路徑 | 複製「檔案」App 中的位置或 file URL | ⚠️ |
| 字型 Avenir Next Condensed、PingFang SC、Impact | iOS 內建 Avenir Next Condensed、PingFang SC/TC；Impact 不存在 → 以 Avenir Next Condensed Heavy 斜體近似 | ⚠️ |
| 日誌 `~/Library/Logs/FormatWheel.log` | `Library/Logs/FormatWheel.log`（App 容器內），開發者選單可匯出 | ⚠️ |
| AppKit 選單列圖示 | 無選單列 → 輪盤小圖示用於 App 內 | ⚠️ |

---

## 3. 互動設計

| 上游（macOS） | iOS / iPadOS |
|---|---|
| Finder 拖住檔案按 ⇧ Shift 開輪盤 | 長按畫面任意處 ~0.25 秒，輪盤以手指為中心展開；iPad 實體鍵盤按住 Shift 在指標位置展開；從其他 App 拖檔案懸停時直接展開，放開手指就執行 |
| 選單「選擇文件打開輪盤…」（點選模式） | 「檔案」選取器（多選、可選資料夾）、PHPicker（`loadFileRepresentation` 保留原始 HEIC 與 EXIF）、貼上、分享／以…開啟 |
| 朝格子方向移動，鬆開滑鼠執行 | 往槽位方向滑或甩；進入槽位播 tick + `UISelectionFeedbackGenerator`；放開執行 |
| 移回中心再鬆開 = 取消；Esc／右鍵取消 | 滑回中心取消；iPad 鍵盤 Esc |
| 再按 Shift／Tab／Q／E／滾輪換頁 | 雙指點擊或點中心頁籤；iPad 鍵盤 Tab（Q／E）；觸控板捲動 |
| Return／Space 選取（點選模式） | iPad 鍵盤 Return／Space |
| 右下角「正在处理 · …%（还有 n 个）」 | App 內 BusyHUD，顯示進度與取消鈕；取消時刪除半成品 |
| MISSION PASSED／WASTED 橫幅 | 同樣動畫與文案；按鈕：分享、在「檔案」中顯示、存到相簿 |
| 去隱私後通緝星閃爍消失 | 相同（WantedHUD） |
| 首次啟動自動示範、「看看效果（演示）」 | 首次啟動示範＋設定頁「看看效果」 |
| — | VoiceOver 開啟時改用可點選的清單模式 |
| 音效 | AVAudioEngine，audio session `.ambient`，不打斷音樂 |

---

## 4. 階段與驗收標準

| 階段 | 內容 | 驗收 |
|---|---|---|
| **P0 偵察與骨架** | upstream 快照、CLAUDE.md、本計畫、PARITY.md、XcodeGen 專案、兩個 Package、測試 target、Info.plist、CI、FFmpeg spike | CI 綠燈、有 IPA artifact、FFmpeg 在 iOS in-process 執行（`-version`、正弦波 → MP3） |
| **P1 Core：圖片、PDF、通用** | Catalog、Engine、Support、ImageOps、PDFOps、Privacy（圖片＋PDF）、gen.*；「未裝備」改依裝置能力；OutputDestination | 每個 img.* / pdf.*（除 pdf.to.docx）/ gen.* 至少一個測試；輸出可讀回；strip 後 metadata 消失；通緝星等與上游一致 |
| **P2 影音** | MediaOps、Privacy（影音）、完整 FFmpegRunner（進度、取消、FWError、排隊）、串流處理、背景任務、probe 掃描 | 每個 vid.* / aud.* 測試格式、長度、聲道數 |
| **P3 文件** | DocOps、Docx/ODT 讀寫、LegacyDoc、doc.to.pdf、Markdown、doc.strip、pdf.to.docx | docx→odt→docx、md→docx→md 來回不掉字、保留粗體與標題；docx 結構合法 |
| **P4 UI 與互動** | Art 移植、WheelView/Overlay/HUD、全部互動、設定頁、在地化、快照測試、示範影片 | 快照：兩種圖示模式 × 四種主題 × iPhone/iPad；docs/media/ 有操作影片 |
| **P5 系統整合** | App Intents＋docs/SHORTCUTS.md、以…開啟、選用 Share Extension（另一個 IPA）、無障礙稽核 | 捷徑三動作可用；FormatWheel-with-share.ipa 產出 |
| **P6 發布 v1.0.0** | release.yml、AltStore 來源、App 圖示腳本、README、THIRD_PARTY_NOTICES、rc1 演練 | PARITY.md 無 ⬜；全部測試通過；v1.0.0-rc1 流程跑通後發 v1.0.0 |

每階段 CI 綠燈後回報並等「繼續」。

---

## 5. 風險

| # | 風險 | 影響 | 對策 |
|---|---|---|---|
| R1 | FFmpeg 在 iOS in-process 執行：fftools 有全域狀態、會呼叫 `exit()`、安裝 signal handler | 閃退、第二次執行出錯 | `fw_ffmpeg.c` 直接 `#include` ffmpeg.c，把 `main` 改名、`exit()` 改成 longjmp 回入口（非 session 執行緒則只結束該執行緒）、`signal()` 改成 no-op；每次執行前重設檔案內 static 與 CLI 全域選項；C 端互斥鎖＋Swift actor 確保一次一個 session（P0 已驗證） |
| R2 | 上游大量使用 `libx264`（GPL）；模擬器可能沒有 VideoToolbox 編碼器 | 不能用；測試不穩 | 改 `h264_videotoolbox`，`-q:v`／`-b:v` 換算（PARITY 第 5 節）；測試先偵測編碼器，不能用就 `XCTSkip` 並寫明原因 |
| R3 | FFmpeg 建置時間長（CI 約 1–2 小時） | CI 變慢 | 只在 `ffmpeg.yml` 手動建置並發布到 `ffmpeg-v<版本>` Release；一般 CI 只下載 |
| R4 | 免費 Apple ID 側載：7 天重簽、3 個 App、每週 10 個 App ID | 使用者麻煩 | Share Extension 預設不包含（會多佔 App ID）；README 說明 |
| R5 | iOS 沒有 textutil，Word/ODT 讀寫要自己做 | 文件轉換保真度下降 | 自寫 Docx/ODT（段落、標題、粗斜體底線、清單、超連結、表格、內嵌圖片）；來回轉換測試；.doc 寫出標 ⚠️ |
| R6 | `pdf.mono` 依賴 macOS QuartzFilter（向量灰階） | iOS 無等效 API | **已決定**：灰階點陣化（預設 200 dpi）＋隱形文字層（原文字優先，否則 OCR），逐頁串流；檔案可能變大；PARITY 標 ⚠️ |
| R7 | Vision 前景遮罩在模擬器上不可用（只有 simulator GPU，「Could not create inference context」） | img.cutout 測試 | 已確認。App 改顯示「这台设备跑不了抠图模型」；測試偵測到這個錯誤時 XCTSkip 並寫明原因（同 VideoToolbox 規則，待使用者確認），需實機驗證 |
| R8 | Extension 記憶體上限約 120 MB | Share Extension 轉檔會被殺 | Extension 只透過 App Group 轉交檔案，不在 extension 內轉檔 |
| R9 | 背景執行時間有限 | 長影片轉檔被中止 | `beginBackgroundTask`；iOS 26+ `BGContinuedProcessingTask`；中止時清除半成品並顯示 WASTED |
| R10 | GitHub macOS runner 映像與 Xcode 版本變動 | CI 突然壞掉 | `setup-xcode latest-stable`；模擬器動態挑選（`scripts/test.sh`） |
| R12 | iOS PDFKit：寫出選項無效、記憶體中新建的頁面連結會寫壞、`PDFAnnotation.copy()` 遺失資料 | pdf.compress／pdf.mono 結果錯誤 | 自寫 `PDFWriter`（CGPDF 物件逐一序列化）處理圖片重壓與頁面組裝 |
| R11 | 任務說明寫 75 個動作，上游 `Catalog.allIDs` 實際 73 個 | 範圍認知不一致 | **已確認**：以 73 為準 |
