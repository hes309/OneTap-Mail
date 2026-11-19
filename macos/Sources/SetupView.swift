import SwiftUI
import AppKit

struct SetupView: View {
    @EnvironmentObject private var store: AppStore

    @State private var recipient = ""
    @State private var sender = ""
    @State private var senderName = ""
    @State private var useSeparateSender = false
    @State private var provider: MailProvider = .custom
    @State private var smtpHost = ""
    @State private var smtpPort = "465"
    @State private var security: SMTPSecurity = .ssl
    @State private var password = ""
    @State private var showPassword = false
    @State private var showAdvanced = false
    @State private var errorMessage: String?
    @State private var testMessage: String?
    @State private var isSaving = false
    @State private var isTesting = false
    @State private var didLoad = false

    private var draft: MailConfig {
        MailConfig(
            recipient: recipient,
            senderName: senderName,
            senderEmail: useSeparateSender ? sender : recipient,
            provider: provider,
            smtpHost: smtpHost,
            smtpPort: Int(smtpPort) ?? 0,
            security: security
        ).normalized
    }

    private var canSubmit: Bool {
        draft.isComplete && !password.isEmpty && !isSaving && !isTesting
    }

    private var recipientBinding: Binding<String> {
        Binding(
            get: { recipient },
            set: { value in
                recipient = value
                if !useSeparateSender {
                    sender = value
                    syncProvider(for: value)
                }
            }
        )
    }

    private var senderBinding: Binding<String> {
        Binding(
            get: { sender },
            set: { value in
                sender = value
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
        HStack(spacing: 0) {
            brandPanel
                .frame(width: 340)
            formPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppBackground())
        .onAppear(perform: loadExistingIfNeeded)
    }

    // MARK: - Brand panel

    private var brandPanel: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x14213C), Color(hex: 0x0E172B)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(hex: 0x315FE8).opacity(0.30))
                .frame(width: 280, height: 280)
                .blur(radius: 40)
                .offset(x: -110, y: -190)
            Circle()
                .fill(Palette.accent.opacity(0.16))
                .frame(width: 240, height: 240)
                .blur(radius: 50)
                .offset(x: 150, y: 250)

            VStack(alignment: .leading, spacing: 0) {
                LogoMark(size: 70)
                    .padding(.bottom, 28)

                Text("一键邮")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(1)

                Text("文件，一键回到工作邮箱。")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 17) {
                    brandFeature(icon: "hand.draw.fill", text: "拖入文件，一键发送")
                    brandFeature(icon: "lock.shield.fill", text: "授权码存入系统钥匙串")
                    brandFeature(icon: "arrow.uturn.backward.circle.fill", text: "随时修改收件邮箱")
                }
                .padding(.top, 44)

