import AppKit
import CoreGraphics
import Foundation

func spaceGuardHomeDirectory() -> String {
    if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty {
        return home
    }
    return NSHomeDirectory()
}

let lastDetectionURL = URL(fileURLWithPath: spaceGuardHomeDirectory())
    .appendingPathComponent(".spaceguard/last-detection.json")
let detectionsDirectoryURL = URL(fileURLWithPath: spaceGuardHomeDirectory())
    .appendingPathComponent(".spaceguard/detections")
let threadSpacesDirectoryURL = URL(fileURLWithPath: spaceGuardHomeDirectory())
    .appendingPathComponent(".spaceguard/thread-spaces")
let pluginInstallURL = URL(fileURLWithPath: spaceGuardHomeDirectory())
    .appendingPathComponent("plugins/spaceguard")
let pluginSkillName = "spaceguard-safe-desktop-operation"
let marketplaceURL = URL(fileURLWithPath: spaceGuardHomeDirectory())
    .appendingPathComponent(".agents/plugins/marketplace.json")
let codexAgentsURL = URL(fileURLWithPath: spaceGuardHomeDirectory())
    .appendingPathComponent(".codex/AGENTS.md")
let highConfidenceCacheMaxAgeSeconds: TimeInterval = 600
let recentLastDetectionMaxAgeSeconds: TimeInterval = 60
let knownElectronWindowMappingMaxAgeSeconds: TimeInterval = 60 * 60 * 36
let currentRendererSnapshotMaxAgeSeconds: TimeInterval = 300
let threadSpaceMaxAgeSeconds: TimeInterval = 60 * 60 * 24 * 30
let currentDetectionSchemaVersion = 4
let currentThreadSpaceSchemaVersion = 4
let spaceGuardRuleBegin = "<!-- BEGIN SPACEGUARD CODEX RULE -->"
let spaceGuardRuleEnd = "<!-- END SPACEGUARD CODEX RULE -->"
let spaceGuardRuleBlock = """
\(spaceGuardRuleBegin)
## SpaceGuard

Before using Chrome, Computer Use, or macOS desktop automation, use SpaceGuard only to identify the target macOS Desktop/Space for this Codex thread.

Run `spaceguard detect --json` and treat the detected `space.desktopName` as the target Space when `confidence` is `high`, `electron-window-inferred`, `thread-bound`, `cached-high`, or `fallback-active-space`.

If multiple Codex windows are open and SpaceGuard cannot infer the current thread's window, stop and ask the user to bring the target Codex thread into view before continuing.

Before using Computer Use for a non-Chrome macOS app, run `spaceguard windows --json` and `spaceguard assert --app "<App Name>"` after `detect`. Continue only when the target app appears in the detected Space.

After `get_app_state("<App Name>")`, continue with clicks, typing, scrolling, dragging, or `set_value` only if the visible window title or content can be matched to a window returned by `spaceguard windows --json` for the detected Space. If the same app has windows in multiple Spaces and the target Space cannot be confirmed, stop instead of operating the app.

Do not move, activate, or reuse an existing window from another Space. If a newly created window appears in the wrong Space, handle it only when you captured `spaceguard windows --all-json` before and after creation and can identify that exact new window; otherwise stop.

Re-run `spaceguard detect --json` at the start of every new assistant turn before using Computer Use. Do not rely on a previous turn's GUI state.

For Chrome tab creation, tab groups, claiming tabs, finalization, and browser operation details, follow the Codex Chrome Extension workflow and the user's global Chrome-operation rules. Do not use SpaceGuard rules as the source of truth for Chrome tab lifecycle.
\(spaceGuardRuleEnd)
"""

let cliUsage = "usage: spaceguard detect [--json] [--thread-id <id>]|windows [--json|--all-json]|assert --app <name>|open-url [--activate] --app \"Google Chrome\" <url>|setup-codex [--with-agents-rule] [--dry-run] [--yes]|uninstall [--dry-run] [--yes] [--keep-agents-rule]|menubar|status|clear [--all-stale]"

