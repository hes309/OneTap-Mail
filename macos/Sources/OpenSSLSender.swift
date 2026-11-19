import Foundation
import Darwin

enum OpenSSLSendError: LocalizedError {
    case unsupported
    case timeout
    case rejected(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "当前加密方式不支持备用发信通道，请使用 SSL 或 STARTTLS。"
        case .timeout:
            return "连接 SMTP 服务器超时，请检查网络。"
        case .rejected(let message):
            return "邮件服务器拒绝了发信：\(message)"
        case .failed(let message):
            return "备用发信通道失败：\(message)"
        }
    }
}

/// A small interactive SMTP client built on the system OpenSSL binary.
/// It sends `AUTH PLAIN` with an initial response (the form QQ Mail accepts)
/// and waits for each server response before sending the next command.
/// Used only as a fallback after curl reports a login failure.
enum OpenSSLSender {
    static func send(
        config: MailConfig,
        password: String,
        recipients: [String],
        messageData: Data
    ) throws {
        signal(SIGPIPE, SIG_IGN)
        guard config.security != .plain else { throw OpenSSLSendError.unsupported }
        guard config.isComplete else { throw OpenSSLSendError.failed("邮箱配置不完整。") }

        let cleanedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPassword.isEmpty else { throw MailSendError.missingPassword }
        guard !cleanedPassword.contains("\r"), !cleanedPassword.contains("\n") else {
            throw OpenSSLSendError.failed("授权码中不能包含换行符。")
        }

        let openSSL = "/usr/bin/openssl"
        guard FileManager.default.isExecutableFile(atPath: openSSL) else {
            throw OpenSSLSendError.failed("系统缺少 openssl。")
        }

        var arguments = [
            "s_client",
            "-connect", "\(config.smtpHost):\(config.smtpPort)",
            "-servername", config.smtpHost,
            "-quiet"
        ]
        if config.security == .starttls {
            arguments.append(contentsOf: ["-starttls", "smtp"])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: openSSL)
        process.arguments = arguments

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw OpenSSLSendError.failed("无法启动备用发信组件。")
        }

        let lines = SMTPLineStream(handle: stdoutPipe.fileHandleForReading)
        let err = DataCollector(handle: stderrPipe.fileHandleForReading)

        func write(_ text: String) throws {
            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: Data(text.utf8))
            } catch {
                throw OpenSSLSendError.failed("SMTP 连接已断开。")
            }
        }

        func finish() {
            try? stdinPipe.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            lines.stop()
            err.stop()
        }

        func waitFor(_ expected: String, timeout: TimeInterval = 30) throws -> String {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                guard let line = lines.takeLine(timeout: 0.5) else {
                    if !process.isRunning {
                        break
                    }
                    continue
                }
                if line.hasPrefix(expected + " ") || line.hasPrefix(expected + "-") {
                    if line.hasPrefix(expected + " ") {
                        return line
                    }
                    // Multiline reply: consume until the final "250 " line.
                    while let next = lines.takeLine(timeout: timeout) {
                        if next.hasPrefix("5") || next.hasPrefix("4") {
                            throw OpenSSLSendError.rejected(next)
                        }
                        if next.hasPrefix(expected + " ") {
                            return next
                        }
                    }
                    break
                }
                if line.hasPrefix("5") || line.hasPrefix("4") {
                    throw OpenSSLSendError.rejected(line)
                }
            }
            let detail = err.text
            finish()
            if detail.localizedCaseInsensitiveContains("certificate") ||
                detail.localizedCaseInsensitiveContains("ssl") ||
                detail.localizedCaseInsensitiveContains("tls") {
                throw OpenSSLSendError.failed("TLS 连接失败：\(detail)")
            }
            throw OpenSSLSendError.timeout
        }

        do {
            _ = try waitFor("220", timeout: 20)
            try write("EHLO oneclickmail.local\r\n")
            _ = try waitFor("250", timeout: 20)

            let authPayload = Data("\u{0}\(config.senderEmail)\u{0}\(cleanedPassword)".utf8).base64EncodedString()
            try write("AUTH PLAIN \(authPayload)\r\n")
            _ = try waitFor("235", timeout: 20)

            try write("MAIL FROM:<\(config.senderEmail)>\r\n")
            _ = try waitFor("250", timeout: 20)

            for recipient in recipients {
                try write("RCPT TO:<\(recipient)>\r\n")
                _ = try waitFor("250", timeout: 20)
            }

            try write("DATA\r\n")
            _ = try waitFor("354", timeout: 20)

            let messageText = String(decoding: messageData, as: UTF8.self)
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            let stuffed = messageText
                .components(separatedBy: "\n")
                .map { $0.hasPrefix(".") ? "." + $0 : $0 }
                .joined(separator: "\r\n")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
            try write(stuffed + "\r\n.\r\n")
            _ = try waitFor("250", timeout: 90)

            try? write("QUIT\r\n")
            finish()
        } catch {
            finish()
            throw error
        }
    }
}

// MARK: - Async stdout line reader

private final class SMTPLineStream {
    private let handle: FileHandle
    private let condition = NSCondition()
    private var buffer = Data()
    private var pending: [String] = []
    private var eof = false
    private var stopped = false

    init(handle: FileHandle) {
        self.handle = handle
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.readLoop()
        }
    }

    private func readLoop() {
        while true {
            let data: Data? = handle.availableData
            guard let data, !data.isEmpty else { break }

            condition.lock()
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                var line = String(decoding: lineData, as: UTF8.self)
                if line.hasSuffix("\r") { line.removeLast() }
                pending.append(line)
            }
            condition.broadcast()
            condition.unlock()
        }

        condition.lock()
        eof = true
        condition.broadcast()
        condition.unlock()
    }

    func takeLine(timeout: TimeInterval) -> String? {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while pending.isEmpty && !eof && !stopped {
            let woke = condition.wait(until: deadline)
            if !woke { return nil }
        }
        if !pending.isEmpty {
            let value = pending.removeFirst()
            return value
        }
        return nil
    }

    func stop() {
        condition.lock()
        stopped = true
        condition.broadcast()
        condition.unlock()
    }
}

// MARK: - Stderr collector

private final class DataCollector {
    private let handle: FileHandle
    private let lock = NSLock()
    private var data = Data()

    init(handle: FileHandle) {
        self.handle = handle
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            while true {
                let chunk: Data? = self.handle.availableData
                guard let chunk, !chunk.isEmpty else { break }
                self.lock.lock()
                self.data.append(chunk)
                self.lock.unlock()
            }
        }
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }

    func stop() {
        // The pipe closes when the child exits; nothing else is required.
    }
}
