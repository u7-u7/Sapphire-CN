//
//  PremiumFeatureManagers.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

#if !SAPPHIRE_FULL_BUILD
import Combine
import Foundation

final class OCRScreenshotMonitor {
    static let shared = OCRScreenshotMonitor()
    private init() {}
}

final class SystemEnhanceWindowRegistry {
    static let shared = SystemEnhanceWindowRegistry()
    private init() {}
}

final class SystemEnhanceDockPreviewController {
    static let shared = SystemEnhanceDockPreviewController()
    private init() {}
    func start() {}
    func dismiss() {}
}

final class SystemEnhanceWindowSwitcher {
    static let shared = SystemEnhanceWindowSwitcher()
    private init() {}
    func start() {}
    func dismiss() {}
}

final class SystemEnhanceDockClicks {
    static let shared = SystemEnhanceDockClicks()
    private init() {}
    func start() {}
    func stopMonitoring() {}
}

final class SystemEnhanceAutoQuit {
    static let shared = SystemEnhanceAutoQuit()
    private init() {}
    func start() {}
    func stopObserving() {}
}

final class SystemEnhanceQuitProtection {
    static let shared = SystemEnhanceQuitProtection()
    private init() {}
    func start() {}
    func removeTap() {}
}

final class SystemEnhanceGreenMaximize {
    static let shared = SystemEnhanceGreenMaximize()
    private init() {}
    func start() {}
    func stopMonitoring() {}
}

final class SystemEnhanceContextMenu {
    static let shared = SystemEnhanceContextMenu()
    private init() {}
    func installIfNeeded() {}
}

final class SystemEnhanceHingeAnimationManager {
    static let shared = SystemEnhanceHingeAnimationManager()
    private init() {}
    func start() {}
    func stop() {}
}

final class DockLayoutsManager {
    static let shared = DockLayoutsManager()
    private init() {}
    func start() {}
    func startDockBehaviorSync() {}
    func importLayoutFiles(at urls: [URL]) {}
}

final class MediaOptimizerManager {
    static let shared = MediaOptimizerManager()
    private init() {}
    func start() {}
}

final class EmojiShortcutManager {
    static let shared = EmojiShortcutManager()
    private init() {}
    func stopMonitoring() {}
}

@MainActor
final class ClipboardPickerManager: ObservableObject {
    static let shared = ClipboardPickerManager()
    private init() {}
    func presentPicker() {}
    func stopMonitoring() {}
}

final class ClipboardAutoClearManager {
    static let shared = ClipboardAutoClearManager()
    private init() {}
    func start() {}
    func stop() {}
}

final class CleanURLManager {
    static let shared = CleanURLManager()
    private init() {}
    func start() {}
    func stopPolling() {}
    func stopMonitoring() { stopPolling() }
}

final class FinderCutPasteManager {
    static let shared = FinderCutPasteManager()
    private init() {}
    func start() {}
    func removeTap() {}
}

final class SnippetManager {
    static let shared = SnippetManager()
    private init() {}
    func start() {}
    func removeHandler() {}
}

final class MouseControlManager {
    static let shared = MouseControlManager()
    private init() {}
    func shutdown() {}
    func restoreSystemSettings() {}
}

final class FocusFollowsMouseManager {
    static let shared = FocusFollowsMouseManager()
    private init() {}
    func start() {}
    func removeMonitors() {}
}

final class ExtraClickFilterManager {
    static let shared = ExtraClickFilterManager()
    private init() {}
    func start() {}
    func shutdown() {}
}

final class KeyboardDebounceManager {
    static let shared = KeyboardDebounceManager()
    private init() {}
    func start() {}
    func stopMonitoring() {}
}

final class SuperKeyManager {
    static let shared = SuperKeyManager()
    private init() {}
    func start() {}
    func stopMonitoring() {}
}
#endif
