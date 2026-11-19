import Foundation
import Compression

struct ArchiveResult {
    let url: URL
    let directory: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

enum ArchiveError: LocalizedError {
    case noFiles
    case unreadable(String)
    case tooLarge(Int64)
    case createFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .noFiles:
            return "没有可压缩的文件。"
        case .unreadable(let name):
            return "无法读取文件：\(name)"
        case .tooLarge(let limit):
            return "压缩包超过 \(limit / (1024 * 1024)) MB，无法作为单封附件发送。"
        case .createFailed:
            return "无法创建压缩包。"
        case .writeFailed:
            return "写入压缩包失败。"
        }
    }
}

/// Creates a standard ZIP archive natively, with UTF-8 file names and
/// DEFLATE compression. No external zip tool or Python installation is needed.
enum FileArchiver {
    static func makeZip(
        files: [URL],
        maxBytes: Int64 = 20 * 1024 * 1024,
        date: Date = Date(),
        nameSuffix: String = ""
    ) async throws -> ArchiveResult {
        try await Task.detached(priority: .userInitiated) { () throws -> ArchiveResult in
            try makeZipSync(files: files, maxBytes: maxBytes, date: date, nameSuffix: nameSuffix)
        }.value
    }

    // MARK: - ZIP writing

    private struct Entry {
        let name: String
        let data: Data
        let compressed: Data
        let method: UInt16
        let crc: UInt32
        let localOffset: UInt32
        let permissions: UInt32
    }

    private static func makeZipSync(files: [URL], maxBytes: Int64, date: Date, nameSuffix: String) throws -> ArchiveResult {
        guard !files.isEmpty else { throw ArchiveError.noFiles }

        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("OneClickMail-Zip-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ArchiveError.createFailed
        }

        var cleanupOnFailure = true
        defer {
            if cleanupOnFailure {
                try? fileManager.removeItem(at: directory)
            }
        }

        let archiveName = archiveFileName(for: date, suffix: nameSuffix)
        let archiveURL = directory.appendingPathComponent(archiveName)
        let (time, dosDate) = dosDateTime(date)

        var archiveData = Data()
        var centralDirectory = Data()
        var entries: [Entry] = []
        var usedNames = Set<String>()

        for url in files {
            let standardized = url.standardizedFileURL
            let accessed = standardized.startAccessingSecurityScopedResource()
            defer {
                if accessed { standardized.stopAccessingSecurityScopedResource() }
            }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                throw ArchiveError.unreadable(standardized.lastPathComponent)
            }

            let data: Data
            do {
                data = try Data(contentsOf: standardized, options: .mappedIfSafe)
            } catch {
                throw ArchiveError.unreadable(standardized.lastPathComponent)
            }

            let name = uniqueName(sanitized(standardized.lastPathComponent), used: &usedNames)
            let compressed = deflate(data)
            let method: UInt16
            let payload: Data
            if let compressed, compressed.count < data.count {
                method = 8
                payload = compressed
            } else {
                method = 0
                payload = data
            }

            let crc = crc32(data)
            let localOffset = UInt32(archiveData.count)
            let permissions = filePermissions(for: standardized)

            archiveData.appendUInt32(0x04034b50)
            archiveData.appendUInt16(20)              // version needed
            archiveData.appendUInt16(0x0800)          // UTF-8 file name
            archiveData.appendUInt16(method)
            archiveData.appendUInt16(time)
            archiveData.appendUInt16(dosDate)
            archiveData.appendUInt32(crc)
            archiveData.appendUInt32(UInt32(payload.count))
            archiveData.appendUInt32(UInt32(data.count))
            archiveData.appendUInt16(UInt16(name.utf8.count))
            archiveData.appendUInt16(0)               // extra length
            archiveData.append(contentsOf: name.utf8)
            archiveData.append(payload)

            entries.append(
                Entry(
                    name: name,
                    data: data,
                    compressed: payload,
                    method: method,
                    crc: crc,
                    localOffset: localOffset,
                    permissions: permissions
                )
            )
        }

