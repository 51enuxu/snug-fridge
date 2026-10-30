import SwiftUI

@main
struct FridgeDemoApp: App {
    init() { FridgeFonts.registerBundled() }

    var body: some Scene {
        WindowGroup {
            FridgeRoot()
        }
    }
}

struct FridgeRoot: View {
    @StateObject private var theme = FridgeTheme()

    var body: some View {
        FridgePageView(theme: theme)
    }
}
