import AppKit
import Combine
import Foundation

enum TabKind: Hashable {
    case shell
    case agent(AgentDefinition)
}

enum PaneSplitOrientation: String, Codable {
    case horizontal
    case vertical
}

struct ScrollbackSearchMatch: Equatable {
    let location: Int
    let length: Int
}

@MainActor
final class TerminalPaneViewModel: ObservableObject, Identifiable {
    let id: UUID
    let kind: TabKind

    let terminalBuffer: TerminalBuffer
    @Published private(set) var displayText = ""
    @Published private(set) var statusText = "starting shell..."
    @Published private(set) var title: String
    @Published private(set) var currentWorkingDirectory: URL?
    @Published var appearance: TerminalAppearance
    @Published var activeProviderName: String = "No provider"
    @Published var activeModelName: String = "No model"
    @Published var inputText: String = ""
    @Published var queryResponse = QueryResponseState()
    @Published var aiShellState = AIShellState()
    @Published var submissionState: InputSubmissionState = .idle
    @Published var modeIndicatorText: String = "TERMINAL"
    @Published var agentExitBanner: String?
    @Published var isAgentAutoRestartEnabled = false
    @Published var isSearchPresented = false
    @Published var searchQuery = ""
    @Published var isRegexSearchEnabled = false
    @Published private(set) var searchMatchCount = 0
    @Published private(set) var currentSearchIndex = 0
    /// Incremented on every buffer update to trigger SwiftUI redraw
    @Published private(set) var bufferVersion: UInt64 = 0
    /// True when the running program has switched to the alternate screen (e.g. vim, less, claude)
    @Published private(set) var isAlternateScreen = false
    
    // MARK: - Chat Mode
    @Published var isChatModeActive = false
    @Published var chatProviderID: String?
    @Published var chatModelID: String?
    let chatConversationHistory = ConversationHistory(maxMessages: 60)

    private(set) var profileID: UUID?
    private(set) var profileName: String
    var stateDidChange: (() -> Void)?
    var onChatRequest: ((String) -> Void)?
    /// When set, Return on the main shell screen routes the typed line through smart classification instead of only the PTY.
    var onSubmitSmartLine: ((String) -> Void)?

    private var preferredWorkingDirectory: URL?
    private var currentColumns: UInt16 = 100
    private var currentRows: UInt16 = 30
    private var session: PTYSession?
    private var outputTask: Task<Void, Never>?
    private var autoRestartTask: Task<Void, Never>?
    private var searchUpdateTask: Task<Void, Never>?
    private lazy var vt100Parser: VT100Parser = VT100Parser(buffer: terminalBuffer)
    let conversationHistory = ConversationHistory()
    private var recentCommands: [String] = []
    private var lastOutputSnippet = ""
    private var lastExitCode: Int32?
    private var recentFailures: [String] = []
    private var chatInputBuffer = ""
    private var sessionStartTime: Date?
    private var projectInfo: ProjectContextDetector.ProjectInfo = ProjectContextDetector.ProjectInfo(type: .generic, gitBranch: nil, rootDirectory: nil)
    private let explicitLaunchConfiguration: PTYLaunchConfiguration?
    private let projectDetector = ProjectContextDetector.shared

    init(
        id: UUID = UUID(),
        initialTitle: String = "zsh",
        workingDirectory: URL?,
        profile: Profile,
        kind: TabKind = .shell,
        launchConfiguration: PTYLaunchConfiguration? = nil
    ) {
        self.id = id
        terminalBuffer = TerminalBuffer(columns: Int(currentColumns), rows: Int(currentRows))
        terminalBuffer.scrollbackLimit = profile.appearance.scrollbackSize
        title = initialTitle
        currentWorkingDirectory = workingDirectory
        preferredWorkingDirectory = workingDirectory
        appearance = profile.appearance
        profileID = profile.id
        profileName = profile.name
        self.kind = kind
        explicitLaunchConfiguration = launchConfiguration
        if case let .agent(agent) = kind {
            modeIndicatorText = "AGENT"
            title = agent.name
        }
    }

    var isAgentTab: Bool {
        if case .agent = kind { return true }
        return false
    }

