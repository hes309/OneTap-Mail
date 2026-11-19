import Foundation
import AppKit
import Combine
import Carbon
import UniformTypeIdentifiers

enum SendPhase: Equatable {
    case idle
    case sending(String)
    case success(String)
    case failure(String, String?)
}

enum ConfigError: LocalizedError {
    case incomplete
    case missingPassword
    case invalidPort

    var errorDescription: String? {
        switch self {
        case .incomplete:
            return "请填写有效的工作邮箱、发件邮箱和 SMTP 服务器。"
        case .missingPassword:
            return "请填写发件邮箱的 SMTP 授权码。"
        case .invalidPort:
            return "端口号需要在 1 – 65535 之间。"
        }
    }
}

private struct PreparedArchive {
    let archive: ArchiveResult
    let files: [URL]
}

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published private(set) var config: MailConfig
    @Published var files: [URL] = []
    @Published var phase: SendPhase = .idle
    @Published var showSettings = false
    @Published var showAbout = false
    @Published var showsFullMailbox = false
    @Published var suppressQuickActionPrompt = false

    private let defaultsKey = "OneClickMail.config.v1"
    private var lastQuickURL: String?

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(MailConfig.self, from: data) {
            config = saved
        } else {
            config = .empty
        }
    }

    // MARK: - Derived state

    var webmailURL: URL? {
        config.provider.webmailURL
    }

    var needsSetup: Bool {
        !config.isComplete
    }

    var isSending: Bool {
        if case .sending = phase { return true }
        return false
    }

    var totalBytes: Int64 {
        files.reduce(Int64(0)) { partial, url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return partial + Int64(values?.fileSize ?? 0)
        }
    }

    var sendPlan: SendPlan {
        SendPlanner.make(files: files, config: config)
    }

    var sizeLimitBytes: Int64 {
        config.attachmentLimitBytes
    }

    var sizeLimitMB: Int {
        config.attachmentLimitMB
    }

    var isNearSizeLimit: Bool {
        totalBytes > sizeLimitBytes * 8 / 10
    }

    var defaultSubject: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return MailBranding.subject("\(config.subjectPrefix) · \(formatter.string(from: Date()))")
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    func completeSetup(config newConfig: MailConfig, password: String) throws {
        let normalized = newConfig.normalized
        guard normalized.isComplete else { throw ConfigError.incomplete }
        let cleanedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPassword.isEmpty else { throw ConfigError.missingPassword }
        try KeychainStore.save(cleanedPassword, for: normalized.senderEmail)
        config = normalized
        persist()
        phase = .idle
    }

    func updateSettings(config newConfig: MailConfig, password: String?) throws {
        let normalized = newConfig.normalized
        guard normalized.isComplete else { throw ConfigError.incomplete }

        if let password {
            let cleanedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanedPassword.isEmpty {
                try KeychainStore.save(cleanedPassword, for: normalized.senderEmail)
            } else if !KeychainStore.hasPassword(for: normalized.senderEmail) {
                throw ConfigError.missingPassword
            }
        } else if !KeychainStore.hasPassword(for: normalized.senderEmail) {
            throw ConfigError.missingPassword
        }

        config = normalized
        persist()
        phase = .idle
    }

    // MARK: - Files

    func addFiles(_ urls: [URL]) {
        var rejectedDirectories = 0
        for url in urls {
            let standardized = url.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                rejectedDirectories += 1
                continue
            }
            if !files.contains(where: { $0.standardizedFileURL.path == standardized.path }) {
                files.append(standardized)
            }
        }
        if rejectedDirectories > 0 {
            phase = .failure("文件夹暂不支持直接发送，请选择里面的文件。", nil)
        }
    }

    func removeFile(_ url: URL) {
        files.removeAll { $0.standardizedFileURL.path == url.standardizedFileURL.path }
    }

    func clearFiles() {
        files.removeAll()
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "选择要发送的文件"
        panel.prompt = "添加"
        panel.message = "选择后会添加到发送列表，不会立即发送。"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                self?.addFiles(panel.urls)
            }
        }
    }

    func fileSize(_ url: URL) -> String {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let bytes = values.fileSize else {
            return ""
        }
        return Format.bytes(bytes)
    }

    // MARK: - Sending

    func send(
        subject: String,
        body: String = "",
        recipients: [String]? = nil,
        saveContact: String? = nil
    ) {
        guard !isSending else { return }
        guard !files.isEmpty else {
            phase = .failure(MailSendError.noFiles.localizedDescription, nil)
            return
        }

        let recipientList = (recipients ?? [config.recipient])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !recipientList.isEmpty, recipientList.allSatisfy(Validation.isEmail) else {
            phase = .failure("请填写有效的收件邮箱地址。", nil)
            return
        }

        let sendingConfig = config
        guard sendingConfig.isComplete else {
            phase = .failure("邮箱配置不完整，请先完成设置。", nil)
            showSettings = true
            return
        }
        guard let password = KeychainStore.password(for: sendingConfig.senderEmail), !password.isEmpty else {
            phase = .failure("没有找到已保存的授权码。请打开设置，重新填写后再发送。", nil)
            showSettings = true
            return
        }

        let sendingFiles = files
        let plan = SendPlanner.make(files: sendingFiles, config: sendingConfig)
        let baseSubject = MailBranding.subject(subject)
        let customBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .sending(plan.usesZip ? "正在准备压缩包…" : "正在发送…")

        Task {
            if plan.usesZip {
                await sendArchived(
                    plan: plan,
                    subject: baseSubject,
                    customBody: customBody,
                    recipients: recipientList,
                    config: sendingConfig,
                    password: password,
                    saveContact: saveContact
                )
            } else {
                do {
                    phase = .sending("正在发送…")
                    let receipt = try await MailSender.send(
                        files: sendingFiles,
                        config: sendingConfig,
                        password: password,
                        subject: baseSubject,
                        body: customBody.isEmpty ? nil : customBody,
                        recipients: recipientList
                    )
                    phase = .success("已发送到 \(receipt.recipient)")
                    if let saveContact {
                        ContactsStore.shared.record(email: saveContact)
                    }
                } catch {
                    phase = .failure(error.localizedDescription, nil)
                }
            }
        }
    }

    private func sendArchived(
        plan: SendPlan,
        subject: String,
        customBody: String,
        recipients: [String],
        config sendingConfig: MailConfig,
        password: String,
        saveContact: String?
    ) async {
        var parts: [PreparedArchive] = []
        var sentEmails = 0
        defer { parts.forEach { $0.archive.cleanup() } }

        do {
            let archiveTotal = plan.batches.count
            for (index, batch) in plan.batches.enumerated() {
                phase = .sending(archiveTotal > 1
                    ? "正在压缩第 \(index + 1)/\(archiveTotal) 个压缩包…"
                    : "正在压缩文件…")

                let nameSuffix = archiveTotal > 1 ? "_\(index + 1)of\(archiveTotal)" : ""
                let archive = try await FileArchiver.makeZip(
                    files: batch,
                    maxBytes: plan.limitBytes,
                    nameSuffix: nameSuffix
                )
                parts.append(PreparedArchive(archive: archive, files: batch))
            }

            let sizes = parts.map { byteSize($0.archive.url) }
            guard let groups = ArchiveGrouper.group(sizes: sizes, limit: plan.limitBytes) else {
                throw MailSendError.attachmentTooLarge(
                    "有一个压缩包超过单封 \(plan.limitMB) MB 上限，无法发送。请先手动拆分这个文件。"
                )
            }

            for (groupIndex, group) in groups.enumerated() {
                let groupParts = group.map { parts[$0] }
                let archives = groupParts.map { $0.archive.url }
                let suffix = groups.count > 1 ? "（第 \(groupIndex + 1)/\(groups.count) 封）" : ""
                let body = archiveBody(
                    parts: groupParts,
                    groupIndex: groupIndex,
                    groupCount: groups.count,
                    customBody: customBody
                )

                phase = .sending(groups.count > 1
                    ? "正在发送第 \(groupIndex + 1)/\(groups.count) 封…"
                    : "正在发送压缩包…")

                _ = try await MailSender.send(
                    files: archives,
                    config: sendingConfig,
                    password: password,
                    subject: subject + suffix,
                    body: body,
                    recipients: recipients
                )
                sentEmails += 1
            }

            if groups.count > 1 {
                phase = .success("已分 \(groups.count) 封发送到 \(recipients.joined(separator: "、"))")
                NotificationManager.shared.notifySuccess(
                    recipient: recipients.joined(separator: "、"),
                    detail: "已分 \(groups.count) 封发送，共 \(parts.count) 个压缩包"
                )
            } else if parts.count > 1 {
                phase = .success("已将 \(parts.count) 个压缩包合并发送到 \(recipients.joined(separator: "、"))")
                NotificationManager.shared.notifySuccess(
                    recipient: recipients.joined(separator: "、"),
                    detail: "\(parts.count) 个压缩包已合并到一封邮件"
                )
            } else {
                phase = .success("已发送到 \(recipients.joined(separator: "、"))")
                NotificationManager.shared.notifySuccess(
                    recipient: recipients.joined(separator: "、"),
                    detail: "1 个压缩包"
                )
            }
            if let saveContact {
                ContactsStore.shared.record(email: saveContact)
            }
        } catch {
            if sentEmails > 0 {
                phase = .failure("已发送 \(sentEmails) 封，后续发送失败：\(error.localizedDescription)", nil)
            } else {
                phase = .failure(error.localizedDescription, nil)
            }
        }
    }

    private func archiveBody(
        parts: [PreparedArchive],
        groupIndex: Int,
        groupCount: Int,
        customBody: String
    ) -> String {
        let archiveLines = parts.map {
            "· \($0.archive.url.lastPathComponent)（\($0.files.count) 个文件）"
        }.joined(separator: "\n")
        let partText = groupCount > 1 ? "（第 \(groupIndex + 1)/\(groupCount) 封）" : ""
        let countText = parts.count == 1 ? "1 个 ZIP 压缩包" : "\(parts.count) 个 ZIP 压缩包"
        let intro: String
        if customBody.isEmpty {
            intro = "你好：\n\n以下文件已由 Mac 上的「一键邮」打包成 \(countText)\(partText)："
        } else {
            intro = "\(customBody)\n\n附件\(partText)："
        }
        return "\(intro)\n\n\(archiveLines)\n\n—— 一键邮"
    }

    private func byteSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    // MARK: - Finder Quick Action

    var shouldOfferQuickActionPrompt: Bool {
        !suppressQuickActionPrompt && FinderQuickAction.shouldOfferOnLaunch
    }

    func handleQuickSend(url: URL) {
        guard url.scheme == "oneclickmail", url.host == "send" else { return }
        let key = url.absoluteString
        guard lastQuickURL != key else { return }
        lastQuickURL = key
        suppressQuickActionPrompt = true

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let manifestPath = components.queryItems?.first(where: { $0.name == "manifest" })?.value,
              !manifestPath.isEmpty else {
            phase = .failure("右键发送失败：没有收到文件列表。", nil)
            return
        }

        let manifestURL = URL(fileURLWithPath: manifestPath)
        let content = (try? String(contentsOf: manifestURL, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(at: manifestURL)

        var urls: [URL] = []
        var seen = Set<String>()
        for rawLine in content.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("\""), line.hasSuffix("\""), line.count >= 2 {
                line.removeFirst()
                line.removeLast()
            }
            guard !line.isEmpty else { continue }
            let fileURL = URL(fileURLWithPath: line).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { continue }
            if seen.insert(fileURL.path).inserted {
                urls.append(fileURL)
            }
        }

        quickSend(urls: urls)
    }

    func quickSend(urls incoming: [URL]) {
        let urls = incoming
            .map { $0.standardizedFileURL }
            .filter { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    && !isDirectory.boolValue
            }
        guard !urls.isEmpty else {
            phase = .failure("右键发送失败：没有找到有效的文件。", nil)
            return
        }
        suppressQuickActionPrompt = true
        files = urls
        phase = .idle
        NSApp.activate(ignoringOtherApps: true)
        send(subject: defaultSubject)
    }

    func clearStatus() {
        if case .sending = phase { return }
        phase = .idle
    }
}

// MARK: - App lifecycle

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        NotificationManager.shared.prepare()
        NSApp.activate(ignoringOtherApps: true)

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc func sendFiles(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else {
            error.pointee = "没有收到文件。" as NSString
            return
        }
        Task { @MainActor in
            AppStore.shared.quickSend(urls: urls)
        }
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: value) else { return }
        Task { @MainActor in
            AppStore.shared.handleQuickSend(url: url)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            var files: [URL] = []
            for url in urls {
                if url.scheme == "oneclickmail" {
                    AppStore.shared.handleQuickSend(url: url)
                } else if url.isFileURL {
                    files.append(url)
                }
            }
            if !files.isEmpty {
                AppStore.shared.addFiles(files)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}
