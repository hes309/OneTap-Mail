import Foundation

// MARK: - SMTP security

enum SMTPSecurity: String, Codable, CaseIterable, Identifiable {
    case ssl
    case starttls
    case plain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ssl: return "SSL / TLS"
        case .starttls: return "STARTTLS"
        case .plain: return "不加密"
        }
    }

    var shortTitle: String {
        switch self {
        case .ssl: return "SSL"
        case .starttls: return "STARTTLS"
        case .plain: return "明文"
        }
    }
}

// MARK: - Provider presets

enum MailProvider: String, Codable, CaseIterable, Identifiable {
    case qq
    case net163
    case net126
    case gmail
    case outlook
    case icloud
    case aliyun
    case sina
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qq: return "QQ 邮箱"
        case .net163: return "163 邮箱"
        case .net126: return "126 邮箱"
        case .gmail: return "Gmail"
        case .outlook: return "Outlook / Microsoft"
        case .icloud: return "iCloud 邮箱"
        case .aliyun: return "阿里云邮箱"
        case .sina: return "新浪邮箱"
        case .custom: return "企业邮箱 / 其他"
        }
    }

    var defaultHost: String {
        switch self {
        case .qq: return "smtp.qq.com"
        case .net163: return "smtp.163.com"
        case .net126: return "smtp.126.com"
        case .gmail: return "smtp.gmail.com"
        case .outlook: return "smtp-mail.outlook.com"
        case .icloud: return "smtp.mail.me.com"
        case .aliyun: return "smtp.aliyun.com"
        case .sina: return "smtp.sina.com"
        case .custom: return ""
        }
    }

    var defaultPort: Int {
        switch self {
        case .outlook, .icloud: return 587
        default: return 465
        }
    }

    var defaultSecurity: SMTPSecurity {
        switch self {
        case .outlook, .icloud: return .starttls
        default: return .ssl
        }
    }


    var webmailURL: URL? {
        switch self {
        case .qq: return URL(string: "https://mail.qq.com/")
        case .net163: return URL(string: "https://mail.163.com/")
        case .net126: return URL(string: "https://mail.126.com/")
        case .gmail: return URL(string: "https://mail.google.com/")
        case .outlook: return URL(string: "https://outlook.live.com/mail/")
        case .icloud: return URL(string: "https://www.icloud.com/mail/")
        case .aliyun: return URL(string: "https://mail.aliyun.com/")
        case .sina: return URL(string: "https://mail.sina.com.cn/")
        case .custom: return nil
        }
    }

    var domains: [String] {
        switch self {
        case .qq: return ["qq.com", "foxmail.com"]
        case .net163: return ["163.com"]
        case .net126: return ["126.com"]
        case .gmail: return ["gmail.com", "googlemail.com"]
        case .outlook: return ["outlook.com", "hotmail.com", "live.com", "msn.com", "office365.com"]
        case .icloud: return ["icloud.com", "me.com", "mac.com"]
        case .aliyun: return ["aliyun.com", "aliyun.cn"]
        case .sina: return ["sina.com", "sina.cn"]
        case .custom: return []
        }
    }

    var passwordLabel: String {
        switch self {
        case .qq: return "QQ 邮箱授权码"
        case .net163: return "163 邮箱授权码"
        case .net126: return "126 邮箱授权码"
        case .gmail: return "Google 应用专用密码"
        case .outlook: return "Microsoft 账户密码 / 应用密码"
        case .icloud: return "iCloud App 专用密码"
        case .aliyun: return "阿里云邮箱密码 / 授权码"
        case .sina: return "新浪邮箱授权码"
        case .custom: return "SMTP 密码 / 授权码"
        }
    }

    var helpURL: URL? {
        switch self {
        case .qq:
            return URL(string: "https://service.mail.qq.com/detail/0/75")
        case .net163:
            return URL(string: "https://help.mail.163.com/faqDetail.do?code=d7a5dc8471cd0c0e8b4b8f4f8e49998b374173cfe9171305")
        case .net126:
            return URL(string: "https://help.mail.163.com/faqDetail.do?code=d7a5dc8471cd0c0e8b4b8f4f8e49998b374173cfe9171305")
        case .gmail:
            return URL(string: "https://support.google.com/accounts/answer/185833")
        case .outlook:
            return URL(string: "https://support.microsoft.com/account-billing/using-app-passwords-with-apps-that-don-t-support-two-step-verification-5896ed9b-4263-e681-128a-a6f2979a7944")
        case .icloud:
            return URL(string: "https://support.apple.com/zh-cn/102654")
        case .aliyun, .sina, .custom:
            return nil
        }
    }

    var authCodeGuide: String? {
        switch self {
        case .qq:
            return "QQ邮箱为例，请登录 QQ 邮箱-右上角设置-左下角账号与安全-安全设置-POP3/IMAP/SMTP/Exchange/CardDAV 服务-生成授权码"
        default:
            return nil
        }
    }

    var helpText: String {
        switch self {
        case .qq:
            return "需在 QQ 邮箱网页版「设置 → 账号」中开启 SMTP 服务，并生成授权码。"
        case .net163, .net126:
            return "需在网页版邮箱「设置 → POP3/SMTP/IMAP」中开启 SMTP，并获取授权码。"
        case .gmail:
            return "需开启两步验证，并生成 16 位「应用专用密码」。"
        case .outlook:
            return "若账号开启了两步验证，请使用 Microsoft 账户的「应用密码」。"
        case .icloud:
            return "需在 Apple ID 账户安全中生成「App 专用密码」。"
        case .aliyun:
            return "请确认已在阿里云邮箱设置中开启 SMTP 服务。"
        case .sina:
            return "请在新浪邮箱设置中开启 SMTP 服务并获取授权码。"
        case .custom:
            return "请向公司 IT 或邮箱管理员确认 SMTP 服务器地址、端口和加密方式。"
        }
    }

    static func detect(from email: String) -> MailProvider? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let domain = trimmed.split(separator: "@").last.map(String.init), !domain.isEmpty else {
            return nil
        }
        return allCases.first { provider in
            provider.domains.contains { domain == $0 || domain.hasSuffix("." + $0) }
        }
    }
}

