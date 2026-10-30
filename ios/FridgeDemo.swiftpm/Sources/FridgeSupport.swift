import SwiftUI
import UIKit

// MARK: - 独立运行所需的小件：颜色扩展、主题、顶栏、字体注册

extension Color {
    /// "#RRGGBB" / "RRGGBB" / "#RRGGBBAA"
    init(cpHex hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: text).scanHexInt64(&value)
        let r, g, b, a: Double
        if text.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// 极简主题：冰箱页只用到这几个颜色。Demo 固定浅色
final class FridgeTheme: ObservableObject {
    let textMain = Color(cpHex: "#5A4334")
    let textSub = Color(cpHex: "#8A7260")
    let surface = Color(cpHex: "#FFFBF4")
    let effectiveDark = false
}

struct FridgeTopBar<Trailing: View>: View {
    @ObservedObject var theme: FridgeTheme
    let title: String
    let sub: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(FridgeFont.cute(22)).foregroundStyle(theme.textMain)
                Text(sub).font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(theme.textSub.opacity(0.7))
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
    }
}

enum FridgeFonts {
    /// 启动时把随包字体注册进进程（不用改 Info.plist，Swift Playgrounds 也能用）
    static func registerBundled() {
        for name in ["ZCOOLKuaiLe-Regular", "WoAiWanWeiWeiShouXieTi"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                    ?? Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// 设置：填服务器地址 + token 就开启同步；留空 = 纯本机
struct FridgeSyncSettingsSheet: View {
    @ObservedObject var store: FridgeStore
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("服务器地址，如 http://192.168.1.5:8787", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("Token（Bearer）", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: {
                    Text("可选：同步")
                } footer: {
                    Text("默认只存在这台设备上。填了地址和 token，改动会先拉取服务器最新、套上改动再写回；留空即关闭同步。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { store.setSync(url: url, token: token); dismiss() }
                }
            }
        }
        .onAppear { url = store.syncBaseURL; token = store.syncToken }
    }
}
