# 功能對照表（PARITY）

> 由 `scripts/gen-parity.py` 依 `scripts/parity_data.py` 產生，請改資料檔後重新產生。

上游：Elise616/FormatWheel @ `1eb19a1`。動作 ID 以上游 `Catalog.allIDs` 為準：**73 個**。

狀態：⬜ 未開始 · 🟨 進行中 · ✅ 完成且有測試 · ⚠️ 有差異（見備註）

動作進度：⬜ 73

## 1. 動作（73）

| # | ID | 類別 | 上游檔案與函式 | macOS 專屬依賴 | iOS 實作 | 狀態 | 備註 |
|---|---|---|---|---|---|---|---|
| 1 | `img.to.png` | 圖片 | ImageOps.convert → write(png) | — | ImageIO（同上游） | ⬜ |  |
| 2 | `img.to.jpg` | 圖片 | ImageOps.convert → write(jpg, q0.9, flatten) | — | ImageIO（同上游） | ⬜ |  |
| 3 | `img.to.heic` | 圖片 | ImageOps.convert → write(heic, q0.82) | — | ImageIO；裝置沒有 HEIC 編碼器時槽位「未装备」 | ⬜ | 上游一律可用；iOS 依 `CGImageDestinationCopyTypeIdentifiers()` 判斷 |
| 4 | `img.to.webp` | 圖片 | ImageOps.writeWebP（cwebp -q 84 -mt -metadata icc） | cwebp（Homebrew） | libwebp：quality 84、thread_level 1、ICC 以 WebPMux 寫入 | ⬜ | 上游沒裝 cwebp 時「未装备」；iOS 內建 libwebp，永遠可用 |
| 5 | `img.to.pdf` | 圖片 | ImageOps.convert → PDFMaker.write；多張 → PDFOps.merge（合并成 PDF） | — | CGContext PDF（同上游） | ⬜ | 多檔邏輯沿用 Engine.run 特例 |
| 6 | `img.to.avif` | 圖片 | ImageOps.writeAVIF（ffmpeg libsvtav1 -crf (52-q*34) -preset 6, yuv420p, 先鋪白） | ffmpeg | ImageIO 有 `public.avif` 編碼器就用，否則 FFmpeg libsvtav1（同參數） | ⬜ |  |
| 7 | `img.to.gif` | 圖片 | ImageOps.convert → write(gif) | — | ImageIO（同上游） | ⬜ |  |
| 8 | `img.to.tiff` | 圖片 | ImageOps.convert → write(tiff, LZW) | — | ImageIO（同上游） | ⬜ |  |
| 9 | `img.compress` | 圖片 | ImageOps.compress（≤4096、同格式降品質、透明 PNG→WebP、shrinkResult） | cwebp（透明圖） | ImageIO + libwebp | ⬜ | 「已经很小了，压不动了」沿用 |
| 10 | `img.half` | 圖片 | ImageOps.half（長寬各半，note = 尺寸） | — | CoreGraphics（同上游） | ⬜ |  |
| 11 | `img.cutout` | 圖片 | ImageOps.cutout（VNGenerateForegroundInstanceMaskRequest → 透明 PNG） | — | Vision（iOS 17+，同 API） | ⬜ | 見風險 R7（模擬器能力） |
| 12 | `img.ocr` | 圖片 | ImageOps.ocr（VNRecognizeTextRequest zh-Hans/zh-Hant/en → .txt + 剪貼簿） | NSPasteboard | Vision + 注入的 UIPasteboard | ⬜ |  |
| 13 | `img.mono` | 圖片 | ImageOps.mono（CIPhotoEffectMono） | — | CoreImage（同上游） | ⬜ |  |
| 14 | `img.rotate` | 圖片 | ImageOps.rotate（順時針 90°） | — | CoreGraphics（同上游） | ⬜ |  |
| 15 | `img.strip` | 圖片 | ImageOps.strip（CGImageDestinationCopyImageSource 去 GPS/XMP，不重新編碼；否則重寫） | — | ImageIO（同上游） | ⬜ | 測試需驗證 GPS 與機型真的消失 |
| 16 | `img.backdrop` | 圖片 | ImageOps.backdrop（漸層、9% 邊距、圓角、陰影 → PNG） | — | CoreGraphics（同上游） | ⬜ |  |
| 17 | `pdf.to.png` | PDF | PDFOps.toImages(png, scale 2；多頁 → 資料夾 base-NN) | — | CGPDF + ImageIO（同上游） | ⬜ |  |
| 18 | `pdf.to.jpg` | PDF | PDFOps.toImages(jpg q0.9) | — | CGPDF + ImageIO（同上游） | ⬜ |  |
| 19 | `pdf.to.long` | PDF | PDFOps.longImage（寬 1242、間距 16、>60000px 分段、最多 120 頁） | — | CoreGraphics（同上游） | ⬜ | 「只拼了前 N 页」沿用 |
| 20 | `pdf.to.docx` | PDF | PDFOps.toText → DocOps.write(docx)（NSAttributedString → officeOpenXML） | AppKit DocumentType.officeOpenXML | PDFKit 段落重建（同上游）+ 自寫 DocxWriter | ⬜ | P3 |
| 21 | `pdf.to.txt` | PDF | PDFOps.toText(txt)（PDFSelection 逐行重組段落、TextFix.radicals） | — | PDFKit（同上游） | ⬜ |  |
| 22 | `pdf.to.md` | PDF | PDFOps.toText → Markdown.from（字級推斷標題） | NSFont | PDFKit + CTFont 取字級／粗體 | ⬜ |  |
| 23 | `pdf.to.rtf` | PDF | PDFOps.toText → NSAttributedString RTF | AppKit DocumentType.rtf | 注入的 RichTextCodec（UIKit NSAttributedString RTF） | ⬜ |  |
| 24 | `pdf.to.html` | PDF | PDFOps.toText → NSAttributedString HTML | AppKit DocumentType.html | 注入的 RichTextCodec（HTML） | ⬜ |  |
| 25 | `pdf.compress` | PDF | PDFOps.compress（PDFDocument.write saveImagesAsJPEG + optimizeImagesForScreen） | — | PDFKit 寫出選項（iOS 16+） | ⬜ | 「这个 PDF 已经很精简了」沿用 |
| 26 | `pdf.split` | PDF | PDFOps.split（每頁一檔 → 資料夾「拆分」） | — | PDFKit（同上游） | ⬜ |  |
| 27 | `pdf.merge` | PDF | PDFOps.merge（PDF 與圖片依拖入順序合併） | — | PDFKit（同上游） | ⬜ | 少於 2 個 PDF 時停用（同上游） |
| 28 | `pdf.rotate` | PDF | PDFOps.rotate（每頁 +90°） | — | PDFKit（同上游） | ⬜ |  |
| 29 | `pdf.mono` | PDF | PDFOps.mono（QuartzFilter「Gray Tone」重繪，文字保持向量） | QuartzFilter（macOS 專屬） | 逐頁以灰階點陣化（設定 150／200／300 dpi，預設 200），保留頁面尺寸與旋轉；加上看不見的文字層：原 PDF 有可抽取文字就用原文字與位置，否則用 pdf.ocr 的 Vision 流程；逐頁串流 | ⬜ | 預計 ⚠️：見第 5 節「pdf.mono」 |
| 30 | `pdf.ocr` | PDF | PDFOps.ocr（逐頁渲染 + Vision） | NSPasteboard | CGPDF + Vision + UIPasteboard | ⬜ |  |
| 31 | `pdf.strip` | PDF | Privacy.stripPDF（清作者、軟體、主題、關鍵詞、日期） | — | PDFKit（同上游） | ⬜ |  |
| 32 | `vid.to.mp4` | 影片 | MediaOps.video（AVAssetExportSession passthrough／HighestQuality；不支援時 ffmpeg libx264 crf 20） | ffmpeg libx264（備援） | AVFoundation；備援 FFmpeg `h264_videotoolbox` | ⬜ | 預計 ⚠️：x264 為 GPL。換算規則見第 5 節「libx264 → h264_videotoolbox」 |
| 33 | `vid.to.mov` | 影片 | 同上，mov | ffmpeg libx264（備援） | AVFoundation；備援 FFmpeg `h264_videotoolbox` | ⬜ | 預計 ⚠️：x264 為 GPL。換算規則見第 5 節「libx264 → h264_videotoolbox」 |
| 34 | `vid.to.hevc` | 影片 | ffmpeg hevc_videotoolbox -b:v 來源/2（1.2–25 Mbps）；無 ffmpeg → AVAssetExportPresetHEVCHighestQuality | ffmpeg | FFmpeg hevc_videotoolbox（同參數）；備援保留 | ⬜ |  |
| 35 | `vid.to.webm` | 影片 | ffmpeg libvpx-vp9 -crf 32 -b:v 0 -row-mt 1 -deadline good -cpu-used 4 + libopus 128k | ffmpeg | FFmpeg（同參數） | ⬜ |  |
| 36 | `vid.to.gif` | 影片 | ffmpeg fps=12、≤540、palettegen max_colors=200 stats_mode=diff、paletteuse bayer、-t 30；無 ffmpeg → nativeGIF 10fps | ffmpeg | FFmpeg（同濾鏡圖）；nativeGIF 備援保留 | ⬜ | 「只取了前 30 秒」沿用 |
| 37 | `vid.to.mp3` | 影片 | ffmpeg -vn libmp3lame -q:a 2 | ffmpeg | FFmpeg（同參數） | ⬜ |  |
| 38 | `vid.to.m4a` | 影片 | AVAssetExportPresetAppleM4A；不支援時 ffmpeg aac 192k | — | AVFoundation；備援 FFmpeg | ⬜ |  |
| 39 | `vid.to.wav` | 影片 | ffmpeg -vn pcm_s16le | ffmpeg | FFmpeg（同參數） | ⬜ |  |
| 40 | `vid.compress` | 影片 | ffmpeg libx264 faster crf 27 ≤1920 aac 128k；無 ffmpeg → AVAssetExportPreset1280x720；shrinkResult | ffmpeg libx264 | FFmpeg `h264_videotoolbox`（≤1920）；備援 AVFoundation 720P | ⬜ | 預計 ⚠️：x264 為 GPL。換算規則見第 5 節「libx264 → h264_videotoolbox」 |
| 41 | `vid.mute` | 影片 | ffmpeg -map 0:v -c copy -an；無 ffmpeg → muteNative（AVMutableComposition passthrough .mov） | ffmpeg | FFmpeg（同參數）；備援保留 | ⬜ |  |
| 42 | `vid.720p` | 影片 | AVAssetExportPreset1280x720；不支援時 ffmpeg scale 1280 + libx264 | ffmpeg libx264（備援） | AVFoundation；備援 FFmpeg `h264_videotoolbox` | ⬜ | 預計 ⚠️（備援路徑；換算規則見第 5 節） |
| 43 | `vid.cover` | 影片 | AVAssetImageGenerator @ min(1s, 10%) → JPG q0.92；不支援時 ffmpeg -frames:v 1 | — | AVFoundation；備援 FFmpeg | ⬜ |  |
| 44 | `vid.fast` | 影片 | ffmpeg setpts=0.5*PTS + atempo=2.0 + libx264 crf 20 + aac 160k | ffmpeg libx264 | FFmpeg 同濾鏡 + `h264_videotoolbox` | ⬜ | 預計 ⚠️：x264 為 GPL。換算規則見第 5 節「libx264 → h264_videotoolbox」 |
| 45 | `vid.slow` | 影片 | ffmpeg setpts=2.0*PTS + atempo=0.5 + libx264 | ffmpeg libx264 | FFmpeg 同濾鏡 + `h264_videotoolbox` | ⬜ | 預計 ⚠️：x264 為 GPL。換算規則見第 5 節「libx264 → h264_videotoolbox」 |
| 46 | `vid.strip` | 影片 | Privacy.stripVideo（passthrough、metadata=[]、forSharing；否則 ffmpeg -map_metadata -1 -c copy） | — | AVFoundation；備援 FFmpeg | ⬜ |  |
| 47 | `aud.to.mp3` | 音訊 | ffmpeg -vn libmp3lame -q:a 2 | ffmpeg | FFmpeg（同參數） | ⬜ |  |
| 48 | `aud.to.m4a` | 音訊 | afconvert m4af aac 256k；失敗 → ffmpeg aac 256k | afconvert | AVAssetReader/Writer AAC 256k；備援 FFmpeg | ⬜ |  |
| 49 | `aud.to.wav` | 音訊 | afconvert WAVE LEI16；失敗 → ffmpeg pcm_s16le | afconvert | ExtAudioFile／AVAudioFile LEI16；備援 FFmpeg | ⬜ |  |
| 50 | `aud.to.flac` | 音訊 | afconvert flac；失敗 → ffmpeg flac | afconvert | ExtAudioFile FLAC（執行時偵測）；否則 FFmpeg flac | ⬜ |  |
| 51 | `aud.to.aiff` | 音訊 | afconvert AIFF BEI16；失敗 → ffmpeg pcm_s16be | afconvert | ExtAudioFile BEI16；備援 FFmpeg | ⬜ |  |
| 52 | `aud.to.opus` | 音訊 | ffmpeg -vn libopus 128k | ffmpeg | FFmpeg（同參數） | ⬜ |  |
| 53 | `aud.to.alac` | 音訊 | afconvert m4af alac（檔名加「无损」）；失敗 → ffmpeg alac | afconvert | AVAssetWriter ALAC；備援 FFmpeg | ⬜ |  |
| 54 | `aud.to.m4r` | 音訊 | AVAssetExportPresetAppleM4A 前 40 秒 → .m4r；不支援時 ffmpeg -t 40 aac 256k -f ipod | — | AVFoundation；備援 FFmpeg | ⬜ | 「截取了前 40 秒」沿用 |
| 55 | `aud.compress` | 音訊 | afconvert aac 96k；失敗 → ffmpeg aac 96k；shrinkResult | afconvert | AVAssetWriter AAC 96k；備援 FFmpeg | ⬜ |  |
| 56 | `aud.mono` | 音訊 | ffmpeg -ac 1（同格式輸出） | ffmpeg | FFmpeg（同參數） | ⬜ |  |
| 57 | `aud.loud` | 音訊 | ffmpeg loudnorm=I=-16:TP=-1.5:LRA=11 -ar 原取樣率 | ffmpeg | FFmpeg（同參數） | ⬜ |  |
| 58 | `aud.fast` | 音訊 | ffmpeg atempo=1.5 | ffmpeg | FFmpeg（同參數） | ⬜ |  |
| 59 | `doc.to.pdf` | 文件 | DocOps.convert → load → printPDF（NSPrintOperation + NSTextView，A4 595×842，邊界 56/60） | textutil、NSPrintOperation | DocReader → UIMarkupTextPrintFormatter + UIPrintPageRenderer（注入，A4 同邊界） | ⬜ | P3 |
| 60 | `doc.to.docx` | 文件 | textutil -convert docx（markdown 走 NSAttributedString） | textutil | 自寫 DocxWriter | ⬜ | P3 |
| 61 | `doc.to.txt` | 文件 | textutil -convert txt；md → Markdown.plain | textutil | DocReader → 純文字；Markdown.plain（同上游） | ⬜ | P3 |
| 62 | `doc.to.md` | 文件 | load → Markdown.from | textutil | DocReader → Markdown.from（同上游） | ⬜ | P3 |
| 63 | `doc.to.html` | 文件 | textutil -convert html | textutil | DocReader → RichTextCodec HTML | ⬜ | P3 |
| 64 | `doc.to.rtf` | 文件 | textutil -convert rtf | textutil | DocReader → RichTextCodec RTF | ⬜ | P3 |
| 65 | `doc.to.odt` | 文件 | textutil -convert odt | textutil | 自寫 ODTWriter | ⬜ | P3 |
| 66 | `doc.to.doc` | 文件 | textutil -convert doc（真正的 Word 97 格式） | textutil | RTF 內容配 .doc 副檔名（Word 可開） | ⬜ | 預計 ⚠️：不是二進位 .doc |
| 67 | `doc.strip` | 文件 | Privacy.stripDocx（unzip core.xml/app.xml → 清欄位 → zip 回去） | unzip、zip | ZIPFoundation 改寫 docProps/core.xml 與 app.xml | ⬜ | P3 |
| 68 | `doc.count` | 文件 | DocOps.count（中文字 + 英文詞 + 字元數） | textutil | DocReader（同上游計數邏輯） | ⬜ | P3 |
| 69 | `doc.copy` | 文件 | DocOps.copy（全文 → 剪貼簿） | textutil、NSPasteboard | DocReader + UIPasteboard | ⬜ | P3 |
| 70 | `gen.zip` | 通用 | GenericOps.zip（ditto -c -k --sequesterRsrc --keepParent；多檔 →「归档 N 项.zip」） | ditto | ZIPFoundation（同命名） | ⬜ | iOS 檔案沒有資源分支，不產生 AppleDouble |
| 71 | `gen.path` | 通用 | Engine.run：檔案 POSIX 路徑 → 剪貼簿 | NSPasteboard | 複製「檔案」App 中的位置或 file URL | ⬜ | 預計 ⚠️：iOS 沙盒路徑對使用者沒有意義 |
| 72 | `gen.sha` | 通用 | GenericOps.sha256（CryptoKit 串流 4 MB、複製全值） | NSPasteboard | CryptoKit + UIPasteboard | ⬜ |  |
| 73 | `gen.name` | 通用 | Engine.run：檔名 → 剪貼簿 | NSPasteboard | UIPasteboard | ⬜ |  |

