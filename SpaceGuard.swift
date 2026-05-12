import AppKit
import CoreGraphics
import Foundation

let stateURL = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent(".spaceguard/state.json")

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
    let width: Double
    let height: Double
}

struct SpaceInfo {
    let uuid: String
    let id: Int?
    let windows: [Int]
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
        if
            let managementData = config["Management Data"] as? [String: Any],
            let monitors = managementData["Monitors"] as? [[String: Any]]
        {
            for monitor in monitors {
                if let spaces = monitor["Spaces"] as? [[String: Any]] {
                    for space in spaces {
                        if let uuid = space["uuid"] as? String {
                            idsByUuid[uuid] = space["ManagedSpaceID"] as? Int
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
        return "OK bound \(displayName(selected.1)) space=\(selected.0.id.map(String.init) ?? "?")"
    }

    static func statusText() -> String {
        guard let state = loadState() else {
            return "UNBOUND"
        }
        let spaces = loadSpaces()
        let windows = loadWindows()
        let space = boundSpace(spaces: spaces, state: state)
        let stale = space?.windows.contains(state.windowId) == true ? "OK" : "STALE"
        var lines = ["\(stale) space=\(state.spaceId.map(String.init) ?? "?") uuid=\(state.spaceUuid) window=\(state.windowId) boundAt=\(state.boundAt)"]
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
        var lines = ["Space \(space.id.map(String.init) ?? "?") \(space.uuid)"]
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
            return "\(marker) Space \(space.id.map(String.init) ?? "?") windows=\(visibleWindows.count) \(apps)"
        }.joined(separator: "\n")
    }

    static func assertText(app: String) -> (String, Int32) {
        guard let state = loadState(), let space = boundSpace(spaces: loadSpaces(), state: state) else {
            return ("NG unbound", 1)
        }
        let windows = loadWindows()
        let matches = space.windows.compactMap { windows[$0] }.filter {
            $0.owner == app && $0.layer == 0 && $0.width > 20 && $0.height > 20
        }
        if matches.isEmpty {
            return ("NG no \(app) window in bound space \(state.spaceId.map(String.init) ?? "?")", 1)
        }
        return (["OK \(matches.count) \(app) window(s) in bound space \(state.spaceId.map(String.init) ?? "?")"] + matches.map(displayName)).joined(separator: "\n").withExit(0)
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
        let status = SpaceGuardCore.statusText()
        if status.hasPrefix("UNBOUND") {
            statusItem.button?.title = "SpaceGuard:unbound"
        } else if status.hasPrefix("STALE") {
            statusItem.button?.title = "SpaceGuard:stale"
        } else {
            let space = status.range(of: #"space=([^\s]+)"#, options: .regularExpression).map { String(status[$0]).replacingOccurrences(of: "space=", with: "") } ?? "?"
            statusItem.button?.title = "SpaceGuard:S\(space)"
        }
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(disabled("SpaceGuard"))
        menu.addItem(disabled("メニューバー表示はbind済みの作業Spaceです"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(disabled("Bound Space"))
        for line in SpaceGuardCore.statusText().split(separator: "\n") {
            menu.addItem(disabled(String(line)))
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(disabled("Windows in Bound Space"))
        for line in SpaceGuardCore.windowsText().split(separator: "\n") {
            menu.addItem(disabled(String(line)))
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(disabled("All Known Spaces"))
        for line in SpaceGuardCore.allSpacesText().split(separator: "\n") {
            menu.addItem(disabled(String(line)))
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(action("Bind Codex Window", #selector(bindCodex)))
        menu.addItem(action("Refresh", #selector(refreshAction)))
        menu.addItem(action("Clear Bind", #selector(clearBind)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(action("Quit SpaceGuard", #selector(quit)))
        return menu
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
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
        print("usage: spaceguard bind|status|windows|assert --app <name>|clear")
        exit(2)
    }

    switch command {
    case "bind":
        print(SpaceGuardCore.bindCodex())
    case "status":
        print(SpaceGuardCore.statusText())
    case "windows":
        print(SpaceGuardCore.windowsText())
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
        print("usage: spaceguard bind|status|windows|assert --app <name>|clear")
        exit(2)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--cli" {
    runCLI(arguments: Array(arguments.dropFirst()))
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
