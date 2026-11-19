import Foundation

struct SendPlan {
    let batches: [[URL]]
    let usesZip: Bool
    let totalBytes: Int64
    let limitBytes: Int64

    var limitMB: Int {
        Int(limitBytes / (1024 * 1024))
    }

    var archiveCount: Int {
        usesZip ? max(1, batches.count) : 0
    }
}

enum SendPlanner {
    static func make(files: [URL], config: MailConfig) -> SendPlan {
        let limit = config.attachmentLimitBytes
        guard !files.isEmpty else {
            return SendPlan(batches: [], usesZip: false, totalBytes: 0, limitBytes: limit)
        }

        var totalBytes: Int64 = 0
        let batchLimit = max(1, limit - 1 * 1024 * 1024)
        var batches: [[URL]] = []
        var current: [URL] = []
        var currentBytes: Int64 = 0

        for url in files {
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            totalBytes += size

            if !current.isEmpty && currentBytes + size > batchLimit {
                batches.append(current)
                current = []
                currentBytes = 0
            }
            current.append(url)
            currentBytes += size
        }
        if !current.isEmpty { batches.append(current) }

        // One file below the limit goes as a normal attachment. Two or more
        // files, or a single file at/over the limit, are compressed.
        let usesZip = files.count >= 2 || totalBytes >= limit
        return SendPlan(
            batches: batches,
            usesZip: usesZip,
            totalBytes: totalBytes,
            limitBytes: limit
        )
    }
}

/// Packs already-built ZIP archives into emails. Each email may carry several
/// archives as long as their combined size stays under the provider limit.
enum ArchiveGrouper {
    static func group(sizes: [Int64], limit: Int64) -> [[Int]]? {
        guard !sizes.isEmpty else { return [] }
        if sizes.contains(where: { $0 > limit }) { return nil }

        var groups: [[Int]] = []
        var current: [Int] = []
        var currentSize: Int64 = 0

        for (index, size) in sizes.enumerated() {
            if !current.isEmpty && currentSize + size > limit {
                groups.append(current)
                current = []
                currentSize = 0
            }
            current.append(index)
            currentSize += size
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }
}