        let centralOffset = UInt32(archiveData.count)
        for entry in entries {
            centralDirectory.appendUInt32(0x02014b50)
            centralDirectory.appendUInt16(0x0314)      // made by UNIX, version 2.0
            centralDirectory.appendUInt16(20)          // version needed
            centralDirectory.appendUInt16(0x0800)      // UTF-8 file name
            centralDirectory.appendUInt16(entry.method)
            centralDirectory.appendUInt16(time)
            centralDirectory.appendUInt16(dosDate)
            centralDirectory.appendUInt32(entry.crc)
            centralDirectory.appendUInt32(UInt32(entry.compressed.count))
            centralDirectory.appendUInt32(UInt32(entry.data.count))
            centralDirectory.appendUInt16(UInt16(entry.name.utf8.count))
            centralDirectory.appendUInt16(0)           // extra length
            centralDirectory.appendUInt16(0)           // comment length
            centralDirectory.appendUInt16(0)           // disk number
            centralDirectory.appendUInt16(0)           // internal attributes
            centralDirectory.appendUInt32(entry.permissions << 16)
            centralDirectory.appendUInt32(entry.localOffset)
            centralDirectory.append(contentsOf: entry.name.utf8)
        }

        let centralSize = UInt32(centralDirectory.count)
        archiveData.append(centralDirectory)
        archiveData.appendUInt32(0x06054b50)
        archiveData.appendUInt16(0)                    // disk number
        archiveData.appendUInt16(0)                    // central directory start disk
        archiveData.appendUInt16(UInt16(entries.count))
        archiveData.appendUInt16(UInt16(entries.count))
        archiveData.appendUInt32(centralSize)
        archiveData.appendUInt32(centralOffset)
        archiveData.appendUInt16(0)                    // comment length

        if archiveData.count > maxBytes {
            throw ArchiveError.tooLarge(maxBytes)
        }

        do {
            try archiveData.write(to: archiveURL, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archiveURL.path)
        } catch {
            throw ArchiveError.writeFailed
        }

        cleanupOnFailure = false
        return ArchiveResult(url: archiveURL, directory: directory)
    }

    // MARK: - Names

    static func archiveFileName(for date: Date, suffix: String = "") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let cleanSuffix = suffix.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return "文件打包_\(formatter.string(from: date))\(cleanSuffix).zip"
    }

    private static func sanitized(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "file" : cleaned
    }

    private static func uniqueName(_ name: String, used: inout Set<String>) -> String {
        guard used.contains(name) else {
            used.insert(name)
            return name
        }
        let nsName = name as NSString
        let ext = nsName.pathExtension
        let stem = nsName.deletingPathExtension
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            if !used.contains(candidate) {
                used.insert(candidate)
                return candidate
            }
            index += 1
        }
    }

    private static func filePermissions(for url: URL) -> UInt32 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mode = (attributes?[.posixPermissions] as? NSNumber)?.uint32Value ?? 0o644
        return 0o100000 | (mode & 0o777)
    }

    // MARK: - Dates

    private static func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, min(2107, parts.year ?? 1980))
        let month = max(1, min(12, parts.month ?? 1))
        let day = max(1, min(31, parts.day ?? 1))
        let hour = max(0, min(23, parts.hour ?? 0))
        let minute = max(0, min(59, parts.minute ?? 0))
        let second = max(0, min(59, parts.second ?? 0))
        let dosTime = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
        return (dosTime, dosDate)
    }

    // MARK: - Compression

    private static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        var output = Data(count: data.count + 64 * 1024)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            data.withUnsafeBytes { source -> Int in
                guard let dst = destination.bindMemory(to: UInt8.self).baseAddress,
                      let src = source.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return compression_encode_buffer(
                    dst,
                    destination.count,
                    src,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }
        return output.prefix(written)
    }

    // MARK: - CRC32

    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) != 0 ? (0xEDB88320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { buffer in
            for byte in buffer.bindMemory(to: UInt8.self) {
                crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - Little-endian helpers

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
