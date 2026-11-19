import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var recipient = ""
    @State private var sender = ""
    @State private var senderName = ""
    @State private var provider: MailProvider = .custom
    @State private var smtpHost = ""
    @State private var smtpPort = "465"
    @State private var security: SMTPSecurity = .ssl
    @State private var password = ""
    @State private var showPassword = false
    @State private var showAdvanced = false
    @State private var errorMessage: String?
    @State private var noticeMessage: String?
    @State private var isSaving = false
    @State private var isTesting = false
    @State private var isDiagnosing = false
    @State private var didLoad = false
    @State private var quickActionInstalled = FinderQuickAction.isInstalled
    @State private var quickActionBusy = false
    @State private var quickActionError: String?
    @State private var storedPasswordAccount: String?
    @State private var storedPasswordExists = false

    private var draft: MailConfig {
        MailConfig(
            recipient: recipient,
            senderName: senderName,
            senderEmail: sender,
            provider: provider,
            smtpHost: smtpHost,
            smtpPort: Int(smtpPort) ?? 0,
            security: security,
            subjectPrefix: store.config.subjectPrefix
        ).normalized
    }

    private var currentSenderKey: String {
        draft.senderEmail.lowercased()
    }

    private var passwordStatusKnown: Bool {
        storedPasswordAccount == currentSenderKey
    }

    private var hasStoredPassword: Bool {
        passwordStatusKnown && storedPasswordExists
    }

    private var passwordPlaceholder: String {
        if hasStoredPassword { return "已保存，留空则不修改" }
        if passwordStatusKnown { return "输入授权码" }
        return "留空则使用已保存的授权码"
    }

    private var canSubmit: Bool {
        draft.isComplete && !isSaving && !isTesting && !isDiagnosing
    }

    private var qqPasswordHint: (text: String, color: Color)? {
        guard provider == .qq, !password.isEmpty else { return nil }
        let count = password.trimmingCharacters(in: .whitespacesAndNewlines).count
        if count == 16 {
            return ("已输入 16 位授权码", Palette.success)
        }
        return ("当前 \(count) 位；QQ 授权码通常为 16 位，请检查是否漏复制", Palette.warning)
    }

    private var senderBinding: Binding<String> {
        Binding(
            get: { sender },
            set: { value in
                sender = value
                if storedPasswordAccount != value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                    storedPasswordAccount = nil
                    storedPasswordExists = false
                }
                syncProvider(for: value)
            }
        )
    }

    private var providerBinding: Binding<MailProvider> {
        Binding(
            get: { provider },
            set: { value in
                provider = value
                if value != .custom {
                    smtpHost = value.defaultHost
                    smtpPort = String(value.defaultPort)
                    security = value.defaultSecurity
                    showAdvanced = false
                } else {
                    showAdvanced = true
                    if smtpHost.isEmpty { smtpPort = "465" }
                }
            }
        )
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                header
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionLabel("收件")
                        field(
                            label: "工作邮箱",
                            hint: "文件会发送到这个地址。",
                            placeholder: "name@company.com",
                            text: $recipient
                        )

                        Divider().overlay(Palette.softBorder)

                        sectionLabel("发件")
                        field(
                            label: "发件邮箱",
                            hint: "真正登录 SMTP 的邮箱。可以和收件邮箱不同。",
                            placeholder: "yourname@qq.com",
                            text: senderBinding
                        )
                        VStack(alignment: .leading, spacing: 7) {
                            FieldLabel(title: "邮箱服务商", hint: "选择后会自动填入服务器和端口。")
                            InputShell {
                                Picker("邮箱服务商", selection: providerBinding) {
                                    ForEach(MailProvider.allCases) { item in
                                        Text(item.title).tag(item)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            FieldLabel(
                                title: provider.passwordLabel,
                                hint: hasStoredPassword
                                    ? "授权码已保存在系统钥匙串。输入新授权码会覆盖旧值。"
                                    : "不是网页登录密码；若之前已保存过授权码，可以留空。"
                            )
                            passwordField
                            if let qqPasswordHint {
                                Text(qqPasswordHint.text)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(qqPasswordHint.color)
                            }
                            if let guide = provider.authCodeGuide {
                                Text(guide)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.secondary)
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if let helpURL = provider.helpURL {
                                Link(destination: helpURL) {
                                    HStack(spacing: 3) {
                                        Text("如何获取授权码")
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Palette.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        serverSettings

                        Divider().overlay(Palette.softBorder)

                        quickActionSection
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 18)
                    .padding(.bottom, 22)
                }

                footer
            }
        }
        .frame(width: 620, height: 780)
        .onAppear(perform: loadIfNeeded)
    }

    private var header: some View {
        HStack(spacing: 13) {
            LogoMark(size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("邮箱设置")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                Text("修改收件地址或发件邮箱")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(SoftIconButtonStyle())
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .background(Color.white.opacity(0.55))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.softBorder).frame(height: 1)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Palette.tertiary)
    }

    private func field(
        label: String,
        hint: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabel(title: label, hint: hint)
            InputShell {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.ink)
                    .disableAutocorrection(true)
            }
        }
    }

    private var passwordField: some View {
        InputShell {
            HStack(spacing: 8) {
                Group {
                    if showPassword {
                        TextField(passwordPlaceholder, text: $password)
                    } else {
                        SecureField(passwordPlaceholder, text: $password)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .disableAutocorrection(true)

                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var serverSettings: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("显示名称")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                    InputShell(height: 38) {
                        TextField("例如：Bei Bei（可留空）", text: $senderName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                    }
                }

                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SMTP 服务器")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Palette.secondary)
                        InputShell(height: 38) {
                            TextField("smtp.example.com", text: $smtpHost)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .disableAutocorrection(true)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("端口")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Palette.secondary)
                        InputShell(height: 38) {
                            TextField("465", text: $smtpPort)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                        }
                        .frame(width: 74)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("加密")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Palette.secondary)
                        InputShell(height: 38) {
                            Picker("加密", selection: $security) {
                                ForEach(SMTPSecurity.allCases) { item in
                                    Text(item.title).tag(item)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        .frame(width: 124)
                    }
                }
                Text("SSL 通常使用 465 端口；STARTTLS 通常使用 587 端口。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiary)
            }
            .padding(.top, 11)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "server.rack")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiary)
                Text("高级设置")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                Spacer()
                Text(smtpHost.isEmpty ? "待填写" : "\(smtpHost):\(smtpPort)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(smtpHost.isEmpty ? Palette.accent : Palette.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: 0xF8FAFD))
        )
    }

    private func inlineNotice(_ text: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11.5))
                .foregroundStyle(color)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(color.opacity(0.07))
        )
    }

    private var quickActionSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.blueSoft)
                    Image(systemName: "cursorarrow.click.2")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.blue)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Finder 右键菜单")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(quickActionInstalled
                         ? "系统服务已注册：右键 → 服务 → 用一键邮发送"
                         : "点击刷新，注册 Finder 服务")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if quickActionBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Button(quickActionInstalled ? "刷新菜单" : "启用") { installQuickAction() }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                }
            }

            if let quickActionError {
                Text(quickActionError)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: 0xF8FAFD))
        )
    }

    private func installQuickAction() {
        quickActionError = nil
        quickActionBusy = true
        do {
            try FinderQuickAction.install()
            quickActionInstalled = FinderQuickAction.isInstalled
        } catch {
            quickActionError = error.localizedDescription
        }
        quickActionBusy = false
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Divider().overlay(Palette.softBorder)

            if let noticeMessage {
                inlineNotice(noticeMessage, color: Palette.success, icon: "checkmark.circle.fill")
            }
            if let errorMessage {
                inlineNotice(errorMessage, color: Palette.danger, icon: "exclamationmark.circle.fill")
            }

            HStack(spacing: 10) {
                Button(action: testConnection) {
                    HStack(spacing: 6) {
                        if isTesting {
                            ProgressView().controlSize(.small)
                        }
                        Text(isTesting ? "正在测试…" : "发送测试邮件")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!canSubmit)

                Button(action: diagnoseLogin) {
                    HStack(spacing: 6) {
                        if isDiagnosing {
                            ProgressView().controlSize(.small)
                        }
                        Text(isDiagnosing ? "正在验证…" : "仅验证登录")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!canSubmit)

                Spacer()

                Button("取消") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())

                Button(action: save) {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text(isSaving ? "保存中…" : "保存修改")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmit)
                .keyboardShortcut(.return, modifiers: [.command])
            }

            HStack(spacing: 5) {
                Image(systemName: "lock.fill").font(.system(size: 9))
                Text("授权码只保存在本机钥匙串，不会写入配置文件。")
                    .font(.system(size: 10.5))
            }
            .foregroundStyle(Palette.tertiary)
        }
        .padding(.horizontal, 30)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.softBorder).frame(height: 1)
        }
    }

    // MARK: - Actions

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        let current = store.config
        recipient = current.recipient
        sender = current.senderEmail
        senderName = current.senderName
        provider = current.provider
        smtpHost = current.smtpHost
        smtpPort = String(current.smtpPort)
        security = current.security
        showAdvanced = false
    }

    private func syncProvider(for email: String) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let detected = MailProvider.detect(from: trimmed) {
            if provider != detected {
                provider = detected
                smtpHost = detected.defaultHost
                smtpPort = String(detected.defaultPort)
                security = detected.defaultSecurity
                showAdvanced = false
            }
        } else if provider != .custom, smtpHost == provider.defaultHost || smtpHost.isEmpty {
            provider = .custom
            smtpHost = ""
            smtpPort = "465"
            security = .ssl
            showAdvanced = true
        }
    }

    private func save() {
        errorMessage = nil
        noticeMessage = nil
        guard draft.isComplete else {
            errorMessage = ConfigError.incomplete.localizedDescription
            return
        }
        isSaving = true
        do {
            try store.updateSettings(config: draft, password: password.isEmpty ? nil : password)
            storedPasswordAccount = currentSenderKey
            storedPasswordExists = true
            dismiss()
        } catch {
            if case ConfigError.missingPassword = error {
                storedPasswordAccount = currentSenderKey
                storedPasswordExists = false
                errorMessage = "没有找到已保存的授权码，请填写后再保存。"
            } else {
                errorMessage = error.localizedDescription
            }
        }
        isSaving = false
    }

    private func testConnection() {
        errorMessage = nil
        noticeMessage = nil
        guard draft.isComplete else {
            errorMessage = ConfigError.incomplete.localizedDescription
            return
        }
        var effectivePassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        if effectivePassword.isEmpty {
            effectivePassword = KeychainStore.password(for: draft.senderEmail)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            storedPasswordAccount = currentSenderKey
            storedPasswordExists = !effectivePassword.isEmpty
        }
        guard !effectivePassword.isEmpty else {
            errorMessage = "没有找到已保存的授权码，请填写后再发送测试邮件。"
            return
        }

        let config = draft
        isTesting = true
        Task { @MainActor in
            do {
                _ = try await MailSender.sendTest(config: config, password: effectivePassword)
                noticeMessage = "测试邮件已发送到 \(config.recipient)，请查收。"
            } catch {
                errorMessage = error.localizedDescription
            }
            isTesting = false
        }
    }

    private func diagnoseLogin() {
        errorMessage = nil
        noticeMessage = nil
        guard draft.isComplete else {
            errorMessage = ConfigError.incomplete.localizedDescription
            return
        }

        var effectivePassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        if effectivePassword.isEmpty {
            effectivePassword = KeychainStore.password(for: draft.senderEmail)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            storedPasswordAccount = currentSenderKey
            storedPasswordExists = !effectivePassword.isEmpty
        }
        guard !effectivePassword.isEmpty else {
            errorMessage = "请先填写授权码，再验证登录。"
            return
        }

        let config = draft
        isDiagnosing = true
        Task { @MainActor in
            do {
                let response = try await SMTPDiagnostics.checkLogin(config: config, password: effectivePassword)
                noticeMessage = "SMTP 登录成功（\(response)）。可以点“保存修改”保存这个授权码。"
            } catch {
                errorMessage = error.localizedDescription
            }
            isDiagnosing = false
        }
    }
}