    var searchMatches: [ScrollbackSearchMatch] {
        searchResult.matches
    }

    func duplicateForSplit(id: UUID = UUID()) -> TerminalPaneViewModel {
        TerminalPaneViewModel(
            id: id,
            initialTitle: title,
            workingDirectory: currentWorkingDirectory ?? preferredWorkingDirectory,
            profile: Profile(id: profileID ?? UUID(), name: profileName, appearance: appearance),
            kind: kind,
            launchConfiguration: explicitLaunchConfiguration
        )
    }

    func startIfNeeded() {
        guard session == nil else {
            Log.debug("pty", "startIfNeeded() skipped — session already exists for pane=\(id)")
            return
        }
        Log.debug("pty", "startIfNeeded() starting session for pane=\(id)")
        startSession()
    }

    func handleInput(_ data: Data) {
        guard let session else {
            Log.debug("input", "handleInput: no session, dropping \(data.count) bytes")
            return
        }

        // Return on the main screen: classify the visible line (zsh already holds the same text in readline).
        if !isChatModeActive, !isAgentTab, !terminalBuffer.isAlternateScreen,
           let onSubmitSmartLine,
           data == Data([0x0d]) || data == Data([0x0a]) {
            let userLine = terminalBuffer.userInputForSmartClassification()
            if userLine.isEmpty {
                if session.isRunning {
                    session.send(data)
                } else {
                    restartSessionIfPossible()
                }
                return
            }
            onSubmitSmartLine(userLine)
            return
        }

        // Check for chat command interception
        if let text = String(data: data, encoding: .utf8) {
            if isChatModeActive {
                // In chat mode, collect a full line and only send to AI on Enter.
                if text == "\r" || text == "\n" || text == "\r\n" {
                    let message = chatInputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    appendChatLine("")
                    chatInputBuffer = ""
                    if message.lowercased() == "/chat-exit" || message.lowercased() == "/chat-eixt" {
                        exitChatMode()
                        return
                    }
                    if !message.isEmpty {
                        onChatRequest?(message)
                    } else {
                        showChatPrompt()
                    }
                    return
                }

                // Handle backspace/delete in local chat line buffer.
                if text == "\u{7f}" || text == "\u{8}" {
                    if !chatInputBuffer.isEmpty {
                        chatInputBuffer.removeLast()
                        eraseLastChatInputCharacter()
                    }
                    return
                }

                // Ignore escape and other control characters while building the chat line.
                if text.unicodeScalars.allSatisfy({ $0.value < 0x20 || $0.value == 0x7f }) {
                    return
                }

                chatInputBuffer.append(text)
                appendChatInputCharacters(text)
                return
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased() == "/chat-exit" || trimmed.lowercased() == "/chat-eixt" {
                exitChatMode()
                return
            }
            if trimmed.lowercased().hasPrefix("/chat ") || trimmed.lowercased() == "/chat" {
                let chatContent = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                enterChatMode(providerID: appearance.chatProvider, modelID: appearance.chatModel)
                if !chatContent.isEmpty {
                    // Process the chat message via callback
                    onChatRequest?(chatContent)
                }
                return
            }
        }

        if session.isRunning {
            Log.debug("input", "handleInput: sending \(data.count) bytes to PTY")
            session.send(data)
            return
        }

        Log.debug("input", "handleInput: session not running, attempting restart")
        restartSessionIfPossible()
    }

    func updateTerminalSize(columns: UInt16, rows: UInt16) {
        guard columns > 0, rows > 0 else { return }
        guard columns != currentColumns || rows != currentRows else { return }
        currentColumns = columns
        currentRows = rows
        session?.resize(columns: columns, rows: rows)
        terminalBuffer.resize(columns: Int(columns), rows: Int(rows))
        bufferVersion &+= 1
    }

    func terminate() {
        autoRestartTask?.cancel()
        autoRestartTask = nil
        outputTask?.cancel()
        outputTask = nil
        session?.terminate()
        session = nil
    }

    func restartSessionIfPossible() {
        agentExitBanner = nil
        terminate()
        startSession()
    }

    func terminalContext() -> ClassificationContext {
        // Update project info if working directory changed
        if let cwd = currentWorkingDirectory {
            projectInfo = projectDetector.detectProjectInfo(for: cwd)
        }
        
        return ClassificationContext(
            workingDirectory: currentWorkingDirectory,
            lastCommands: Array(recentCommands.suffix(5)),
            lastOutputSnippet: lastOutputSnippet,
            lastExitCode: lastExitCode.map(Int.init),
            gitBranch: projectInfo.gitBranch,
            projectType: projectInfo.type,
            recentFailures: Array(recentFailures.suffix(3)),
            sessionDuration: sessionStartTime.map { Date().timeIntervalSince($0) }
        )
    }

    func recordTerminalCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentCommands.append(trimmed)
        if recentCommands.count > 20 {
            recentCommands.removeFirst(recentCommands.count - 20)
        }
    }

