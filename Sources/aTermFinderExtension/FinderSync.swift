import Cocoa
import FinderSync

class ATermFinderSync: FIFinderSync {
    override init() {
        super.init()

        // Watch all mounted volumes
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) ?? []
        FIFinderSyncController.default().directoryURLs = Set(volumes)
    }

    // MARK: - Menu Items

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        let item = NSMenuItem(
            title: "Open in aTerm",
            action: #selector(openInATerm(_:)),
            keyEquivalent: ""
        )
        item.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Terminal")
        menu.addItem(item)
        return menu
    }

    @objc private func openInATerm(_ sender: AnyObject?) {
        guard let target = FIFinderSyncController.default().targetedURL() else { return }
        let url = target

        // Try to open via URL scheme first (preferred — activates existing aTerm)
        let aTermURL = URL(string: "aterm://open?path=\(url.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url.path)")!
        NSWorkspace.shared.open(aTermURL)
    }
}
