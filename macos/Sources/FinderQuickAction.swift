import Foundation
import AppKit

enum FinderQuickActionError: LocalizedError {
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .installFailed(let message):
            return "刷新 Finder 菜单失败：\(message)"
        }
    }
}

/// The app now exposes a native NSService (declared in Info.plist). This type
/// cleans up the old Automator workflow and refreshes the system Services menu.
enum FinderQuickAction {
    static let menuTitle = "用一键邮发送"
    static let workflowName = "用一键邮发送"
    private static let promptKey = "OneClickMail.quickActionPromptShown.v1"

    static var legacyWorkflowURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services/\(workflowName).workflow", isDirectory: true)
    }

    static var isInstalled: Bool {
        !FileManager.default.fileExists(atPath: legacyWorkflowURL.path)
    }

    static var shouldOfferOnLaunch: Bool {
        !UserDefaults.standard.bool(forKey: promptKey)
    }

    static func markPromptHandled() {
        UserDefaults.standard.set(true, forKey: promptKey)
    }

    static func install() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: legacyWorkflowURL.path) {
            do {
                try fileManager.removeItem(at: legacyWorkflowURL)
            } catch {
                throw FinderQuickActionError.installFailed(error.localizedDescription)
            }
        }
        refreshServices()
        markPromptHandled()
    }

    static func refreshServices() {
        NSUpdateDynamicServices()
        let pbs = "/System/Library/CoreServices/pbs"
        guard FileManager.default.isExecutableFile(atPath: pbs) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pbs)
        process.arguments = ["-update"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