    func sendTerminalCommand(_ command: String) {
        let normalized = command.hasSuffix("\n") ? command : command + "\n"
        recordTerminalCommand(command)
        guard let session else {
            Log.debug("input", "sendTerminalCommand: no session")
            return
        }
        if session.isRunning {
            session.send(Data(normalized.utf8))
        } else {
            Log.debug("input", "sendTerminalCommand: session not running, restart")
            restartSessionIfPossible()
        }
        modeIndicatorText = isAgentTab ? "AGENT" : InputMode.terminal.rawValue
    }

    /// Submit a line zsh already has buffered (user typed at the prompt; we withheld Return).
    func sendBufferedReturnToShell() {
        guard let session, session.isRunning else { return }
        session.send(Data([0x0d]))
    }

    /// Emacs-style kill line (zsh default); clears a line the user typed when we handle it in-app instead.
    func sendShellKillLineToPTY() {
        guard let session, session.isRunning else { return }
        session.send(Data([0x15]))
    }

    /// Export scrollback + screen content as plain text
    func exportScrollbackText() -> String {
        terminalBuffer.plainText(includeScrollback: true)
    }

    func clearAssistantState() {
        queryResponse = QueryResponseState()
        aiShellState = AIShellState()
        submissionState = .idle
        modeIndicatorText = isAgentTab ? "AGENT" : InputMode.terminal.rawValue
    }
    
    // MARK: - Chat Mode
    
    func enterChatMode(providerID: String?, modelID: String?) {
        isChatModeActive = true
        chatProviderID = providerID
        chatModelID = modelID
        chatInputBuffer = ""
        modeIndicatorText = "CHAT"
        chatConversationHistory.clear()
        appendChatLine("[chat mode enabled: type a message and press Enter, /chat-exit to leave]")
        showChatPrompt()
    }
    
    func exitChatMode() {
        isChatModeActive = false
        chatInputBuffer = ""
        modeIndicatorText = isAgentTab ? "AGENT" : InputMode.terminal.rawValue
        // Clear conversation history when exiting chat mode
        chatConversationHistory.clear()
        appendChatLine("[chat mode disabled: back to terminal]")
        syncShellLineAfterChatExit()
    }

    /// `/chat` and `/chat-exit` are handled locally, so the shell never receives Enter; clear the
    /// pending line and submit an empty line so zsh redraws a normal prompt.
    private func syncShellLineAfterChatExit() {
        guard let session, session.isRunning else { return }
        session.send(Data([0x15])) // Ctrl+U — kill line (zsh emacs default)
        session.send(Data("\r".utf8))
    }

    func clearScrollback() {
        terminalBuffer.eraseInDisplay(3)
        displayText = ""
        lastOutputSnippet = ""
        bufferVersion &+= 1
        refreshSearch()
    }

    func refreshSearch() {
        displayText = terminalBuffer.plainText()
        searchResult = Self.computeSearchResult(
            text: displayText,
            query: searchQuery,
            isRegex: isRegexSearchEnabled
        )
        searchMatchCount = searchResult.matches.count
        currentSearchIndex = min(currentSearchIndex, max(searchMatchCount - 1, 0))
    }

