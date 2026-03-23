import AppKit
import Foundation

struct SessionStore {
    struct StoredPane: Codable {
        let id: UUID
        let title: String
        let workingDirectoryPath: String?
        let profileID: UUID?
        let agentDefinitionID: String?

        var workingDirectoryURL: URL? {
            guard let workingDirectoryPath else { return nil }
            return URL(fileURLWithPath: workingDirectoryPath)
        }
    }

    struct StoredTab: Codable {
        let id: UUID
        let title: String
        let workingDirectoryPath: String?
        let profileID: UUID?
        let agentDefinitionID: String?
        let activePaneID: UUID?
        let splitOrientation: String?
        let panes: [StoredPane]?

        var workingDirectoryURL: URL? {
            guard let workingDirectoryPath else { return nil }
            return URL(fileURLWithPath: workingDirectoryPath)
        }

        var resolvedSplitOrientation: PaneSplitOrientation? {
            guard let splitOrientation else { return nil }
            return PaneSplitOrientation(rawValue: splitOrientation)
        }
    }

    struct WindowState: Codable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var selectedTabID: UUID?
    }

    private let fileManager = FileManager.default

    func loadTabs() -> [StoredTab] {
        guard let data = try? Data(contentsOf: tabsStorageURL) else { return [] }
        return (try? JSONDecoder().decode([StoredTab].self, from: data)) ?? []
    }

    func saveTabs(_ tabs: [StoredTab]) {
        do {
            try fileManager.createDirectory(at: tabsStorageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(tabs)
            try data.write(to: tabsStorageURL, options: .atomic)
        } catch {
            fputs("aTerm: failed to persist tabs: \(error)\n", stderr)
        }
    }

    func loadWindowState() -> WindowState? {
        guard let data = try? Data(contentsOf: windowStorageURL) else { return nil }
        return try? JSONDecoder().decode(WindowState.self, from: data)
    }

    func saveWindowState(_ state: WindowState) {
        do {
            try fileManager.createDirectory(at: windowStorageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(state)
            try data.write(to: windowStorageURL, options: .atomic)
        } catch {
            fputs("aTerm: failed to persist window state: \(error)\n", stderr)
        }
    }

    private var tabsStorageURL: URL {
        AppSupport.baseURL.appendingPathComponent("session-tabs.json")
    }

    private var windowStorageURL: URL {
        AppSupport.baseURL.appendingPathComponent("window-state.json")
    }
}

// MARK: - Window Frame Restoration (SwiftUI helper)

import SwiftUI

/// Attaches to the hosting NSWindow and restores/saves frame using autosave.
struct WindowFrameRestorer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let window = view.window else { return }
            window.setFrameAutosaveName("aTermMainWindow")

            // Observe window move/resize to persist state (debounced in coordinator)
            NotificationCenter.default.addObserver(
                context.coordinator, selector: #selector(Coordinator.windowDidChange(_:)),
                name: NSWindow.didResizeNotification, object: window
            )
            NotificationCenter.default.addObserver(
                context.coordinator, selector: #selector(Coordinator.windowDidChange(_:)),
                name: NSWindow.didMoveNotification, object: window
            )
            context.coordinator.isReady = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject {
        private let store = SessionStore()
        var isReady = false
        private var debounceWork: DispatchWorkItem?

        @MainActor @objc func windowDidChange(_ notification: Notification) {
            guard isReady, let window = notification.object as? NSWindow else { return }
            // Capture frame on main actor before dispatching
            let frame = window.frame
            // Debounce: save at most once per 500ms
            debounceWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isReady else { return }
                let state = SessionStore.WindowState(
                    x: frame.origin.x, y: frame.origin.y,
                    width: frame.size.width, height: frame.size.height,
                    selectedTabID: nil
                )
                self.store.saveWindowState(state)
            }
            debounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }
}
