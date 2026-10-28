// hostblock-menubar - macOS menu bar front end for hostblockd.
//
// A plain shield in the menu bar. Click it, type a site, confirm, and the
// site is routed to 127.0.0.1 permanently. Deliberately:
//   - no badge, no count, a tooltip that never names a site
//   - no list, no remove button, and the blocklist is never requested
//   - a confirm step that shows the exact /etc/hosts lines before writing
// All privileged work happens in the daemon; this app only shells out to the
// unprivileged CLI (`hostblock status --json` and `hostblock add`).

import Cocoa

let cliPath = ProcessInfo.processInfo.environment["HOSTBLOCK_CLI"] ?? "/usr/local/bin/hostblock"
let launchdLabel = "io.github.esoteric-frog.hostblockd"

// MARK: - Model (mirror of the daemon's normalize/expand, preview only)

enum Model {
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        s = s.components(separatedBy: "/")[0]
        s = s.components(separatedBy: "?")[0]
        s = s.components(separatedBy: "#")[0]
        if let at = s.lastIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        if s.hasPrefix("[") { return "" }
        if s.components(separatedBy: ":").count > 2 { return "" }
        if s.contains(":") { s = s.components(separatedBy: ":")[0] }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return s.lowercased()
    }

    static func expand(_ domain: String) -> [String] {
        if domain.isEmpty { return [] }
        if domain.hasPrefix("www.") {
            let apex = String(domain.dropFirst(4))
            return apex.contains(".") ? [domain, apex] : [domain]
        }
        return [domain, "www." + domain]
    }

    static func localReason(_ domain: String) -> String {
        if domain.isEmpty { return "Enter a website address." }
        if domain.range(of: "^[0-9.]+$", options: .regularExpression) != nil {
            return "That is an IP address, not a hostname."
        }
        if !domain.contains(".") { return "Needs at least two parts, e.g. example.com" }
        if domain.hasSuffix(".local") { return ".local names are Bonjour names and cannot be blocked via /etc/hosts." }
        if domain.hasSuffix(".arpa") { return "Reverse-DNS names cannot be blocked this way." }
        if domain == "localhost" { return "Refusing to block this machine's own name." }
        if domain.range(of: "[^a-z0-9.-]", options: .regularExpression) != nil {
            return "Contains characters that are not valid in a hostname."
        }
        return ""
    }

    static func previewLines(_ domain: String, _ addresses: [String]) -> [String] {
        let names = expand(domain)
        let addrs = addresses.isEmpty ? ["127.0.0.1", "::1"] : addresses
        var out: [String] = []
        for a in addrs { for n in names { out.append("\(a)  \(n)") } }
        return out
    }

    static func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateFormat = "d MMM yyyy"
        return out.string(from: d)
    }
}

// MARK: - CLI plumbing

func runCLI(_ args: [String], _ completion: @escaping (Int32, String, String) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cliPath)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
        } catch {
            DispatchQueue.main.async { completion(-1, "", "Could not run \(cliPath)") }
            return
        }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let so = String(data: o, encoding: .utf8) ?? ""
        let se = String(data: e, encoding: .utf8) ?? ""
        DispatchQueue.main.async { completion(p.terminationStatus, so, se) }
    }
}

// MARK: - Panel

final class PanelViewController: NSViewController, NSTextFieldDelegate {
    var onStateChange: ((Bool) -> Void)?

    private(set) var daemonUp = false { didSet { onStateChange?(daemonUp) } }
    private var blockAddresses = ["127.0.0.1", "::1"]
    private var lastRevert = ""
    private var pendingDomain = ""
    private var busy = false
    private var statusRunning = false

    private let heroIcon = NSImageView()
    private let heroTitle = NSTextField(labelWithString: "Host Block")
    private let subtitle = NSTextField(labelWithString: "Blocks are permanent")

    private let downStack = NSStackView()
    private let downTitle = NSTextField(labelWithString: "hostblockd is not running")
    private let downHint = NSTextField(wrappingLabelWithString: "sudo launchctl kickstart -k system/\(launchdLabel)")

    private let inputRow = NSStackView()
    private let inputField = NSTextField()
    private let blockButton = NSButton(title: "Block", target: nil, action: nil)