    private func scheduleSearchUpdate() {
        searchUpdateTask?.cancel()
        searchUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms debounce
            guard !Task.isCancelled else { return }
            self?.refreshSearch()
        }
    }

    func nextSearchMatch() {
        guard searchMatchCount > 0 else { return }
        currentSearchIndex = (currentSearchIndex + 1) % searchMatchCount
    }

    func previousSearchMatch() {
        guard searchMatchCount > 0 else { return }
        currentSearchIndex = (currentSearchIndex - 1 + searchMatchCount) % searchMatchCount
    }

    func applyProfile(_ profile: Profile) {
        appearance = profile.appearance
        profileID = profile.id
        profileName = profile.name
        refreshProviderLabel()
        if let path = profile.appearance.defaultWorkingDirectoryPath {
            preferredWorkingDirectory = URL(fileURLWithPath: path)
        }
        stateDidChange?()
    }

    func markStateChanged() {
        refreshProviderLabel()
        stateDidChange?()
    }

    func setProviderLabel(providerName: String?, modelName: String?) {
        activeProviderName = providerName ?? "No provider"
        activeModelName = modelName ?? "No model"
    }

    private func startSession() {
        Log.debug("pty", "startSession() pane=\(id) kind=\(isAgentTab ? "agent" : "shell")")
        outputTask?.cancel()
        vt100Parser.reset()
        sessionStartTime = Date()

        do {
            let configuration = try sessionConfiguration()
            Log.debug("pty", "Spawning PTY: \(configuration.executablePath) cols=\(currentColumns) rows=\(currentRows)")
            let session = try PTYSession(
                columns: currentColumns,
                rows: currentRows,
                configuration: configuration
            )
            self.session = session
            statusText = configuration.displayName
            // Wire CPR responses from parser back to PTY
            vt100Parser.sendToPTY = { [weak session] data in
                session?.send(data)
            }
            session.start()
            Log.debug("pty", "PTY started successfully for pane=\(id)")

            // Events are yielded from the PTY read queue; consume them on the main actor so
            // TerminalBuffer / @Published updates and AppKit redraws are well-defined.
            let eventStream = session.events
            // Consume the PTY stream entirely on the main actor: one task, one isolation domain,
            // same as UI observation — avoids per-chunk MainActor.run scheduling that can backlog
            // the main queue and starve key events / redraws under heavy output.
            outputTask = Task { @MainActor [weak self] in
                for await event in eventStream {
                    guard let self else { return }
                    switch event {
                    case let .output(data):
                        self.vt100Parser.feed(data)
                        TerminalKeyMapper.applicationCursorKeys = self.terminalBuffer.applicationCursorKeys
                        self.isAlternateScreen = self.terminalBuffer.isAlternateScreen
                        if self.terminalBuffer.bellFired {
                            self.terminalBuffer.bellFired = false
                            NSApplication.shared.requestUserAttention(.informationalRequest)
                        }
                        self.lastOutputSnippet = self.terminalBuffer.lastScreenLine(maxChars: 120)
                        self.bufferVersion &+= 1
                        if self.isSearchPresented { self.scheduleSearchUpdate() }

                        if let workingDirectory = self.terminalBuffer.workingDirectory {
                            if workingDirectory != self.currentWorkingDirectory {
                                self.currentWorkingDirectory = workingDirectory
                                self.preferredWorkingDirectory = workingDirectory
                                if !self.isAgentTab {
                                    self.title = workingDirectory.lastPathComponent.isEmpty ? "/" : workingDirectory.lastPathComponent
                                }
                                self.stateDidChange?()
                            }
                        }
                        if let title = self.terminalBuffer.title, !title.isEmpty, !self.isAgentTab {
                            if title != self.title {
                                self.title = title
                                self.stateDidChange?()
                            }
                        }
                    case let .exit(status):
                        self.handleExit(status: status)
                    }
                }
            }
        } catch {
            Log.error("pty", "Failed to start session for pane=\(id): \(error.localizedDescription)")
            statusText = "failed to start session"
            displayText = "Failed to start session: \(error.localizedDescription)"
            appendSystemNoticeToBuffer(
                "aTerm could not start the shell: \(error.localizedDescription)\r\n\r\nCheck Profiles → Shell, or that zsh is installed and listed in /etc/shells.\r\n"
            )
        }
    }

    private func appendSystemNoticeToBuffer(_ text: String) {
        for ch in text {
            if ch == "\r" { terminalBuffer.carriageReturn() }
            else if ch == "\n" { terminalBuffer.lineFeed() }
            else { terminalBuffer.putChar(ch) }
        }
        bufferVersion &+= 1
    }

    private func handleExit(status: Int32) {
        lastExitCode = status
        
        // Track failed commands for context
        if status != 0, let lastCommand = recentCommands.last {
            recentFailures.append(lastCommand)
            if recentFailures.count > 10 {
                recentFailures.removeFirst(recentFailures.count - 10)
            }
        }
        
        statusText = "session ended (\(status))"
        // Write exit message into the buffer
        let exitMsg = "\r\n[session ended — press any key to restart]"
        for ch in exitMsg {
            if ch == "\r" { terminalBuffer.carriageReturn() }
            else if ch == "\n" { terminalBuffer.lineFeed() }
            else { terminalBuffer.putChar(ch) }
        }
        displayText = terminalBuffer.plainText()
        lastOutputSnippet = String(displayText.suffix(120))
        bufferVersion &+= 1

        if case let .agent(agent) = kind {
            agentExitBanner = "[\(agent.name) exited with code \(status) — Restart?]"
            if status != 0, isAgentAutoRestartEnabled {
                autoRestartTask?.cancel()
                autoRestartTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { return }
                    self?.restartSessionIfPossible()
                }
            }
        }
    }

    private func sessionConfiguration() throws -> PTYLaunchConfiguration {
        if let explicitLaunchConfiguration {
            return explicitLaunchConfiguration
        }
        return try PTYLaunchConfiguration.shell(workingDirectory: preferredWorkingDirectory ?? currentWorkingDirectory)
    }

    private func refreshProviderLabel() {
        activeProviderName = appearance.aiProvider ?? "No provider"
        activeModelName = appearance.aiModel ?? "No model"
    }

    private static func computeSearchResult(text: String, query: String, isRegex: Bool) -> SearchResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SearchResult(matches: []) }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)

        if isRegex {
            guard let regex = try? NSRegularExpression(pattern: trimmed, options: []) else {
                return SearchResult(matches: [])
            }
            let matches = regex.matches(in: text, options: [], range: range)
                .map { ScrollbackSearchMatch(location: $0.range.location, length: $0.range.length) }
            return SearchResult(matches: matches)
        }

        let escaped = NSRegularExpression.escapedPattern(for: trimmed)
        guard let regex = try? NSRegularExpression(pattern: escaped, options: []) else {
            return SearchResult(matches: [])
        }
        let matches = regex.matches(in: text, options: [], range: range)
            .map { ScrollbackSearchMatch(location: $0.range.location, length: $0.range.length) }
        return SearchResult(matches: matches)
    }

    private struct SearchResult {
        let matches: [ScrollbackSearchMatch]
    }

    private var searchResult = SearchResult(matches: [])

    /// Move to the start of the next row, then write `text` (LF before CR so we never repaint from column 0 on the same row).
    private func appendChatLine(_ text: String) {
        terminalBuffer.lineFeed()
        terminalBuffer.carriageReturn()
        for ch in text {
            terminalBuffer.putChar(ch)
        }
        bufferVersion &+= 1
    }

    private func showChatPrompt() {
        terminalBuffer.lineFeed()
        terminalBuffer.carriageReturn()
        for ch in "chat> " {
            terminalBuffer.putChar(ch)
        }
        bufferVersion &+= 1
    }

    private func appendChatInputCharacters(_ text: String) {
        for ch in text {
            terminalBuffer.putChar(ch)
        }
        bufferVersion &+= 1
    }

    private func eraseLastChatInputCharacter() {
        terminalBuffer.backspace()
        terminalBuffer.putChar(" ")
        terminalBuffer.backspace()
        bufferVersion &+= 1
    }

    /// Word-wrap at spaces so Core Text grid wrapping does not split mid-word.
    private static func wrapChatParagraph(_ paragraph: String, lineBudget: Int) -> [String] {
        guard !paragraph.isEmpty else { return [] }
        let words = paragraph.split { $0.isWhitespace || $0.isNewline }.map(String.init)
        guard !words.isEmpty else { return [String(paragraph.prefix(lineBudget))] }

        var lines: [String] = []
        var current = ""

        func flush() {
            if !current.isEmpty {
                lines.append(current)
                current = ""
            }
        }

        for word in words {
            let candidate = current.isEmpty ? word : "\(current) \(word)"
            if candidate.count <= lineBudget {
                current = candidate
            } else {
                flush()
                if word.count > lineBudget {
                    var rest = word
                    while rest.count > lineBudget {
                        lines.append(String(rest.prefix(lineBudget)))
                        rest = String(rest.dropFirst(lineBudget))
                    }
                    current = rest
                } else {
                    current = word
                }
            }
        }
        flush()
        return lines.isEmpty ? [""] : lines
    }

    func appendChatAssistantResponse(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            appendChatLine("ai> [no response]")
            showChatPrompt()
            return
        }

        let prefixLength = 4 // "ai> " and "    "
        let columns = max(40, terminalBuffer.columns)
        let lineBudget = max(24, columns - prefixLength)

        let normalized = cleaned.replacingOccurrences(of: "\r\n", with: "\n")
        let paragraphs = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var firstRendered = true
        for para in paragraphs {
            if para.isEmpty {
                appendChatLine("    ")
                continue
            }
            let wrapped = Self.wrapChatParagraph(para, lineBudget: lineBudget)
            for w in wrapped {
                let prefix = firstRendered ? "ai> " : "    "
                appendChatLine(prefix + w)
                firstRendered = false
            }
        }
        showChatPrompt()
    }
}

