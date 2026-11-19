import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject private var store: AppStore
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var temporaryRecipient = ""
    @State private var sendToWorkMailbox = true
    @State private var isDropTarget = false
    @State private var didSetSubject = false
    @State private var showContacts = false
    @ObservedObject private var contacts = ContactsStore.shared

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 32)
                    .padding(.top, 42)
                    .padding(.bottom, 16)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        recipientsCard

                        dropZone

                        if store.files.isEmpty {
                            tipsRow
                                .transition(.opacity)
                        }

                        if !store.files.isEmpty {
                            filesCard
                                .transition(.opacity.combined(with: .move(edge: .top)))

                            optionsCard

                            bodyCard
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 18)
                    .animation(.easeOut(duration: 0.2), value: store.files)
                }

                if store.phase != .idle {
                    StatusBanner(phase: store.phase) {
                        store.clearStatus()
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                footer
            }
        }
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .sheet(isPresented: $showContacts) {
            ContactsPickerView(contacts: contacts) { email in
                temporaryRecipient = email
            }
        }
        .onAppear {
            if !didSetSubject {
                subject = store.defaultSubject
                didSetSubject = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            LogoMark(size: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("一键邮")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                HStack(spacing: 5) {
                    Circle()
                        .fill(Palette.success)
                        .frame(width: 5, height: 5)
                    Text("邮箱已配置")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                }
            }

            Spacer()

            Button {
                store.showsFullMailbox = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                        .font(.system(size: 11, weight: .medium))
                    Text("完整邮箱")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Palette.blue)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(Capsule().fill(Color.white.opacity(0.86)))
                .overlay(Capsule().stroke(Palette.softBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("切换到完整邮箱（网页版）")

            Button {
                store.showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
            }
            .buttonStyle(SoftIconButtonStyle())
            .help("设置")
        }
    }

    private var recipientList: [String] {
        var list: [String] = []
        if sendToWorkMailbox {
            let work = store.config.recipient.trimmingCharacters(in: .whitespacesAndNewlines)
            if !work.isEmpty { list.append(work) }
        }
        let temp = temporaryRecipient.trimmingCharacters(in: .whitespacesAndNewlines)
        if !temp.isEmpty,
           !list.contains(where: { $0.caseInsensitiveCompare(temp) == .orderedSame }) {
            list.append(temp)
        }
        return list
    }

    private var recipientWarning: String? {
        if recipientList.isEmpty {
            return "请填写临时邮箱，或开启「同时发送到工作邮箱」"
        }
        if !recipientList.allSatisfy(Validation.isEmail) {
            return "临时邮箱格式不正确"
        }
        return nil
    }

    private var recipientsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("临时邮箱（可选）")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                InputShell(height: 36) {
                    HStack(spacing: 6) {
                        TextField("name@example.com", text: $temporaryRecipient)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5))
                            .disableAutocorrection(true)

                        Button(action: pasteTemporaryRecipient) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Palette.blue)
                        }
                        .buttonStyle(.plain)
                        .help("粘贴剪贴板里的邮箱")

                        Button {
                            showContacts = true
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.blue)
                        }
                        .buttonStyle(.plain)
                        .help("打开通讯录")

                        Menu {
                            let recent = contacts.recent(limit: 7)
                            if recent.isEmpty {
                                Text("暂无历史收件人")
                            } else {
                                ForEach(recent) { contact in
                                    Button(contact.hasDisplayName
                                           ? "\(contact.displayName) · \(contact.email)"
                                           : contact.email) {
                                        temporaryRecipient = contact.email
                                    }
                                }
                                Divider()
                                Button("搜索通讯录…") {
                                    showContacts = true
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Palette.tertiary)
                                .frame(width: 16, height: 22)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("选择发送过的临时邮箱")
                    }
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("默认工作邮箱")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                InputShell(height: 36) {
                    HStack(spacing: 7) {
                        Text(store.config.recipient.isEmpty ? "未设置" : store.config.recipient)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(store.config.recipient.isEmpty ? Palette.tertiary : Palette.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Button { store.showSettings = true } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .opacity(sendToWorkMailbox ? 1 : 0.45)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("发送选项")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Toggle(isOn: $sendToWorkMailbox) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("同时发送到工作邮箱")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text(sendToWorkMailbox
                             ? "工作邮箱 + 临时邮箱"
                             : "只发送到临时邮箱")
                            .font(.system(size: 10.5))
                            .foregroundStyle(sendToWorkMailbox ? Palette.blue : Palette.warning)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .frame(width: 220, alignment: .leading)
        }

        if let recipientWarning {
            Text(recipientWarning)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.danger)
                .padding(.leading, 2)
        }
        }
        .card(cornerRadius: 14, padding: 12)
    }

    private func pasteTemporaryRecipient() {
        guard let raw = NSPasteboard.general.string(forType: .string) else {
            store.phase = .failure("剪贴板里没有文字。", nil)
            return
        }
        let candidate = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard !candidate.isEmpty else {
            store.phase = .failure("剪贴板里没有可用的邮箱地址。", nil)
            return
        }
        temporaryRecipient = candidate
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isDropTarget
                                ? [Palette.accent.opacity(0.22), Palette.accent.opacity(0.06)]
                                : [Color(hex: 0xEEF3FF), Color(hex: 0xF7F9FF)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: store.files.isEmpty ? 66 : 40, height: store.files.isEmpty ? 66 : 40)
                Image(systemName: isDropTarget ? "arrow.down.circle.fill" : "tray.and.arrow.down.fill")
                    .font(.system(size: store.files.isEmpty ? 26 : 17, weight: .medium))
                    .foregroundStyle(isDropTarget ? Palette.accent : Palette.blue)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(store.files.isEmpty ? "把文件拖到这里" : "继续拖入更多文件")
                    .font(.system(size: store.files.isEmpty ? 17 : 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(store.files.isEmpty ? "支持任意格式，可一次发送多个文件" : "松开即可添加")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
            }

            Spacer(minLength: 12)

            Button {
                store.chooseFiles()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("选择文件")
                }
            }
            .buttonStyle(SecondaryButtonStyle(compact: store.files.isEmpty ? false : true))
        }
        .padding(.horizontal, 22)
        .frame(height: store.files.isEmpty ? 158 : 64)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isDropTarget ? Palette.accentSoft.opacity(0.65) : Color.white.opacity(0.82))
                .shadow(color: Color(hex: 0x22345B).opacity(0.045), radius: 14, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isDropTarget ? Palette.accent : Palette.border.opacity(0.9),
                    style: StrokeStyle(lineWidth: isDropTarget ? 1.8 : 1.2, dash: [7, 5])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTarget) { providers in
            handleDrop(providers)
        }
        .animation(.easeOut(duration: 0.16), value: isDropTarget)
        .animation(.easeOut(duration: 0.2), value: store.files.isEmpty)
    }

    private var tipsRow: some View {
        HStack(spacing: 10) {
            tipCard(
                icon: "bolt.fill",
                tint: Palette.accent,
                title: "一键直达",
                detail: "保存后不用再登录网页邮箱"
            )
            tipCard(
                icon: "lock.shield.fill",
                tint: Palette.blue,
                title: "只在本机",
                detail: "授权码存进系统钥匙串"
            )
            tipCard(
                icon: "paperclip",
                tint: Palette.success,
                title: "多文件",
                detail: "2 个文件或 ≥\(store.sizeLimitMB) MB 自动压缩"
            )
        }
    }

    private func tipCard(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.10))
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 67, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Palette.softBorder, lineWidth: 1)
        )
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {        var accepted = false
        for provider in providers where provider.canLoadObject(ofClass: NSURL.self) {
            accepted = true
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let nsURL = object as? NSURL else { return }
                let url = nsURL as URL
                Task { @MainActor in
                    store.addFiles([url])
                }
            }
        }
        return accepted
    }

    // MARK: - Files

    private var filesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("已选择 \(store.files.count) 个文件")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(Format.bytes(store.totalBytes))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.tertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(hex: 0xF1F4F9)))

                Spacer()

                Button("清空") {
                    store.clearFiles()
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.secondary)
                .buttonStyle(.plain)
                .disabled(store.isSending)
            }
            .padding(.bottom, 10)

            ScrollView(.vertical, showsIndicators: store.files.count > 4) {
                VStack(spacing: 0) {
                    ForEach(store.files, id: \.self) { url in
                        if let index = store.files.firstIndex(of: url), index > 0 {
                            Divider()
                                .overlay(Palette.softBorder)
                                .padding(.leading, 46)
                        }
                        fileRow(url)
                    }
                }
            }
            .frame(maxHeight: store.files.count > 4 ? 216 : nil)

            if store.sendPlan.totalBytes > store.sendPlan.limitBytes {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 10))
                    Text("超过单封限制，将自动打包成 \(store.sendPlan.archiveCount) 个 ZIP；压缩后总量不超限就合并到一封邮件发送。")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Palette.blue)
                .padding(.top, 9)
            } else if store.isNearSizeLimit {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10))
                    Text("附件接近单封 \(store.sizeLimitMB) MB 上限。")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Palette.warning)
                .padding(.top, 9)
            }
        }
        .card(padding: 17)
    }

    private func fileRow(_ url: URL) -> some View {
        HStack(spacing: 11) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(store.fileSize(url))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiary)
            }

            Spacer()

            Button {
                store.removeFile(url)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.tertiary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color(hex: 0xF4F6FA)))
            }
            .buttonStyle(.plain)
            .help("移除")
            .disabled(store.isSending)
        }
        .padding(.vertical, 9)
    }

    // MARK: - Options

    private var optionsCard: some View {
        let plan = store.sendPlan
        let zipActive = plan.usesZip

        return VStack(spacing: 12) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(zipActive ? Palette.accentSoft : Palette.blueSoft)
                    Image(systemName: zipActive ? "archivebox.fill" : "doc.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(zipActive ? Palette.accent : Palette.blue)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(zipActive
                             ? (plan.archiveCount > 1 ? "自动压缩并拆分" : "自动压缩发送")
                             : "直接发送，不压缩")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        Text(zipActive ? "ZIP" : "原文件")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(zipActive ? Palette.accent : Palette.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule().fill(
                                    zipActive ? Palette.accentSoft : Palette.blueSoft
                                )
                            )
                    }
                    Text(planDetail(plan))
                        .font(.system(size: 11))
                        .foregroundStyle(zipActive ? Palette.secondary : Palette.blue)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text("自动")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.tertiary)
            }

            Divider().overlay(Palette.softBorder)

            HStack(spacing: 12) {
                Text("邮件主题")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 58, alignment: .leading)

                InputShell(height: 38) {
                    TextField("默认主题", text: $subject)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.ink)
                }
            }
        }
        .card(cornerRadius: 14, padding: 14)
        .animation(.easeOut(duration: 0.16), value: zipActive)
    }

    private func planDetail(_ plan: SendPlan) -> String {
        if !plan.usesZip {
            return "1 个文件，未超过 \(plan.limitMB) MB，直接作为普通附件发送"
        }
        if plan.totalBytes >= plan.limitBytes {
            return "共 \(Format.bytes(plan.totalBytes))，达到单封 \(plan.limitMB) MB；将打包成 \(plan.archiveCount) 个 ZIP，压缩后总量不超限就合并到一封邮件发送"
        }
        if store.files.count == 1 {
            return "文件达到单封 \(plan.limitMB) MB，自动压缩成 1 个 ZIP 附件"
        }
        return "\(store.files.count) 个文件，自动打包成 1 个 ZIP 附件"
    }

    private var bodyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text("正文")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("可选")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Palette.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Color(hex: 0xF1F4F9)))

                Spacer()

                Button {
                    pasteClipboardToBody()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 10, weight: .medium))
                        Text("粘贴剪贴板")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.blue)
                }
                .buttonStyle(.plain)
                .help("把剪贴板里的文字粘贴为邮件正文")
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $bodyText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.ink)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 6)
                    .frame(minHeight: 80, maxHeight: 120)

                if bodyText.isEmpty {
                    Text("粘贴或输入正文，随文件一起发送…")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: 0xFBFCFE))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Palette.border, lineWidth: 1)
            )
        }
        .card(cornerRadius: 14, padding: 14)
    }

    private func pasteClipboardToBody() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.isEmpty else {
            store.phase = .failure("剪贴板里没有可粘贴的文字。", nil)
            return
        }
        bodyText = text
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Palette.border.opacity(0.7))
                .frame(height: 1)

            HStack(spacing: 14) {
                HStack(spacing: 7) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.tertiary)
                    Text("将发送至")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.tertiary)
                    Text(recipientList.isEmpty
                         ? "请填写收件邮箱"
                         : recipientList.joined(separator: "、"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 230, alignment: .leading)
                }

                Spacer()

                if !store.files.isEmpty {
                    Text(footerAttachmentText)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiary)
                }

                Button {
                    store.send(
                        subject: subject,
                        body: bodyText,
                        recipients: recipientList,
                        saveContact: temporaryRecipient
                    )
                } label: {
                    HStack(spacing: 9) {
                        if store.isSending {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Text(store.isSending ? "正在处理…" : "一键发送")
                            .font(.system(size: 14.5, weight: .semibold))
                        if !store.isSending {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .frame(width: 196, height: 46)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: canSend
                                        ? [Color(hex: 0xFF8250), Palette.accent]
                                        : [Color(hex: 0xC8D0DD), Color(hex: 0xB8C1D0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(
                                color: canSend ? Palette.accent.opacity(0.30) : .clear,
                                radius: 12, x: 0, y: 5
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("发送到 \(store.config.recipient)（⌘↩）")
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
        }
        .background(.ultraThinMaterial)
    }

    private var footerAttachmentText: String {
        let plan = store.sendPlan
        if plan.usesZip {
            if plan.archiveCount > 1 {
                return "\(plan.archiveCount) 个压缩包 / 自动合并发送"
            }
            return "打包为 1 个附件"
        }
        return "\(store.files.count) 个附件"
    }

    private var canSend: Bool {
        !store.files.isEmpty &&
        !store.isSending &&
        !recipientList.isEmpty &&
        recipientList.allSatisfy(Validation.isEmail)
    }
}
