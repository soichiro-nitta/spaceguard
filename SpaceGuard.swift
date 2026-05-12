import AppKit
import CoreGraphics
import Foundation

let stateURL = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent(".spaceguard/state.json")
let lastDetectionURL = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent(".spaceguard/last-detection.json")

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
        guard let detection = loadLastDetection() else {
            return ("NG current thread has not been detected yet", 1)
        }
        guard let space = loadSpaces().first(where: { $0.uuid == detection.spaceUuid }) else {
            return ("NG last detected Space was not found", 1)
        }
        let windows = loadWindows()
        let matches = space.windows.compactMap { windows[$0] }.filter {
            $0.owner == app && $0.layer == 0 && $0.width > 20 && $0.height > 20
        }
        if matches.isEmpty {
            return ("NG no \(app) window in \(spaceLabel(space))", 1)
        }
        return (["OK \(matches.count) \(app) window(s) in \(spaceLabel(space))"] + matches.map(displayName)).joined(separator: "\n").withExit(0)
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
            task.waitUntilExit()
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

        let electronId = latestCodexElectronWindowId(threadId: threadId)
        let codexCountInSpace = space.windows.compactMap { windows[$0] }.filter {
            $0.owner == "Codex" && $0.layer == 0 && $0.width > 200 && $0.height > 200
        }.count
        let confidence = electronId == nil ? "medium" : "high"
        return .success(DetectionResult(
            confidence: confidence,
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
        if let detection = loadLastDetection() {
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
            return [
                "状態: 未検出",
                "Codex側で spaceguard --cli detect-current-thread を実行してください",
            ]
        }
    }

    static func windowsForCurrentThreadText() -> String {
        guard let detection = loadLastDetection() else {
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
        guard let detection = loadLastDetection() else {
            printJSON(ErrorPayload(ok: false, error: "current thread has not been detected yet"))
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
}

extension String {
    func withExit(_ code: Int32) -> (String, Int32) {
        (self, code)
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
        print("usage: spaceguard detect [--json] [--thread-id <id>]|windows [--json]|assert --app <name>|menubar|bind|status|clear")
        exit(2)
    }

    switch command {
    case "help", "--help", "-h":
        print("usage: spaceguard detect [--json] [--thread-id <id>]|windows [--json]|assert --app <name>|menubar|bind|status|clear")
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
    case "clear":
        SpaceGuardCore.clearState()
        print("OK cleared")
    default:
        print("usage: spaceguard detect [--json] [--thread-id <id>]|windows [--json]|assert --app <name>|menubar|bind|status|clear")
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