@MainActor
final class TerminalTabViewModel: ObservableObject, Identifiable {
    let id: UUID
    let kind: TabKind

    @Published private(set) var panes: [TerminalPaneViewModel]
    @Published var activePaneID: UUID
    @Published var splitOrientation: PaneSplitOrientation?
    @Published var hasUnreadOutput = false

    var stateDidChange: (() -> Void)?

    private var cancellables: Set<AnyCancellable> = []

    init(
        id: UUID = UUID(),
        initialTitle: String = "zsh",
        workingDirectory: URL?,
        profile: Profile,
        kind: TabKind = .shell,
        launchConfiguration: PTYLaunchConfiguration? = nil,
        panes: [TerminalPaneViewModel]? = nil,
        activePaneID: UUID? = nil,
        splitOrientation: PaneSplitOrientation? = nil
    ) {
        self.id = id
        self.kind = kind
        let rootPanes = panes ?? [
            TerminalPaneViewModel(
                initialTitle: initialTitle,
                workingDirectory: workingDirectory,
                profile: profile,
                kind: kind,
                launchConfiguration: launchConfiguration
            )
        ]
        self.panes = rootPanes
        self.activePaneID = activePaneID ?? rootPanes.first?.id ?? UUID()
        self.splitOrientation = splitOrientation
        bindPanes()
    }

