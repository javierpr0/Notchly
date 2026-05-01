import SwiftUI

struct CommandPaletteView: View {
    let currentDirectory: String
    let onExecute: (String) -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var commands: [StoredCommand] = []
    @State private var filtered: [StoredCommand] = []

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
                .background(Color.white.opacity(0.1))
            commandList
        }
        .frame(width: 500)
        .background(Color(nsColor: NSColor(white: 0.15, alpha: 0.95)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 20)
        .onAppear {
            commands = CommandStore.shared.commands(for: currentDirectory)
                .sorted { $0.count > $1.count }
            applyFilter()
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        PaletteSearchField(
            text: $searchText,
            selectedIndex: $selectedIndex,
            itemCount: max(filtered.count, 1),
            onSubmit: executeSelected,
            onEscape: onDismiss
        )
        .onChange(of: searchText) { _, _ in
            applyFilter()
            selectedIndex = 0
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Command List

    private var commandList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.offset) { index, cmd in
                        commandRow(cmd, index: index)
                            .id(index)
                    }
                }
            }
            .frame(maxHeight: 300)
            .onChange(of: selectedIndex) { _, newValue in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func commandRow(_ cmd: StoredCommand, index: Int) -> some View {
        HStack(spacing: 8) {
            highlightedText(cmd.text, query: searchText)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)

            Spacer()

            if cmd.count > 1 {
                Text("\(cmd.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(index == selectedIndex ? Color(hex: 0x0066FF, alpha: 0.19) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedIndex = index
            executeSelected()
        }
        .contextMenu {
            Button(L10n.shared.deleteCommand) {
                CommandStore.shared.deleteCommand(cmd.text, in: currentDirectory)
                commands.removeAll { $0.text == cmd.text }
                applyFilter()
            }
        }
    }

    // MARK: - Highlighting

    private func highlightedText(_ text: String, query: String) -> some View {
        let matchIndices = fuzzyMatchIndices(text: text, query: query)
        var result = Text("")
        for (i, char) in text.enumerated() {
            let segment = Text(String(char))
            if matchIndices.contains(i) {
                result = result + segment.foregroundStyle(Color(hex: 0x4DA3FF))
            } else {
                result = result + segment.foregroundStyle(.white)
            }
        }
        return result
    }

    // MARK: - Filtering

    private func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else {
            filtered = commands
            return
        }

        var prefixMatches: [(StoredCommand, Int)] = []
        var fuzzyMatches: [(StoredCommand, Int)] = []

        for cmd in commands {
            let lower = cmd.text.lowercased()
            if lower.hasPrefix(query) {
                prefixMatches.append((cmd, 0))
            } else if let score = fuzzyScore(text: lower, query: query) {
                fuzzyMatches.append((cmd, score))
            }
        }

        prefixMatches.sort { $0.0.count > $1.0.count }
        fuzzyMatches.sort { $0.1 == $1.1 ? $0.0.count > $1.0.count : $0.1 < $1.1 }

        filtered = prefixMatches.map(\.0) + fuzzyMatches.map(\.0)
    }

    private func fuzzyScore(text: String, query: String) -> Int? {
        var score = 0
        var textIndex = text.startIndex
        for qChar in query {
            guard let found = text[textIndex...].firstIndex(of: qChar) else { return nil }
            let gap = text.distance(from: textIndex, to: found)
            score += gap
            textIndex = text.index(after: found)
        }
        return score
    }

    private func fuzzyMatchIndices(text: String, query: String) -> Set<Int> {
        let lower = text.lowercased()
        let queryLower = query.lowercased()
        var indices = Set<Int>()
        var searchStart = lower.startIndex
        for qChar in queryLower {
            guard let found = lower[searchStart...].firstIndex(of: qChar) else { break }
            indices.insert(lower.distance(from: lower.startIndex, to: found))
            searchStart = lower.index(after: found)
        }
        return indices
    }

    // MARK: - Execution

    private func executeSelected() {
        let command: String
        if filtered.indices.contains(selectedIndex) {
            command = filtered[selectedIndex].text
        } else if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            command = searchText.trimmingCharacters(in: .whitespaces)
        } else {
            return
        }
        CommandStore.shared.recordCommand(command, in: currentDirectory)
        onExecute(command)
        onDismiss()
    }
}

// MARK: - NSViewRepresentable Search Field

/// AppKit text field that stays first responder and forwards arrow keys / enter / escape to SwiftUI state.
struct PaletteSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedIndex: Int
    let itemCount: Int
    let onSubmit: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.placeholderString = L10n.shared.runCommand
        field.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        field.isBordered = false
        field.drawsBackground = false
        field.textColor = .white
        field.focusRingType = .none
        field.cell?.sendsActionOnEndEditing = false

        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }

        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        context.coordinator.itemCount = itemCount
        context.coordinator.selectedIndex = $selectedIndex
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onEscape = onEscape
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedIndex: $selectedIndex, itemCount: itemCount, onSubmit: onSubmit, onEscape: onEscape)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var selectedIndex: Binding<Int>
        var itemCount: Int
        var onSubmit: () -> Void
        var onEscape: () -> Void

        init(text: Binding<String>, selectedIndex: Binding<Int>, itemCount: Int, onSubmit: @escaping () -> Void, onEscape: @escaping () -> Void) {
            self.text = text
            self.selectedIndex = selectedIndex
            self.itemCount = itemCount
            self.onSubmit = onSubmit
            self.onEscape = onEscape
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                if selectedIndex.wrappedValue > 0 {
                    selectedIndex.wrappedValue -= 1
                }
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                if selectedIndex.wrappedValue < itemCount - 1 {
                    selectedIndex.wrappedValue += 1
                }
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onEscape()
                return true
            }
            return false
        }
    }
}

// MARK: - Color Hex Helper

// Color(hex:alpha:) initializer is now defined in DesignSystem.swift

