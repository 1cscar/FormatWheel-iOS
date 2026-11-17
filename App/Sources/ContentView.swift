import FormatWheelArt
import FormatWheelCore
import SwiftUI

/// P0 placeholder home screen: proves the app launches and the bundled FFmpeg links and runs.
/// Replaced by the wheel / import UI in P4.
struct ContentView: View {
    private let runner = FFmpegRunner.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("格式轮盘").font(.largeTitle.bold())
                        Text("长按任意处打开轮盘").foregroundStyle(.secondary)
                        Text("iOS 移植版正在建造中（P0 骨架）").font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                Section("弹药状态") {
                    ForEach(runner.components, id: \.self) { line in
                        Text(line).font(.body.monospaced())
                    }
                    LabeledContent("授权", value: runner.license)
                }
            }
            .tint(Color(cgColor: Crew.online.cgColor))
        }
    }
}

#Preview {
    ContentView()
}