    var isAgentTab: Bool {
        if case .agent = kind { return true }
        return false
    }

    var activePane: TerminalPaneViewModel? {
        panes.first(where: { $0.id == activePaneID }) ?? panes.first
    }

    var title: String { activePane?.title ?? "zsh" }
    var statusText: String { activePane?.statusText ?? "starting shell..." }
    var currentWorkingDirectory: URL? { activePane?.currentWorkingDirectory }
    var appearance: TerminalAppearance {
        get { activePane?.appearance ?? .default }
        set { activePane?.appearance = newValue }
    }
    var activeProviderName: String { activePane?.activeProviderName ?? "No provider" }
    var activeModelName: String { activePane?.activeModelName ?? "No model" }
    var profileID: UUID? { activePane?.profileID }
    var profileName: String { activePane?.profileName ?? "Default" }
    var inputText: String {
        get { activePane?.inputText ?? "" }
        set { activePane?.inputText = newValue }
    }
    var queryResponse: QueryResponseState {
        get { activePane?.queryResponse ?? QueryResponseState() }
        set { activePane?.queryResponse = newValue }
    }
    var aiShellState: AIShellState {
        get { activePane?.aiShellState ?? AIShellState() }
        set { activePane?.aiShellState = newValue }
    }
    var submissionState: InputSubmissionState {
        get { activePane?.submissionState ?? .idle }
        set { activePane?.submissionState = newValue }
    }
    var modeIndicatorText: String {
        get { activePane?.modeIndicatorText ?? "TERMINAL" }
        set { activePane?.modeIndicatorText = newValue }
    }
    var agentExitBanner: String? {
        get { activePane?.agentExitBanner }
        set { activePane?.agentExitBanner = newValue }
    }
    var isAgentAutoRestartEnabled: Bool {
        get { activePane?.isAgentAutoRestartEnabled ?? false }
        set { activePane?.isAgentAutoRestartEnabled = newValue }
    }
    var isSearchPresented: Bool {
        get { activePane?.isSearchPresented ?? false }
        set { activePane?.isSearchPresented = newValue }
    }
    var searchQuery: String {
        get { activePane?.searchQuery ?? "" }
        set { activePane?.searchQuery = newValue }
    }
    var isRegexSearchEnabled: Bool {
        get { activePane?.isRegexSearchEnabled ?? false }
        set { activePane?.isRegexSearchEnabled = newValue }
    }
    var searchMatchCount: Int { activePane?.searchMatchCount ?? 0 }
    var currentSearchIndex: Int { activePane?.currentSearchIndex ?? 0 }

