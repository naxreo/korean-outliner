//
//  MenuBarController.swift
//  macos-korean-outliner — MenuBarPresenting 구현체
//
//  NSStatusItem을 강한 참조로 보유한다. 약한 참조 시 즉시 메뉴바에서 사라진다.
//

import AppKit

public final class MenuBarController: NSObject, MenuBarPresenting {

    private var statusItem: NSStatusItem?
    private let onShowPreferences: () -> Void
    private let onQuit: () -> Void

    private var lastLanguage: InputLanguage = .english
    private var enabled: Bool = true

    public init(
        onShowPreferences: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onShowPreferences = onShowPreferences
        self.onQuit = onQuit
        super.init()
        install()
    }

    public func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton(item.button)
        item.menu = makeMenu()
        self.statusItem = item
    }

    public func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        applyAppearance()
    }

    public func setLanguage(_ language: InputLanguage) {
        self.lastLanguage = language
        applyAppearance()
    }

    // MARK: - Private

    private func configureButton(_ button: NSStatusBarButton?) {
        guard let button else { return }
        button.image = NSImage(
            systemSymbolName: "rectangle.dashed",
            accessibilityDescription: "Korean Outliner"
        )
        button.image?.isTemplate = true
        button.toolTip = "Korean Outliner"
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let prefs = NSMenuItem(
            title: "Preferences…",
            action: #selector(prefsAction),
            keyEquivalent: ","
        )
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func applyAppearance() {
        guard let button = statusItem?.button else { return }
        button.appearsDisabled = !enabled
        switch lastLanguage {
        case .korean:
            button.toolTip = enabled ? "Korean Outliner — 한글" : "Korean Outliner (off)"
        case .english:
            button.toolTip = enabled ? "Korean Outliner — English" : "Korean Outliner (off)"
        case .other(let id):
            button.toolTip = enabled ? "Korean Outliner — \(id)" : "Korean Outliner (off)"
        }
    }

    @objc private func prefsAction() { onShowPreferences() }
    @objc private func quitAction() { onQuit() }
}
