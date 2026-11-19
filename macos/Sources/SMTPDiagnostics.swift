import Foundation

enum SMTPDiagnosticError: LocalizedError {
    case unsupported
    case timeout
    case rejected(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "当前加密方式不支持“仅验证登录”诊断，请使用 SSL 或 STARTTLS。"
        case .timeout:
            return "连接 SMTP 服务器超时，请检查网络。"
        case .rejected(let message):
            return "SMTP 登录被拒绝：\(message)"
        case .failed(let message):
            return "登录诊断失败：\(message)"
        }
    }
}

/// Performs SMTP AUTH only. No message is sent.
/// This helps distinguish a bad authorization code from rate limiting or
/// account restrictions by surfacing the server's own 5xx response.
enum SMTPDiagnostics {
    static func checkLogin(config: MailConfig, password: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) { () throws -> String in
            try checkLoginSync(config: config, password: password)
        }.value
    }

    private static func checkLoginSync(config: MailConfig, password: String) throws -> String {
        guard config.security != .plain else { throw SMTPDiagnosticError.unsupported }
        guard config.isComplete else {
            throw SMTPDiagnosticError.failed("邮箱配置不完整。")
        }

        let cleanedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPassword.isEmpty else { throw MailSendError.missingPassword }
        guard !cleanedPassword.contains("\r"), !cleanedPassword.contains("\n") else {
            throw SMTPDiagnosticError.failed("授权码中不能包含换行符。")
        }

        let openSSL = "/usr/bin/openssl"
        guard FileManager.default.isExecutableFile(atPath: openSSL) else {
            throw SMTPDiagnosticError.failed("系统缺少 openssl，无法诊断。")
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

        let authPayload = Data("\u{0}\(config.senderEmail)\u{0}\(cleanedPassword)".utf8).base64EncodedString()
        let script = "EHLO oneclickmail.local\r\nAUTH PLAIN \(authPayload)\r\nQUIT\r\n"

        do {
            try process.run()
        } catch {
            throw SMTPDiagnosticError.failed("无法启动诊断组件。")
        }

        if let data = script.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        try? stdinPipe.fileHandleForWriting.close()

        let killer = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: killer)

        process.waitUntilExit()
        killer.cancel()

        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let output = (String(data: stdout, encoding: .utf8) ?? "")
            + "\n"
            + (String(data: stderr, encoding: .utf8) ?? "")

        let redacted = redact(output, secrets: [cleanedPassword, authPayload])
        let lines = redacted
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let success = lines.first(where: {
            $0.hasPrefix("235") || $0.localizedCaseInsensitiveContains("authentication successful")
        }) {
            return success
        }
        if let rejected = lines.first(where: { $0.hasPrefix("5") || $0.hasPrefix("4") }) {
            throw SMTPDiagnosticError.rejected(rejected)
        }
        if process.terminationReason == .uncaughtSignal {
            throw SMTPDiagnosticError.timeout
        }
        let meaningful = lines.filter {
            !$0.hasPrefix("depth=") && !$0.hasPrefix("verify ") && !$0.hasPrefix("read:errno")
        }
        if let first = meaningful.first {
            throw SMTPDiagnosticError.failed(first)
        }
        throw SMTPDiagnosticError.failed("没有收到服务器响应。")
    }

    private static func redact(_ text: String, secrets: [String]) -> String {
        var result = text
        for secret in secrets where !secret.isEmpty {
            result = result.replacingOccurrences(of: secret, with: "••••")
        }
        return result
    }
}
