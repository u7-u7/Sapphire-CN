//
//  UserWindowSupport.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import AppKit
import SwiftUI
import ServiceManagement

extension Notification.Name {
    static let sapphireHelperConnectionLost = Notification.Name("sapphireHelperConnectionLost")
    static let sapphireHelperConnectionRestored = Notification.Name("sapphireHelperConnectionRestored")
    static let sapphireSettingsWillClose = Notification.Name("sapphireSettingsWillClose")
    static let sapphireUpdateAvailable = Notification.Name("sapphireUpdateAvailable")
}

enum SapphireStandardMenu {
    static func installIfNeeded() {
        guard NSApp.mainMenu == nil || !hasEditMenu else { return }

        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            withTitle: NSLocalizedString("Quit Sapphire", comment: "Application menu action"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let editTitle = NSLocalizedString("Edit", comment: "Edit menu title")
        let editMenuItem = NSMenuItem(title: editTitle, action: nil, keyEquivalent: "")
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: editTitle)
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: NSLocalizedString("Undo", comment: "Edit menu action"), action: Selector("undo:"), keyEquivalent: "z")
        editMenu.addItem(withTitle: NSLocalizedString("Redo", comment: "Edit menu action"), action: Selector("redo:"), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: NSLocalizedString("Cut", comment: "Edit menu action"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: NSLocalizedString("Copy", comment: "Edit menu action"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: NSLocalizedString("Paste", comment: "Edit menu action"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: NSLocalizedString("Select All", comment: "Edit menu action"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    private static var hasEditMenu: Bool {
        NSApp.mainMenu?.items.contains {
            $0.title == "Edit" || $0.title == NSLocalizedString("Edit", comment: "Edit menu title")
        } == true
    }
}

enum UtilityWindowMetrics {
    static func visibleFrame(for screen: NSScreen? = NSScreen.main) -> NSRect {
        screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 950, height: 650)
    }

    static func maxUserWindowHeight(screen: NSScreen? = NSScreen.main) -> CGFloat {
        visibleFrame(for: screen).height
    }

    static func settingsDefaultSize(screen: NSScreen? = NSScreen.main) -> NSSize {
        let visible = visibleFrame(for: screen)
        let width = min(
            NotchConfiguration.settingsWindowWidth,
            floor(visible.width * 0.92)
        )
        let height = floor(visible.height)
        return NSSize(
            width: max(NotchConfiguration.settingsWindowMinWidth, width),
            height: max(NotchConfiguration.settingsWindowMinHeight, height)
        )
    }

    static func onboardingWindowSize(screen: NSScreen? = NSScreen.main) -> NSSize {
        let visible = visibleFrame(for: screen)
        let width = min(
            NotchConfiguration.onboardingWindowWidth,
            floor(visible.width * 0.92)
        )
        let height = floor(visible.height)
        return NSSize(
            width: max(NotchConfiguration.settingsWindowMinWidth, width),
            height: max(NotchConfiguration.settingsWindowMinHeight, height)
        )
    }

    static func fittedSize(
        preferredWidth: CGFloat,
        preferredHeight: CGFloat,
        screen: NSScreen? = NSScreen.main,
        maxWidthFraction: CGFloat = 0.90,
        maxHeightFraction: CGFloat = 0.82
    ) -> NSSize {
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let maxWidth = floor(visible.width * maxWidthFraction)
        let maxHeight = floor(visible.height * maxHeightFraction)
        return NSSize(
            width: min(preferredWidth, max(1, maxWidth)),
            height: min(preferredHeight, max(1, maxHeight))
        )
    }

    static func centeredFrame(size: NSSize, screen: NSScreen? = NSScreen.main) -> NSRect {
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        return NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

enum UtilityWindowPresenter {
    private static let elevatedWindowLevel = NSWindow.Level.normal

    static func presentSettingsWindow(_ window: NSWindow) {
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }

            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
            if NSApp.isHidden {
                NSApp.unhide(nil)
            }

            window.collectionBehavior = .fullScreenAuxiliary
            window.level = .normal
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }

            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    static func present(_ window: NSWindow) {
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }

            activateAsRegularApp()
            window.collectionBehavior.insert(.canJoinAllSpaces)
            window.level = elevatedWindowLevel
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.center()

            window.makeKeyAndOrderFront(nil)
        }
    }

    static func activateAsRegularApp() {
        if NSApp.isHidden {
            NSApp.unhide(nil)
        }
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
enum HelperAlertPresenter {
    private static var hostWindow: KeyableWindow?
    private static var activeModalCount = 0

    static func showHelperConnectionLost(onDismiss: (() -> Void)? = nil) {
        presentModal(
            messageText: "Sapphire Helper Needs Attention",
            informativeText: """
            Sapphire lost connection to its system helper.

            Click “Reset Helper” to unregister Sapphire’s own background items, reinstall the helper, and relaunch. Other apps are not affected.
            """,
            alertStyle: .warning,
            buttonTitles: ["Reset Helper", "OK"]
        ) { index in
            if index == 0 {
                HelperManager.shared.resetOwnBackgroundActivity()
            }
            onDismiss?()
        }
    }

    static func present(_ issue: HelperIssue) {
        let buttons: [String]
        switch issue {
        case .notFound:
            buttons = ["Reset Helper", "Relaunch Sapphire", "OK"]
        case .needsApproval:
            buttons = ["Open Login Items", "OK"]
        case .spawnFailed:
            buttons = ["Reset Helper", "Open Login Items", "OK"]
        }

        presentModal(
            messageText: "Sapphire Helper  ·  \(issue.code)",
            informativeText: issue.instructions,
            alertStyle: issue == .spawnFailed ? .critical : .warning,
            buttonTitles: buttons
        ) { index in
            switch issue {
            case .notFound:
                if index == 0 {
                    HelperManager.shared.resetOwnBackgroundActivity()
                } else if index == 1 {
                    HelperManager.relaunchApp()
                }
            case .needsApproval:
                if index == 0 {
                    SMAppService.openSystemSettingsLoginItems()
                }
            case .spawnFailed:
                if index == 0 {
                    HelperManager.shared.resetOwnBackgroundActivity()
                } else if index == 1 {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        }
    }

    static func presentModal(
        messageText: String,
        informativeText: String,
        alertStyle: NSAlert.Style = .warning,
        buttonTitles: [String],
        completion: @escaping (Int) -> Void
    ) {
        UtilityWindowPresenter.activateAsRegularApp()

        let host = acquireHostWindow()
        host.orderFrontRegardless()
        host.makeKeyAndOrderFront(nil)

        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.alertStyle = alertStyle
        for title in buttonTitles {
            alert.addButton(withTitle: title)
        }

        activeModalCount += 1

        DispatchQueue.main.async {
            alert.beginSheetModal(for: host) { response in
                releaseHostWindowIfIdle()
                let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                completion(index)
            }
        }
    }

    private static func acquireHostWindow() -> KeyableWindow {
        if let hostWindow {
            return hostWindow
        }

        let window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Sapphire"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0.001
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.center()
        hostWindow = window
        return window
    }

    private static func releaseHostWindowIfIdle() {
        activeModalCount = max(0, activeModalCount - 1)
        guard activeModalCount == 0 else { return }
        hostWindow?.orderOut(nil)
        hostWindow = nil
    }
}

final class FocusableHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleStandardEditShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func handleStandardEditShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.modifierFlags.contains(.command) else {
            return false
        }

        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let selector: Selector?
        switch key {
        case "c":
            selector = #selector(NSText.copy(_:))
        case "v":
            selector = #selector(NSText.paste(_:))
        case "x":
            selector = #selector(NSText.cut(_:))
        case "a":
            selector = #selector(NSText.selectAll(_:))
        case "z":
            selector = event.modifierFlags.contains(.shift) ? Selector("redo:") : Selector("undo:")
        default:
            selector = nil
        }

        guard let selector else { return false }
        return NSApp.sendAction(selector, to: nil, from: self)
    }
}
