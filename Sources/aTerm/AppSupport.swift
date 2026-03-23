import Foundation

enum AppSupport {
    static var baseURL: URL {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL
            .appendingPathComponent("aTerm", isDirectory: true)
    }
}
