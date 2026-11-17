# 格式輪盤 FormatWheel for iOS / iPadOS

> 🚧 **開發中（P0 骨架）**。完整的功能介紹、安裝教學與截圖會在 v1.0.0 發布時補上。

把 macOS 選單列 App [格式轮盘 FormatWheel](https://github.com/Elise616/FormatWheel)（作者 Elise616，MIT）
原生移植到 iPhone 與 iPad：長按畫面叫出「武器輪盤」，往格式槽位一甩就轉檔。圖片、PDF、影片、音訊、文件，
73 種轉換與小工具，全部在裝置上完成、不連網。

- 原生 Swift（SwiftUI + UIKit 輪盤），iOS / iPadOS 17 以上
- 內建自行編譯的 FFmpeg（LGPL，動態連結），不需要額外安裝任何東西
- 開源、免費；透過 AltStore / SideStore（免費 Apple ID）、TrollStore 或 Xcode 自行建置安裝

## 從原始碼建置（開發者）

```bash
brew install xcodegen ldid
scripts/fetch-ffmpeg.sh        # 下載預先編好的 FFmpeg（或 scripts/build-ffmpeg.sh 自己編）
xcodegen generate
open FormatWheel.xcodeproj
```

- 測試：`scripts/test.sh`
- 未簽章 IPA：`scripts/build-unsigned.sh` → `dist/FormatWheel.ipa`、`dist/FormatWheel.tipa`

### 修改 Bundle ID

預設是佔位符 `io.github.YOUR_GITHUB_USERNAME.formatwheel`。用自己的 Apple ID 建置前，把
[`project.yml`](project.yml) 裡所有 `YOUR_GITHUB_USERNAME`（`bundleIdPrefix` 與各 target 的
`PRODUCT_BUNDLE_IDENTIFIER`）換成你的 GitHub 帳號或任何唯一字串，再執行 `xcodegen generate`。

## 文件

- [移植計畫](docs/IOS_PORT_PLAN.md)
- [功能對照表（與 macOS 版的差異）](docs/PARITY.md)
- [FFmpeg 建置說明](docs/FFMPEG.md)
- [第三方授權](THIRD_PARTY_NOTICES.md)

## 隱私

所有轉換都在你的裝置上完成：不連網、不上傳、不收集任何資料，沒有任何分析或廣告 SDK。

## 致謝與聲明

- 原作：[Elise616/FormatWheel](https://github.com/Elise616/FormatWheel)，靈感來自
  [@th2049 的推文](https://x.com/th2049/status/2111477585461039241)。
- 本專案是致敬作品，與任何遊戲公司無關；圖示、武器剪影與音效全部由程式繪製、合成，沒有使用任何遊戲素材。

## 授權

[MIT](LICENSE)。內含的 FFmpeg 等元件依各自授權散佈，見 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

---

**English** — Native iOS/iPadOS port of the macOS menu-bar app FormatWheel by Elise616: long-press to open a
weapon-wheel and flick toward a slot to convert images, PDFs, video, audio and documents on-device.
Work in progress; sideload with AltStore/SideStore, TrollStore, or build with Xcode. MIT licensed.