struct WindowInfo {
    let id: Int
    let owner: String
    let title: String
    let layer: Int
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct WindowPayload: Encodable {
    let id: Int
    let owner: String
    let title: String
    let layer: Int
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct SpacePayload: Encodable {
    let uuid: String
    let internalSpaceId: Int?
    let desktopIndex: Int?
    let desktopName: String
}

struct DetectionPayload: Encodable {
    let ok: Bool
    let confidence: String
    let threadId: String
    let threadName: String?
    let electronWindowId: String?
    let codexWindow: WindowPayload
    let space: SpacePayload
    let codexWindowsInSpace: Int
    let detectedAt: String
}

struct WindowsPayload: Encodable {
    let ok: Bool
    let source: String
    let confidence: String
    let threadId: String
    let threadName: String?
    let detectedAt: String
    let space: SpacePayload
    let windows: [WindowPayload]
}

struct SpaceWindowsPayload: Encodable {
    let space: SpacePayload
    let windows: [WindowPayload]
}

struct AllWindowsPayload: Encodable {
    let ok: Bool
    let source: String
    let threadId: String?
    let threadName: String?
    let targetSpace: SpacePayload?
    let capturedAt: String
    let windows: [WindowPayload]?
    let spaces: [SpaceWindowsPayload]
}

struct ErrorPayload: Encodable {
    let ok: Bool
    let error: String
}

struct SetupCodexOptions {
    let dryRun: Bool
    let yes: Bool
    let withAgentsRule: Bool
}

struct UninstallOptions {
    let dryRun: Bool
    let yes: Bool
    let keepAgentsRule: Bool
}

struct SpaceInfo {
    let uuid: String
    let id: Int?
    let desktopIndex: Int?
    let windows: [Int]
}

struct SpacesSnapshot {
    let spaces: [SpaceInfo]
    let activeSpaceUuids: Set<String>
}

struct RectInfo {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct DetectionResult {
    let confidence: String
    let threadId: String
    let threadName: String?
    let electronWindowId: String?
    let window: WindowInfo
    let space: SpaceInfo
    let codexWindowsInSpace: Int
}

struct DetectionError: Error {
    let message: String
}

struct LastDetection: Codable {
    let schemaVersion: Int?
    let confidence: String
    let threadId: String
    let threadName: String?
    let electronWindowId: String?
    let cgWindowId: Int
    let desktopIndex: Int?
    let internalSpaceId: Int?
    let spaceUuid: String
    let codexWindowsInSpace: Int
    let detectedAt: String
}

struct ThreadSpaceBinding: Codable {
    let schemaVersion: Int?
    let threadId: String
    let threadName: String?
    let electronWindowId: String?
    let cgWindowId: Int
    let desktopIndex: Int?
    let internalSpaceId: Int?
    let spaceUuid: String
    let codexWindowsInSpace: Int
    let createdAt: String
    let detectedAt: String
    let lastUsedAt: String
}

enum SpaceGuardCore {
    static func loadSpaces() -> [SpaceInfo] {
        loadSpacesSnapshot().spaces
    }

    static func loadSpacesSnapshot() -> SpacesSnapshot {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["export", "com.apple.spaces", "-"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return SpacesSnapshot(spaces: [], activeSpaceUuids: [])
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let root = plist as? [String: Any],
            let config = root["SpacesDisplayConfiguration"] as? [String: Any]
        else {
            return SpacesSnapshot(spaces: [], activeSpaceUuids: [])
        }

        var idsByUuid: [String: Int] = [:]
        var desktopIndexesByUuid: [String: Int] = [:]
        var activeSpaceUuids = Set<String>()
        if
            let managementData = config["Management Data"] as? [String: Any],
            let monitors = managementData["Monitors"] as? [[String: Any]]
        {
            for monitor in monitors {
                if let spaces = monitor["Spaces"] as? [[String: Any]] {
                    for (index, space) in spaces.enumerated() {
                        if let uuid = space["uuid"] as? String {
                            idsByUuid[uuid] = space["ManagedSpaceID"] as? Int
                            desktopIndexesByUuid[uuid] = index + 1
                        }
                    }
                }
                if
                    let current = monitor["Current Space"] as? [String: Any],
                    let uuid = current["uuid"] as? String
                {
                    idsByUuid[uuid] = current["ManagedSpaceID"] as? Int
                    activeSpaceUuids.insert(uuid)
                }
                if
                    let collapsed = monitor["Collapsed Space"] as? [String: Any],
                    let uuid = collapsed["uuid"] as? String
                {
                    idsByUuid[uuid] = collapsed["ManagedSpaceID"] as? Int
                }
            }
        }

        guard let properties = config["Space Properties"] as? [[String: Any]] else {
            return SpacesSnapshot(spaces: [], activeSpaceUuids: activeSpaceUuids)
        }

        let spaces: [SpaceInfo] = properties.compactMap { property in
            guard let uuid = property["name"] as? String else {
                return nil
            }
            return SpaceInfo(
                uuid: uuid,
                id: idsByUuid[uuid],
                desktopIndex: desktopIndexesByUuid[uuid],
                windows: property["windows"] as? [Int] ?? []
            )
        }
        return SpacesSnapshot(spaces: spaces, activeSpaceUuids: activeSpaceUuids)
    }

    static func loadWindows() -> [Int: WindowInfo] {
        let raw = CGWindowListCopyWindowInfo(.optionAll, CGWindowID(0)) as? [[String: Any]] ?? []
        var windows: [Int: WindowInfo] = [:]

        for item in raw {
            guard let id = item[kCGWindowNumber as String] as? Int else {
                continue
            }
            let owner = item[kCGWindowOwnerName as String] as? String ?? ""
            let title = item[kCGWindowName as String] as? String ?? ""
            let layer = item[kCGWindowLayer as String] as? Int ?? 0
            let bounds = item[kCGWindowBounds as String] as? [String: Any] ?? [:]
            windows[id] = WindowInfo(
                id: id,
                owner: owner,
                title: title,
                layer: layer,
                x: bounds["X"] as? Double ?? 0,
                y: bounds["Y"] as? Double ?? 0,
                width: bounds["Width"] as? Double ?? 0,
                height: bounds["Height"] as? Double ?? 0
            )
        }

        return windows
    }

    static func saveLastDetection(_ detection: DetectionResult) {
        cleanupStaleThreadSpaces()
        try? FileManager.default.createDirectory(
            at: lastDetectionURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let storedConfidence = detection.confidence == "cached-high" ? "high" : detection.confidence
        let payload = LastDetection(
            schemaVersion: currentDetectionSchemaVersion,
            confidence: storedConfidence,
            threadId: detection.threadId,
            threadName: detection.threadName,
            electronWindowId: detection.electronWindowId,
            cgWindowId: detection.window.id,
            desktopIndex: detection.space.desktopIndex,
            internalSpaceId: detection.space.id,
            spaceUuid: detection.space.uuid,
            codexWindowsInSpace: detection.codexWindowsInSpace,
            detectedAt: ISO8601DateFormatter().string(from: Date())
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(payload) {
            try? data.write(to: lastDetectionURL)
            try? FileManager.default.createDirectory(
                at: detectionsDirectoryURL,
                withIntermediateDirectories: true
            )
            try? data.write(to: detectionURL(threadId: detection.threadId))
        }
        if detection.confidence == "high" || detection.confidence == "electron-window-inferred" {
            saveThreadSpaceBinding(detection)
        }
    }

    static func loadLastDetection() -> LastDetection? {
        guard let data = try? Data(contentsOf: lastDetectionURL) else {
            return nil
        }
        guard
            let detection = try? JSONDecoder().decode(LastDetection.self, from: data),
            detection.schemaVersion == currentDetectionSchemaVersion
        else {
            return nil
        }
        return detection
    }

    static func detectionURL(threadId: String) -> URL {
        detectionsDirectoryURL.appendingPathComponent("\(safeFileName(threadId)).json")
    }

    static func threadSpaceURL(threadId: String) -> URL {
        threadSpacesDirectoryURL.appendingPathComponent("\(safeFileName(threadId)).json")
    }

    static func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    static func loadDetection(threadId: String) -> LastDetection? {
        if
            let data = try? Data(contentsOf: detectionURL(threadId: threadId)),
            let detection = try? JSONDecoder().decode(LastDetection.self, from: data),
            detection.schemaVersion == currentDetectionSchemaVersion
        {
            return detection
        }
        if let detection = loadLastDetection(), detection.threadId == threadId {
            return detection
        }
        return nil
    }

    static func saveThreadSpaceBinding(_ detection: DetectionResult) {
        let now = ISO8601DateFormatter().string(from: Date())
        let existing = loadThreadSpaceBinding(threadId: detection.threadId, updateLastUsedAt: false)
        let binding = ThreadSpaceBinding(
            schemaVersion: currentThreadSpaceSchemaVersion,
            threadId: detection.threadId,
            threadName: detection.threadName,
            electronWindowId: detection.electronWindowId,
            cgWindowId: detection.window.id,
            desktopIndex: detection.space.desktopIndex,
            internalSpaceId: detection.space.id,
            spaceUuid: detection.space.uuid,
            codexWindowsInSpace: detection.codexWindowsInSpace,
            createdAt: existing?.createdAt ?? now,
            detectedAt: now,
            lastUsedAt: now
        )
        try? FileManager.default.createDirectory(
            at: threadSpacesDirectoryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(binding) {
            try? data.write(to: threadSpaceURL(threadId: detection.threadId))
        }
    }

    static func loadThreadSpaceBinding(
        threadId: String,
        updateLastUsedAt: Bool = true
    ) -> ThreadSpaceBinding? {
        cleanupStaleThreadSpaces()
        guard
            let data = try? Data(contentsOf: threadSpaceURL(threadId: threadId)),
            let binding = try? JSONDecoder().decode(ThreadSpaceBinding.self, from: data),
            binding.schemaVersion == currentThreadSpaceSchemaVersion,
            !isStaleThreadSpace(binding),
            !isThreadSpaceSupersededByDetection(binding)
        else {
            return nil
        }
        if updateLastUsedAt {
            touchThreadSpaceBinding(binding)
        }
        return binding
    }

    static func touchThreadSpaceBinding(_ binding: ThreadSpaceBinding) {
        let updated = ThreadSpaceBinding(
            schemaVersion: currentThreadSpaceSchemaVersion,
            threadId: binding.threadId,
            threadName: binding.threadName,
            electronWindowId: binding.electronWindowId,
            cgWindowId: binding.cgWindowId,
            desktopIndex: binding.desktopIndex,
            internalSpaceId: binding.internalSpaceId,
            spaceUuid: binding.spaceUuid,
            codexWindowsInSpace: binding.codexWindowsInSpace,
            createdAt: binding.createdAt,
            detectedAt: binding.detectedAt,
            lastUsedAt: ISO8601DateFormatter().string(from: Date())
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(updated) {
            try? data.write(to: threadSpaceURL(threadId: binding.threadId))
        }
    }

    static func isStaleThreadSpace(_ binding: ThreadSpaceBinding) -> Bool {
        guard let lastUsedAt = date(from: binding.lastUsedAt) else {
            return true
        }
        return Date().timeIntervalSince(lastUsedAt) > threadSpaceMaxAgeSeconds
    }

    static func isThreadSpaceSupersededByDetection(_ binding: ThreadSpaceBinding) -> Bool {
        guard
            let detection = loadDetection(threadId: binding.threadId),
            detection.threadId == binding.threadId,
            detectionConflictsWithBinding(detection, binding),
            let detectedAt = date(from: detection.detectedAt),
            let bindingDetectedAt = date(from: binding.detectedAt)
        else {
            return false
        }
        return detectedAt > bindingDetectedAt
    }

    static func detectionConflictsWithBinding(_ detection: LastDetection, _ binding: ThreadSpaceBinding) -> Bool {
        detection.spaceUuid != binding.spaceUuid
            || detection.desktopIndex != binding.desktopIndex
            || detection.internalSpaceId != binding.internalSpaceId
    }

    static func cleanupStaleThreadSpaces() {
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: threadSpacesDirectoryURL,
                includingPropertiesForKeys: nil
            )
        else {
            return
        }
        for url in urls where url.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: url),
                let binding = try? JSONDecoder().decode(ThreadSpaceBinding.self, from: data)
            else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            if
                binding.schemaVersion != currentThreadSpaceSchemaVersion
                    || isStaleThreadSpace(binding)
                    || isThreadSpaceSupersededByDetection(binding)
            {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    static func clearCurrentThreadState() {
        if let threadId = currentThreadId() {
            try? FileManager.default.removeItem(at: detectionURL(threadId: threadId))
            try? FileManager.default.removeItem(at: threadSpaceURL(threadId: threadId))
            if loadLastDetection()?.threadId == threadId {
                try? FileManager.default.removeItem(at: lastDetectionURL)
            }
        }
    }

    static func lastDetection(from binding: ThreadSpaceBinding) -> LastDetection {
        LastDetection(
            schemaVersion: currentDetectionSchemaVersion,
            confidence: "thread-bound",
            threadId: binding.threadId,
            threadName: binding.threadName,
            electronWindowId: binding.electronWindowId,
            cgWindowId: binding.cgWindowId,
            desktopIndex: binding.desktopIndex,
            internalSpaceId: binding.internalSpaceId,
            spaceUuid: binding.spaceUuid,
            codexWindowsInSpace: binding.codexWindowsInSpace,
            detectedAt: binding.detectedAt
        )
    }

    static func currentThreadId() -> String? {
        let value = ProcessInfo.processInfo.environment["CODEX_THREAD_ID"]
        if let value, !value.isEmpty {
            return value
        }
        return nil
    }

    static func loadCurrentThreadDetection(threadId explicitThreadId: String? = nil) -> Result<LastDetection, DetectionError> {
        guard let threadId = explicitThreadId ?? currentThreadId() else {
            return .failure(DetectionError(message: "NG CODEX_THREAD_ID is missing"))
        }
        if let binding = loadThreadSpaceBinding(threadId: threadId) {
            return .success(lastDetection(from: binding))
        }
        guard let detection = loadDetection(threadId: threadId) else {
            return .failure(DetectionError(message: "NG current thread has not been detected yet"))
        }
        guard detection.threadId == threadId else {
            return .failure(DetectionError(message: "NG last detection belongs to another thread. expected=\(threadId) actual=\(detection.threadId). Run `spaceguard detect --json` in this thread before operating windows."))
        }
        guard isUsableStoredDetection(detection) else {
            return .failure(DetectionError(message: "NG current thread detection is stale. Run `spaceguard detect --json` again before operating windows."))
        }
        return .success(detection)
    }

    static func loadRecentLastDetection() -> LastDetection? {
        guard
            let detection = loadLastDetection(),
            isRecentDetection(detection, maxAge: recentLastDetectionMaxAgeSeconds)
        else {
            return nil
        }
        return detection
    }

    static func displayName(_ window: WindowInfo) -> String {
        let title = window.title.isEmpty ? "(no title)" : window.title
        return "\(window.owner) #\(window.id) - \(title)"
    }

    static func userDisplayName(_ window: WindowInfo) -> String {
        if window.title.isEmpty {
            return "\(window.owner) #\(window.id)"
        }
        return "\(window.owner) #\(window.id) - \(window.title)"
    }

    static func windowPayload(_ window: WindowInfo) -> WindowPayload {
        WindowPayload(
            id: window.id,
            owner: window.owner,
            title: window.title,
            layer: window.layer,
            x: window.x,
            y: window.y,
            width: window.width,
            height: window.height
        )
    }

    static func spacePayload(_ space: SpaceInfo) -> SpacePayload {
        SpacePayload(
            uuid: space.uuid,
            internalSpaceId: space.id,
            desktopIndex: space.desktopIndex,
            desktopName: spaceLabel(space)
        )
    }

    static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
            print(text)
        } else {
            print(#"{"ok":false,"error":"failed to encode json"}"#)
        }
    }

    static func spaceLabel(_ space: SpaceInfo) -> String {
        if let desktopIndex = space.desktopIndex {
            return "デスクトップ\(desktopIndex)"
        }
        return "Space \(space.id.map(String.init) ?? "?")"
    }

    static func date(from value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    static func stateSpaceLabel(spaceId: Int?, uuid: String) -> String {
        if let space = loadSpaces().first(where: { $0.uuid == uuid }) {
            return spaceLabel(space)
        }
        return "Space \(spaceId.map(String.init) ?? "?")"
    }

    static func statusText() -> String {
        cleanupStaleThreadSpaces()
        guard let threadId = currentThreadId() else {
            return "UNBOUND CODEX_THREAD_ID is missing"
        }
        if let binding = loadThreadSpaceBinding(threadId: threadId, updateLastUsedAt: false) {
            let spaceLabel = stateSpaceLabel(spaceId: binding.internalSpaceId, uuid: binding.spaceUuid)
            return [
                "OK thread-bound \(spaceLabel) internalSpace=\(binding.internalSpaceId.map(String.init) ?? "?") uuid=\(binding.spaceUuid)",
                "thread=\(binding.threadName ?? binding.threadId)",
                "window=\(binding.cgWindowId) createdAt=\(binding.createdAt) detectedAt=\(binding.detectedAt) lastUsedAt=\(binding.lastUsedAt)",
            ].joined(separator: "\n")
        }
        guard let detection = loadDetection(threadId: threadId) else {
            return "UNBOUND thread=\(threadId)"
        }
        let spaceLabel = stateSpaceLabel(spaceId: detection.internalSpaceId, uuid: detection.spaceUuid)
        return [
            "OK detection \(spaceLabel) internalSpace=\(detection.internalSpaceId.map(String.init) ?? "?") uuid=\(detection.spaceUuid)",
            "thread=\(detection.threadName ?? detection.threadId)",
            "confidence=\(detection.confidence) window=\(detection.cgWindowId) detectedAt=\(detection.detectedAt)",
        ].joined(separator: "\n")
    }

    static func allSpacesText() -> String {
        let spaces = loadSpaces()
        let windows = loadWindows()
        let binding = currentThreadId().flatMap { loadThreadSpaceBinding(threadId: $0, updateLastUsedAt: false) }
        if spaces.isEmpty {
            return "No Spaces found"
        }

        return spaces.map { space in
            let marker = binding?.spaceUuid == space.uuid ? "*" : " "
            let visibleWindows = space.windows.compactMap { windows[$0] }.filter { $0.layer == 0 }
            let apps = Array(Set(visibleWindows.map(\.owner))).sorted().joined(separator: ", ")
            return "\(marker) \(spaceLabel(space)) windows=\(visibleWindows.count) \(apps)"
        }.joined(separator: "\n")
    }

    static func normalizedAppName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func candidateAppNames(for app: String) -> Set<String> {
        var names = Set<String>()
        func add(_ value: String?) {
            guard let value, !value.isEmpty else {
                return
            }
            names.insert(normalizedAppName(value))
            let lastPathComponent = URL(fileURLWithPath: value).lastPathComponent
            if !lastPathComponent.isEmpty && lastPathComponent != value {
                names.insert(normalizedAppName(lastPathComponent))
            }
            if lastPathComponent.hasSuffix(".app") {
                names.insert(normalizedAppName(String(lastPathComponent.dropLast(4))))
            }
        }

        add(app)
        if normalizedAppName(app) == "chrome" {
            add("Google Chrome")
            add("com.google.Chrome")
            add("Google Chrome.app")
            add("/Applications/Google Chrome.app")
        }
        let queryNames = names
        for application in NSWorkspace.shared.runningApplications {
            let values = [
                application.localizedName,
                application.bundleIdentifier,
                application.bundleURL?.path,
                application.bundleURL?.lastPathComponent,
                application.bundleURL?.deletingPathExtension().lastPathComponent,
                application.executableURL?.lastPathComponent,
            ]
            let applicationNames = Set(values.compactMap { value -> String? in
                guard let value, !value.isEmpty else {
                    return nil
                }
                return normalizedAppName(value)
            })
            if !queryNames.isDisjoint(with: applicationNames) {
                for value in values {
                    add(value)
                }
            }
        }
        return names
    }

    static func assertText(app: String) -> (String, Int32) {
        let detectionResult = loadCurrentThreadDetection()
        guard case .success(let detection) = detectionResult else {
            if case .failure(let error) = detectionResult {
                return (error.message, 1)
            }
            return ("NG current thread has not been detected yet", 1)
        }
        guard let space = loadSpaces().first(where: { $0.uuid == detection.spaceUuid }) else {
            return ("NG last detected Space was not found", 1)
        }
        let windows = loadWindows()
        if detection.electronWindowId == nil && detection.codexWindowsInSpace > 1 {
            return ("NG last detection is ambiguous because multiple Codex windows are in the target Space and no thread/window hint was saved. Bring the target Codex thread into view, then run `spaceguard clear` and `spaceguard detect --json` again.", 1)
        }
        let appNames = candidateAppNames(for: app)
        let matches = space.windows.compactMap { windows[$0] }.filter {
            appNames.contains(normalizedAppName($0.owner)) && $0.layer == 0 && $0.width > 20 && $0.height > 20
        }
        if matches.isEmpty {
            return ("NG no \(app) window in \(spaceLabel(space))", 1)
        }
        return (["OK \(matches.count) \(app) window(s) in \(spaceLabel(space))"] + matches.map(displayName)).joined(separator: "\n").withExit(0)
    }

    static func openURLText(app: String, url: String, activate: Bool) -> (String, Int32) {
        let appNames = candidateAppNames(for: app)
        if !appNames.contains(normalizedAppName("Google Chrome")) && !appNames.contains(normalizedAppName("com.google.Chrome")) {
            return ("NG open-url currently supports only Google Chrome", 1)
        }
        guard URL(string: url)?.scheme != nil else {
            return ("NG invalid URL: \(url)", 1)
        }
        let detectionResult = loadCurrentThreadDetection()
        guard case .success(let detection) = detectionResult else {
            if case .failure(let error) = detectionResult {
                return (error.message, 1)
            }
            return ("NG current thread has not been detected yet", 1)
        }
        guard let space = loadSpaces().first(where: { $0.uuid == detection.spaceUuid }) else {
            return ("NG last detected Space was not found", 1)
        }
        let windows = loadWindows()
        if detection.electronWindowId == nil && detection.codexWindowsInSpace > 1 {
            return ("NG last detection is ambiguous because multiple Codex windows are in the target Space and no thread/window hint was saved. Bring the target Codex thread into view, then run `spaceguard clear` and `spaceguard detect --json` again.", 1)
        }
        let matches = space.windows.compactMap { windows[$0] }.filter {
            appNames.contains(normalizedAppName($0.owner)) && $0.layer == 0 && $0.width > 20 && $0.height > 20
        }
        guard let window = matches.first else {
            return ("NG no \(app) window in \(spaceLabel(space))", 1)
        }
        return openChromeURL(window: window, url: url, space: space, activate: activate)
    }

    static func openChromeURL(window: WindowInfo, url: String, space: SpaceInfo, activate: Bool) -> (String, Int32) {
        let left = Int(window.x.rounded())
        let top = Int(window.y.rounded())
        let right = Int((window.x + window.width).rounded())
        let bottom = Int((window.y + window.height).rounded())
        let script = """
        on run argv
          set targetTitle to item 1 of argv
          set targetLeft to item 2 of argv as integer
          set targetTop to item 3 of argv as integer
          set targetRight to item 4 of argv as integer
          set targetBottom to item 5 of argv as integer
          set targetURL to item 6 of argv
          set shouldActivate to item 7 of argv is "1"

          tell application "Google Chrome"
            repeat with w in windows
              set b to bounds of w
              set titleText to title of w
              set leftDiff to my absValue((item 1 of b) - targetLeft)
              set topDiff to my absValue((item 2 of b) - targetTop)
              set rightDiff to my absValue((item 3 of b) - targetRight)
              set bottomDiff to my absValue((item 4 of b) - targetBottom)
              set boundsMatch to leftDiff <= 3 and topDiff <= 3 and rightDiff <= 3 and bottomDiff <= 3
              set titleMatch to titleText is targetTitle or targetTitle is "" or titleText contains targetTitle or targetTitle contains titleText
              if boundsMatch and titleMatch then
                set previousActiveTabIndex to active tab index of w
                make new tab at end of tabs of w with properties {URL:targetURL}
                if shouldActivate then
                  set index of w to 1
                  set active tab index of w to (count of tabs of w)
                  activate
                  return "OK opened URL in target Google Chrome window"
                end if
                set active tab index of w to previousActiveTabIndex
                return "OK opened background URL in target Google Chrome window"
              end if
            end repeat
          end tell
          return "NG matching Google Chrome window was not found"
        end run

        on absValue(n)
          if n < 0 then return -n
          return n
        end absValue
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = [
            "-e", script,
            window.title,
            String(left),
            String(top),
            String(right),
            String(bottom),
            url,
            activate ? "1" : "0"
        ]

        let pipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ("NG failed to run osascript: \(error.localizedDescription)", 1)
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if task.terminationStatus == 0 && output.hasPrefix("OK") {
            return ("\(output) in \(spaceLabel(space))\n\(displayName(window))", 0)
        }
        if !error.isEmpty {
            return ("NG \(error)", 1)
        }
        return (output.isEmpty ? "NG failed to open URL in target Google Chrome window" : output, 1)
    }

    static func codexMainWindowRect() -> RectInfo? {
        let script = """
        tell application "System Events"
          tell process "Codex"
            repeat with w in windows
              try
                if (value of attribute "AXMain" of w) is true then
                  set p to position of w
                  set s to size of w
                  return (item 1 of p as text) & "," & (item 2 of p as text) & "," & (item 1 of s as text) & "," & (item 2 of s as text)
                end if
              end try
            end repeat
          end tell
        end tell
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            let semaphore = DispatchSemaphore(value: 0)
            task.terminationHandler = { _ in
                semaphore.signal()
            }
            if semaphore.wait(timeout: .now() + 3) == .timedOut {
                task.terminate()
                return nil
            }
        } catch {
            return nil
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = output.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4 else {
            return nil
        }
        return RectInfo(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    static func latestCodexElectronWindowId(threadId: String) -> String? {
        let path = "\(NSHomeDirectory())/Library/Application Support/Codex/sentry/scope_v3.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        let breadcrumbs = sentryBreadcrumbs(from: data)
        guard currentThreadId() == threadId else {
            return latestBrowserSessionWindowId(threadId: threadId, breadcrumbs: breadcrumbs)
        }

        if let rendererId = latestCurrentRendererWebContentsId(breadcrumbs: breadcrumbs) {
            return rendererId
        }
        return latestBrowserSessionWindowId(threadId: threadId, breadcrumbs: breadcrumbs)
    }

    static func sentryBreadcrumbs(from data: Data) -> [[String: Any]] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let scope = root["scope"] as? [String: Any],
            let breadcrumbs = scope["breadcrumbs"] as? [[String: Any]]
        else {
            return []
        }
        return breadcrumbs
    }

    static func latestBrowserSessionWindowId(threadId: String, breadcrumbs: [[String: Any]]) -> String? {
        let pattern = #"conversationId=\#(NSRegularExpression.escapedPattern(for: threadId))\b[^"]*?windowId=([0-9]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let now = Date().timeIntervalSince1970
        for breadcrumb in breadcrumbs.reversed() {
            guard
                let message = breadcrumb["message"] as? String,
                let timestamp = breadcrumb["timestamp"] as? NSNumber,
                now >= timestamp.doubleValue,
                now - timestamp.doubleValue <= currentRendererSnapshotMaxAgeSeconds
            else {
                continue
            }
            let range = NSRange(message.startIndex..<message.endIndex, in: message)
            guard
                let match = regex.firstMatch(in: message, options: [], range: range),
                let idRange = Range(match.range(at: 1), in: message)
            else {
                continue
            }
            return String(message[idRange])
        }
        return nil
    }

    static func latestCurrentRendererWebContentsId(breadcrumbs: [[String: Any]]) -> String? {
        let now = Date().timeIntervalSince1970
        for breadcrumb in breadcrumbs.reversed() {
            guard
                let message = breadcrumb["message"] as? String,
                message == "app_state_snapshot",
                let timestamp = breadcrumb["timestamp"] as? NSNumber,
                now >= timestamp.doubleValue,
                now - timestamp.doubleValue <= currentRendererSnapshotMaxAgeSeconds,
                let data = breadcrumb["data"] as? [String: Any],
                let rendererId = data["renderer_webcontents_id"] as? NSNumber
            else {
                continue
            }
            return rendererId.stringValue
        }
        return nil
    }

    static func currentThreadName(threadId: String) -> String? {
        if let name = currentThreadNameFromSessionIndex(threadId: threadId) {
            return name
        }
        return currentThreadNameFromSQLite(threadId: threadId)
    }

    static func currentThreadNameFromSessionIndex(threadId: String) -> String? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex/session_index.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        var latestName: String?
        for line in text.split(separator: "\n") {
            guard
                let data = String(line).data(using: .utf8),
                let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                item["id"] as? String == threadId,
                let name = item["thread_name"] as? String,
                !name.isEmpty
            else {
                continue
            }
            latestName = name
        }
        return latestName
    }

    static func currentThreadNameFromSQLite(threadId: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        task.arguments = [
            "\(NSHomeDirectory())/.codex/state_5.sqlite",
            "select title from threads where id='\(threadId.replacingOccurrences(of: "'", with: "''"))' limit 1;"
        ]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            if !task.waitUntilExit(seconds: 2) {
                task.terminate()
                return nil
            }
        } catch {
            return nil
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let output, !output.isEmpty {
            return output.split(separator: "\n").first.map(String.init)
        }
        return nil
    }

    static func detectCurrentThread(threadId: String?) -> (String, Int32) {
        let result = detectCurrentThreadResult(threadId: threadId)
        switch result {
        case .success(let detection):
            saveLastDetection(detection)
            return (formatDetection(detection), 0)
        case .failure(let error):
            if let cached = cachedDetectionText(threadId: threadId) {
                return (cached, 0)
            }
            return (error.message, 1)
        }
    }

    static func detectCurrentThreadJSON(threadId: String?) -> Int32 {
        let result = detectCurrentThreadResult(threadId: threadId)
        switch result {
        case .success(let detection):
            saveLastDetection(detection)
            printJSON(DetectionPayload(
                ok: true,
                confidence: detection.confidence,
                threadId: detection.threadId,
                threadName: detection.threadName,
                electronWindowId: detection.electronWindowId,
                codexWindow: windowPayload(detection.window),
                space: spacePayload(detection.space),
                codexWindowsInSpace: detection.codexWindowsInSpace,
                detectedAt: ISO8601DateFormatter().string(from: Date())
            ))
            return 0
        case .failure(let error):
            if let cached = cachedDetectionPayload(threadId: threadId) {
                printJSON(cached)
                return 0
            }
            printJSON(ErrorPayload(ok: false, error: error.message))
            return 1
        }
    }

    static func cachedDetectionText(threadId: String?) -> String? {
        guard
            let threadId,
            let cached = loadDetection(threadId: threadId),
            let space = loadSpaces().first(where: { $0.uuid == cached.spaceUuid })
        else {
            return nil
        }
        let windows = loadWindows()
        if cached.electronWindowId == nil && cached.codexWindowsInSpace > 1 {
            return nil
        }
        let title = windows[cached.cgWindowId].map(displayName) ?? "Codex #\(cached.cgWindowId)"
        return ("""
        OK confidence=cached-\(cached.confidence) thread=\(cached.threadId) electronWindowId=\(cached.electronWindowId ?? "?") cgWindowId=\(cached.cgWindowId) desktop=\(space.desktopIndex.map(String.init) ?? "?") internalSpace=\(space.id.map(String.init) ?? "?") uuid=\(space.uuid)
        \(title)
        codexWindowsInSpace=\(cached.codexWindowsInSpace)
        """)
    }

    static func cachedDetectionPayload(threadId: String?) -> DetectionPayload? {
        guard
            let threadId,
            let cached = loadDetection(threadId: threadId),
            let space = loadSpaces().first(where: { $0.uuid == cached.spaceUuid })
        else {
            return nil
        }
        let windows = loadWindows()
        let window = windows[cached.cgWindowId] ?? WindowInfo(
            id: cached.cgWindowId,
            owner: "Codex",
            title: "Codex",
            layer: 0,
            x: 0,
            y: 0,
            width: 0,
            height: 0
        )
        if cached.electronWindowId == nil && cached.codexWindowsInSpace > 1 {
            return nil
        }
        return DetectionPayload(
            ok: true,
            confidence: "cached-\(cached.confidence)",
            threadId: cached.threadId,
            threadName: cached.threadName,
            electronWindowId: cached.electronWindowId,
            codexWindow: windowPayload(window),
            space: spacePayload(space),
            codexWindowsInSpace: cached.codexWindowsInSpace,
            detectedAt: cached.detectedAt
        )
    }

    static func detectCurrentThreadResult(threadId: String?) -> Result<DetectionResult, DetectionError> {
        guard let threadId, !threadId.isEmpty else {
            return .failure(DetectionError(message: "NG CODEX_THREAD_ID is missing"))
        }
        let snapshot = loadSpacesSnapshot()
        let spaces = snapshot.spaces
        let windows = loadWindows()
        let electronId = latestCodexElectronWindowId(threadId: threadId)
        let totalCodexWindows = windows.values.filter(isCodexWindowCandidate).count
        if totalCodexWindows > 1 {
            if
                let inferred = inferredElectronWindowDetection(
                    threadId: threadId,
                    threadName: currentThreadName(threadId: threadId),
                    electronId: electronId,
                    spaces: spaces,
                    windows: windows
                )
            {
                return .success(inferred)
            }
            if let bound = threadSpaceDetectionResult(threadId: threadId, spaces: spaces, windows: windows) {
                return .success(bound)
            }
            if let cached = cachedDetectionResult(threadId: threadId, spaces: spaces, windows: windows) {
                return .success(cached)
            }
            return .failure(DetectionError(message: "NG multiple Codex windows are open and the native Codex window cannot be mapped safely to the current thread. Bring the target Codex thread into view, then close extra Codex windows or use an existing thread-bound/cached-high detection before operating windows."))
        }
        guard let rect = codexMainWindowRect() else {
            return activeSpaceFallbackDetection(
                threadId: threadId,
                threadName: currentThreadName(threadId: threadId),
                electronId: electronId,
                snapshot: snapshot,
                windows: windows,
                failureReason: "Codex AX main window not found"
            )
        }
        let candidates = windows.values.filter {
            $0.owner == "Codex"
                && $0.layer == 0
                && abs($0.x - rect.x) < 2
                && abs($0.y - rect.y) < 2
                && abs($0.width - rect.width) < 2
                && abs($0.height - rect.height) < 2
        }

        guard candidates.count == 1, let window = candidates.first else {
            return activeSpaceFallbackDetection(
                threadId: threadId,
                threadName: currentThreadName(threadId: threadId),
                electronId: electronId,
                snapshot: snapshot,
                windows: windows,
                failureReason: "expected 1 Codex CGWindow match, got \(candidates.count) for AX rect x=\(rect.x) y=\(rect.y) w=\(rect.width) h=\(rect.height)"
            )
        }
        guard let space = spaces.first(where: { $0.windows.contains(window.id) }) else {
            return activeSpaceFallbackDetection(
                threadId: threadId,
                threadName: currentThreadName(threadId: threadId),
                electronId: electronId,
                snapshot: snapshot,
                windows: windows,
                failureReason: "matched \(displayName(window)) but no Space contains it"
            )
        }

        let codexCountInSpace = space.windows.compactMap { windows[$0] }.filter(isCodexWindowCandidate).count
        if
            let bound = threadSpaceDetectionResult(threadId: threadId, spaces: spaces, windows: windows),
            bound.window.id == window.id,
            bound.space.uuid == space.uuid
        {
            return .success(bound)
        }
        return .success(DetectionResult(
            confidence: "high",
            threadId: threadId,
            threadName: currentThreadName(threadId: threadId),
            electronWindowId: electronId,
            window: window,
            space: space,
            codexWindowsInSpace: codexCountInSpace
        ))
    }

    static func activeSpaceFallbackDetection(
        threadId: String,
        threadName: String?,
        electronId: String?,
        snapshot: SpacesSnapshot,
        windows: [Int: WindowInfo],
        failureReason: String
    ) -> Result<DetectionResult, DetectionError> {
        let totalCodexWindows = windows.values.filter(isCodexWindowCandidate).count
        if totalCodexWindows <= 1, let bound = threadSpaceDetectionResult(threadId: threadId, spaces: snapshot.spaces, windows: windows) {
            return .success(bound)
        }
        if totalCodexWindows <= 1, let cached = cachedDetectionResult(threadId: threadId, spaces: snapshot.spaces, windows: windows) {
            return .success(cached)
        }
        if totalCodexWindows > 1 {
            return .failure(DetectionError(message: "NG \(failureReason); active Space fallback is disabled while multiple Codex windows are open for thread=\(threadId)"))
        }

        let activeSpaces = snapshot.spaces.filter { snapshot.activeSpaceUuids.contains($0.uuid) }
        let activeCodexMatches = activeSpaces.flatMap { space in
            space.windows.compactMap { id -> (SpaceInfo, WindowInfo)? in
                guard let window = windows[id], isCodexWindowCandidate(window) else {
                    return nil
                }
                return (space, window)
            }
        }
        guard activeCodexMatches.count == 1, let match = activeCodexMatches.first else {
            return .failure(DetectionError(message: "NG \(failureReason); active Space Codex fallback expected 1 match, got \(activeCodexMatches.count) for thread=\(threadId)"))
        }
        let codexCountInSpace = match.0.windows.compactMap { windows[$0] }.filter(isCodexWindowCandidate).count
        return .success(DetectionResult(
            confidence: "fallback-active-space",
            threadId: threadId,
            threadName: threadName,
            electronWindowId: electronId,
            window: match.1,
            space: match.0,
            codexWindowsInSpace: codexCountInSpace
        ))
    }

    static func inferredElectronWindowDetection(
        threadId: String,
        threadName: String?,
        electronId: String?,
        spaces: [SpaceInfo],
        windows: [Int: WindowInfo]
    ) -> DetectionResult? {
        guard let electronId else {
            return nil
        }
        let codexWindows = windows.values.filter(isCodexWindowCandidate)
        let knownMappings = knownElectronWindowMappings(spaces: spaces, windows: windows)
        if let windowId = knownMappings[electronId], let window = windows[windowId] {
            return detectionResultFromElectronInference(
                threadId: threadId,
                threadName: threadName,
                electronId: electronId,
                window: window,
                spaces: spaces,
                windows: windows
            )
        }

        let knownOtherWindowIds = Set(knownMappings.filter { $0.key != electronId }.map(\.value))
        let remaining = codexWindows.filter { !knownOtherWindowIds.contains($0.id) }
        guard remaining.count == 1, let window = remaining.first else {
            return nil
        }
        return detectionResultFromElectronInference(
            threadId: threadId,
            threadName: threadName,
            electronId: electronId,
            window: window,
            spaces: spaces,
            windows: windows
        )
    }

    static func detectionResultFromElectronInference(
        threadId: String,
        threadName: String?,
        electronId: String,
        window: WindowInfo,
        spaces: [SpaceInfo],
        windows: [Int: WindowInfo]
    ) -> DetectionResult? {
        guard
            isCodexWindowCandidate(window),
            let space = spaces.first(where: { $0.windows.contains(window.id) })
        else {
            return nil
        }
        let codexCountInSpace = space.windows.compactMap { windows[$0] }.filter(isCodexWindowCandidate).count
        return DetectionResult(
            confidence: "electron-window-inferred",
            threadId: threadId,
            threadName: threadName,
            electronWindowId: electronId,
            window: window,
            space: space,
            codexWindowsInSpace: codexCountInSpace
        )
    }

    static func knownElectronWindowMappings(spaces: [SpaceInfo], windows: [Int: WindowInfo]) -> [String: Int] {
        var records: [(electronWindowId: String, cgWindowId: Int, detectedAt: Date)] = []
        for detection in loadKnownElectronWindowDetections() {
            guard
                let electronWindowId = detection.electronWindowId,
                detection.confidence == "high" || detection.confidence == "electron-window-inferred",
                let detectedAt = date(from: detection.detectedAt),
                Date().timeIntervalSince(detectedAt) <= knownElectronWindowMappingMaxAgeSeconds,
                let window = windows[detection.cgWindowId],
                isCodexWindowCandidate(window),
                let space = spaces.first(where: { $0.uuid == detection.spaceUuid }),
                space.windows.contains(detection.cgWindowId)
            else {
                continue
            }
            records.append((electronWindowId, detection.cgWindowId, detectedAt))
        }

        let newestByElectronId = records.sorted { $0.detectedAt > $1.detectedAt }.reduce(into: [String: (cgWindowId: Int, detectedAt: Date)]()) { result, record in
            if result[record.electronWindowId] == nil {
                result[record.electronWindowId] = (record.cgWindowId, record.detectedAt)
            }
        }
        let idsWithWindowConflict = Dictionary(grouping: newestByElectronId, by: { $0.value.cgWindowId })
            .filter { $0.value.count > 1 }
            .flatMap { $0.value.map(\.key) }
        return newestByElectronId.filter { !idsWithWindowConflict.contains($0.key) }.mapValues(\.cgWindowId)
    }

    static func loadKnownElectronWindowDetections() -> [LastDetection] {
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: detectionsDirectoryURL,
                includingPropertiesForKeys: nil
            )
        else {
            return []
        }
        return urls.compactMap { url in
            guard
                url.pathExtension == "json",
                let data = try? Data(contentsOf: url),
                let detection = try? JSONDecoder().decode(LastDetection.self, from: data)
            else {
                return nil
            }
            return detection
        }
    }

    static func isCodexWindowCandidate(_ window: WindowInfo) -> Bool {
        window.owner == "Codex" && window.layer == 0 && window.width > 200 && window.height > 200
    }

    static func cachedDetectionResult(
        threadId: String,
        spaces: [SpaceInfo],
        windows: [Int: WindowInfo]
    ) -> DetectionResult? {
        guard
            let cached = loadDetection(threadId: threadId),
            cached.confidence == "high",
            isRecentDetection(cached, maxAge: highConfidenceCacheMaxAgeSeconds),
            let space = spaces.first(where: { $0.uuid == cached.spaceUuid }),
            space.windows.contains(cached.cgWindowId),
            let window = windows[cached.cgWindowId],
            window.owner == "Codex",
            window.layer == 0,
            window.width > 200,
            window.height > 200
        else {
            return nil
        }
        let codexCountInSpace = space.windows.compactMap { windows[$0] }.filter {
            $0.owner == "Codex" && $0.layer == 0 && $0.width > 200 && $0.height > 200
        }.count
        return DetectionResult(
            confidence: "cached-high",
            threadId: cached.threadId,
            threadName: cached.threadName,
            electronWindowId: cached.electronWindowId,
            window: window,
            space: space,
            codexWindowsInSpace: codexCountInSpace
        )
    }

    static func threadSpaceDetectionResult(
        threadId: String,
        spaces: [SpaceInfo],
        windows: [Int: WindowInfo]
    ) -> DetectionResult? {
        guard
            let binding = loadThreadSpaceBinding(threadId: threadId),
            let space = spaces.first(where: { $0.uuid == binding.spaceUuid }),
            space.windows.contains(binding.cgWindowId),
            let window = windows[binding.cgWindowId],
            window.owner == "Codex",
            window.layer == 0,
            window.width > 200,
            window.height > 200
        else {
            return nil
        }
        let codexCountInSpace = space.windows.compactMap { windows[$0] }.filter {
            $0.owner == "Codex" && $0.layer == 0 && $0.width > 200 && $0.height > 200
        }.count
        return DetectionResult(
            confidence: "thread-bound",
            threadId: binding.threadId,
            threadName: binding.threadName,
            electronWindowId: binding.electronWindowId,
            window: window,
            space: space,
            codexWindowsInSpace: codexCountInSpace
        )
    }

    static func isRecentDetection(_ detection: LastDetection, maxAge: TimeInterval) -> Bool {
        guard let detectedAt = date(from: detection.detectedAt) else {
            return false
        }
        return Date().timeIntervalSince(detectedAt) <= maxAge
    }

    static func isUsableStoredDetection(_ detection: LastDetection) -> Bool {
        if detection.confidence == "high" {
            return isRecentDetection(detection, maxAge: highConfidenceCacheMaxAgeSeconds)
        }
        return isRecentDetection(detection, maxAge: recentLastDetectionMaxAgeSeconds)
    }

    static func formatDetection(_ detection: DetectionResult) -> String {
        let space = detection.space
        return ("""
        OK confidence=\(detection.confidence) thread=\(detection.threadId) electronWindowId=\(detection.electronWindowId ?? "?") cgWindowId=\(detection.window.id) desktop=\(space.desktopIndex.map(String.init) ?? "?") internalSpace=\(space.id.map(String.init) ?? "?") uuid=\(space.uuid)
        \(displayName(detection.window))
        codexWindowsInSpace=\(detection.codexWindowsInSpace)
        """)
    }

    static func userFacingCurrentThreadLines() -> [String] {
        let detectionResult = loadCurrentThreadDetection()
        if case .success(let detection) = detectionResult {
            var lines = [
                "状態: 検出済み \(detection.confidence == "high" ? "✓" : "△")",
                "スレッド: \(detection.threadName ?? detection.threadId)",
                "作業場所: \(detection.desktopIndex.map { "デスクトップ\($0)" } ?? "Space \(detection.internalSpaceId.map(String.init) ?? "?")")",
                "Codexウィンドウ: #\(detection.cgWindowId)",
                "検出日時: \(detection.detectedAt)",
            ]
            if detection.codexWindowsInSpace > 1 {
                lines.append("注意: 同じデスクトップにCodexが\(detection.codexWindowsInSpace)つあります")
            }
            return lines
        } else {
            if case .failure(let error) = detectionResult {
                return [
                    "状態: 未検出",
                    error.message,
                ]
            }
            return [
                "状態: 未検出",
                "Codex側で spaceguard --cli detect-current-thread を実行してください",
            ]
        }
    }

    static func windowsForCurrentThreadText(threadId: String? = nil) -> (String, Int32) {
        var detection: LastDetection?
        let detectionResult = loadCurrentThreadDetection(threadId: threadId)
        if case .success(let currentDetection) = detectionResult {
            detection = currentDetection
        }
        if detection == nil {
            detection = loadRecentLastDetection()
        }
        guard let detection else {
            if case .failure(let error) = detectionResult {
                return (error.message, 1)
            }
            return ("現在スレッドの作業場所はまだ検出されていません", 1)
        }
        guard let space = loadSpaces().first(where: { $0.uuid == detection.spaceUuid }) else {
            return ("最後に検出したデスクトップが見つかりません", 1)
        }
        let windows = loadWindows()
        var lines = ["\(spaceLabel(space))のウィンドウ"]
        for id in space.windows {
            if let window = windows[id], window.layer == 0, window.width > 20, window.height > 20 {
                lines.append(userDisplayName(window))
            }
        }
        return (lines.joined(separator: "\n"), 0)
    }

    static func windowsForLastDetectionJSON(threadId: String? = nil) -> Int32 {
        var source = "current-thread-detection"
        var detection: LastDetection?
        let detectionResult = loadCurrentThreadDetection(threadId: threadId)
        if case .success(let currentDetection) = detectionResult {
            detection = currentDetection
        }
        if detection == nil, let recentDetection = loadRecentLastDetection() {
            source = "recent-last-detection"
            detection = recentDetection
        }
        guard let detection else {
            if case .failure(let error) = detectionResult {
                printJSON(ErrorPayload(ok: false, error: error.message))
            } else {
                printJSON(ErrorPayload(ok: false, error: "current thread has not been detected yet"))
            }
            return 1
        }
        guard let space = loadSpaces().first(where: { $0.uuid == detection.spaceUuid }) else {
            printJSON(ErrorPayload(ok: false, error: "last detected Space was not found"))
            return 1
        }
        let windows = loadWindows()
        printJSON(WindowsPayload(
            ok: true,
            source: source,
            confidence: detection.confidence,
            threadId: detection.threadId,
            threadName: detection.threadName,
            detectedAt: detection.detectedAt,
            space: spacePayload(space),
            windows: space.windows.compactMap { windows[$0] }
                .filter { $0.layer == 0 && $0.width > 20 && $0.height > 20 }
                .map(windowPayload)
        ))
        return 0
    }

    static func allWindowsJSON(threadId: String? = nil) -> Int32 {
        let snapshot = loadSpacesSnapshot()
        guard !snapshot.spaces.isEmpty else {
            printJSON(ErrorPayload(ok: false, error: "Spaces were not found"))
            return 1
        }

        let windows = loadWindows()
        var source = "no-current-thread-detection"
        var detection: LastDetection?
        let detectionResult = loadCurrentThreadDetection(threadId: threadId)
        if case .success(let currentDetection) = detectionResult {
            source = "current-thread-detection"
            detection = currentDetection
        }

        printJSON(AllWindowsPayload(
            ok: true,
            source: source,
            threadId: detection?.threadId ?? threadId ?? currentThreadId(),
            threadName: detection?.threadName,
            targetSpace: detection.flatMap { currentDetection in
                snapshot.spaces.first(where: { $0.uuid == currentDetection.spaceUuid }).map(spacePayload)
            },
            capturedAt: ISO8601DateFormatter().string(from: Date()),
            windows: windows.values
                .filter { $0.layer == 0 && $0.width > 20 && $0.height > 20 }
                .map(windowPayload)
                .sorted { $0.id < $1.id },
            spaces: snapshot.spaces.map { space in
                SpaceWindowsPayload(
                    space: spacePayload(space),
                    windows: space.windows.compactMap { windows[$0] }
                        .filter { $0.layer == 0 && $0.width > 20 && $0.height > 20 }
                        .map(windowPayload)
                )
            }
        ))
        return 0
    }

    static func setupCodex(options: SetupCodexOptions) -> Int32 {
        print("SpaceGuard Codex setup")
        print("Plugin path: \(pluginInstallURL.path)")
        print("Skill path: \(pluginInstallURL.appendingPathComponent("skills/\(pluginSkillName)/SKILL.md").path)")
        print("Marketplace: \(marketplaceURL.path)")
        if options.withAgentsRule {
            print("Codex rules: \(codexAgentsURL.path)")
        } else {
            print("Codex rules: skipped. Use --with-agents-rule to add the managed rule block.")
        }

        if !runSetupStep(title: "Install or update local plugin", options: options) {
            print("Skipped plugin install/update")
        } else if !options.dryRun {
            do {
                try installOrUpdatePlugin()
                print("OK plugin is ready at \(pluginInstallURL.path)")
            } catch {
                print("NG plugin install/update failed: \(error.localizedDescription)")
                return 1
            }
        }

        if !runSetupStep(title: "Update Codex plugin marketplace", options: options) {
            print("Skipped marketplace update")
        } else if !options.dryRun {
            do {
                try updateMarketplace()
                print("OK marketplace updated at \(marketplaceURL.path)")
            } catch {
                print("NG marketplace update failed: \(error.localizedDescription)")
                return 1
            }
        }

        if options.withAgentsRule {
            if !runSetupStep(title: "Backup and update Codex AGENTS.md rule block", options: options) {
                print("Skipped Codex rule update")
            } else if !options.dryRun {
                do {
                    let backup = try updateCodexAgentsRule()
                    if let backup {
                        print("OK Codex rule updated. Backup: \(backup.path)")
                    } else {
                        print("OK Codex rule created at \(codexAgentsURL.path)")
                    }
                } catch {
                    print("NG Codex rule update failed: \(error.localizedDescription)")
                    return 1
                }
            }
        }

        if options.dryRun {
            print("Dry run complete. No files were changed.")
        } else {
            print("Setup complete. Restart Codex if the plugin or \(pluginSkillName) skill does not appear immediately.")
        }
        return 0
    }

    static func runSetupStep(title: String, options: SetupCodexOptions) -> Bool {
        if options.dryRun {
            print("DRY-RUN would: \(title)")
            return true
        }
        if options.yes {
            print("DO \(title)")
            return true
        }
        print("\n\(title)")
        print("Proceed? [y/N] ", terminator: "")
        let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return answer == "y" || answer == "yes"
    }

    static func installOrUpdatePlugin() throws {
        try FileManager.default.createDirectory(
            at: pluginInstallURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: pluginInstallURL.appendingPathComponent(".git").path) {
            try runProcess("/usr/bin/git", ["-C", pluginInstallURL.path, "pull", "--ff-only"])
        } else {
            if FileManager.default.fileExists(atPath: pluginInstallURL.path) {
                throw NSError(
                    domain: "SpaceGuard",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "\(pluginInstallURL.path) exists but is not a git checkout"]
                )
            }
            try runProcess("/usr/bin/git", [
                "clone",
                "https://github.com/soichiro-nitta/spaceguard.git",
                pluginInstallURL.path
            ])
        }
    }

    static func updateMarketplace() throws {
        try FileManager.default.createDirectory(
            at: marketplaceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var root: [String: Any] = [
            "name": "local",
            "interface": ["displayName": "Local Codex Plugins"],
            "plugins": []
        ]
        if FileManager.default.fileExists(atPath: marketplaceURL.path) {
            let data = try Data(contentsOf: marketplaceURL)
            if
                let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                root = existing
            }
        }

        var plugins = root["plugins"] as? [[String: Any]] ?? []
        plugins.removeAll { $0["name"] as? String == "spaceguard" }
        plugins.append([
            "name": "spaceguard",
            "source": [
                "source": "local",
                "path": "./plugins/spaceguard"
            ],
            "policy": [
                "installation": "AVAILABLE",
                "authentication": "ON_INSTALL"
            ],
            "category": "Productivity"
        ])
        root["plugins"] = plugins
        if root["name"] == nil {
            root["name"] = "local"
        }
        if root["interface"] == nil {
            root["interface"] = ["displayName": "Local Codex Plugins"]
        }

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: marketplaceURL)
    }

    static func updateCodexAgentsRule() throws -> URL? {
        try FileManager.default.createDirectory(
            at: codexAgentsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existing = (try? String(contentsOf: codexAgentsURL, encoding: .utf8)) ?? ""
        let backup: URL?
        if FileManager.default.fileExists(atPath: codexAgentsURL.path) {
            backup = uniqueBackupURL(for: codexAgentsURL)
            try FileManager.default.copyItem(at: codexAgentsURL, to: backup!)
        } else {
            backup = nil
        }

        let updated: String
        if
            let beginRange = existing.range(of: spaceGuardRuleBegin),
            let endRange = existing.range(of: spaceGuardRuleEnd),
            beginRange.lowerBound < endRange.upperBound
        {
            updated = existing.replacingCharacters(
                in: beginRange.lowerBound..<endRange.upperBound,
                with: spaceGuardRuleBlock
            )
        } else if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated = "\(spaceGuardRuleBlock)\n"
        } else {
            updated = "\(existing.trimmingCharacters(in: .whitespacesAndNewlines))\n\n\(spaceGuardRuleBlock)\n"
        }
        try updated.write(to: codexAgentsURL, atomically: true, encoding: .utf8)
        return backup
    }

    static func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    static func uniqueBackupURL(for url: URL) -> URL {
        let directory = url.deletingLastPathComponent()
        let baseName = url.lastPathComponent
        let timestamp = backupTimestamp()
        var candidate = directory.appendingPathComponent("\(baseName).bak.\(timestamp)")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName).bak.\(timestamp).\(index)")
            index += 1
        }
        return candidate
    }

    static func runProcess(_ executable: String, _ arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let output = Pipe()
        task.standardOutput = output
        task.standardError = output
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "process failed"
            throw NSError(domain: "SpaceGuard", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    static func uninstall(options: UninstallOptions) -> Int32 {
        print("SpaceGuard uninstall")
        print("Will remove SpaceGuard-owned files and entries only.")

        let paths = uninstallPaths()
        for path in paths {
            if FileManager.default.fileExists(atPath: path.path) {
                print("Will remove: \(path.path)")
            } else {
                print("Not found: \(path.path)")
            }
        }
        print("Will remove marketplace entry named: spaceguard")

        if options.keepAgentsRule {
            print("Will keep Codex AGENTS.md SpaceGuard rule block")
        } else {
            printAgentsRuleRemovalPreview()
        }

        if options.dryRun {
            print("Dry run complete. No files were changed.")
            return 0
        }

        if !options.yes {
            print("\nProceed with uninstall? [y/N] ", terminator: "")
            let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if answer != "y" && answer != "yes" {
                print("Cancelled.")
                return 1
            }
        }

        do {
            if !options.keepAgentsRule {
                try removeCodexAgentsRule(confirmWhenInteractive: !options.yes)
            }
            try removeMarketplaceEntry()
            try removeUninstallPaths(paths)
            print("Uninstall complete.")
            return 0
        } catch {
            print("NG uninstall failed: \(error.localizedDescription)")
            return 1
        }
    }

    static func uninstallPaths() -> [URL] {
        [
            URL(fileURLWithPath: spaceGuardHomeDirectory()).appendingPathComponent(".local/bin/spaceguard"),
            URL(fileURLWithPath: spaceGuardHomeDirectory()).appendingPathComponent(".spaceguard"),
            pluginInstallURL
        ]
    }

    static func removeUninstallPaths(_ paths: [URL]) throws {
        for path in paths where FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
            print("Removed: \(path.path)")
        }
    }

    static func removeMarketplaceEntry() throws {
        guard FileManager.default.fileExists(atPath: marketplaceURL.path) else {
            return
        }
        let data = try Data(contentsOf: marketplaceURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        let plugins = root["plugins"] as? [[String: Any]] ?? []
        let filtered = plugins.filter { $0["name"] as? String != "spaceguard" }
        if filtered.count != plugins.count {
            root["plugins"] = filtered
            let updated = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try updated.write(to: marketplaceURL)
            print("Removed marketplace entry: spaceguard")
        }
    }

    static func agentsRuleRange(in text: String) -> Range<String.Index>? {
        guard
            let beginRange = text.range(of: spaceGuardRuleBegin),
            let endRange = text.range(of: spaceGuardRuleEnd),
            beginRange.lowerBound < endRange.upperBound
        else {
            return nil
        }
        return beginRange.lowerBound..<endRange.upperBound
    }

    static func agentsRuleBlockText() -> String? {
        guard
            let text = try? String(contentsOf: codexAgentsURL, encoding: .utf8),
            let range = agentsRuleRange(in: text)
        else {
            return nil
        }
        return String(text[range])
    }

    static func printAgentsRuleRemovalPreview() {
        guard let block = agentsRuleBlockText() else {
            print("No SpaceGuard managed rule block found in \(codexAgentsURL.path)")
            return
        }
        print("Found SpaceGuard managed rule block in \(codexAgentsURL.path):")
        print("--- remove begin ---")
        print(block)
        print("--- remove end ---")
    }

    static func removeCodexAgentsRule(confirmWhenInteractive: Bool) throws {
        guard
            let text = try? String(contentsOf: codexAgentsURL, encoding: .utf8),
            let range = agentsRuleRange(in: text)
        else {
            return
        }

        let block = String(text[range])
        print("SpaceGuard rule block selected for removal:")
        print("--- remove begin ---")
        print(block)
        print("--- remove end ---")

        if confirmWhenInteractive {
            print("Remove only this block from \(codexAgentsURL.path)? [y/N] ", terminator: "")
            let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if answer != "y" && answer != "yes" {
                print("Skipped Codex rule block removal.")
                return
            }
        }

        let backup = uniqueBackupURL(for: codexAgentsURL)
        try FileManager.default.copyItem(at: codexAgentsURL, to: backup)
        let updated = text.replacingCharacters(in: range, with: "")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        try updated.write(to: codexAgentsURL, atomically: true, encoding: .utf8)
        print("Removed Codex rule block. Backup: \(backup.path)")
    }
}

extension String {
    func withExit(_ code: Int32) -> (String, Int32) {
        (self, code)
    }
}

extension Process {
    func waitUntilExit(seconds: TimeInterval) -> Bool {
        let limit = Date().addingTimeInterval(seconds)
        while isRunning && Date() < limit {
            Thread.sleep(forTimeInterval: 0.05)
        }
        return !isRunning
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.title = "SG:..."
        statusItem.menu = makeMenu()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        if let detection = SpaceGuardCore.loadLastDetection() {
            let desktop = detection.desktopIndex.map { "デスクトップ\($0)" } ?? "S\(detection.internalSpaceId.map(String.init) ?? "?")"
            statusItem.button?.title = "SG:\(desktop) \(detection.confidence == "high" ? "✓" : "△")"
        } else {
            let status = SpaceGuardCore.statusText()
            if status.hasPrefix("UNBOUND") {
                statusItem.button?.title = "SG:未検出"
            } else if status.hasPrefix("STALE") {
                statusItem.button?.title = "SG:要確認"
            } else {
                let desktop = status.range(of: #"デスクトップ[0-9]+"#, options: .regularExpression).map { String(status[$0]) }
                let internalSpace = status.range(of: #"internalSpace=([^\s]+)"#, options: .regularExpression).map { String(status[$0]).replacingOccurrences(of: "internalSpace=", with: "") } ?? "?"
                statusItem.button?.title = "SG:\(desktop ?? "S\(internalSpace)")"
            }
        }
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(header("SpaceGuard"))
        menu.addItem(label("Codex操作を同じデスクトップ内に閉じ込める"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(header("このスレッドの作業場所"))
        for line in SpaceGuardCore.userFacingCurrentThreadLines() {
            menu.addItem(label(String(line)))
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(header("操作対象になる同じデスクトップのウィンドウ"))
        for line in SpaceGuardCore.windowsForCurrentThreadText().0.split(separator: "\n") {
            menu.addItem(label(String(line)))
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(header("全デスクトップの要約"))
        for line in SpaceGuardCore.allSpacesText().split(separator: "\n") {
            menu.addItem(label(String(line)))
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(action("表示を更新", #selector(refreshAction)))
        menu.addItem(action("現在スレッドの保存状態を解除", #selector(clearCurrentThread)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(action("Quit SpaceGuard", #selector(quit)))
        return menu
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = true
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func refreshAction() {
        refresh()
    }

    @objc private func clearCurrentThread() {
        SpaceGuardCore.clearCurrentThreadState()
        refresh()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}

func runCLI(arguments: [String]) {
    guard let command = arguments.first else {
        print(cliUsage)
        exit(2)
    }

    switch command {
    case "help", "--help", "-h":
        print(cliUsage)
    case "detect":
        var threadId = ProcessInfo.processInfo.environment["CODEX_THREAD_ID"]
        if
            let index = arguments.firstIndex(of: "--thread-id"),
            arguments.indices.contains(index + 1)
        {
            threadId = arguments[index + 1]
        }
        if arguments.contains("--json") {
            exit(SpaceGuardCore.detectCurrentThreadJSON(threadId: threadId))
        }
        let result = SpaceGuardCore.detectCurrentThread(threadId: threadId)
        print(result.0)
        exit(result.1)
    case "bind":
        print("NG bind is deprecated. Run `spaceguard detect --json` from the target Codex thread; high-confidence detection is persisted automatically.")
        exit(2)
    case "status":
        print(SpaceGuardCore.statusText())
    case "windows":
        var threadId = ProcessInfo.processInfo.environment["CODEX_THREAD_ID"]
        if
            let index = arguments.firstIndex(of: "--thread-id"),
            arguments.indices.contains(index + 1)
        {
            threadId = arguments[index + 1]
        }
        if arguments.contains("--all-json") {
            exit(SpaceGuardCore.allWindowsJSON(threadId: threadId))
        }
        if arguments.contains("--json") {
            exit(SpaceGuardCore.windowsForLastDetectionJSON(threadId: threadId))
        }
        let result = SpaceGuardCore.windowsForCurrentThreadText(threadId: threadId)
        print(result.0)
        exit(result.1)
    case "detect-current-thread":
        var threadId = ProcessInfo.processInfo.environment["CODEX_THREAD_ID"]
        if
            let index = arguments.firstIndex(of: "--thread-id"),
            arguments.indices.contains(index + 1)
        {
            threadId = arguments[index + 1]
        }
        let result = SpaceGuardCore.detectCurrentThread(threadId: threadId)
        print(result.0)
        exit(result.1)
    case "assert":
        guard
            let appIndex = arguments.firstIndex(of: "--app"),
            arguments.indices.contains(appIndex + 1)
        else {
            print("usage: spaceguard assert --app <name>")
            exit(2)
        }
        let result = SpaceGuardCore.assertText(app: arguments[appIndex + 1])
        print(result.0)
        exit(result.1)
    case "open-url":
        guard
            let appIndex = arguments.firstIndex(of: "--app"),
            arguments.indices.contains(appIndex + 2)
        else {
            print("usage: spaceguard open-url [--activate] --app \"Google Chrome\" <url>")
            exit(2)
        }
        let result = SpaceGuardCore.openURLText(
            app: arguments[appIndex + 1],
            url: arguments[appIndex + 2],
            activate: arguments.contains("--activate")
        )
        print(result.0)
        exit(result.1)
    case "setup-codex":
        exit(SpaceGuardCore.setupCodex(options: SetupCodexOptions(
            dryRun: arguments.contains("--dry-run"),
            yes: arguments.contains("--yes"),
            withAgentsRule: arguments.contains("--with-agents-rule")
        )))
    case "uninstall":
        exit(SpaceGuardCore.uninstall(options: UninstallOptions(
            dryRun: arguments.contains("--dry-run"),
            yes: arguments.contains("--yes"),
            keepAgentsRule: arguments.contains("--keep-agents-rule")
        )))
    case "clear":
        if arguments.contains("--all-stale") {
            SpaceGuardCore.cleanupStaleThreadSpaces()
            print("OK cleared stale thread bindings")
        } else {
            SpaceGuardCore.clearCurrentThreadState()
            print("OK cleared current thread")
        }
    default:
        print(cliUsage)
        exit(2)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--cli" {
    runCLI(arguments: Array(arguments.dropFirst()))
} else if arguments.first == "menubar" {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
} else {
    runCLI(arguments: arguments)
}
