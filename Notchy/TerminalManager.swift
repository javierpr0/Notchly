import AppKit
import SwiftTerm

struct PaneCompletionInfo {
    let summary: String
    let hadError: Bool
}

class ClickThroughTerminalView: LocalProcessTerminalView {
    var sessionId: UUID?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var rightClickMonitor: Any?
    private var statusDebounceTimer: Timer?
    var isInitializing = false
    private var dataReceivedCount = 0

    // Autocomplete state
    private var autocompleteDebounceTimer: Timer?
    private var lastPromptInput: String = ""
    private var currentWorkingDir: String?
    private var ghostView: GhostTextView?
    private var currentGhostSuggestion: String?
    private static let promptCharacters: Set<Character> = ["$", "%", ">"]

    private var mouseUpMonitor: Any?
    private(set) lazy var searchController = TerminalSearchController()

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        // no-op: prevent SwiftTerm from auto-opening URLs in the browser
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        installArrowKeyMonitor()
        installClickMonitor()
        installRightClickMonitor()
        installMouseUpMonitor()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
        installArrowKeyMonitor()
        installClickMonitor()
        installRightClickMonitor()
        installMouseUpMonitor()
    }

    deinit {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = rightClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func installClickMonitor() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let id = self.sessionId,
                  let eventWindow = event.window,
                  eventWindow === self.window else { return event }
            let locationInView = self.convert(event.locationInWindow, from: nil)
            if self.bounds.contains(locationInView) {
                Task { @MainActor in
                    SessionStore.shared.focusPane(id)
                }
            }
            return event
        }
    }

    /// Intercept arrow key events locally and send standard VT100/xterm sequences
    /// to avoid kitty keyboard protocol (CSI u) encoding issues.
    /// Also handles autocomplete overlay navigation.
    private func installArrowKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.window?.firstResponder === self else { return event }

            // Ghost text: Tab accepts full suggestion, Right arrow accepts it too
            if self.currentGhostSuggestion != nil {
                let mods = event.modifierFlags.intersection([.shift, .option, .control, .command])

                // Tab → accept full ghost suggestion
                if event.keyCode == 48 && mods.isEmpty {
                    self.acceptGhostSuggestion()
                    return nil
                }
                // Right arrow (no mods) → accept full ghost suggestion
                if event.keyCode == 124 && mods.isEmpty {
                    self.acceptGhostSuggestion()
                    return nil
                }
                // Esc → dismiss ghost text
                if event.keyCode == 53 {
                    self.clearGhostText()
                    return nil
                }
            }

            // Shift+Enter → send newline sequence for Claude Code multiline input
            if event.keyCode == 36 && event.modifierFlags.contains(.shift) {
                self.send(txt: "\u{1b}[13;2u")
                return nil
            }

            // Enter without overlay — record the command being executed
            if event.keyCode == 36 {
                self.recordCurrentCommand()
            }

            let arrowCode: String?
            switch event.keyCode {
            case 126: arrowCode = "A" // Up
            case 125: arrowCode = "B" // Down
            case 124: arrowCode = "C" // Right
            case 123: arrowCode = "D" // Left
            default: arrowCode = nil
            }

            guard let code = arrowCode else { return event }

            let mods = event.modifierFlags.intersection([.shift, .option, .control])
            if mods.isEmpty {
                self.send(txt: "\u{1b}[\(code)")
            } else {
                var modifier = 1
                if mods.contains(.shift) { modifier += 1 }
                if mods.contains(.option) { modifier += 2 }
                if mods.contains(.control) { modifier += 4 }
                self.send(txt: "\u{1b}[1;\(modifier)\(code)")
            }
            return nil // consume the event
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else {
            return false
        }
        if isRunningClaudeCode() {
            let paths = items.map { "@" + $0.path.replacingOccurrences(of: " ", with: "\\ ") }.joined(separator: " ")
            send(txt: paths)
        } else {
            let paths = items.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
            send(txt: paths)
        }
        return true
    }

    private func isRunningClaudeCode() -> Bool {
        let terminal = getTerminal()
        let startRow = max(0, terminal.rows - 5)
        for row in startRow..<terminal.rows {
            var line = ""
            for col in 0..<terminal.cols {
                let ch = terminal.getCharacter(col: col, row: row) ?? " "
                line.append(ch == "\u{0}" ? " " : ch)
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("\u{276F}") { return true }
            if Self.hasTokenCounterLine(trimmed) { return true }
            if trimmed.contains("Esc to cancel") || trimmed.contains("esc to interrupt") { return true }
        }
        return false
    }

    /// Returns all visible lines from the terminal buffer.
    private func extractAllLines() -> [String]? {
        let terminal = getTerminal()
        guard terminal.rows >= 20 else { return nil }
        var lineTexts: [String] = []
        for row in 0..<terminal.rows {
            var line = ""
            for col in 0..<terminal.cols {
                let ch = terminal.getCharacter(col: col, row: row) ?? " "
                line.append(ch == "\u{0}" ? " " : ch)
            }
            lineTexts.append(line)
        }
        return lineTexts
    }

    /// Returns the last 20 non-blank lines from the given lines, joined by newlines.
    private func relevantText(from lines: [String]) -> String {
        let nonBlankLines = lines.filter { !$0.allSatisfy({ $0 == " " }) }
        return nonBlankLines.suffix(20).joined(separator: "\n")
    }

    /// Returns the last 20 non-blank lines of terminal output above the prompt separator.
    func extractVisibleText() -> String? {
        guard var lineTexts = extractAllLines() else { return nil }

        // Find the last horizontal rule separator (────...) which divides
        // Claude's output from the user's current prompt input area.
        // Only consider text above it so we don't capture the in-progress prompt.
        let separator = "────────"
        if let lastSeparatorIndex = lineTexts.lastIndex(where: { $0.contains(separator) }) {
            lineTexts = Array(lineTexts.prefix(lastSeparatorIndex))
        }

        return relevantText(from: lineTexts)
    }

    /// Returns the last 20 non-blank lines of the full terminal output (including prompt area).
    func extractFullVisibleText() -> String? {
        guard let lineTexts = extractAllLines() else { return nil }
        return relevantText(from: lineTexts)
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)

        guard let id = sessionId else { return }

        // Log raw terminal output for session history
        if !isInitializing {
            if let text = String(bytes: slice, encoding: .utf8), !text.isEmpty {
                SessionHistoryManager.shared.appendText(text, for: id)
            }
        }

        // Reveal terminal after shell init + clear completes
        if isInitializing {
            dataReceivedCount += 1
            if dataReceivedCount >= 4 {
                isInitializing = false
                Task { @MainActor in
                    self.alphaValue = 1
                }
            }
            return
        }

        // Debounce status checks — the buffer can be mid-render when
        // dataReceived fires, causing transient misreads that flicker
        // between .working and .idle.
        statusDebounceTimer?.invalidate()
        statusDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.evaluateStatus(for: id)
        }

        // Trigger autocomplete evaluation
        triggerAutocomplete()
    }

    private static let errorPatterns: [String] = ["error:", "failed", "permission denied"]
    private static let errorSymbols: Set<Character> = ["\u{2717}", "\u{2718}"]
    private static let successSymbols: Set<Character> = ["\u{2713}", "\u{2714}"]

    private func evaluateStatus(for id: UUID) {
        guard let visibleText = extractVisibleText() else { return }
        let fullText = extractFullVisibleText() ?? visibleText

        let newStatus: TerminalStatus

        if Self.hasTokenCounterLine(visibleText) || fullText.contains("esc to interrupt") {
            newStatus = .working
        }
        else if fullText.contains("Esc to cancel") {
            newStatus = .waitingForInput
        } else if visibleText.contains("Interrupted") {
            newStatus = .interrupted
        } else {
            newStatus = .idle
        }

        let summary: String? = (newStatus == .idle) ? Self.extractSummary(from: visibleText) : nil
        let hadError: Bool = (newStatus == .idle) ? Self.detectError(in: visibleText) : false

        Task { @MainActor in
            if let summary {
                SessionStore.shared.paneCompletionInfo[id] = PaneCompletionInfo(summary: summary, hadError: hadError)
            }
            SessionStore.shared.updateTerminalStatus(id, status: newStatus)
        }
    }

    private static func extractSummary(from text: String) -> String? {
        let separator = "\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix(separator) }
        guard let last = lines.last else { return nil }
        return String(last.prefix(100))
    }

    private static func detectError(in text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            for pattern in errorPatterns {
                if lower.contains(pattern) { return true }
            }
            if let first = trimmed.first {
                if errorSymbols.contains(first) { return true }
            }
        }
        return false
    }

    /// Checks whether the text contains a Claude spinner character (visible during working state)
    private static let spinnerCharacters: Set<Character> = ["·", "✢", "✳", "✶", "✻", "✽"]

    /// Checks for a line like "Idle for 30s" — must contain " for " and end with "s",
    /// but must NOT contain parentheses (which indicate thinking duration, not true idle).
    private static func hasIdleForLine(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains(" for ") else { return false }
            guard trimmed.hasSuffix("s") else { return false }
            guard !trimmed.contains("(") && !trimmed.contains(")") else { return false }
            return true
        }
    }

    private static func hasTokenCounterLine(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.contains { line in
            guard let first = line.first, spinnerCharacters.contains(first) else { return false }
            guard line.dropFirst().first == " " else { return false }
            return line.contains("…")
        }
    }

    // MARK: - Autocomplete (Ghost Text)

    func setWorkingDirectory(_ dir: String) {
        currentWorkingDir = dir
        CommandStore.shared.importHistoryIfNeeded(for: dir)
    }

    private func ensureGhostView() {
        guard ghostView == nil else { return }
        let gv = GhostTextView(frame: .zero)
        gv.font = font ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        addSubview(gv)
        ghostView = gv
    }

    private func triggerAutocomplete() {
        autocompleteDebounceTimer?.invalidate()
        autocompleteDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            self?.evaluateAutocomplete()
        }
    }

    private func evaluateAutocomplete() {
        guard let dir = currentWorkingDir else { return }
        guard let input = extractPromptInput() else {
            clearGhostText()
            lastPromptInput = ""
            return
        }

        guard input != lastPromptInput else { return }
        lastPromptInput = input

        guard input.count >= 2 else {
            clearGhostText()
            return
        }

        let suggestions = AutocompleteEngine.shared.suggestions(for: input, in: dir)
        guard let best = suggestions.first else {
            clearGhostText()
            return
        }

        showGhostText(full: best.command, typed: input)
    }

    private func showGhostText(full command: String, typed input: String) {
        ensureGhostView()
        guard let gv = ghostView else { return }

        // Show only the remaining part of the command after what's typed
        let remaining: String
        if command.lowercased().hasPrefix(input.lowercased()) {
            remaining = String(command.dropFirst(input.count))
        } else {
            // Fuzzy match — show full command
            remaining = "  " + command
        }

        guard !remaining.trimmingCharacters(in: .whitespaces).isEmpty else {
            clearGhostText()
            return
        }

        currentGhostSuggestion = command
        gv.font = font ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        gv.ghostText = remaining

        // Position at cursor
        let terminal = getTerminal()
        let cursor = terminal.getCursorLocation()
        guard terminal.cols > 0, terminal.rows > 0 else { return }

        let scrollerWidth = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay)
        let contentWidth = frame.width - scrollerWidth
        let cellWidth = contentWidth / CGFloat(terminal.cols)
        let cellHeight = frame.height / CGFloat(terminal.rows)

        let x = cellWidth * CGFloat(cursor.x)
        // AppKit coordinates: y=0 is bottom, so invert
        let y = frame.height - cellHeight * CGFloat(cursor.y + 1)

        let size = gv.intrinsicContentSize
        gv.frame = NSRect(x: x, y: y, width: size.width, height: cellHeight)
    }

    private func clearGhostText() {
        currentGhostSuggestion = nil
        lastPromptInput = ""
        ghostView?.ghostText = ""
    }

    private func acceptGhostSuggestion() {
        guard let command = currentGhostSuggestion,
              let input = lastPromptInput.nilIfEmpty else {
            clearGhostText()
            return
        }

        clearGhostText()

        // Send only the remaining characters
        if command.lowercased().hasPrefix(input.lowercased()) {
            let remaining = String(command.dropFirst(input.count))
            send(txt: remaining)
        } else {
            // Fuzzy match: delete input first, then type full command
            let backspaces = String(repeating: "\u{7f}", count: input.count)
            send(txt: backspaces + command)
        }

        if let dir = currentWorkingDir {
            CommandStore.shared.recordCommand(command, in: dir)
        }
    }

    /// Extracts the text the user is typing at the current shell prompt.
    /// Returns nil if not at a shell prompt.
    private func extractPromptInput() -> String? {
        let terminal = getTerminal()
        let cursor = terminal.getCursorLocation()

        // Read the cursor row
        var line = ""
        for col in 0..<terminal.cols {
            let ch = terminal.getCharacter(col: col, row: cursor.y) ?? " "
            line.append(ch == "\u{0}" ? " " : ch)
        }
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard !trimmedLine.isEmpty else { return nil }

        // Don't autocomplete inside Claude (look for Claude's prompt character)
        if trimmedLine.contains("❯") { return nil }

        // Find the last prompt character in the line before cursor position
        var promptEnd: Int? = nil
        for i in stride(from: min(cursor.x, terminal.cols - 1), through: 0, by: -1) {
            let ch = terminal.getCharacter(col: i, row: cursor.y) ?? " "
            if Self.promptCharacters.contains(ch) {
                promptEnd = i
                break
            }
        }

        guard let pe = promptEnd else { return nil }

        // Extract text after prompt character + space
        let inputStart = pe + 2 // prompt char + space
        guard inputStart < cursor.x else { return nil }

        var input = ""
        for col in inputStart..<cursor.x {
            let ch = terminal.getCharacter(col: col, row: cursor.y) ?? " "
            input.append(ch == "\u{0}" ? " " : ch)
        }

        let trimmed = input.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func recordCurrentCommand() {
        guard let dir = currentWorkingDir,
              let input = extractPromptInput(),
              input.count >= 2 else { return }
        CommandStore.shared.recordCommand(input, in: dir)
    }

    // MARK: - Command Blocks (Copy Output)

    private struct CommandBlock {
        let promptRow: Int
        let outputStartRow: Int
        let outputEndRow: Int
    }

    private func readBufferLine(absoluteRow: Int) -> String? {
        let terminal = getTerminal()
        guard let bufferLine = terminal.getScrollInvariantLine(row: absoluteRow) else { return nil }
        return bufferLine.translateToString(trimRight: true)
    }

    private static let blockPromptCharacters: Set<Character> = ["$", "%", ">", "\u{276F}"] // includes ❯

    private func isPromptLine(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        for (index, char) in trimmed.enumerated() {
            if index > 60 { break }
            if Self.blockPromptCharacters.contains(char) {
                let nextIdx = trimmed.index(trimmed.startIndex, offsetBy: index + 1, limitedBy: trimmed.endIndex)
                if nextIdx == nil || nextIdx == trimmed.endIndex || trimmed[nextIdx!] == " " {
                    return true
                }
            }
        }
        return false
    }

    private func findCommandBlock(at absoluteRow: Int) -> CommandBlock? {
        // Scan backward to find the prompt line
        var promptRow: Int? = nil
        for row in stride(from: absoluteRow, through: max(0, absoluteRow - 5000), by: -1) {
            guard let line = readBufferLine(absoluteRow: row) else { break }
            if isPromptLine(line) {
                promptRow = row
                break
            }
        }
        guard let promptRow else { return nil }

        // Scan forward to find the next prompt (or end of buffer)
        var endRow = promptRow
        for row in (promptRow + 1)...(absoluteRow + 5000) {
            guard let line = readBufferLine(absoluteRow: row) else {
                endRow = row - 1
                break
            }
            if isPromptLine(line) {
                endRow = row - 1
                break
            }
            endRow = row
        }

        let outputStart = promptRow + 1
        guard outputStart <= endRow else { return nil }
        return CommandBlock(promptRow: promptRow, outputStartRow: outputStart, outputEndRow: endRow)
    }

    private func extractOutputText(from block: CommandBlock) -> String? {
        var lines: [String] = []
        for row in block.outputStartRow...block.outputEndRow {
            if let line = readBufferLine(absoluteRow: row) {
                lines.append(line)
            }
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    private func installMouseUpMonitor() {
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self,
                  let eventWindow = event.window,
                  eventWindow === self.window else { return event }
            let locationInView = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(locationInView) else { return event }

            DispatchQueue.main.async { [weak self] in
                guard let self, let text = self.getSelection(), !text.isEmpty else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            return event
        }
    }

    private func installRightClickMonitor() {
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self,
                  let eventWindow = event.window,
                  eventWindow === self.window else { return event }
            let locationInView = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(locationInView) else { return event }

            self.showContextMenu(with: event)
            return nil // consume the event
        }
    }

    private func showContextMenu(with event: NSEvent) {
        let terminal = getTerminal()
        guard terminal.cols > 0, terminal.rows > 0 else { return }

        let point = convert(event.locationInWindow, from: nil)
        let cellHeight = frame.height / CGFloat(terminal.rows)

        let viewportRow = Int((frame.height - point.y) / cellHeight)
        let absoluteRow = viewportRow + terminal.buffer.yDisp

        let menu = NSMenu()

        if let block = findCommandBlock(at: absoluteRow),
           let outputText = extractOutputText(from: block) {
            let copyOutput = NSMenuItem(title: L10n.shared.copyOutput, action: #selector(copyBlockOutput(_:)), keyEquivalent: "")
            copyOutput.representedObject = outputText
            copyOutput.target = self
            menu.addItem(copyOutput)

            if let cmdLine = readBufferLine(absoluteRow: block.promptRow) {
                let copyCmd = NSMenuItem(title: L10n.shared.copyCommand, action: #selector(copyBlockOutput(_:)), keyEquivalent: "")
                let trimmed = cmdLine.trimmingCharacters(in: .whitespaces)
                var cmdText = trimmed
                for (index, char) in trimmed.enumerated() {
                    if Self.blockPromptCharacters.contains(char) {
                        let afterPrompt = trimmed.index(trimmed.startIndex, offsetBy: index + 1, limitedBy: trimmed.endIndex)
                        if let afterPrompt, afterPrompt < trimmed.endIndex {
                            cmdText = String(trimmed[afterPrompt...]).trimmingCharacters(in: .whitespaces)
                        }
                        break
                    }
                }
                copyCmd.representedObject = cmdText
                copyCmd.target = self
                menu.addItem(copyCmd)
            }

            menu.addItem(.separator())
        }

        let paste = NSMenuItem(title: L10n.shared.paste, action: #selector(pasteFromClipboard), keyEquivalent: "")
        paste.target = self
        menu.addItem(paste)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func copyBlockOutput(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        send(txt: text)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

class TerminalManager: NSObject, LocalProcessTerminalViewDelegate {
    static let shared = TerminalManager()

    private static let fontSizeKey = "terminalFontSize"
    private static let themeKey = "terminalTheme"
    private static let defaultFontSize: CGFloat = 11
    private static let minFontSize: CGFloat = 9
    private static let maxFontSize: CGFloat = 24

    var fontSize: CGFloat {
        let saved = CGFloat(UserDefaults.standard.double(forKey: Self.fontSizeKey))
        return saved > 0 ? saved : Self.defaultFontSize
    }

    private(set) var terminals: [UUID: LocalProcessTerminalView] = [:]

    func terminal(for sessionId: UUID, workingDirectory: String, launchClaude: Bool = true, customCommand: String? = nil) -> LocalProcessTerminalView {
        if let existing = terminals[sessionId] {
            return existing
        }

        let terminal = ClickThroughTerminalView(frame: NSRect(x: 0, y: 0, width: 720, height: 460))
        terminal.sessionId = sessionId
        terminal.processDelegate = self
        terminal.setWorkingDirectory(workingDirectory)

        terminal.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        applyTheme(to: terminal)

        let config = ProjectConfig.load(from: workingDirectory)
        let shell = config?.shell ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let environment = buildEnvironment(extra: config?.env)

        terminal.startProcess(
            executable: shell,
            args: ["--login"],
            environment: environment,
            execName: "-" + (shell as NSString).lastPathComponent
        )

        // Hide terminal until cd && clear finishes (revealed in dataReceived)
        terminal.alphaValue = 0
        terminal.isInitializing = true

        let escapedDir = shellEscape(workingDirectory)
        if let cmd = customCommand {
            terminal.send(txt: "cd \(escapedDir) && clear && \(cmd)\r")
        } else if let cmd = config?.command {
            terminal.send(txt: "cd \(escapedDir) && clear && \(cmd)\r")
        } else {
            let hasClaude = launchClaude && FileManager.default.fileExists(atPath: (workingDirectory as NSString).appendingPathComponent("CLAUDE.md"))
            if hasClaude {
                terminal.send(txt: "cd \(escapedDir) && clear && claude\r")
            } else {
                terminal.send(txt: "cd \(escapedDir) && clear\r")
            }
        }

        terminals[sessionId] = terminal
        return terminal
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let dir = directory,
              let terminal = source as? ClickThroughTerminalView,
              let sessionId = terminal.sessionId else { return }
        // OSC 7 sends directory as file://hostname/path — extract just the path
        let path: String
        if let url = URL(string: dir), url.scheme == "file" {
            path = url.path
        } else {
            path = dir
        }
        terminal.setWorkingDirectory(path)
        Task { @MainActor in
            SessionStore.shared.updateWorkingDirectory(sessionId, directory: path)
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {}

    /// Returns the visible text from a terminal's buffer
    func visibleText(for sessionId: UUID) -> String? {
        guard let terminal = terminals[sessionId] as? ClickThroughTerminalView else { return nil }
        return terminal.extractVisibleText()
    }

    func increaseFontSize() { changeFontSize(by: 1) }
    func decreaseFontSize() { changeFontSize(by: -1) }
    func resetFontSize() { setFontSize(Self.defaultFontSize) }

    private func changeFontSize(by delta: CGFloat) {
        setFontSize(fontSize + delta)
    }

    private func setFontSize(_ size: CGFloat) {
        let clamped = max(Self.minFontSize, min(Self.maxFontSize, size))
        UserDefaults.standard.set(Double(clamped), forKey: Self.fontSizeKey)
        let font = NSFont.monospacedSystemFont(ofSize: clamped, weight: .regular)
        for terminal in terminals.values {
            terminal.font = font
        }
    }

    func sendCommand(to paneId: UUID, command: String) {
        guard let terminal = terminals[paneId] else { return }
        terminal.send(txt: "\(command)\r")
    }

    func focusTerminal(for paneId: UUID) {
        guard let terminal = terminals[paneId] else { return }
        terminal.window?.makeFirstResponder(terminal)
    }

    func destroyTerminal(for sessionId: UUID) {
        terminals.removeValue(forKey: sessionId)
    }

    private func buildEnvironment(extra: [String: String]? = nil) -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["TERM_PROGRAM"] = "Apple_Terminal"
        if let extra {
            for (key, value) in extra {
                env[key] = value
            }
        }
        return env.map { "\($0.key)=\($0.value)" }
    }

    private func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Theme

    var currentThemeId: String {
        UserDefaults.standard.string(forKey: Self.themeKey) ?? "default"
    }

    var currentTheme: TerminalTheme {
        TerminalTheme.theme(forId: currentThemeId)
    }

    private func applyTheme(to terminal: LocalProcessTerminalView) {
        let theme = currentTheme
        terminal.nativeBackgroundColor = theme.background
        terminal.nativeForegroundColor = theme.foreground
        terminal.caretColor = theme.cursor
        terminal.selectedTextBackgroundColor = theme.selection
        terminal.installColors(theme.swiftTermColors())
    }

    func setTheme(_ themeId: String) {
        UserDefaults.standard.set(themeId, forKey: Self.themeKey)
        let theme = TerminalTheme.theme(forId: themeId)
        for terminal in terminals.values {
            terminal.nativeBackgroundColor = theme.background
            terminal.nativeForegroundColor = theme.foreground
            terminal.caretColor = theme.cursor
            terminal.selectedTextBackgroundColor = theme.selection
            terminal.installColors(theme.swiftTermColors())
            terminal.setNeedsDisplay(terminal.bounds)
        }
        SessionStore.shared.currentTheme = theme
    }
}
