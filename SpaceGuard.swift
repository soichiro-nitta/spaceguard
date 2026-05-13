import AppKit
import CoreGraphics
import Foundation

func spaceGuardHomeDirectory() -> String {
    if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty {
        return home
    }
    return NSHomeDirectory()
}

let stateURL = URL(fileURLWithPath: spaceGuardHomeDirectory())
    .appendingPathComponent(".spaceguard/state.json")
let lastDetectionURL = URL(fileURLWithPath: spaceGuardHomeDirectory())
    .appendingPathComponent(".spaceguard/last-detection.json")
let pluginInstallURL = URL(fileURLWithPath: spaceGuardHomeDirectory())
    .appendingPathComponent("plugins/spaceguard")
let marketplaceURL = URL(fileURLWithPath: spaceGuardHomeDirectory())
    .appendingPathComponent(".agents/plugins/marketplace.json")
let codexAgentsURL = URL(fileURLWithPath: spaceGuardHomeDirectory())
    .appendingPathComponent(".codex/AGENTS.md")
let spaceGuardRuleBegin = "<!-- BEGIN SPACEGUARD CODEX RULE -->"
let spaceGuardRuleEnd = "<!-- END SPACEGUARD CODEX RULE -->"
let spaceGuardRuleBlock = """
\(spaceGuardRuleBegin)
## SpaceGuard

Before using Chrome, Computer Use, or macOS desktop automation, use the SpaceGuard plugin workflow.

If the plugin is unavailable, run `spaceguard detect --json` and only operate in the detected `space.desktopName` when `confidence` is `high` or `cached-high`.

When opening a new Chrome URL, do not use the Codex Chrome Extension `tabs.new()` as the first step because it may create a tab in a Chrome window from another macOS Space. Use `spaceguard open-url --app "Google Chrome" <url>` first, then operate the tab after confirming it is in the detected Desktop.

If multiple Codex windows are open and SpaceGuard cannot infer the current thread's window, stop. If the user explicitly identifies the correct Desktop, run `spaceguard bind --desktop <n>` before continuing.
\(spaceGuardRuleEnd)
"""

struct BoundState: Codable {
    let windowId: Int
    let spaceUuid: String
    let spaceId: Int?
    let boundAt: String
}

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
    let space: SpacePayload
    let windows: [WindowPayload]
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

enum SpaceGuardCore {
    static func loadSpaces() -> [SpaceInfo] {
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
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let root = plist as? [String: Any],
            let config = root["SpacesDisplayConfiguration"] as? [String: Any]
        else {
            return []
        }

        var idsByUuid: [String: Int] = [:]
        var desktopIndexesByUuid: [String: Int] = [:]
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
            return []
        }