    private let confirmStack = NSStackView()
    private let confirmQuestion = NSTextField(wrappingLabelWithString: "")
    private let previewBox = NSTextField(wrappingLabelWithString: "")
    private let confirmWarning = NSTextField(wrappingLabelWithString: "This cannot be undone from here.")
    private let confirmButton = NSButton(title: "Block permanently", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)

    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let noticeLabel = NSTextField(wrappingLabelWithString: "")
    private let footer = NSTextField(labelWithString: "Watching /etc/hosts")

    override func loadView() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 9
        root.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        root.translatesAutoresizingMaskIntoConstraints = false

        // hero
        heroIcon.image = NSImage(systemSymbolName: "shield.fill", accessibilityDescription: "Host Block")
        heroIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        heroIcon.contentTintColor = .labelColor
        heroTitle.font = NSFont.boldSystemFont(ofSize: 15)
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        let heroText = NSStackView(views: [heroTitle, subtitle])
        heroText.orientation = .vertical
        heroText.alignment = .leading
        heroText.spacing = 1
        let hero = NSStackView(views: [heroIcon, heroText])
        hero.orientation = .horizontal
        hero.spacing = 12
        root.addArrangedSubview(hero)

        // daemon down
        downTitle.font = NSFont.boldSystemFont(ofSize: 12)
        downTitle.textColor = .systemRed
        downHint.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        downHint.textColor = .secondaryLabelColor
        downHint.isSelectable = true
        downStack.orientation = .vertical
        downStack.alignment = .leading
        downStack.spacing = 3
        downStack.addArrangedSubview(downTitle)
        downStack.addArrangedSubview(downHint)
        root.addArrangedSubview(downStack)

        // input
        inputField.placeholderString = ""
        inputField.delegate = self
        inputField.target = self
        inputField.action = #selector(submit)
        inputField.font = NSFont.systemFont(ofSize: 13)
        blockButton.target = self
        blockButton.action = #selector(submit)
        blockButton.bezelStyle = .rounded
        inputRow.orientation = .horizontal
        inputRow.spacing = 6
        inputRow.addArrangedSubview(inputField)
        inputRow.addArrangedSubview(blockButton)
        root.addArrangedSubview(inputRow)

        // confirm
        confirmQuestion.font = NSFont.boldSystemFont(ofSize: 12)
        previewBox.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        previewBox.textColor = .secondaryLabelColor
        previewBox.wantsLayer = true
        previewBox.layer?.borderWidth = 1
        previewBox.layer?.borderColor = NSColor.separatorColor.cgColor
        previewBox.layer?.cornerRadius = 6
        previewBox.isBordered = false
        previewBox.drawsBackground = false
        confirmWarning.font = NSFont.systemFont(ofSize: 11)
        confirmWarning.textColor = .secondaryLabelColor
        confirmButton.target = self
        confirmButton.action = #selector(confirmPending)
        confirmButton.bezelStyle = .rounded
        confirmButton.keyEquivalent = "\r"
        cancelButton.target = self
        cancelButton.action = #selector(cancelPending)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [confirmButton, cancelButton])
        buttons.orientation = .horizontal
        buttons.spacing = 6
        confirmStack.orientation = .vertical
        confirmStack.alignment = .leading
        confirmStack.spacing = 6
        confirmStack.addArrangedSubview(confirmQuestion)
        confirmStack.addArrangedSubview(previewBox)
        confirmStack.addArrangedSubview(confirmWarning)
        confirmStack.addArrangedSubview(buttons)
        root.addArrangedSubview(confirmStack)

        // messages
        errorLabel.font = NSFont.systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        noticeLabel.font = NSFont.systemFont(ofSize: 11)
        noticeLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(errorLabel)
        root.addArrangedSubview(noticeLabel)

        // footer
        footer.font = NSFont.systemFont(ofSize: 10)
        footer.textColor = .tertiaryLabelColor
        root.addArrangedSubview(footer)