// MARK: - Config

struct MailConfig: Codable, Equatable {
    var recipient: String = ""
    var senderName: String = ""
    var senderEmail: String = ""
    var provider: MailProvider = .custom
    var smtpHost: String = ""
    var smtpPort: Int = 465
    var security: SMTPSecurity = .ssl
    var subjectPrefix: String = "来自 Mac 的文件"

    static let empty = MailConfig()

    var normalized: MailConfig {
        var copy = self
        copy.recipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.senderName = senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.senderEmail = senderEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.smtpHost = smtpHost.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.subjectPrefix = subjectPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.subjectPrefix.isEmpty {
            copy.subjectPrefix = "来自 Mac 的文件"
        }
        return copy
    }

    var isComplete: Bool {
        Validation.isEmail(recipient)
            && Validation.isEmail(senderEmail)
            && !smtpHost.isEmpty
            && (1...65535).contains(smtpPort)
    }

    /// QQ Mail supports 50 MB of regular attachments per message. Other
    /// providers are kept at a conservative 20 MB.
    var attachmentLimitBytes: Int64 {
        let host = smtpHost.lowercased()
        let isQQ = provider == .qq || host.hasSuffix("qq.com") || host.hasSuffix("foxmail.com")
        return (isQQ ? 50 : 20) * 1024 * 1024
    }

    var attachmentLimitMB: Int {
        Int(attachmentLimitBytes / (1024 * 1024))
    }

    var fromDisplayName: String {
        let name = senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return String(senderEmail.split(separator: "@").first ?? "一键邮")
    }

    var smtpURL: String {
        let scheme = security == .ssl ? "smtps" : "smtp"
        return "\(scheme)://\(smtpHost):\(smtpPort)"
    }

    init(
        recipient: String = "",
        senderName: String = "",
        senderEmail: String = "",
        provider: MailProvider = .custom,
        smtpHost: String = "",
        smtpPort: Int = 465,
        security: SMTPSecurity = .ssl,
        subjectPrefix: String = "来自 Mac 的文件"
    ) {
        self.recipient = recipient
        self.senderName = senderName
        self.senderEmail = senderEmail
        self.provider = provider
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.security = security
        self.subjectPrefix = subjectPrefix
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recipient = try container.decodeIfPresent(String.self, forKey: .recipient) ?? ""
        senderName = try container.decodeIfPresent(String.self, forKey: .senderName) ?? ""
        senderEmail = try container.decodeIfPresent(String.self, forKey: .senderEmail) ?? ""
        provider = try container.decodeIfPresent(MailProvider.self, forKey: .provider) ?? .custom
        smtpHost = try container.decodeIfPresent(String.self, forKey: .smtpHost) ?? ""
        smtpPort = try container.decodeIfPresent(Int.self, forKey: .smtpPort) ?? 465
        security = try container.decodeIfPresent(SMTPSecurity.self, forKey: .security) ?? .ssl
        subjectPrefix = try container.decodeIfPresent(String.self, forKey: .subjectPrefix) ?? "来自 Mac 的文件"
    }
}

// MARK: - Validation

enum Validation {
    static func isEmail(_ value: String) -> Bool {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, email.count <= 254 else { return false }
        let pattern = #"^[A-Z0-9a-z.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    static func isPort(_ value: String) -> Bool {
        guard let port = Int(value) else { return false }
        return (1...65535).contains(port)
    }
}

// MARK: - Formatting

enum MailBranding {
    static let prefix = "【一键邮】"

    static func subject(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(prefix) { return trimmed }
        return prefix + (trimmed.isEmpty ? "来自 Mac 的文件" : trimmed)
    }
}

enum Format {
    static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: count)
    }

    static func bytes(_ count: Int) -> String {
        bytes(Int64(count))
    }
}