## 2. 非動作功能（49）

| 功能 | 上游 | iOS 實作 | 狀態 | 備註 |
|---|---|---|---|---|
| 拖著檔案按 ⇧ Shift 開輪盤 | DragWatcher（全域滑鼠監聽 + 拖曳剪貼簿）、Overlay.open(.drag) | 長按任意處 0.25 秒；拖放懸停直接展開；iPad 實體鍵盤按住 Shift 在指標處展開 | ⬜ | 預計 ⚠️：iOS 無法監聽系統全域拖曳 |
| 拖放執行／放開執行 | Overlay.performDrop、mouseReleased 備援（「文件被拖到别的地方了，这次没转换」） | UIDropInteraction；放開手指執行 | ⬜ |  |
| 點選模式（選擇文件打開輪盤…） | AppDelegate.chooseFiles（NSOpenPanel 多選、可選資料夾） | 「檔案」選取器、PHPicker（loadFileRepresentation）、貼上、分享／以…開啟 | ⬜ |  |
| 示範模式（看看效果） | AppDelegate.showDemo、Runner.demo（「演示模式 · 拖一个真文件再按 ⇧ 试试」） | 設定頁「看看效果」＋首次啟動自動示範；文案改成 iOS 手勢 | ⬜ | 預計 ⚠️：文案 |
| 首次啟動自動示範 | Settings.welcomed | 同（UserDefaults） | ⬜ |  |
| 輪盤：8 槽、頁面、hover 放大、pop 動畫、內容淡入 | WheelView、Overlay.tick | UIKit WheelView + CADisplayLink | ⬜ |  |
| 選槽判定：死區、遲滯、偏移後需刻意移動（armed） | Overlay.slot(at:) | 同演算法（手指座標） | ⬜ |  |
| 換頁 | 再按 Shift、Tab/Q/E、滾輪 | 雙指點擊、點中心頁籤、iPad Tab/Q/E、觸控板捲動 | ⬜ |  |
| 取消 | 移回中心、Esc、右鍵 | 滑回中心、點輪盤外、iPad Esc | ⬜ |  |
| Return / Space 選取 | OverlayRootView.keyDown | iPad 鍵盤 Return / Space | ⬜ |  |
| stat 比較條（白保留／藍提升／紅犧牲） | StatsPanelView | UIKit 移植 | ⬜ |  |
| 操作提示面板 | HelpPanelView（⇧ Shift 切换、松开鼠标执行、移回中心＝取消） | 同樣式，文字改成 iOS 手勢 | ⬜ | 預計 ⚠️：文案 |
| 通緝星等（開輪盤時掃描、星星出現、wanted 音效） | Privacy.scan、WantedView、Overlay.reveal | 同 | ⬜ |  |
| 指向去隱私時星星閃爍「松手 = 甩掉警察」 | Overlay.tick（evading） | 同 | ⬜ |  |
| 去隱私成功後星星閃爍消失「已甩掉警察」＋「通缉 ★★ 已解除」 | WantedHUD.evade、Runner.run | 同 | ⬜ |  |
| 背景壓暗＋模糊 | DimView、NSVisualEffectView(.hudWindow) | UIVisualEffectView | ⬜ |  |
| MISSION PASSED / WASTED 橫幅（2.2 s / 3.2 s） | BannerView、BannerController | 同動畫；加按鈕：分享、在「檔案」中顯示、存到相簿 | ⬜ |  |
| 完成橫幅開關 | Settings.banner（失敗永遠顯示） | 同 | ⬜ |  |
| 處理中 HUD（正在处理 · 名稱 %（还有 n 个）） | BusyHUD（0.35 s 後才出現） | App 內 HUD，加取消鈕 | ⬜ |  |
| 進度回報 | ProgressFn、ffmpeg -progress | FFmpegRunner／AVAssetExportSession 輪詢 | ⬜ |  |
| 取消執行中的轉換 | （上游沒有） | 取消鈕，刪除半成品 | ⬜ | iOS 新增 |
| 音效 16 種（音量表、延遲播放） | SFX（程式合成 PCM） | AVAudioEngine，session .ambient | ⬜ |  |
| 武器上膛音對應 | Weapon.sound、Runner（上膛 → 0.3 s → passed/evaded） | 同 | ⬜ |  |
| 格式圖示 51 種 | Glyphs（Glyph.of(id)） | FormatWheelArt（CoreGraphics） | ⬜ |  |
| 武器剪影 19 種 | Weapons（Weapon.of(id)） | FormatWheelArt | ⬜ |  |
| 圖示模式：格式／武器 | IconStyle、選單「格子图标」 | 設定頁 | ⬜ |  |
| 主題色 4 種 Crew | Crew、選單「角色配色」 | 設定頁 | ⬜ |  |
| 輪盤大小 3 種（半徑 235/285/330） | WheelSize、選單「轮盘大小」 | 設定頁；依螢幕等比縮放 | ⬜ | 預計 ⚠️：半徑依螢幕縮放 |
| 音效開關 | Settings.sound | 設定頁 | ⬜ |  |
| 背景虛化開關 | Settings.blur | 設定頁 | ⬜ |  |
| 登入時自動啟動 | SMAppService | 不適用 → 「觸覺回饋」開關 | ⬜ | 預計 ⚠️ |
| PDF 黑白解析度（150／200／300 dpi，預設 200） | （上游沒有；Quartz 濾鏡保持向量） | 設定頁，供 pdf.mono 使用 | ⬜ | iOS 新增，配合 pdf.mono 的 ⚠️ |
| 彈藥狀態（ffmpeg ✓ cwebp ✓） | AppDelegate.toolStatus | 設定頁「弹药状态」顯示 FFmpeg / libwebp 版本 | ⬜ | P0 首頁已顯示版本 |
| 最近轉換（8 筆，點擊在 Finder 顯示） | Recents、選單 | 設定頁／首頁：重開、分享、在「檔案」中顯示（QLThumbnailGenerator 縮圖） | ⬜ | 預計 ⚠️：Finder → 檔案 App |
| 退出 | 選單「退出格式轮盘」 | iOS 不提供退出 | ⬜ | 預計 ⚠️：平台慣例 |
| 選單列圖示 | Icons.menuBar | 無選單列；圖示用於 App 內 | ⬜ | 預計 ⚠️ |
| App 圖示（程式繪製） | Icons.app、build.sh --icon | scripts/render-icon（同一套繪圖碼） | ⬜ | P6 |
| 輸出位置：原檔旁、不可寫則到「下載」 | Out.dir | Documents/FormatWheel/；可選資料夾（bookmark）；可自動存相簿；每次可分享 | ⬜ | 預計 ⚠️ |
| 輸出命名與衝突處理（「 2」「 3」、後綴、資料夾） | Out.url/unique/folder | 同（沿用） | ⬜ |  |
| 多檔：依多數類型、跳過其他、「另有 n 个会跳过」 | Catalog.context、Engine.run | 同 | ⬜ |  |
| 「当前」格式槽位停用 | Catalog.format（current） | 同 | ⬜ |  |
| 「未装备」槽位 | Shell.has + installHint（brew install …） | 依裝置能力（HEIC/AVIF 編碼器、FFmpeg）；提示文字改成裝置說明 | ⬜ | 預計 ⚠️：文案 |
| 隱私掃描最多 24 檔、「n 个文件留有痕迹」 | Privacy.scan | 同 | ⬜ |  |
| 日誌檔 | Log（~/Library/Logs/FormatWheel.log，512 KB 輪替） | App 容器 Library/Logs；開發者選單匯出 | ⬜ | 預計 ⚠️ |
| 字型：Avenir Next Condensed、PingFang、HelveticaNeue-CondensedBlack、Impact | Fonts | iOS 內建前三者（加 PingFang TC）；Impact 以替代字型近似 | ⬜ | 預計 ⚠️：Impact |
| 宣傳片渲染（Promo/） | Promo/*.swift、render.sh | 不移植（行銷工具，非 App 功能）；P4 用 simctl 錄操作示範 | ⬜ | 預計 ⚠️ |
| 網站（docs/index.html） | GitHub Pages 介紹頁 | site/altstore 來源＋README | ⬜ | 預計 ⚠️ |
| VoiceOver 清單模式 | （上游沒有） | VoiceOver 開啟時改用可點選清單 | ⬜ | iOS 新增 |
| 觸覺回饋 | （上游沒有） | UISelectionFeedbackGenerator | ⬜ | iOS 新增 |

## 3. 命令列旗標（13）

上游 `main.swift` 的命令列模式在 iOS 不存在，逐一對應如下。

| 旗標 | 上游行為 | iOS 對應 | 狀態 | 備註 |
|---|---|---|---|---|
| `--snapshot <out.png>` | 離屏渲染輪盤（--files --hover --page --x --y --wanted --bg --crew --size） | XCTest 快照測試（兩種圖示模式 × 四種主題 × iPhone/iPad） | ⬜ | P4 |
| `--hover / --page / --x / --y / --files / --wanted / --bg` | --snapshot 的參數 | 快照測試參數化 | ⬜ | P4 |
| `--crew / --size` | 覆寫主題色／輪盤大小 | 快照測試參數化 | ⬜ | P4 |
| `--banner <out.png> [--wasted --title --detail --bg]` | 離屏渲染橫幅 | XCTest 快照測試 | ⬜ | P4 |
| `--icon <out.png> [--px N]` | 渲染 App 圖示 | scripts/render-icon（FormatWheelArt） | ⬜ | P6 |
| `--list <files…>` | 印出檔案的輪盤頁面與槽位 | App Intent「列出可用動作」（可選檔案）＋單元測試 | ⬜ | P5 |
| `--ids` | 列出全部動作 ID | App Intent「列出可用動作」 | ⬜ | P5 |
| `--run <id> <files…>` | 執行一個動作 | App Intent「對檔案執行動作」 | ⬜ | P5 |
| `--scan <files…>` | 印出通緝星等 | App Intent「掃描隱私資訊」 | ⬜ | P5 |
| `--glyphs <out.png>` | 匯出全部格式圖示 | 隱藏開發者選單：匯出 ZIP | ⬜ | P4 |
| `--weapons <out.png>` | 匯出全部武器剪影 | 隱藏開發者選單：匯出 ZIP | ⬜ | P4 |
| `--sounds <folder>` | 匯出全部音效 WAV | 隱藏開發者選單：匯出 ZIP | ⬜ | P4 |
| `--preview` | 叫正在執行的 App 閃一下示範輪盤（DistributedNotification） | 設定頁「看看效果」 | ⬜ | 預計 ⚠️：iOS 無跨行程通知 |

## 4. ⚠️ 差異總表

（尚無已完成的 ⚠️ 項目；「預計 ⚠️」標在各列備註。）

## 5. 替代方案說明

### libx264 → h264_videotoolbox

x264 是 GPL，不能內建，上游所有 `-c:v libx264 … -crf N` 都改用 `h264_videotoolbox`。VideoToolbox 不支援 CRF，換算規則：

1. **優先用 `-q:v`（固定品質）**。執行時先用 16×16 的 1 幀測試編碼檢查裝置是否接受 `-q:v`，結果快取。
   換算：`q = round(108 − 2.14 × crf)`，限制在 1…100。上游用到的值：crf 20 → **q:v 65**（vid.to.mp4/mov 備援、vid.720p 備援、vid.fast/slow），crf 27 → **q:v 50**（vid.compress）。
2. **裝置不接受 `-q:v` 時改用 `-b:v`**，依原片視訊位元率換算：
   - `目標 = 原片視訊位元率 × 係數 × 輸出像素數 ÷ 原片像素數`；crf 20 係數 0.9，crf 27 係數 0.5。
   - 讀不到原片位元率時以每像素每幀估算：crf 20 用 0.10 bit，crf 27 用 0.05 bit（× 寬 × 高 × fps）。
   - 限制在 0.8…25 Mbps，並加 `-maxrate 1.5×目標 -bufsize 2×目標`。
3. 其他參數照上游（`-pix_fmt yuv420p`、`-c:a aac -b:a …`、`-movflags +faststart`、縮放濾鏡）。`-preset` 是 x264 專屬，拿掉。
4. 測試：先偵測 `h264_videotoolbox` 在執行環境能否編碼；能就驗證輸出（格式、長度、尺寸、體積比上游預期合理），不能（例如模擬器沒有硬體編碼器）就 `XCTSkip` 並寫明原因，不讓 CI 時好時壞。

### pdf.mono

上游用 macOS 的 Quartz「Gray Tone」濾鏡把每頁重繪成灰階，文字和向量圖保持向量。iOS 沒有這個濾鏡，改成：

- 每頁以灰階點陣化（設定頁選 150／200／300 dpi，預設 200），保留原頁面尺寸（cropBox）與旋轉角度。
- 每頁疊一層看不見的文字（文字繪製模式 invisible），輸出仍可選取、搜尋、複製：
  - 原 PDF 有可抽取的文字層 → 直接用原文字與位置（PDFKit 逐行選取的字串與邊界），不跑 OCR；
  - 沒有文字層（掃描檔） → 沿用 pdf.ocr 的 Vision 辨識（zh-Hans、zh-Hant、en），用辨識框定位。
- 逐頁串流：一次只算繪、寫入一頁，不把整份文件讀進記憶體。

與上游的差異：

| | 上游（Quartz 濾鏡） | iOS |
|---|---|---|
| 文字 | 向量，原樣保留 | 點陣圖＋隱形文字層（可選取、搜尋、複製，但放大會看到像素） |
| 向量圖形 | 保持向量 | 點陣化 |
| 檔案大小 | 通常和原檔差不多 | 可能變大（依 dpi 和頁數） |
| 解析度 | 不適用 | 150／200／300 dpi 可選 |
| 掃描檔文字 | 沒有文字層就沒有 | 會用 OCR 補上文字層 |
| 連結、註解、表單、書籤 | 保留 | 不保留 |

測試：每頁抽樣像素 R=G=B、頁數與原檔相同、頁面尺寸與旋轉相同、PDFKit 能抽出文字（有文字層的來源與掃描來源各一）。
