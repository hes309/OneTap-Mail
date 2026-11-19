import Foundation
import UniformTypeIdentifiers

struct MailAttachment {
    let fileName: String
    let data: Data
    let mimeType: String
}

enum MIMEError: LocalizedError {
    case cannotEncode
    case headerInjection

    var errorDescription: String? {
        switch self {
        case .cannotEncode:
            return "无法生成邮件内容（编码失败）。"
        case .headerInjection:
            return "邮箱地址或主题中包含非法换行符。"
        }
    }
}

enum MIMEBuilder {
    static func makeMessage(
        from name: String,
        senderEmail: String,
        recipients: [String],
        subject: String,
        body: String,
        attachments: [MailAttachment],
        date: Date = Date()
    ) throws -> Data {
        let safeSender = try cleanHeader(senderEmail)
        let safeRecipients = try recipients.map { try cleanHeader($0) }
        let safeSubject = try cleanHeader(subject)
        let safeName = try cleanHeader(name)

        guard Validation.isEmail(safeSender),
              !safeRecipients.isEmpty,
              safeRecipients.allSatisfy(Validation.isEmail) else {
            throw MIMEError.cannotEncode
        }

        let boundary = "----=_OneClickMail_\(UUID().uuidString)"
        let domain = safeSender.split(separator: "@").last.map(String.init) ?? "oneclickmail.local"
        let messageID = "<\(UUID().uuidString)@\(domain)>"

        var headers: [String] = []
        headers.append("From: \(formatAddress(name: safeName, email: safeSender))")
        headers.append("To: \(safeRecipients.joined(separator: ", "))")
        headers.append("Subject: \(encodeHeader(safeSubject))")
        headers.append("Date: \(rfc2822Date(date))")
        headers.append("Message-ID: \(messageID)")
        headers.append("MIME-Version: 1.0")
        headers.append("X-Mailer: OneClickMail for macOS")

        let textPart = [
            "Content-Type: text/plain; charset=UTF-8",
            "Content-Transfer-Encoding: base64",
            "",
            base64Lines(Data(body.utf8))
        ].joined(separator: "\r\n")

        var message = ""
        if attachments.isEmpty {
            headers.append("Content-Type: text/plain; charset=UTF-8")
            headers.append("Content-Transfer-Encoding: base64")
            message = headers.joined(separator: "\r\n") + "\r\n\r\n" + base64Lines(Data(body.utf8))
        } else {
            headers.append("Content-Type: multipart/mixed; boundary=\"\(boundary)\"")
            message = headers.joined(separator: "\r\n") + "\r\n\r\n"

            message += "--\(boundary)\r\n"
            message += textPart + "\r\n\r\n"

            for attachment in attachments {
                let filename = safeAttachmentName(attachment.fileName)
                let displayName = quotedParameter(filename)
                let encodedFilename = rfc5987Encode(filename)
                message += "--\(boundary)\r\n"
                message += "Content-Type: \(attachment.mimeType); name=\"\(displayName)\"\r\n"
                message += "Content-Transfer-Encoding: base64\r\n"
                message += "Content-Disposition: attachment; filename=\"\(displayName)\"; filename*=UTF-8''\(encodedFilename)\r\n"
                message += "\r\n"
                message += base64Lines(attachment.data)
                message += "\r\n"
            }

            message += "--\(boundary)--\r\n"
        }

        guard let data = message.data(using: .utf8) else { throw MIMEError.cannotEncode }
        return data
    }

    // MARK: - Headers

    private static func cleanHeader(_ value: String) throws -> String {
        if value.contains("\r") || value.contains("\n") { throw MIMEError.headerInjection }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func formatAddress(name: String, email: String) -> String {
        guard !name.isEmpty else { return email }
        if name.unicodeScalars.allSatisfy({ $0.isASCII && $0.value >= 32 }) {
            let escaped = name
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\" <\(email)>"
        }
        return "\(encodeHeader(name)) <\(email)>"
    }

    static func encodeHeader(_ value: String) -> String {
        if value.unicodeScalars.allSatisfy({ $0.isASCII && $0.value >= 32 && $0.value != 63 }) {
            return value
        }
        let base64 = Data(value.utf8).base64EncodedString()
        return "=?UTF-8?B?\(base64)?="
    }

    private static func rfc2822Date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }

    // MARK: - Attachments

    static func mimeType(for url: URL) -> String {
        guard let type = UTType(filenameExtension: url.pathExtension),
              let mime = type.preferredMIMEType else {
            return "application/octet-stream"
        }
        return mime
    }

    private static func safeAttachmentName(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        return cleaned.isEmpty ? "attachment" : cleaned
    }

    /// RFC 2047 encoded-word for non-ASCII names (broad client support),
    /// with quoted-string escaping for plain ASCII names.
    private static func quotedParameter(_ name: String) -> String {
        if name.unicodeScalars.allSatisfy({ $0.isASCII && $0.value >= 32 && $0.value != 63 }) {
            return name
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
        return encodeHeader(name)
    }

    private static func rfc5987Encode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$&+-.^_`|~")
        var result = ""
        for byte in value.utf8 {
            let scalar = UnicodeScalar(byte)
            if allowed.contains(scalar) {
                result.append(Character(scalar))
            } else {
                result += String(format: "%%%02X", byte)
            }
        }
        return result
    }

    // MARK: - Base64

    private static func base64Lines(_ data: Data) -> String {
        let encoded = data.base64EncodedString()
        guard encoded.count > 76 else { return encoded }
        var lines: [String] = []
        var index = encoded.startIndex
        while index < encoded.endIndex {
            let end = encoded.index(index, offsetBy: 76, limitedBy: encoded.endIndex) ?? encoded.endIndex
            lines.append(String(encoded[index..<end]))
            index = end
        }
        return lines.joined(separator: "\r\n")
    }
}
