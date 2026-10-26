import Foundation

enum ZshRuntime {
    static func bootstrapEnvironment(shellPath: String) throws -> [String: String] {
        let originalZDOTDIR = resolveOriginalZDOTDIR()
        let runtimeDirectory = try createRuntimeZDOTDIR(originalZDOTDIR: originalZDOTDIR)

        return [
            "TERM": "xterm-256color",
            "SHELL": shellPath,
            "ZDOTDIR": runtimeDirectory.path,
            "ATERM_ORIGINAL_ZDOTDIR": originalZDOTDIR.path,
            "ATERM_RUNTIME_ZDOTDIR": runtimeDirectory.path,
        ]
    }

    private static func resolveOriginalZDOTDIR() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let zdotdir = environment["ZDOTDIR"], !zdotdir.isEmpty {
            return URL(fileURLWithPath: zdotdir, isDirectory: true)
        }

        let home = environment["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
    }

    private static func createRuntimeZDOTDIR(originalZDOTDIR: URL) throws -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let runtimeDirectory = appSupport
            .appendingPathComponent("aTerm", isDirectory: true)
            .appendingPathComponent("runtime", isDirectory: true)
            .appendingPathComponent("zsh", isDirectory: true)

        try fileManager.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)

        let wrappers = [
            ".zshenv": wrapperFileContent(for: ".zshenv", originalZDOTDIR: originalZDOTDIR, injectHooks: false),
            ".zprofile": wrapperFileContent(for: ".zprofile", originalZDOTDIR: originalZDOTDIR, injectHooks: false),
            ".zshrc": wrapperFileContent(for: ".zshrc", originalZDOTDIR: originalZDOTDIR, injectHooks: true),
            ".zlogin": wrapperFileContent(for: ".zlogin", originalZDOTDIR: originalZDOTDIR, injectHooks: false),
            ".zlogout": wrapperFileContent(for: ".zlogout", originalZDOTDIR: originalZDOTDIR, injectHooks: false),
        ]

        for (filename, contents) in wrappers {
            try contents.write(to: runtimeDirectory.appendingPathComponent(filename), atomically: true, encoding: .utf8)
        }

        return runtimeDirectory
    }

    private static func wrapperFileContent(for filename: String, originalZDOTDIR: URL, injectHooks: Bool) -> String {
        let sourceLine = """
        if [[ -r "\(originalZDOTDIR.path)/\(filename)" ]]; then
          source "\(originalZDOTDIR.path)/\(filename)"
        fi
        """

        guard injectHooks else {
            return "# aTerm runtime wrapper\n\(sourceLine)\n"
        }

        return """
        # aTerm runtime wrapper
        \(sourceLine)

        autoload -Uz add-zsh-hook

        function aterm_emit_terminal_state() {
          local exit_code=$?
          emulate -L zsh
          local host_name path title
          host_name=${HOST:-localhost}
          path=${PWD// /%20}
          title=${PWD:t}
          printf '\\033]133;D;%s\\a' "$exit_code"
          printf '\\033]7;file://%s%s\\a' "$host_name" "$path"
          printf '\\033]0;%s\\a' "$title"
          printf '\\033]133;A\\a'
          if [[ -o interactive ]] && [[ "${PS1:-}" != *133\\;B* ]]; then
            PS1="${PS1}"$'%{\\033]133;B\\a%}'
          fi
        }

        function aterm_preexec() {
          printf '\\033]133;C\\a'
        }

        function __aterm_zle_line_init() {
          printf '\\033]133;B\\a'
        }
        if (( $+functions[zle] )) || [[ -o interactive ]]; then
          zle -N zle-line-init __aterm_zle_line_init 2>/dev/null || true
          bindkey -M emacs '^U' kill-whole-line 2>/dev/null || true
          bindkey -M viins '^U' kill-whole-line 2>/dev/null || true
        fi

        # Ensure aterm_emit_terminal_state runs first in precmd so 133;A precedes any theme precmd output
        precmd_functions=(aterm_emit_terminal_state ${precmd_functions:#aterm_emit_terminal_state})
        add-zsh-hook preexec aterm_preexec
        aterm_emit_terminal_state
        """
    }
}
