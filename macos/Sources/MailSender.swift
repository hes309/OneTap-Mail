import Foundation

struct SendReceipt {
    let recipient: String
    let subject: String
    let attachmentCount: Int
}

enum MailSendError: LocalizedError {
    case noFiles
    case missingPassword
    case invalidConfig(String)
    case tooManyFiles(Int)
    case attachmentTooLarge(String)
    case unreadableFile(String)
    case composeFailed(String)
    case curlMissing
    case network(String)
    case loginFailed(String)
    case tlsFailed(String)
    case rejected(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noFiles:
            return "请先选择或拖入要发送的文件。"
        case .missingPassword:
            return "还没有保存邮箱授权码，请在设置中填写。"
        case .invalidConfig(let reason):
            return reason
        case .tooManyFiles(let max):
            return "一次最多发送 \(max) 个文件。"
        case .attachmentTooLarge(let detail):
            return detail
        case .unreadableFile(let name):
            return "无法读取文件：\(name)"
        case .composeFailed(let detail):
            return "生成邮件失败：\(detail)"
        case .curlMissing:
            return "系统缺少发送组件（curl），无法发送邮件。"
        case .network(let detail):
            return detail
        case .loginFailed(let detail):
            return detail
        case .tlsFailed(let detail):
            return detail
        case .rejected(let detail):
            return detail
        case .failed(let detail):
            return detail
        }
    }
}

enum MailSender {
    static let maxFileCount = 30

    static func send(
        files: [URL],
        config: MailConfig,
        password: String,
        subject: String,
        body: String? = nil,
        recipients: [String]? = nil,
        isTest: Bool = false
    ) async throws -> SendReceipt {
        let normalized = config.normalized
        guard normalized.isComplete else {
            throw MailSendError.invalidConfig("邮箱配置不完整，请先在设置中补全发件邮箱和 SMTP 服务器。")
        }
        let recipientList = (recipients ?? [normalized.recipient])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !recipientList.isEmpty, recipientList.allSatisfy(Validation.isEmail) else {
            throw MailSendError.invalidConfig("请填写有效的收件邮箱地址。")
        }
        let cleanedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPassword.isEmpty else { throw MailSendError.missingPassword }
        guard !cleanedPassword.contains("\r"), !cleanedPassword.contains("\n") else {
            throw MailSendError.invalidConfig("授权码中不能包含换行符。")
        }
        if !isTest && files.isEmpty { throw MailSendError.noFiles }
        if files.count > maxFileCount { throw MailSendError.tooManyFiles(maxFileCount) }

        let finalSubject = MailBranding.subject(subject)

        return try await Task.detached(priority: .userInitiated) { () throws -> SendReceipt in
            try sendSync(
                files: files,
                config: normalized,
                password: cleanedPassword,
                subject: finalSubject,
                customBody: body,
                recipients: recipientList,
                isTest: isTest
            )
        }.value
    }

    static func sendTest(config: MailConfig, password: String) async throws -> SendReceipt {
        try await send(
            files: [],
            config: config,
            password: password,
            subject: "测试邮件",
            body: "你好：\n\n这是一封来自 Mac「一键邮」的测试邮件。\n\n如果你收到了它，说明发件邮箱配置成功，之后就可以拖入文件一键发送了。\n\n—— 一键邮",
            isTest: true
        )
    }

    // MARK: - Synchronous implementation

    private static func sendSync(
        files: [URL],
        config: MailConfig,
        password: String,
        subject: String,
        customBody: String?,
        recipients: [String],
        isTest: Bool
    ) throws -> SendReceipt {
        var attachments: [MailAttachment] = []
        var totalBytes = 0

        for url in files {
            let standardized = url.standardizedFileURL
            let accessed = standardized.startAccessingSecurityScopedResource()
            defer {
                if accessed { standardized.stopAccessingSecurityScopedResource() }
            }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                throw MailSendError.unreadableFile(standardized.lastPathComponent)
            }

            let data: Data
            do {
                data = try Data(contentsOf: standardized, options: .mappedIfSafe)
            } catch {
                throw MailSendError.unreadableFile(standardized.lastPathComponent)
            }

            totalBytes += data.count
            if totalBytes > config.attachmentLimitBytes {
                throw MailSendError.attachmentTooLarge(
                    "附件总大小超过 \(config.attachmentLimitMB) MB。请减少文件或压缩后再发送。"
                )
            }

            attachments.append(
                MailAttachment(
                    fileName: standardized.lastPathComponent,
                    data: data,
                    mimeType: MIMEBuilder.mimeType(for: standardized)
                )
            )
        }

        let body = customBody ?? defaultBody(files: files)
        let messageData: Data
        do {
            messageData = try MIMEBuilder.makeMessage(
                from: config.fromDisplayName,
                senderEmail: config.senderEmail,
                recipients: recipients,
                subject: subject,
                body: body,
                attachments: attachments
            )
        } catch {
            throw MailSendError.composeFailed(error.localizedDescription)
        }

