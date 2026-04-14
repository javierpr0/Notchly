import AppKit
import SwiftTerm

// MARK: - Search Bar

class TerminalSearchBar: NSView {
    var onSearch: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?

    private let backgroundEffect: NSVisualEffectView = {
        let v = NSVisualEffectView()
        v.material = .dark
        v.blendingMode = .withinWindow
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = 8
        v.layer?.masksToBounds = true
        return v
    }()

    private let searchField: NSTextField = {
        let f = NSTextField()
        f.placeholderString = L10n.shared.search
        f.font = .systemFont(ofSize: 12)
        f.isBordered = false
        f.focusRingType = .none
        f.drawsBackground = true
        f.backgroundColor = NSColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1)
        f.textColor = .white
        f.wantsLayer = true
        f.layer?.cornerRadius = 4
        f.cell?.sendsActionOnEndEditing = false
        return f
    }()

    private let matchLabel: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        l.alignment = .center
        return l
    }()

    private let upButton: NSButton = {
        let b = NSButton()
        b.bezelStyle = .accessoryBarAction
        b.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous")
        b.imagePosition = .imageOnly
        b.isBordered = false
        b.contentTintColor = .white
        return b
    }()

    private let downButton: NSButton = {
        let b = NSButton()
        b.bezelStyle = .accessoryBarAction
        b.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next")
        b.imagePosition = .imageOnly
        b.isBordered = false
        b.contentTintColor = .white
        return b
    }()

    private let closeButton: NSButton = {
        let b = NSButton()
        b.bezelStyle = .accessoryBarAction
        b.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        b.imagePosition = .imageOnly
        b.isBordered = false
        b.contentTintColor = .secondaryLabelColor
        return b
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setup() {
        wantsLayer = true

        let stack = NSStackView(views: [searchField, matchLabel, upButton, downButton, closeButton])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 4)

        backgroundEffect.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(backgroundEffect)
        addSubview(stack)

        NSLayoutConstraint.activate([
            backgroundEffect.topAnchor.constraint(equalTo: topAnchor),
            backgroundEffect.bottomAnchor.constraint(equalTo: bottomAnchor),
            backgroundEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundEffect.trailingAnchor.constraint(equalTo: trailingAnchor),

            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),

            searchField.widthAnchor.constraint(equalToConstant: 200),
            upButton.widthAnchor.constraint(equalToConstant: 24),
            downButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            matchLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])

        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldAction)

        upButton.target = self
        upButton.action = #selector(upTapped)
        downButton.target = self
        downButton.action = #selector(downTapped)
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
    }

    func updateStatus(found: Bool, query: String) {
        if query.isEmpty {
            matchLabel.stringValue = ""
        } else {
            matchLabel.stringValue = found ? L10n.shared.found : L10n.shared.noResults
            matchLabel.textColor = found ? .secondaryLabelColor : .systemRed
        }
    }

    func focus() {
        window?.makeFirstResponder(searchField)
    }

    func clear() {
        searchField.stringValue = ""
        matchLabel.stringValue = ""
    }

    var searchText: String {
        searchField.stringValue
    }

    @objc private func searchFieldAction() {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.shift) {
            onPrevious?()
        } else {
            onNext?()
        }
    }

    @objc private func upTapped() { onPrevious?() }
    @objc private func downTapped() { onNext?() }
    @objc private func closeTapped() { onClose?() }
}

extension TerminalSearchBar: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        onSearch?(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onClose?()
            return true
        }
        return false
    }
}

// MARK: - Search Controller (uses SwiftTerm's built-in search)

class TerminalSearchController {
    private let searchBar = TerminalSearchBar()
    private weak var terminalView: TerminalView?
    private(set) var isVisible = false
    private var lastQuery = ""

    init() {
        searchBar.onSearch = { [weak self] query in self?.search(query) }
        searchBar.onNext = { [weak self] in self?.nextMatch() }
        searchBar.onPrevious = { [weak self] in self?.previousMatch() }
        searchBar.onClose = { [weak self] in self?.hide() }
    }

    func show(in view: NSView) {
        guard let tv = view as? TerminalView else { return }
        guard !isVisible else {
            searchBar.focus()
            return
        }
        isVisible = true
        terminalView = tv

        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            searchBar.heightAnchor.constraint(equalToConstant: 32),
        ])

        searchBar.focus()
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        terminalView?.clearSearch()
        searchBar.clear()
        searchBar.removeFromSuperview()
        lastQuery = ""
    }

    func search(_ query: String) {
        lastQuery = query
        guard !query.isEmpty else {
            terminalView?.clearSearch()
            searchBar.updateStatus(found: true, query: "")
            return
        }
        let found = terminalView?.findNext(query) ?? false
        searchBar.updateStatus(found: found, query: query)
    }

    func nextMatch() {
        guard !lastQuery.isEmpty else { return }
        let found = terminalView?.findNext(lastQuery) ?? false
        searchBar.updateStatus(found: found, query: lastQuery)
    }

    func previousMatch() {
        guard !lastQuery.isEmpty else { return }
        let found = terminalView?.findPrevious(lastQuery) ?? false
        searchBar.updateStatus(found: found, query: lastQuery)
    }
}
