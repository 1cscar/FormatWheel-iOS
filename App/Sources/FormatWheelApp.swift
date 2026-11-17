import SwiftUI

@main
struct FormatWheelApp: App {
    init() {
        PlatformServices.install()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
