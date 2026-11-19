import SwiftUI
import AppKit

// MARK: - Palette

enum Palette {
    static let ink = Color(hex: 0x172033)
    static let secondary = Color(hex: 0x667085)
    static let tertiary = Color(hex: 0x98A2B3)
    static let accent = Color(hex: 0xF26B3A)
    static let accentDeep = Color(hex: 0xD94E1F)
    static let blue = Color(hex: 0x2F5BEA)
    static let navy = Color(hex: 0x111D35)
    static let background = Color(hex: 0xF4F7FC)
    static let card = Color.white
    static let border = Color(hex: 0xE2E8F2)
    static let softBorder = Color(hex: 0xEDF1F7)
    static let success = Color(hex: 0x178A60)
    static let successSoft = Color(hex: 0xE9F8F1)
    static let danger = Color(hex: 0xC83B3B)
    static let dangerSoft = Color(hex: 0xFDEEEE)
    static let warning = Color(hex: 0xB46A11)
    static let warningSoft = Color(hex: 0xFFF7E8)
    static let accentSoft = Color(hex: 0xFFF0EA)
    static let blueSoft = Color(hex: 0xEDF2FF)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

// MARK: - Background

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0xF8FAFE), Color(hex: 0xEEF3FB)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(hex: 0xDBE7FF).opacity(0.55))
                .frame(width: 420, height: 420)
                .blur(radius: 80)
                .offset(x: 330, y: -260)
            Circle()
                .fill(Color(hex: 0xFFE7D9).opacity(0.45))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: -360, y: 300)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Logo

struct LogoMark: View {
    var size: CGFloat = 44

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x315FE8), Color(hex: 0x1B389F)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                )
                .shadow(color: Color(hex: 0x1B389F).opacity(0.28), radius: size * 0.22, x: 0, y: size * 0.10)

            Image(systemName: "envelope.fill")
                .font(.system(size: size * 0.40, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size, height: size)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFF8A55), Palette.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "paperplane.fill")
                    .font(.system(size: size * 0.15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: size * 0.34, height: size * 0.34)
            .overlay(Circle().stroke(Color.white, lineWidth: size * 0.035))
            .offset(x: size * 0.06, y: size * 0.06)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Cards and fields

struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 18
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Palette.card)
                    .shadow(color: Color(hex: 0x22345B).opacity(0.055), radius: 14, x: 0, y: 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Palette.softBorder, lineWidth: 1)
            )
    }
}

extension View {
    func card(cornerRadius: CGFloat = 18, padding: CGFloat = 20) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius, padding: padding))
    }
}

struct FieldLabel: View {
    let title: String
    var hint: String? = nil
    var required: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                if required {
                    Text("*")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.accent)
                }
            }
            if let hint {
                Text(hint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct InputShell<Content: View>: View {
    var height: CGFloat = 44
    var highlighted: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(hex: 0xFBFCFE))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(highlighted ? Palette.blue.opacity(0.45) : Palette.border, lineWidth: highlighted ? 1.4 : 1)
            )
    }
}

struct EmailField: View {
    let placeholder: String
    @Binding var text: String
    var focused: Bool = false

    var body: some View {
        InputShell(highlighted: focused) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Palette.ink)
                .disableAutocorrection(true)
        }
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 13 : 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 14 : 22)
            .frame(height: compact ? 36 : 48)
            .background(
                RoundedRectangle(cornerRadius: compact ? 9 : 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFF8250), Palette.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Palette.accent.opacity(configuration.isPressed ? 0.12 : 0.28), radius: 10, x: 0, y: 5)
            )
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12.5 : 14, weight: .medium))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, compact ? 12 : 18)
            .frame(height: compact ? 34 : 42)
            .background(
                RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous)
                    .stroke(Palette.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct SoftIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Palette.secondary)
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(configuration.isPressed ? Color(hex: 0xEDF1F8) : Color.white.opacity(0.72))
            )
            .overlay(Circle().stroke(Palette.softBorder, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Status

struct StatusBanner: View {
    let phase: SendPhase
    var onClose: () -> Void

    private var tint: Color {
        switch phase {
        case .success: return Palette.success
        case .failure: return Palette.danger
        case .sending(_): return Palette.blue
        case .idle: return Palette.secondary
        }
    }

    private var tintSoft: Color {
        switch phase {
        case .success: return Palette.successSoft
        case .failure: return Palette.dangerSoft
        case .sending(_): return Palette.blueSoft
        case .idle: return Color(hex: 0xF4F6FA)
        }
    }

    private var icon: String {
        switch phase {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.circle.fill"
        case .sending(_): return "arrow.triangle.2.circlepath"
        case .idle: return "info.circle.fill"
        }
    }

    private var title: String {
        switch phase {
        case .success(let message): return message
        case .failure(let message, _): return message
        case .sending(let message): return message
        case .idle: return ""
        }
    }

    private var detail: String? {
        if case .failure(_, let detail) = phase, let detail, detail != title {
            return detail
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if case .sending(_) = phase {
                ProgressView()
                    .controlSize(.small)
                    .tint(tint)
                    .frame(width: 16, height: 16)
                    .padding(.top, 1)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            if case .sending(_) = phase {
                EmptyView()
            } else {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.tertiary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tintSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
    }
}

// MARK: - Window

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.styleMask.insert(.resizable)
            window.styleMask.insert(.fullSizeContentView)
            window.minSize = NSSize(width: 820, height: 640)
            window.maxSize = NSSize(width: 10_000, height: 10_000)
            window.center()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