        let fileManager = FileManager.default
        let workingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("OneClickMail-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        } catch {
            throw MailSendError.composeFailed("无法创建临时目录。")
        }
        defer { try? fileManager.removeItem(at: workingDirectory) }

        let messageURL = workingDirectory.appendingPathComponent("message.eml")
        do {
            try messageData.write(to: messageURL, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: messageURL.path)
        } catch {
            throw MailSendError.composeFailed("无法写入临时邮件文件。")
        }

        do {
            try runCurl(config: config, password: password, recipients: recipients, messageURL: messageURL, isTest: isTest)
        } catch let error as MailSendError {
            // QQ Mail can reject curl's challenge-response AUTH PLAIN even when
            // the same code succeeds with an initial-response AUTH PLAIN.
            // Retry through OpenSSL's one-line AUTH PLAIN before giving up.
            guard case .loginFailed = error, config.security != .plain else {
                throw error
            }
            let messageData: Data
            do {
                messageData = try Data(contentsOf: messageURL)
            } catch {
                throw MailSendError.failed("无法读取待发送的邮件内容。")
            }
            try OpenSSLSender.send(config: config, password: password, recipients: recipients, messageData: messageData)
        }

        return SendReceipt(
            recipient: recipients.joined(separator: ", "),
            subject: subject,
            attachmentCount: attachments.count
        )
    }

    static func defaultBody(files: [URL]) -> String {
        let lines = files.map { url -> String in
            let size: String
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
               let bytes = values.fileSize {
                size = "（\(Format.bytes(bytes))）"
            } else {
                size = ""
            }
            return "· \(url.lastPathComponent)\(size)"
        }.joined(separator: "\n")

        return "你好：\n\n以下文件由 Mac 上的「一键邮」发送：\n\n\(lines)\n\n—— 一键邮"
    }

    // MARK: - curl transport

    private static func runCurl(
        config: MailConfig,
        password: String,
        recipients: [String],
        messageURL: URL,
        isTest: Bool
    ) throws {
        let curlPath = "/usr/bin/curl"
        guard FileManager.default.isExecutableFile(atPath: curlPath) else {
            throw MailSendError.curlMissing
        }

        var arguments = [
            "--silent",
            "--show-error",
            "--fail-with-body",
            "--connect-timeout", "20",
            "--max-time", "300",
            "--url", config.smtpURL,
            "--mail-from", config.senderEmail,
            "--upload-file", messageURL.path,
            "--config", "-"
        ]
        if config.security == .starttls {
            arguments.insert("--ssl-reqd", at: 0)
        }
        for recipient in recipients {
            arguments.insert(contentsOf: ["--mail-rcpt", recipient], at: arguments.count - 2)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: curlPath)
        process.arguments = arguments

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let configText = "user = \"\(curlEscape(config.senderEmail)):\(curlEscape(password))\"\n"

        do {
            try process.run()
        } catch {
            throw MailSendError.failed("无法启动发送组件：\(error.localizedDescription)")
        }

        if let data = configText.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        try? stdinPipe.fileHandleForWriting.close()

        process.waitUntilExit()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        _ = stdoutPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            let code = Int(process.terminationStatus)
            throw mapCurlError(code: code, message: stderrText, isTest: isTest)
        }
    }

    private static func curlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func mapCurlError(code: Int, message: String, isTest: Bool) -> MailSendError {
        let detail = message.isEmpty ? "curl 退出码 \(code)" : message
        let lower = message.lowercased()

        if code == 67 || lower.contains("login denied") || lower.contains("authentication") {
            return .loginFailed("邮箱登录失败：请检查发件邮箱和授权码。QQ / 163 等邮箱需要使用「授权码」，不是网页登录密码。\n\n服务器返回：\(detail)")
        }
        if lower.contains("certificate") || lower.contains("ssl") || lower.contains("tls") {
            return .tlsFailed("加密连接失败：请检查服务器地址、端口和加密方式（SSL 对应 465，STARTTLS 对应 587）。\n\n服务器返回：\(detail)")
        }
        switch code {
        case 6:
            return .network("找不到 SMTP 服务器。请检查服务器地址是否正确。\n\n服务器返回：\(detail)")
        case 7:
            return .network("无法连接 SMTP 服务器。请检查服务器地址、端口和网络连接。\n\n服务器返回：\(detail)")
        case 28:
            return .network("连接邮箱服务器超时。请检查网络，或稍后再试。\n\n服务器返回：\(detail)")
        case 35, 51, 53, 54, 58, 59, 60, 64, 66, 77, 80, 82, 83, 90, 91:
            return .tlsFailed("加密连接失败：请检查端口与加密方式是否匹配。\n\n服务器返回：\(detail)")
        case 55, 56:
            return .rejected("邮件发送被服务器中断。文件可能过大，或收件地址被拒收。\n\n服务器返回：\(detail)")
        case 65:
            return .rejected("服务器拒绝了邮件数据，请稍后重试或更换发件邮箱。\n\n服务器返回：\(detail)")
        default:
            let prefix = isTest ? "测试邮件发送失败" : "发送失败"
            return .failed("\(prefix)（curl \(code)）：\(detail)")
        }
    }
}
