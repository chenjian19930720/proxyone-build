import SwiftUI

enum Theme {
    // 背景：深蓝黑
    static let bg = Color(red: 0.043, green: 0.055, blue: 0.098)
    static let bg2 = Color(red: 0.075, green: 0.094, blue: 0.157)
    static let card = Color(red: 0.098, green: 0.118, blue: 0.196)
    static let cardHi = Color(red: 0.137, green: 0.165, blue: 0.267)
    static let line = Color.white.opacity(0.07)

    static let accent = Color(red: 0.298, green: 0.565, blue: 1.0)
    static let accent2 = Color(red: 0.545, green: 0.373, blue: 1.0)
    static let ok = Color(red: 0.204, green: 0.839, blue: 0.541)
    static let warn = Color(red: 1.0, green: 0.702, blue: 0.251)
    static let bad = Color(red: 1.0, green: 0.361, blue: 0.361)

    static let gradient = LinearGradient(colors: [accent, accent2],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing)
    static let gradientSoft = LinearGradient(colors: [accent.opacity(0.22), accent2.opacity(0.16)],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing)
    static let bgGradient = LinearGradient(colors: [bg2, bg],
                                           startPoint: .top,
                                           endPoint: .bottom)

    static func latencyColor(_ level: Int) -> Color {
        switch level {
        case 0: return ok
        case 1: return Color(red: 0.42, green: 0.85, blue: 0.55)
        case 2: return warn
        case 3: return bad
        default: return .secondary
        }
    }
}

/// 通用卡片背景
struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16, radius: CGFloat = 18) -> some View {
        modifier(CardBackground(padding: padding, radius: radius))
    }
}