                Spacer(minLength: 30)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: 0x7FA0FF))
                        Text("直连你的邮箱 SMTP")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.82))
                    }
                    Text("文件不经过任何第三方服务器，\n只发送到你填写的邮箱。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.white.opacity(0.46))
                        .lineSpacing(3)
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 58)
            .padding(.bottom, 36)
        }
        .ignoresSafeArea()
    }

    private func brandFeature(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0xAFC3FF))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.09)))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.78))
        }
    }

    // MARK: - Form

    private var formPanel: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                Text("连接你的邮箱")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                Text("第一次使用，填写一次就好。之后拖入文件，点一下即可发送。")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 7)

                VStack(alignment: .leading, spacing: 17) {
                    VStack(alignment: .leading, spacing: 7) {
                        FieldLabel(title: "工作邮箱", hint: "文件会发送到这个地址，之后也可以修改。", required: true)
                        EmailField(
                            placeholder: "name@company.com",
                            text: recipientBinding
                        )
                    }

                    Toggle(isOn: Binding(
                        get: { useSeparateSender },
                        set: { enabled in
                            useSeparateSender = enabled
                            if enabled {
                                sender = recipient
                                syncProvider(for: sender)
                            } else {
                                sender = recipient
                                syncProvider(for: recipient)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("使用另一个邮箱发送")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Palette.ink)
                            Text("公司邮箱不支持 SMTP 时，可用 QQ / 163 等邮箱代发。")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    if useSeparateSender {
                        VStack(alignment: .leading, spacing: 7) {
                            FieldLabel(title: "发件邮箱", hint: "真正登录 SMTP 发信的邮箱。", required: true)
                            EmailField(
                                placeholder: "yourname@qq.com",
                                text: senderBinding
                            )
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        FieldLabel(title: "邮箱服务商", hint: "自动识别，也可以手动选择。")
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
                            hint: "不是网页登录密码。多数邮箱需要在设置中开启 SMTP 后生成授权码。",
                            required: true
                        )
                        passwordField
                        if let guide = provider.authCodeGuide {
                            Text(guide)
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.secondary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            HStack(spacing: 8) {
                                if let helpURL = provider.helpURL {
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
                                Text(provider.helpText)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    serverSettings
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, 42)
            .padding(.top, 52)
            .padding(.bottom, 20)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            }

            setupFooter
        }
    }

    private var setupFooter: some View {
        VStack(spacing: 10) {
            Divider().overlay(Palette.softBorder)

            if let testMessage {
                inlineNotice(testMessage, color: Palette.success, icon: "checkmark.circle.fill")
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

                Spacer(minLength: 0)

                Button(action: save) {
                    HStack(spacing: 7) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Text(isSaving ? "保存中…" : "保存并开始")
                        if !isSaving {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmit)
                .keyboardShortcut(.return, modifiers: [.command])
            }

            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                Text("授权码只保存在本机钥匙串，不会上传到任何服务器。")
                    .font(.system(size: 10.5))
            }
            .foregroundStyle(Palette.tertiary)
        }
        .padding(.horizontal, 42)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.softBorder).frame(height: 1)
        }
    }

    private var passwordField: some View {
        InputShell {
            HStack(spacing: 8) {
                Group {
                    if showPassword {
                        TextField("输入授权码", text: $password)
                    } else {
                        SecureField("输入授权码", text: $password)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 14))
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
                        .frame(width: 76)
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
                        .frame(width: 126)
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
                Text("SMTP 服务器设置")
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

    // MARK: - Actions

    private func loadExistingIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        let existing = store.config
        guard !existing.recipient.isEmpty else { return }
        recipient = existing.recipient
        sender = existing.senderEmail
        senderName = existing.senderName
        useSeparateSender = existing.senderEmail.lowercased() != existing.recipient.lowercased()
        provider = existing.provider
        smtpHost = existing.smtpHost
        smtpPort = String(existing.smtpPort)
        security = existing.security
        showAdvanced = existing.provider == .custom
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
        } else if provider != .custom {
            if smtpHost == provider.defaultHost || smtpHost.isEmpty {
                smtpHost = ""
                smtpPort = "465"
                security = .ssl
            }
            provider = .custom
            showAdvanced = true
        }
    }

    private func save() {
        errorMessage = nil
        testMessage = nil
        guard draft.isComplete else {
            errorMessage = ConfigError.incomplete.localizedDescription
            return
        }
        guard !password.isEmpty else {
            errorMessage = ConfigError.missingPassword.localizedDescription
            return
        }
        isSaving = true
        do {
            try store.completeSetup(config: draft, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func testConnection() {
        errorMessage = nil
        testMessage = nil
        guard draft.isComplete else {
            errorMessage = ConfigError.incomplete.localizedDescription
            return
        }
        guard !password.isEmpty else {
            errorMessage = "请先填写授权码，再发送测试邮件。"
            return
        }
        let config = draft
        let testPassword = password
        isTesting = true
        Task { @MainActor in
            do {
                _ = try await MailSender.sendTest(config: config, password: testPassword)
                testMessage = "测试邮件已发送到 \(config.recipient)，请查收。"
            } catch {
                errorMessage = error.localizedDescription
            }
            isTesting = false
        }
    }
}
