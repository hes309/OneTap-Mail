import Foundation

@main
struct SendHarness {
    static func main() async {
        if CommandLine.arguments.contains("--zip") {
            let inputs = CommandLine.arguments.dropFirst(2).map { URL(fileURLWithPath: $0) }
            guard !inputs.isEmpty else {
                fputs("usage: SendHarness --zip <file> [file...]\n", stderr)
                exit(2)
            }
            do {
                let result = try await FileArchiver.makeZip(files: Array(inputs))
                defer { result.cleanup() }
                let receipt = try await MailSender.send(
                    files: [result.url],
                    config: MailConfig(
                        recipient: "work-inbox@example.com",
                        senderName: "一键邮测试",
                        senderEmail: "sender@example.com",
                        provider: .custom,
                        smtpHost: "127.0.0.1",
                        smtpPort: 2525,
                        security: .plain
                    ),
                    password: "test-password",
                    subject: "压缩包测试 · 一键邮",
                    body: "以下文件已打包成 ZIP。"
                )
                print("ZIP SENT attachments=\(receipt.attachmentCount) archive=\(result.url.lastPathComponent)")
                return
            } catch {
                fputs("FAILED: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        if CommandLine.arguments.contains("--test") {
            let testConfig = MailConfig(
                recipient: "work-inbox@example.com",
                senderName: "一键邮测试",
                senderEmail: "sender@example.com",
                provider: .custom,
                smtpHost: "127.0.0.1",
                smtpPort: 2525,
                security: .plain
            )
            do {
                let receipt = try await MailSender.sendTest(config: testConfig, password: "test-password")
                print("TEST SENT to=\(receipt.recipient) attachments=\(receipt.attachmentCount)")
                return
            } catch {
                fputs("FAILED: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        guard CommandLine.arguments.count >= 2 else {
            fputs("usage: SendHarness <file-to-attach> | --test\n", stderr)
            exit(2)
        }

        let attachment = URL(fileURLWithPath: CommandLine.arguments[1])
        let config = MailConfig(
            recipient: "work-inbox@example.com",
            senderName: "一键邮测试",
            senderEmail: "sender@example.com",
            provider: .custom,
            smtpHost: "127.0.0.1",
            smtpPort: 2525,
            security: .plain
        )

        do {
            let receipt = try await MailSender.send(
                files: [attachment],
                config: config,
                password: "test-password",
                subject: "中文主题测试 · 一键邮"
            )
            print("SENT to=\(receipt.recipient) attachments=\(receipt.attachmentCount) subject=\(receipt.subject)")
        } catch {
            fputs("FAILED: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
