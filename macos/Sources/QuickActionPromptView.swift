import SwiftUI

struct QuickActionPromptView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var isInstalling = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0x315FE8), Color(hex: 0x1B389F)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "cursorarrow.click.2")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 58, height: 58)
                .shadow(color: Color(hex: 0x1B389F).opacity(0.22), radius: 10, x: 0, y: 5)

                VStack(alignment: .leading, spacing: 4) {
                    Text("把一键邮加到右键菜单？")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                    Text("以后在 Finder 里选中文件，右键就能直接发送。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 12) {
                promptRow(icon: "cursorarrow.rays", text: "Finder 中选中文件 → 右键 → 快速操作")
                promptRow(icon: "paperplane.fill", text: "点「用一键邮发送」直接发送，不用先打开应用")
                promptRow(icon: "lock.shield.fill", text: "仍使用已保存的工作邮箱和授权码")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: 0xF6F9FE))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Palette.softBorder, lineWidth: 1)
            )
            .padding(.bottom, 18)

            if let errorMessage {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11.5))
                    Text(errorMessage)
                        .font(.system(size: 11.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Palette.danger)
                .padding(.bottom, 12)
            }

            HStack(spacing: 10) {
                Button("暂不添加") {
                    FinderQuickAction.markPromptHandled()
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                Button(action: install) {
                    HStack(spacing: 7) {
                        if isInstalling {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text(isInstalling ? "正在添加…" : "添加到右键菜单")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isInstalling)
            }

            Text("稍后也可以在「邮箱设置」里添加或移除。")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.tertiary)
                .padding(.top, 12)
        }
        .padding(26)
        .frame(width: 520)
        .background(AppBackground())
    }

    private func promptRow(icon: String, text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.blue)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func install() {
        errorMessage = nil
        isInstalling = true
        do {
            try FinderQuickAction.install()
            store.suppressQuickActionPrompt = true
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isInstalling = false
    }
}
