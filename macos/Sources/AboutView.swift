import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            LogoMark(size: 82)
                .padding(.top, 4)

            Text("一键邮")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink)
                .padding(.top, 16)

            Text("版本 \(version)")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.tertiary)
                .padding(.top, 3)

            Text("把文件拖进来，一键发到工作邮箱。")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .padding(.top, 10)

            VStack(spacing: 9) {
                Text("作者：阿坝分行 何帅")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.ink)

                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.accent)
                    Text("无版权，免费使用")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: 0xF6F9FE))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Palette.softBorder, lineWidth: 1)
            )
            .padding(.top, 22)

            Button("关闭") {
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())
            .keyboardShortcut(.cancelAction)
            .padding(.top, 20)
        }
        .padding(.horizontal, 30)
        .padding(.top, 26)
        .padding(.bottom, 24)
        .frame(width: 440)
        .background(AppBackground())
    }
}