        return properties.compactMap { property in
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

    static func loadState() -> BoundState? {
        guard let data = try? Data(contentsOf: stateURL) else {
            return nil
        }
        return try? JSONDecoder().decode(BoundState.self, from: data)
    }

    static func saveState(_ state: BoundState) {
        try? FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(state) {
            try? data.write(to: stateURL)
        }
    }

    static func saveLastDetection(_ detection: DetectionResult) {
        try? FileManager.default.createDirectory(
            at: lastDetectionURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload = LastDetection(
            confidence: detection.confidence,
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
        }
    }

    static func loadLastDetection() -> LastDetection? {
        guard let data = try? Data(contentsOf: lastDetectionURL) else {
            return nil
        }
        return try? JSONDecoder().decode(LastDetection.self, from: data)
    }

    static func currentThreadId() -> String? {
        let value = ProcessInfo.processInfo.environment["CODEX_THREAD_ID"]
        if let value, !value.isEmpty {
            return value
        }
        return nil
    }

    static func loadCurrentThreadDetection() -> Result<LastDetection, DetectionError> {
        guard let detection = loadLastDetection() else {
            return .failure(DetectionError(message: "NG current thread has not been detected yet"))
        }
        guard let threadId = currentThreadId() else {
            return .failure(DetectionError(message: "NG CODEX_THREAD_ID is missing"))
        }
        guard detection.threadId == threadId else {
            return .failure(DetectionError(message: "NG last detection belongs to another thread. expected=\(threadId) actual=\(detection.threadId). Run `spaceguard detect --json` in this thread before operating windows."))
        }
        return .success(detection)
    }

    static func clearState() {
        try? FileManager.default.removeItem(at: stateURL)
    }

    static func boundSpace(spaces: [SpaceInfo], state: BoundState) -> SpaceInfo? {
        spaces.first { $0.uuid == state.spaceUuid }
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

    static func stateSpaceLabel(spaceId: Int?, uuid: String) -> String {
        if let space = loadSpaces().first(where: { $0.uuid == uuid }) {
            return spaceLabel(space)
        }
        return "Space \(spaceId.map(String.init) ?? "?")"
    }

    static func bindCodex() -> String {
        let spaces = loadSpaces()
        let windows = loadWindows()
        let candidates = spaces.flatMap { space in
            space.windows.compactMap { id -> (SpaceInfo, WindowInfo)? in
                guard
                    let window = windows[id],
                    window.owner == "Codex",
                    window.layer == 0,
                    window.width > 200,
                    window.height > 200
                else {
                    return nil
                }
                return (space, window)
            }
        }

        guard let selected = candidates.max(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height }) else {
            return "NG Codex window not found"
        }

        let state = BoundState(
            windowId: selected.1.id,
            spaceUuid: selected.0.uuid,
            spaceId: selected.0.id,
            boundAt: ISO8601DateFormatter().string(from: Date())
        )
        saveState(state)
        return "OK bound \(displayName(selected.1)) \(spaceLabel(selected.0)) internalSpace=\(selected.0.id.map(String.init) ?? "?")"
    }

    static func bindDesktop(index: Int, threadId: String?) -> (String, Int32) {
        guard let threadId, !threadId.isEmpty else {
            return ("NG CODEX_THREAD_ID is missing", 1)
        }
        let spaces = loadSpaces()
        let windows = loadWindows()
        guard let space = spaces.first(where: { $0.desktopIndex == index }) else {
            return ("NG デスクトップ\(index) was not found", 1)
        }
        guard let window = space.windows.compactMap({ windows[$0] }).first(where: {
            $0.owner == "Codex" && $0.layer == 0 && $0.width > 200 && $0.height > 200
        }) else {
            return ("NG no Codex window in \(spaceLabel(space))", 1)
        }
        let codexCountInSpace = space.windows.compactMap { windows[$0] }.filter {
            $0.owner == "Codex" && $0.layer == 0 && $0.width > 200 && $0.height > 200
        }.count
        saveLastDetection(DetectionResult(
            confidence: "high",
            threadId: threadId,
            threadName: currentThreadName(threadId: threadId),
            electronWindowId: "manual-desktop-\(index)",
            window: window,
            space: space,
            codexWindowsInSpace: codexCountInSpace
        ))
        return ("OK manually bound thread=\(threadId) to \(spaceLabel(space))\n\(displayName(window))", 0)
    }

    static func statusText() -> String {
        guard let state = loadState() else {
            return "UNBOUND"
        }
        let spaces = loadSpaces()
        let windows = loadWindows()
        let space = boundSpace(spaces: spaces, state: state)
        let stale = space?.windows.contains(state.windowId) == true ? "OK" : "STALE"
        var lines = ["\(stale) \(stateSpaceLabel(spaceId: state.spaceId, uuid: state.spaceUuid)) internalSpace=\(state.spaceId.map(String.init) ?? "?") uuid=\(state.spaceUuid) window=\(state.windowId) boundAt=\(state.boundAt)"]
        if let window = windows[state.windowId] {
            lines.append(displayName(window))
        }
        return lines.joined(separator: "\n")
    }

    static func windowsText() -> String {
        guard let state = loadState(), let space = boundSpace(spaces: loadSpaces(), state: state) else {
            return "UNBOUND"
        }
        let windows = loadWindows()
        var lines = ["\(spaceLabel(space)) internalSpace=\(space.id.map(String.init) ?? "?") \(space.uuid)"]
        for id in space.windows {
            if let window = windows[id], window.layer == 0 {
                lines.append(displayName(window))
            }
        }
        return lines.joined(separator: "\n")
    }

    static func allSpacesText() -> String {
        let spaces = loadSpaces()
        let windows = loadWindows()
        let state = loadState()
        if spaces.isEmpty {
            return "No Spaces found"
        }

        return spaces.map { space in
            let marker = state?.spaceUuid == space.uuid ? "*" : " "
            let visibleWindows = space.windows.compactMap { windows[$0] }.filter { $0.layer == 0 }
            let apps = Array(Set(visibleWindows.map(\.owner))).sorted().joined(separator: ", ")
            return "\(marker) \(spaceLabel(space)) windows=\(visibleWindows.count) \(apps)"
        }.joined(separator: "\n")
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
        let totalCodexWindows = windows.values.filter {
            $0.owner == "Codex" && $0.layer == 0 && $0.width > 200 && $0.height > 200
        }.count
        if detection.electronWindowId == nil && totalCodexWindows > 1 {
            return ("NG last detection is ambiguous because multiple Codex windows are open and no thread/window hint was saved. Run `spaceguard detect --json` from the target Codex window or clear/rebind the target Space.", 1)
        }
        let matches = space.windows.compactMap { windows[$0] }.filter {
            $0.owner == app && $0.layer == 0 && $0.width > 20 && $0.height > 20
        }
        if matches.isEmpty {
            return ("NG no \(app) window in \(spaceLabel(space))", 1)
        }
        return (["OK \(matches.count) \(app) window(s) in \(spaceLabel(space))"] + matches.map(displayName)).joined(separator: "\n").withExit(0)
    }

    static func openURLText(app: String, url: String) -> (String, Int32) {
        if app != "Google Chrome" {
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
        let totalCodexWindows = windows.values.filter {
            $0.owner == "Codex" && $0.layer == 0 && $0.width > 200 && $0.height > 200
        }.count
        if detection.electronWindowId == nil && totalCodexWindows > 1 {
            return ("NG last detection is ambiguous because multiple Codex windows are open and no thread/window hint was saved. Run `spaceguard detect --json` from the target Codex window or clear/rebind the target Space.", 1)
        }
        let matches = space.windows.compactMap { windows[$0] }.filter {
            $0.owner == app && $0.layer == 0 && $0.width > 20 && $0.height > 20
        }
        guard let window = matches.first else {
            return ("NG no \(app) window in \(spaceLabel(space))", 1)
        }
        return openChromeURL(window: window, url: url, space: space)
    }

    static func openChromeURL(window: WindowInfo, url: String, space: SpaceInfo) -> (String, Int32) {
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
                make new tab at end of tabs of w with properties {URL:targetURL}
                set active tab index of w to (count of tabs of w)
                return "OK opened URL in target Google Chrome window"
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
            url
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
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        let pattern = #"conversationId=\#(NSRegularExpression.escapedPattern(for: threadId)).*?windowId=([0-9]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        guard let match = matches.last, let idRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[idRange])
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
            let cached = loadLastDetection(),
            cached.threadId == threadId,
            let space = loadSpaces().first(where: { $0.uuid == cached.spaceUuid })
        else {
            return nil
        }
        let windows = loadWindows()
        let totalCodexWindows = windows.values.filter {
            $0.owner == "Codex" && $0.layer == 0 && $0.width > 200 && $0.height > 200
        }.count
        if cached.electronWindowId == nil && totalCodexWindows > 1 {
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
            let cached = loadLastDetection(),
            cached.threadId == threadId,
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
        let totalCodexWindows = windows.values.filter {
            $0.owner == "Codex" && $0.layer == 0 && $0.width > 200 && $0.height > 200
        }.count
        if cached.electronWindowId == nil && totalCodexWindows > 1 {
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
        guard let rect = codexMainWindowRect() else {
            return .failure(DetectionError(message: "NG Codex AX main window not found for thread=\(threadId)"))
        }

        let spaces = loadSpaces()
        let windows = loadWindows()
        let electronId = latestCodexElectronWindowId(threadId: threadId)
        let totalCodexWindows = windows.values.filter {
            $0.owner == "Codex" && $0.layer == 0 && $0.width > 200 && $0.height > 200
        }.count
        if electronId == nil && totalCodexWindows > 1 {
            return .failure(DetectionError(message: "NG multiple Codex windows are open and no thread/window hint is available for thread=\(threadId)"))
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
            return .failure(DetectionError(message: "NG expected 1 Codex CGWindow match, got \(candidates.count) for AX rect x=\(rect.x) y=\(rect.y) w=\(rect.width) h=\(rect.height)"))
        }
        guard let space = spaces.first(where: { $0.windows.contains(window.id) }) else {
            return .failure(DetectionError(message: "NG matched \(displayName(window)) but no Space contains it"))
        }

        let codexCountInSpace = space.windows.compactMap { windows[$0] }.filter {
            $0.owner == "Codex" && $0.layer == 0 && $0.width > 200 && $0.height > 200
        }.count
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

    static func windowsForCurrentThreadText() -> String {
        let detectionResult = loadCurrentThreadDetection()
        guard case .success(let detection) = detectionResult else {
            if case .failure(let error) = detectionResult {
                return error.message
            }
            return "現在スレッドの作業場所はまだ検出されていません"
        }
        guard let space = loadSpaces().first(where: { $0.uuid == detection.spaceUuid }) else {
            return "最後に検出したデスクトップが見つかりません"
        }
        let windows = loadWindows()
        var lines = ["\(spaceLabel(space))のウィンドウ"]
        for id in space.windows {
            if let window = windows[id], window.layer == 0, window.width > 20, window.height > 20 {
                lines.append(userDisplayName(window))
            }
        }
        return lines.joined(separator: "\n")
    }

    static func windowsForLastDetectionJSON() -> Int32 {
        let detectionResult = loadCurrentThreadDetection()
        guard case .success(let detection) = detectionResult else {
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
            source: "last-detection",
            space: spacePayload(space),
            windows: space.windows.compactMap { windows[$0] }
                .filter { $0.layer == 0 && $0.width > 20 && $0.height > 20 }
                .map(windowPayload)
        ))
        return 0
    }

    static func setupCodex(options: SetupCodexOptions) -> Int32 {
        print("SpaceGuard Codex setup")
        print("Plugin path: \(pluginInstallURL.path)")
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
            print("Setup complete. Restart Codex if the plugin does not appear immediately.")
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
        for line in SpaceGuardCore.windowsForCurrentThreadText().split(separator: "\n") {
            menu.addItem(label(String(line)))
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(header("全デスクトップの要約"))
        for line in SpaceGuardCore.allSpacesText().split(separator: "\n") {
            menu.addItem(label(String(line)))
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(action("表示を更新", #selector(refreshAction)))
        menu.addItem(action("手動で現在のCodexウィンドウを固定", #selector(bindCodex)))
        menu.addItem(action("手動固定を解除", #selector(clearBind)))
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

    @objc private func bindCodex() {
        let result = SpaceGuardCore.bindCodex()
        refresh()
        showAlert(result)
    }

    @objc private func refreshAction() {
        refresh()
    }

    @objc private func clearBind() {
        SpaceGuardCore.clearState()
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
        print("usage: spaceguard detect [--json] [--thread-id <id>]|windows [--json]|assert --app <name>|open-url --app \"Google Chrome\" <url>|setup-codex [--with-agents-rule] [--dry-run] [--yes]|uninstall [--dry-run] [--yes] [--keep-agents-rule]|menubar|bind [--desktop <n>]|status|clear")
        exit(2)
    }

    switch command {
    case "help", "--help", "-h":
        print("usage: spaceguard detect [--json] [--thread-id <id>]|windows [--json]|assert --app <name>|open-url --app \"Google Chrome\" <url>|setup-codex [--with-agents-rule] [--dry-run] [--yes]|uninstall [--dry-run] [--yes] [--keep-agents-rule]|menubar|bind [--desktop <n>]|status|clear")
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
        if
            let desktopIndex = arguments.firstIndex(of: "--desktop"),
            arguments.indices.contains(desktopIndex + 1),
            let index = Int(arguments[desktopIndex + 1])
        {
            var threadId = ProcessInfo.processInfo.environment["CODEX_THREAD_ID"]
            if
                let index = arguments.firstIndex(of: "--thread-id"),
                arguments.indices.contains(index + 1)
            {
                threadId = arguments[index + 1]
            }
            let result = SpaceGuardCore.bindDesktop(index: index, threadId: threadId)
            print(result.0)
            exit(result.1)
        }
        print(SpaceGuardCore.bindCodex())
    case "status":
        print(SpaceGuardCore.statusText())
    case "windows":
        if arguments.contains("--json") {
            exit(SpaceGuardCore.windowsForLastDetectionJSON())
        }
        print(SpaceGuardCore.windowsForCurrentThreadText())
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
            print("usage: spaceguard open-url --app \"Google Chrome\" <url>")
            exit(2)
        }
        let result = SpaceGuardCore.openURLText(app: arguments[appIndex + 1], url: arguments[appIndex + 2])
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
        SpaceGuardCore.clearState()
        print("OK cleared")
    default:
        print("usage: spaceguard detect [--json] [--thread-id <id>]|windows [--json]|assert --app <name>|open-url --app \"Google Chrome\" <url>|setup-codex [--with-agents-rule] [--dry-run] [--yes]|uninstall [--dry-run] [--yes] [--keep-agents-rule]|menubar|bind [--desktop <n>]|status|clear")
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
