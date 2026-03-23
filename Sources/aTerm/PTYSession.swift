import Darwin
import Foundation

enum PTYEvent: Sendable {
    case output(Data)
    case exit(Int32)
}

enum PTYSessionError: LocalizedError {
    case shellNotFound
    case executableNotFound(String)
    case forkFailed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case .shellNotFound:
            return "No valid zsh shell was found in /etc/shells or SHELL."
        case let .executableNotFound(path):
            return "Executable not found: \(path)"
        case let .forkFailed(code):
            return String(cString: strerror(code))
        }
    }
}

struct PTYLaunchConfiguration {
    let executablePath: String
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: URL?
    let displayName: String

    static func shell(workingDirectory: URL?) throws -> PTYLaunchConfiguration {
        let shellPath = try ShellLocator.detectZsh()
        return PTYLaunchConfiguration(
            executablePath: shellPath,
            arguments: ["-il"],
            environment: try ZshRuntime.bootstrapEnvironment(shellPath: shellPath),
            workingDirectory: workingDirectory,
            displayName: shellPath
        )
    }

    static func agent(executablePath: String, arguments: [String], environment: [String: String], workingDirectory: URL?, displayName: String) -> PTYLaunchConfiguration {
        PTYLaunchConfiguration(
            executablePath: executablePath,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            displayName: displayName
        )
    }
}

final class PTYSession {
    let events: AsyncStream<PTYEvent>
    let executablePath: String
    let displayName: String
    let workingDirectory: URL?

    private var continuation: AsyncStream<PTYEvent>.Continuation?
    private(set) var isRunning = false

    private var masterFileDescriptor: Int32 = -1
    private var childProcessID: pid_t = 0
    private var readSource: DispatchSourceRead?
    private let launchConfiguration: PTYLaunchConfiguration

    init(columns: UInt16, rows: UInt16, configuration: PTYLaunchConfiguration) throws {
        executablePath = configuration.executablePath
        displayName = configuration.displayName
        workingDirectory = configuration.workingDirectory
        launchConfiguration = configuration

        var streamContinuation: AsyncStream<PTYEvent>.Continuation?
        events = AsyncStream { continuation in
            streamContinuation = continuation
        }
        self.continuation = streamContinuation

        try spawn(columns: columns, rows: rows)
    }

    deinit {
        terminate()
        continuation?.finish()
    }

    func start() {
        guard masterFileDescriptor >= 0 else { return }
        isRunning = true

        let queue = DispatchQueue(label: "com.aterm.pty.read", qos: .userInitiated)
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFileDescriptor, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readAvailableData()
        }
        source.setCancelHandler { [masterFileDescriptor] in
            if masterFileDescriptor >= 0 {
                close(masterFileDescriptor)
            }
        }
        readSource = source
        source.resume()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.monitorChildExit()
        }
    }

    func send(_ data: Data) {
        guard isRunning, masterFileDescriptor >= 0 else { return }

        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            _ = write(masterFileDescriptor, baseAddress, rawBuffer.count)
        }
    }

    func resize(columns: UInt16, rows: UInt16) {
        guard masterFileDescriptor >= 0 else { return }
        var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFileDescriptor, TIOCSWINSZ, &size)
    }

    func terminate() {
        guard childProcessID > 0 else { return }
        kill(childProcessID, SIGTERM)
        readSource?.cancel()
        readSource = nil
        childProcessID = 0
        isRunning = false
    }

    private func spawn(columns: UInt16, rows: UInt16) throws {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw PTYSessionError.executableNotFound(executablePath)
        }

        var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        var master: Int32 = -1

        let pid = forkpty(&master, nil, nil, &size)
        guard pid >= 0 else {
            throw PTYSessionError.forkFailed(errno: errno)
        }

        if pid == 0 {
            launchChildProcess(configuration: launchConfiguration)
        }

        masterFileDescriptor = master
        childProcessID = pid
    }

    private func readAvailableData() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(masterFileDescriptor, &buffer, buffer.count)

        if bytesRead > 0 {
            continuation?.yield(.output(Data(buffer.prefix(bytesRead))))
            return
        }

        if bytesRead == 0 || errno == EIO {
            finish(exitStatus: 0)
        }
    }

    private func monitorChildExit() {
        guard childProcessID > 0 else { return }

        var status: Int32 = 0
        let waitedPID = waitpid(childProcessID, &status, 0)
        guard waitedPID == childProcessID else { return }

        let code: Int32
        if ProcessExitStatus.didExit(status) {
            code = ProcessExitStatus.exitCode(status)
        } else if ProcessExitStatus.wasSignaled(status) {
            code = 128 + ProcessExitStatus.terminationSignal(status)
        } else {
            code = status
        }

        finish(exitStatus: code)
    }

    private func finish(exitStatus: Int32) {
        guard isRunning else { return }
        isRunning = false
        readSource?.cancel()
        readSource = nil
        continuation?.yield(.exit(exitStatus))
    }
}

private func launchChildProcess(configuration: PTYLaunchConfiguration) -> Never {
    if let workingDirectory = configuration.workingDirectory {
        _ = chdir(workingDirectory.path)
    }

    let environment = PTYEnvironment.make(executablePath: configuration.executablePath, launchEnvironment: configuration.environment)
    let executableName = URL(fileURLWithPath: configuration.executablePath).lastPathComponent
    var arguments = [strdup(executableName)] + configuration.arguments.map { strdup($0) } + [nil]
    var environmentPointers = environment.map { strdup($0) }
    environmentPointers.append(nil)

    execve(configuration.executablePath, &arguments, &environmentPointers)
    _exit(1)
}

private enum PTYEnvironment {
    static func make(executablePath: String, launchEnvironment: [String: String]) -> [String] {
        var environment = ProcessInfo.processInfo.environment
        launchEnvironment.forEach { environment[$0.key] = $0.value }
        environment["TERM"] = environment["TERM"] ?? "xterm-256color"
        environment["SHELL"] = environment["SHELL"] ?? executablePath
        return environment.map { "\($0.key)=\($0.value)" }
    }
}

private enum ProcessExitStatus {
    static func didExit(_ status: Int32) -> Bool {
        (status & 0x7f) == 0
    }

    static func exitCode(_ status: Int32) -> Int32 {
        (status >> 8) & 0xff
    }

    static func wasSignaled(_ status: Int32) -> Bool {
        let signal = status & 0x7f
        return signal != 0 && signal != 0x7f
    }

    static func terminationSignal(_ status: Int32) -> Int32 {
        status & 0x7f
    }
}

enum ShellLocator {
    static func detectZsh() throws -> String {
        let fileManager = FileManager.default
        let candidateShell = ProcessInfo.processInfo.environment["SHELL"]

        if let candidateShell, candidateShell.contains("zsh"), fileManager.isExecutableFile(atPath: candidateShell) {
            return candidateShell
        }

        if let shells = try? String(contentsOfFile: "/etc/shells", encoding: .utf8) {
            for line in shells.split(separator: "\n") {
                let path = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                if path.hasSuffix("zsh"), fileManager.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }

        if fileManager.isExecutableFile(atPath: "/bin/zsh") {
            return "/bin/zsh"
        }

        throw PTYSessionError.shellNotFound
    }
}
