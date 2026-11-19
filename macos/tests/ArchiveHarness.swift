import Foundation

@main
struct ArchiveHarness {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            fputs("usage: ArchiveHarness <output.zip> <file> [file...]\n", stderr)
            exit(2)
        }

        let output = URL(fileURLWithPath: args[1])
        let files = args.dropFirst(2).map { URL(fileURLWithPath: $0) }

        do {
            let result = try await FileArchiver.makeZip(files: files)
            defer { result.cleanup() }
            try? FileManager.default.removeItem(at: output)
            try FileManager.default.copyItem(at: result.url, to: output)
            print("ARCHIVE \(output.path) bytes=\( (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 )")
        } catch {
            fputs("FAILED: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
