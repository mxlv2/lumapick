import SwiftUI

extension Color {
    static let studioAccent = Color(red: 0.12, green: 0.46, blue: 0.40)
    static let studioCanvas = Color(nsColor: .controlBackgroundColor)
}
struct StudioButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(prominent ? Color.studioAccent : Color.primary.opacity(configuration.isPressed ? 0.10 : 0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(prominent ? 0 : 0.045)))
            .opacity(enabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
struct KeyboardHint: View {
    let title: String
    var body: some View { Text(title).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.vertical, 3).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4)) }
}
struct FormatChip: View {
    let title: String; let active: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).font(.system(size: 11, weight: active ? .semibold : .medium)).padding(.horizontal, 12).padding(.vertical, 7).foregroundStyle(active ? Color.studioAccent : .secondary).background(active ? Color.studioAccent.opacity(0.10) : .clear, in: Capsule()) }.buttonStyle(.plain)
    }
}
struct StudioMark: View {
    var body: some View {
        Image(systemName: "viewfinder").font(.system(size: 23, weight: .medium)).foregroundStyle(Color.studioAccent)
            .overlay { Circle().fill(Color.studioAccent).frame(width: 7, height: 7) }
            .frame(width: 44, height: 44).background(Color.studioAccent.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
    }
}