    func startIfNeeded() {
        panes.forEach { $0.startIfNeeded() }
    }

    func terminate() {
        panes.forEach { $0.terminate() }
    }

    func restartSessionIfPossible() {
        activePane?.restartSessionIfPossible()
    }

    func terminalContext() -> ClassificationContext {
        activePane?.terminalContext() ?? ClassificationContext(workingDirectory: nil, lastCommands: [], lastOutputSnippet: "")
    }

    func sendTerminalCommand(_ command: String) {
        activePane?.sendTerminalCommand(command)
    }

    func clearAssistantState() {
        activePane?.clearAssistantState()
    }

    func clearScrollback() {
        activePane?.clearScrollback()
    }

    func refreshSearch() {
        activePane?.refreshSearch()
    }

    func nextSearchMatch() {
        activePane?.nextSearchMatch()
    }

    func previousSearchMatch() {
        activePane?.previousSearchMatch()
    }

    func applyProfile(_ profile: Profile) {
        panes.forEach { $0.applyProfile(profile) }
        stateDidChange?()
    }

    func markStateChanged() {
        activePane?.markStateChanged()
    }

    func setProviderLabel(providerName: String?, modelName: String?) {
        activePane?.setProviderLabel(providerName: providerName, modelName: modelName)
    }

    func splitActivePane(orientation: PaneSplitOrientation) {
        guard let activePane, panes.count < 4 else { return }
        let clone = activePane.duplicateForSplit()
        clone.stateDidChange = { [weak self] in
            self?.stateDidChange?()
        }
        clone.onChatRequest = activePane.onChatRequest
        clone.onSubmitSmartLine = activePane.onSubmitSmartLine
        panes.append(clone)
        activePaneID = clone.id
        splitOrientation = splitOrientation ?? orientation
        bindPanes()
        clone.startIfNeeded()
        stateDidChange?()
    }

    func closePane(id: UUID) {
        guard panes.count > 1, let index = panes.firstIndex(where: { $0.id == id }) else { return }
        panes[index].terminate()
        panes.remove(at: index)
        if activePaneID == id {
            activePaneID = panes[min(index, panes.count - 1)].id
        }
        if panes.count <= 1 {
            splitOrientation = nil
        }
        bindPanes()
        stateDidChange?()
    }

    func selectPane(id: UUID) {
        activePaneID = id
        panes.first(where: { $0.id == id })?.startIfNeeded()
        objectWillChange.send()
    }

    private func bindPanes() {
        cancellables.removeAll()
        for pane in panes {
            pane.stateDidChange = { [weak self] in
                self?.stateDidChange?()
            }
            pane.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }
    }
}