        let container = NSView()
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: 360),
        ])
        for v in [hero, downStack, inputRow, confirmStack, errorLabel, noticeLabel, footer] as [NSView] {
            v.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -28).isActive = true
        }
        previewBox.widthAnchor.constraint(equalTo: confirmStack.widthAnchor).isActive = true
        view = container
        render()
    }

    // MARK: state

    func opened() {
        errorLabel.stringValue = ""
        noticeLabel.stringValue = ""
        pendingDomain = ""
        inputField.stringValue = ""
        render()
        refresh()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.view.window?.makeFirstResponder(self.inputField)
        }
    }

    // Only `status` is ever requested. The panel never asks for the blocklist,
    // so nothing in this process could render a site name.
    func refresh() {
        if statusRunning { return }
        statusRunning = true
        runCLI(["status", "--json"]) { [weak self] code, out, _ in
            guard let self = self else { return }
            self.statusRunning = false
            if code == 0,
               let data = out.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.daemonUp = (obj["ok"] as? Bool) ?? true
                if let a = obj["blockAddresses"] as? [String], !a.isEmpty { self.blockAddresses = a }
                self.lastRevert = (obj["lastRevert"] as? String) ?? ""
            } else {
                self.daemonUp = false
            }
            self.render()
        }
    }

    @objc func submit() {
        errorLabel.stringValue = ""
        noticeLabel.stringValue = ""
        let domain = Model.normalize(inputField.stringValue)
        let reason = Model.localReason(domain)
        if !reason.isEmpty {
            errorLabel.stringValue = reason
            render()
            return
        }
        pendingDomain = domain
        render()
        view.window?.makeFirstResponder(confirmButton)
    }

    @objc func cancelPending() {
        pendingDomain = ""
        render()
        view.window?.makeFirstResponder(inputField)
    }

    @objc func confirmPending() {
        if pendingDomain.isEmpty || busy { return }
        busy = true
        errorLabel.stringValue = ""
        render()
        runCLI(["add", pendingDomain]) { [weak self] code, _, err in
            guard let self = self else { return }
            self.busy = false
            if code == 0 {
                self.pendingDomain = ""
                self.inputField.stringValue = ""
                self.noticeLabel.stringValue = "Blocked. Quit and reopen your browser - Chrome, Brave and Safari cache DNS internally and may ignore /etc/hosts until restarted."
                self.refresh()
            } else {
                let msg = err.trimmingCharacters(in: .whitespacesAndNewlines)
                self.errorLabel.stringValue = msg.isEmpty ? "hostblock refused that address." : msg
            }
            self.render()
            self.view.window?.makeFirstResponder(self.inputField)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        errorLabel.stringValue = ""
        noticeLabel.stringValue = ""
        render()
    }

    private func render() {
        heroIcon.alphaValue = daemonUp ? 1.0 : 0.42
        downStack.isHidden = daemonUp
        inputRow.isHidden = !(daemonUp && pendingDomain.isEmpty)
        confirmStack.isHidden = pendingDomain.isEmpty
        inputField.isEnabled = !busy
        blockButton.isEnabled = !busy
        confirmButton.isEnabled = !busy
        cancelButton.isEnabled = !busy
        confirmButton.title = busy ? "Blocking…" : "Block permanently"
        confirmQuestion.stringValue = "Block \(pendingDomain) permanently?"
        previewBox.stringValue = "  " + Model.previewLines(pendingDomain, blockAddresses).joined(separator: "\n  ")
        errorLabel.isHidden = errorLabel.stringValue.isEmpty
        noticeLabel.isHidden = noticeLabel.stringValue.isEmpty
        footer.isHidden = true
        view.layoutSubtreeIfNeeded()
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let panel = PanelViewController()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "shield.fill", accessibilityDescription: "Block a website")
            img?.isTemplate = true
            button.image = img
            button.target = self
            button.action = #selector(toggle(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        // Tooltip never names a site or a count: the bar is visible to anyone
        // glancing at the screen.
        panel.onStateChange = { [weak self] up in
            guard let b = self?.statusItem.button else { return }
            b.toolTip = up ? "Block a website" : "hostblockd is not running"
            b.appearsDisabled = !up
        }
        popover.contentViewController = panel
        popover.behavior = .transient
        popover.delegate = self
        panel.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.panel.refresh()
        }
    }

    @objc func toggle(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            panel.opened()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
