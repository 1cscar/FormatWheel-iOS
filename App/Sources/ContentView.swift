import FormatWheelArt
import FormatWheelCore
import SwiftUI

/// Placeholder home screen until the wheel UI lands in P4: shows that the app runs, what the device can
/// encode ("弹药状态"), and the pdf.mono resolution setting.
struct ContentView: View {
    private let runner = FFmpegRunner.shared
    private let tools = Tools.current
    @AppStorage("pdfMonoDPI") private var monoDPI = 200

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("格式轮盘").font(.largeTitle.bold())
                        Text("长按任意处打开轮盘").foregroundStyle(.secondary)
                        Text("iOS 移植版正在建造中").font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                Section("弹药状态") {
                    capability("HEIC 编码", tools.heicEncoder)
                    capability("AVIF 编码（系统）", tools.avifImageIO)
                    capability("AVIF 编码（FFmpeg）", tools.ffmpeg)
                    capability("WebP 编码（libwebp）", tools.webp)
                    ForEach(runner.components, id: \.self) { line in
                        Text(line).font(.body.monospaced())
                    }
                    LabeledContent("授权", value: runner.license)
                }
                Section {
                    Picker("PDF 黑白分辨率", selection: $monoDPI) {
                        Text("150 dpi").tag(150)
                        Text("200 dpi").tag(200)
                        Text("300 dpi").tag(300)
                    }
                } footer: {
                    Text("「黑白」会把每页转成灰度图片并保留可选取的文字；分辨率越高越清晰，文件也越大。")
                }
            }
            .tint(Color(cgColor: Crew.online.cgColor))
        }
    }

    private func capability(_ name: LocalizedStringKey, _ available: Bool) -> some View {
        LabeledContent(name) {
            Label(available ? "可用" : "不支持", systemImage: available ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(available ? .green : .secondary)
        }
    }
}

#Preview {
    ContentView()
}
