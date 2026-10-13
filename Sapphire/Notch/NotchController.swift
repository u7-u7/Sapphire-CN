//
//  NotchController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-04
//

import SwiftUI
import Combine
import ScreenCaptureKit
import NearbyShare
import AppKit
import Carbon.HIToolbox
import os.log

private let notchLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "NotchController")

private struct FileDropResult {
    let fallbackZone: DropZone?
    let finalLocation: CGPoint?
    let copiedURLs: [URL]
    let wasDraggedFromShelf: Bool
}

private struct NotchRuntimeSettings: Equatable {
    let animationProfile: AnimationProfile
    let customAnimationConfiguration: CustomizableAnimationConfiguration
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let perDisplayNotchSize: [String: NotchSizeOverride]
    let floatingIslandOnNotchlessDisplays: Bool
    let floatingIslandTopOffset: CGFloat
    let swipeToHideNotch: Bool
    let hideWhenInactive: Bool
}

struct NotchController: View {
    let notchWindow: NSWindow?
    private let notchWidget: NotchWidgetView
    private let timerManager: TimerManager
    private let systemHUD = SystemHUDManager.shared
    private let runtimeStateSource: ObjectIdentifier?

    enum NotchState: Hashable {
        case initial, autoExpanded, hoverExpanded, clickExpanded
    }

    private static let widgetSwitchProtectionDuration: TimeInterval = 2.5
    private static let hoverDetectionMargin: CGFloat = 8
    private static let hoverCollapseMargin: CGFloat = 60
    private static let hoverProximityMargin: CGFloat = 32
    private static let revealSettlingInterval: TimeInterval = 0.7
    private static let activitySwitchBlurWindow: TimeInterval = 0.45

    // MARK: - Environment Objects
    @EnvironmentObject var liveActivityManager: LiveActivityManager
    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject var activeAppMonitor: ActiveAppMonitor

    // MARK: - State Objects
    @StateObject private var fileShelfState = FileShelfState()
    @StateObject private var dragManager = GlobalDragManager()
    @StateObject private var dragState = DragStateManager.shared
    @StateObject private var calendarViewModel: InteractiveCalendarViewModel

    @ObservedObject private var windowDrag = WindowDragState.shared
    // MARK: - State Properties
    @State private var config: ResolvedNotchConfiguration?
    @State private var notchState: NotchState = .initial
    @State private var isHovered: Bool = false
    @State private var collapseTask: Task<Void, Never>?
    @State private var dragEndCollapseTask: Task<Void, Never>?
    @State private var isCollapseTimerActive: Bool = false
    @State private var widgetSwitchProtectionTask: Task<Void, Never>?
    @State private var widgetSwitchSettleTask: Task<Void, Never>?
    @State private var widgetSwitchProtectionGeneration: UInt64 = 0
    @State private var clickExpandedOpenedAt: Date = .distantPast
    @State private var isPinned = false
    @State private var popoverPresentation = NotchPopoverPresentationState()
    @State private var animatedWidth: CGFloat = 0
    @State private var animatedHeight: CGFloat = 0
    @State private var animatedCornerRadius: CGFloat = 0
    @State private var animatedBottomCornerRadius: CGFloat = 0
    @State private var animatedContentScale: CGFloat = 1.0

    @State private var shadowOpacity: Double = 0
    @State private var measuredClickContentSize: CGSize = .zero
    @State private var measuredAutoContentSize: CGSize = .zero
    @State private var notchIconsLeftWidth: CGFloat = 0
    @State private var notchIconsRightWidth: CGFloat = 0
    @State private var navigationStack: [NotchWidgetMode] = [.defaultWidgets]
    @State private var autoContentOpacity: Double = 0
    @State private var activityBlurRadius: CGFloat = 0
    @State private var activityContentScale: CGFloat = 1.0
    @State private var canRenderAutoContent: Bool = false
    @State private var isAnimatingActivityOut = false
    @State public var isFileDropTargeted: Bool = false
    @State private var activeDropZone: DropZone? = nil
    @State private var activeSnapZone: SnapZone? = nil
    @State private var notchDragLocationState = NotchDragLocationState()
    @State private var dropZoneFrames: [DropZone: CGRect] = [:]
    @State private var snapZoneHitRegions: [SnapZoneHitRegion] = []
    @State private var showLyrics: Bool = false
    @State private var liveActivityHorizontalPadding: CGFloat = 0
    @State private var expansionAnimation: Animation = .default
    @State private var awaitingDropCompletion: Bool = false
    @State private var isFileDragSessionInProgress = false
    @State private var activeFileDragIsFromShelf = false
    @State private var displayedFileDragMode: FileDragMode = .newFile
    @State private var nextFileDropSequence: UInt64 = 0
    @State private var nextFileDropSequenceToRoute: UInt64 = 0
    @State private var pendingFileDropSequences: Set<UInt64> = []
    @State private var completedFileDrops: [UInt64: FileDropResult] = [:]
    @State private var dropZoneResolutionTask: Task<Void, Never>?
    @State private var isHandlingActiveWindowDrag = false
    @State private var hudOverlayOpacity: Double = 0.0
    @State private var hudOverlayBlur: CGFloat = 10.0

    @State private var hoverMonitor: NotchHoverMonitor?
    @State private var lastSampledMouseLocation: CGPoint?
    @State private var lastPublishedInteractiveFrame: CGRect = .null
    @State private var lastActivityShapeSignature: NotchShapeSignature = .none
    @State private var isCalendarHovered: Bool = false
    @State private var fileDropFlowObserver: NSObjectProtocol?
    @State private var snapZoneEscapeMonitorToken: UUID?
    @State private var completeHideReason: NotchCompleteHideReason? = nil
    @State private var lastInactiveVisibilityEvaluation: (hideWhenInactive: Bool, hideReason: NotchCompleteHideReason?)?
    @State private var inactiveHideUserOverride: Bool = false
    @State private var inactiveRehideTask: Task<Void, Never>?
    @State private var suppressHoverAfterReveal = false
    @State private var revealSettlingUntil: Date = .distantPast
    @State private var hoverExpandTask: Task<Void, Never>?
    @State private var blurRemovalTask: Task<Void, Never>?
    @State private var activitySwitchBlurWindowEnd: Date = .distantPast
    @State private var hasRingingTimer: Bool
    @State private var hudOverlayKind: HUDOverlayKind?

    private enum HUDOverlayKind: Equatable {
        case volume
        case brightness
    }

    private enum NotchCompleteHideReason {
        case manualSwipe
        case inactive
    }

    private var isManuallyHidden: Bool { completeHideReason != nil }

    // MARK: - Computed Properties
    private var isLiveActivityActive: Bool { effectiveActivity != .none }

    private var shouldSuppressSnapZoneActivation: Bool {
        (notchState == .clickExpanded && navigationStack.last != .snapZones)
            || (windowDrag.isDragging && windowDrag.isSnapZoneDismissedForCurrentDrag)
            || (windowDrag.isDragging && windowDrag.isSnapZoneBypassModifierPressed)
    }

    private var notchDisplayID: CGDirectDisplayID? {
        if let window = notchWindow as? DynamicFocusWindow, window.displayID != 0 {
            return window.displayID
        }
        return notchWindow?.screen?.displayID
    }

    private var runtimeSettings: NotchRuntimeSettings {
        let current = settings.settings
        return NotchRuntimeSettings(
            animationProfile: current.animationProfile,
            customAnimationConfiguration: current.customAnimationConfiguration,
            notchWidth: current.notchWidth,
            notchHeight: current.notchHeight,
            perDisplayNotchSize: current.perDisplayNotchSize,
            floatingIslandOnNotchlessDisplays: current.floatingIslandOnNotchlessDisplays,
            floatingIslandTopOffset: current.floatingIslandTopOffset,
            swipeToHideNotch: current.swipeToHideNotch,
            hideWhenInactive: current.resolvedHideNotchWhenInactive(
                forDisplayID: notchWindow?.screen?.displayIdentifier
            )
        )
    }

    private var effectiveActivity: ActivityType {
        liveActivityManager.effectiveActivity(onDisplayID: notchDisplayID)
    }
    private var isFullViewActivity: Bool { liveActivityManager.isFullViewActivity }
    private var isGeminiActive: Bool { liveActivityManager.currentActivity == .geminiLive || liveActivityManager.currentActivity == .intelligenceAgent }

    private var isDisplayingMusicLiveActivity: Bool {
        let isMusic = (liveActivityManager.currentActivity == .music)
        let isShowingActivityView = (notchState == .autoExpanded || notchState == .hoverExpanded)
        return isMusic && isShowingActivityView
    }

    private var isInteractiveLiveActivity: Bool {
        guard isLiveActivityActive else { return false }

        let activityType = liveActivityManager.currentActivity

        switch activityType {
        case .nearbyShare:
            if let payload = liveActivityManager.currentNearDropPayload,
               payload.state == .waitingForConsent {
                return true
            }
        case .eyeBreak, .notification, .otp, .parcel:
            return true
        case .timer:
            return hasRingingTimer
        default:
            break
        }

        return false
    }

    private var currentMode: NotchWidgetMode { navigationStack.last ?? .defaultWidgets }

    private var notchIconsIntrinsicWidth: CGFloat {
        notchIconsLeftWidth + notchIconsRightWidth + (config?.defaultModeIconsHorizontalPadding ?? 0) * 2
    }

    private var activeAppearanceSettings: NotchAppearanceSettings {
        switch notchState {
        case .initial, .clickExpanded:
            return settings.settings.notchWidgetAppearance
        case .autoExpanded, .hoverExpanded:
            if isLiveActivityActive {
                return settings.settings.notchLiveActivityAppearance
            } else {
                return settings.settings.notchWidgetAppearance
            }
        }
    }

    private var isExpandedLiveActivity: Bool {
        (notchState == .autoExpanded || notchState == .hoverExpanded) && isLiveActivityActive
    }

    private var liveActivityFadeStartLocation: Double {
        guard let config, animatedHeight > 0 else { return 1 }
        let initialHeight = config.initialSize.height
        guard animatedHeight > initialHeight else { return 1 }
        return min(max(Double(initialHeight / animatedHeight), 0), 1)
    }

    private enum DefaultAppearancePalette {
        static let opaqueBlack = NSColor(Color.black).cgColor
        static let clearBlack = NSColor(Color.black.opacity(0)).cgColor

        static func black(at location: CGFloat) -> CodableColor {
            CodableColor(cgColor: opaqueBlack, location: location)
        }

        static func fadedOut(at location: CGFloat) -> CodableColor {
            CodableColor(cgColor: clearBlack, location: location)
        }
    }

    private var resolvedAppearanceSettings: NotchAppearanceSettings {
        var appearance = activeAppearanceSettings
        switch appearance.mode {
        case .default:
            appearance.solidColor = DefaultAppearancePalette.black(at: 0)
            appearance.opacity = 1
            appearance.enableTransparencyBlur = false
            appearance.liquidGlassLook = true
            if appearance.bottomFadeEnabled {
                if isExpandedLiveActivity {
                    if liveActivityManager.isFullViewActivity || liveActivityManager.activityHasBottomContent {
                        appearance.backgroundStyle = .gradient
                        appearance.gradientAngle = 90
                        appearance.gradientColors = [
                            DefaultAppearancePalette.black(at: CGFloat(liveActivityFadeStartLocation)),
                            DefaultAppearancePalette.fadedOut(at: 1.0)
                        ]
                    } else {
                        appearance.backgroundStyle = .solid
                    }
                } else {
                    appearance.backgroundStyle = .gradient
                    appearance.gradientAngle = 90
                    appearance.gradientColors = [
                        DefaultAppearancePalette.black(at: 0.7),
                        DefaultAppearancePalette.fadedOut(at: 1.0)
                    ]
                }
            } else {
                appearance.backgroundStyle = .solid
            }
        case .liquidGlass:
            appearance.backgroundStyle = .solid
            appearance.solidColor = DefaultAppearancePalette.black(at: 0)
            appearance.opacity = 0.0
            appearance.enableTransparencyBlur = false
            appearance.liquidGlassLook = true
            appearance.bottomFadeEnabled = false
        case .blur:
            appearance.backgroundStyle = .solid
            appearance.solidColor = DefaultAppearancePalette.black(at: 0)
            appearance.opacity = 0.55
            appearance.enableTransparencyBlur = true
            appearance.liquidGlassLook = false
            appearance.bottomFadeEnabled = false
        case .custom:
            appearance.bottomFadeEnabled = false
        }
        return appearance
    }

    private var isInteractive: Bool {
        !isManuallyHidden && (notchState == .clickExpanded || isHovered || dragManager.isDraggingInActivationZone || windowDrag.isDragging)
    }

    private var isPointerInteractionActive: Bool {
        !isManuallyHidden && (isHovered || dragManager.isDraggingInActivationZone || windowDrag.isDragging)
    }

    private var isPointerCaptureActive: Bool {
        dragManager.isDraggingInActivationZone
            || windowDrag.isDragging
            || (isHovered && NSEvent.pressedMouseButtons != 0)
    }

    private var cursorIsOnMyScreen: Bool {
        guard let notchScreen = notchWindow?.screen else {
            return CursorPosition.targetNotchScreen() == nil
        }
        let mouseLocation = NSEvent.mouseLocation
        return notchScreen.frame.contains(mouseLocation)
    }

    private var shouldHideWindowForSharing: Bool {
        settings.settings.hideFromScreenSharing
    }

    private var shouldBlockNotchExpansionWhileLocked: Bool {
        settings.settings.preventNotchExpandWhenLocked
            && ((NSApp.delegate as? AppDelegate)?.isScreenLocked == true)
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var activeScaleFactor: CGFloat {
        guard let config = config, notchState == .hoverExpanded && !isFullViewActivity else { return 1.0 }
        return config.scaleFactor
    }

    private var showRightHUDOverlay: Bool {
        guard notchState == .clickExpanded else { return false }
        guard cursorIsOnMyScreen else { return false }
        switch hudOverlayKind {
        case .volume:
            guard settings.settings.enableVolumeHUD else { return false }
            return true
        case .brightness:
            guard settings.settings.enableBrightnessHUD else { return false }
            return true
        case nil:
            return false
        }
    }

    private static func overlayKind(for hud: HUDType?) -> HUDOverlayKind? {
        switch hud?.caseIdentifier {
        case .volume, .externalDeviceVolume, .appVolume:
            return .volume
        case .brightness, .keyboardBrightness, .multiDisplayBrightness:
            return .brightness
        case nil:
            return nil
        }
    }

    private func updateHUDOverlayAnimation() {
        if showRightHUDOverlay {
            withAnimation(.easeOut(duration: 0.18)) {
                hudOverlayOpacity = 1.0
                hudOverlayBlur = 0.0
            }
        } else {
            withAnimation(.easeIn(duration: 0.12)) {
                hudOverlayOpacity = 0.0
                hudOverlayBlur = 10.0
            }
        }
    }

    private var surfaceShadowOpacity: Double {
        guard !isGeminiActive, !isManuallyHidden else { return 0 }
        return shadowOpacity
    }

    private var activeShape: CustomNotchShape {
        CustomNotchShape(
            cornerRadius: animatedCornerRadius,
            bottomCornerRadius: animatedBottomCornerRadius,
            isMusicActivity: isDisplayingMusicLiveActivity,
            isFloatingIsland: config?.isFloatingIsland ?? false
        )
    }

    // MARK: - Initializer
    public init(notchWindow: NSWindow?, timerManager: TimerManager) {
        self.notchWindow = notchWindow
        self.timerManager = timerManager
        self.runtimeStateSource = notchWindow.map(ObjectIdentifier.init)
        _hasRingingTimer = State(initialValue: timerManager.hasRingingTimer)
        _hudOverlayKind = State(
            initialValue: Self.overlayKind(for: SystemHUDManager.shared.currentHUD)
        )
        let calendarViewModel = InteractiveCalendarViewModel()
        _calendarViewModel = StateObject(wrappedValue: calendarViewModel)
        self.notchWidget = NotchWidgetView(calendarViewModel: calendarViewModel)
    }

    // MARK: - Body
    var body: some View {
        if let config = config {
            configuredNotchView(config: config)
        } else {
            Color.clear
                .onAppear {
                    let targetScreen = notchWindow?.screen ?? CursorPosition.targetNotchScreen()
                    let initialConfig = ResolvedNotchConfiguration(from: settings.settings, screen: targetScreen)
                    self.config = initialConfig
                    self.animatedWidth = initialConfig.initialSize.width
                    self.animatedHeight = initialConfig.initialSize.height
                    self.animatedCornerRadius = initialConfig.initialCornerRadius
                    self.animatedBottomCornerRadius = initialConfig.initialCornerRadius
                    self.expansionAnimation = initialConfig.expandAnimation
                    self.liveActivityHorizontalPadding = initialConfig.activityDefaultHorizontalPadding
                }
        }
    }

    @ViewBuilder
    private func configuredNotchView(config: ResolvedNotchConfiguration) -> some View {
        let chrome = applyNotchChrome(to: notchSurface(config: config), config: config)
        applyNotchSettingsHandlers(
            to: applyNotchNotificationHandlers(
                to: applyNotchStateHandlers(to: chrome)
            )
        )
    }

    private func notchSurface(config: ResolvedNotchConfiguration) -> some View {
        let appearance = resolvedAppearanceSettings
        return NotchSurfaceBackground(
            appearance: appearance,
            config: config,
            shape: activeShape,
            notchState: notchState,
            isGeminiActive: isGeminiActive,
            isManuallyHidden: isManuallyHidden,
            surfaceShadowOpacity: surfaceShadowOpacity,
            radialEndRadius: appearance.backgroundStyle == .radial ? animatedWidth / 2 : 0
        )
            .equatable()
            .overlay(alignment: .top) { notchContent(config: config) }
            .onTapGesture(perform: handleTap)
    }

    @ViewBuilder
    private func notchContent(config: ResolvedNotchConfiguration) -> some View {
        let showActivityView = (notchState == .autoExpanded || notchState == .hoverExpanded || isAnimatingActivityOut)

        ZStack(alignment: .top) {
            if showActivityView && effectiveActivity != .none && canRenderAutoContent {
                let activityTransition = liveActivityManager.activityHasBottomContent
                    ? config.bottomContentTransitionAnimation
                    : config.activityToActivityAnimation
                NotchActivityContentView(
                    content: liveActivityManager.activityContent,
                    config: config,
                    horizontalPadding: liveActivityHorizontalPadding,
                    screen: notchWindow?.screen,
                    measuredSize: $measuredAutoContentSize,
                    showLyrics: $showLyrics,
                    blurRadius: activityBlurRadius
                )
                    .geometryGroup()
                    .id(liveActivityManager.currentActivity)
                    .animation(activityTransition, value: liveActivityManager.activityAnimationKey)
                    .opacity(autoContentOpacity)
                    .scaleEffect(activityContentScale * animatedContentScale)
            } else {
                contentView
            }

            if notchState == .clickExpanded {
                expandedOverlayIcons(config: config)
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    .zIndex(1)

                hudOverlayView
                    .transition(.opacity.animation(.easeOut(duration: 0.18)))
                    .zIndex(3)
            }
        }
    }

    private func applyNotchChrome<V: View>(to view: V, config: ResolvedNotchConfiguration) -> some View {
        return view
            .frame(width: animatedWidth, height: animatedHeight)
            .contentShape(activeShape)
            .padding(.top, config.topInset - config.topBuffer)
            .frame(maxWidth: .infinity, alignment: .top)
            .preferredColorScheme(.dark)
    }

    private func applyNotchStateHandlers<V: View>(to view: V) -> some View {
        view
            .onAppear(perform: setupMonitors)
            .onDisappear(perform: teardownMonitors)
            .onChange(of: fileShelfState.selectedItemForPreview, perform: handlePreviewItemChange)
            .onChange(of: liveActivityManager.currentActivity, perform: handleActivityChange)
            .onChange(of: showRightHUDOverlay) { _, _ in
                updateHUDOverlayAnimation()
            }
            .onChange(of: liveActivityManager.contentUpdateID) {
                handleLiveActivityContentUpdate()
            }
            .onChange(of: notchState) { oldState, newState in
                handleStateChange(from: oldState, to: newState)
                updateRuntimeExpansionState()
            }
            .onChange(of: navigationStack, handleNavigationStackChange)
            .onChange(of: dragManager.isDraggingInActivationZone, perform: handleDragActivationZoneChange)
            .onChange(of: windowDrag.isDragging, perform: handleActiveWindowDragChange)
            .onChange(of: windowDrag.isSnapZoneDismissedForCurrentDrag, perform: handleSnapZoneDismissalChange)
            .onChange(of: windowDrag.isSnapZoneBypassModifierPressed) { _, isPressed in
                handleSnapZoneBypassModifierChange(isPressed)
            }
            .onChange(of: isFileDropTargeted, perform: handleFileDropTargetChange)
            .onChange(of: measuredClickContentSize, perform: handleMeasuredClickSizeChange)
            .onChange(of: measuredAutoContentSize, perform: handleMeasuredAutoSizeChange)
            .onChange(of: activeAppMonitor.fullScreenDisplayIDs) { _, _ in
                handleFullScreenDisplayChange()
            }
            .onReceive(
                timerManager.$ringingTimers
                    .map { !$0.isEmpty }
                    .removeDuplicates()
            ) { isRinging in
                hasRingingTimer = isRinging
            }
            .onReceive(
                systemHUD.$currentHUD
                    .map(Self.overlayKind(for:))
                    .removeDuplicates()
            ) { kind in
                hudOverlayKind = kind
            }
    }

    private static let notchNotifications = Publishers.MergeMany(
        [
            Notification.Name.sapphireOpenMusicQueue,
            .sapphireOpenMusicDevices,
            .sapphireRevealHiddenNotch,
            .sapphireOpenCircleToSearch,
            NSApplication.didChangeScreenParametersNotification
        ].map { NotificationCenter.default.publisher(for: $0) }
    )

    private func applyNotchNotificationHandlers<V: View>(to view: V) -> some View {
        view
            .background(GeminiPickerBridge())
            .onReceive(Self.notchNotifications) { notification in
                switch notification.name {
                case .sapphireOpenMusicQueue:
                    openMusicHub(mode: .musicQueueAndPlaylists)
                case .sapphireOpenMusicDevices:
                    openMusicHub(mode: .musicDevices)
                case .sapphireRevealHiddenNotch:
                    guard isManuallyHidden,
                          let displayID = notchDisplayID,
                          (notification.object as? NSNumber)?.uint32Value == displayID else { return }
                    haptic()
                    inactiveHideUserOverride = true
                    revealNotchFromCompleteHide()
                    scheduleInactiveRehideAfterReveal()
                case .sapphireOpenCircleToSearch:
                    openCircleToSearch(object: notification.object as? String)
                case NSApplication.didChangeScreenParametersNotification:
                    handleScreenParametersChange()
                default:
                    break
                }
            }
    }

    private func applyNotchSettingsHandlers<V: View>(to view: V) -> some View {
        view
            .onChange(of: showLyrics, perform: handleShowLyricsChange)
            .onChange(of: isInteractive) { _, isNowInteractive in
                updateMouseEventHandling(isInteractive: isNowInteractive)
                MenuBarInteractionManager.shared.setSuspended(isNowInteractive)
            }
            .onChange(of: CGSize(width: animatedWidth, height: animatedHeight)) { _, _ in
                updateMouseEventHandling(isInteractive: isInteractive)
                scheduleWidgetSwitchSettledCheck()
            }
            .onChange(of: notchIconsIntrinsicWidth) { _, _ in
                applyNotchIconsWidthFloor()
            }
            .onChange(of: shouldHideWindowForSharing, perform: handleSharingVisibilityChange)
            .onChange(of: runtimeSettings, perform: handleSettingsChange)
    }

    private func handleDragActivationZoneChange(_ isDragging: Bool) {
        if isDragging {
            let mouseLocation = NSEvent.mouseLocation
            let notchScreen = notchWindow?.screen
            let notchScreenFrame = notchScreen?.frame ?? .zero
            let myDisplayID = notchScreen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            notchLog.info("handleDragActivationZoneChange: isDragging=true mouse=\(mouseLocation.x),\(mouseLocation.y) myDisplayID=\(myDisplayID.map(String.init) ?? "nil") notchScreenFrame=\(notchScreenFrame.minX),\(notchScreenFrame.minY)-\(notchScreenFrame.maxX),\(notchScreenFrame.maxY) cursorIsOnMyScreen=\(cursorIsOnMyScreen)")
            guard cursorIsOnMyScreen else { return }
        }
        Task {
            await handleDragActivationChange(isDragging: isDragging)
        }
    }

    private func handleActiveWindowDragChange(_ isDragging: Bool) {
        if !isDragging {
            let wasHandlingActiveWindowDrag = isHandlingActiveWindowDrag
            isHandlingActiveWindowDrag = false
            hoverMonitor?.setExternalMouseDragActive(false)
            guard wasHandlingActiveWindowDrag else { return }
            handleWindowDragChange(isDragging: false)
            return
        }

        guard settings.settings.snapOnWindowDragEnabled else { return }
        guard !shouldSuppressSnapZoneActivation else { return }
        let mouseLocation = NSEvent.mouseLocation
        let notchScreen = notchWindow?.screen
        let notchScreenFrame = notchScreen?.frame ?? .zero
        let myDisplayID = notchScreen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        notchLog.info("handleActiveWindowDragChange: isDragging=true mouse=\(mouseLocation.x),\(mouseLocation.y) myDisplayID=\(myDisplayID.map(String.init) ?? "nil") notchScreenFrame=\(notchScreenFrame.minX),\(notchScreenFrame.minY)-\(notchScreenFrame.maxX),\(notchScreenFrame.maxY) cursorIsOnMyScreen=\(cursorIsOnMyScreen)")
        guard cursorIsOnMyScreen else { return }
        isHandlingActiveWindowDrag = true
        hoverMonitor?.setExternalMouseDragActive(true)
        handleWindowDragChange(isDragging: true)
    }

    private func handleSnapZoneDismissalChange(_ isDismissed: Bool) {
        guard isDismissed,
              windowDrag.isDragging,
              navigationStack.last == .snapZones else { return }
        dismissActiveSnapZones()
    }

    private func handleSnapZoneBypassModifierChange(_ isPressed: Bool) {
        guard windowDrag.isDragging else { return }

        if isPressed {
            isHandlingActiveWindowDrag = false
            dragManager.cancelActivation()
            if navigationStack.last == .snapZones {
                dismissActiveSnapZones()
            }
            return
        }

        guard settings.settings.snapOnWindowDragEnabled,
              !windowDrag.isSnapZoneDismissedForCurrentDrag,
              cursorIsOnMyScreen else { return }
        isHandlingActiveWindowDrag = true
        hoverMonitor?.setExternalMouseDragActive(true)
        handleWindowDragChange(isDragging: true)
    }

    private func startSnapZoneEscapeMonitoring() {
        guard snapZoneEscapeMonitorToken == nil else { return }
        snapZoneEscapeMonitorToken = EventMonitorHub.shared.register(for: .keyDown) { event in
            guard event.keyCode == CGKeyCode(kVK_Escape),
                  windowDrag.isDragging,
                  navigationStack.last == .snapZones else { return }
            windowDrag.dismissSnapZonesForCurrentDrag()
            dismissActiveSnapZones()
        }
    }

    private func stopSnapZoneEscapeMonitoring() {
        guard let snapZoneEscapeMonitorToken else { return }
        EventMonitorHub.shared.unregister(token: snapZoneEscapeMonitorToken, for: .keyDown)
        self.snapZoneEscapeMonitorToken = nil
    }

    private func dismissActiveSnapZones() {
        dragEndCollapseTask?.cancel()
        dragEndCollapseTask = nil
        dragManager.cancelActivation()
        SnapPreviewManager.shared.hidePreview()
        activeSnapZone = nil
        snapZoneHitRegions = []
        notchDragLocationState.update(nil)
        navigationStack = []
        notchState = isLiveActivityActive ? .autoExpanded : .initial
    }

    private func handleMeasuredClickSizeChange(_ newSize: CGSize) {
        handleSizeChange(newSize, for: .clickExpanded)
    }

    private func handleMeasuredAutoSizeChange(_ newSize: CGSize) {
        handleSizeChange(newSize, for: .autoExpanded)
    }

    private func handleSharingVisibilityChange(_ shouldBeHidden: Bool) {
        updateWindowSharingBehavior(shouldBeHidden: shouldBeHidden)
    }

    private func handleLiveActivityContentUpdate() {
        guard notchState == .autoExpanded || notchState == .hoverExpanded else { return }
        let shapeSignature = liveActivityManager.notchShapeSignature
        if shapeSignature != lastActivityShapeSignature {
            lastActivityShapeSignature = shapeSignature
            handleStateChange(from: notchState, to: notchState, refreshSize: false)
        } else {
            updateAutoContentSize()
        }
    }

    private func handleSettingsChange(_ runtimeSettings: NotchRuntimeSettings) {
        let newSettings = settings.settings
        let targetScreen = notchWindow?.screen ?? CursorPosition.targetNotchScreen()
        let newConfig = ResolvedNotchConfiguration(from: newSettings, screen: targetScreen)
        if newConfig != config {
            self.config = newConfig
            self.expansionAnimation = newConfig.expandAnimation
            handleStateChange(from: notchState, to: notchState)
        }
        if !runtimeSettings.swipeToHideNotch, completeHideReason == .manualSwipe {
            revealNotchFromCompleteHide()
        }
        if !runtimeSettings.hideWhenInactive {
            inactiveHideUserOverride = false
            if completeHideReason == .inactive {
                revealNotchFromCompleteHide()
            }
        }
        evaluateInactiveNotchVisibility()
    }

    private func handleScreenParametersChange() {
        let targetScreen = notchWindow?.screen ?? CursorPosition.targetNotchScreen()
        let newConfig = ResolvedNotchConfiguration(from: settings.settings, screen: targetScreen)

        guard let currentConfig = config,
              currentConfig.initialSize != newConfig.initialSize ||
              currentConfig.initialCornerRadius != newConfig.initialCornerRadius else {
            return
        }

        self.config = newConfig
        self.expansionAnimation = newConfig.expandAnimation
        handleStateChange(from: notchState, to: notchState)
    }

    // MARK: - Subviews
    @ViewBuilder
    private var contentView: some View {
        if let config = config, notchState == .clickExpanded {
            notchWidget
                .environmentObject(fileShelfState)
                .environmentObject(dragState)
                .environment(\.navigationStack, $navigationStack)
                .environment(\.activeDropZone, $activeDropZone)
                .environment(\.isCalendarHovered, $isCalendarHovered)
                .environment(\.onNotchPopoverPresentationChange, handlePopoverPresentation)
                .environment(\.onActiveSnapZoneChange, { activeSnapZone = $0 })
                .environment(\.onDropZoneFramesChange, handleDropZoneFramesChange)
                .environment(\.onSnapZoneHitRegionsChange, { snapZoneHitRegions = $0 })
                .environmentObject(notchDragLocationState)
                .environment(\.fileDragMode, displayedFileDragMode)
                .padding(.top, config.contentTopPadding)
                .padding(.bottom, config.contentBottomPadding)
                .padding(.horizontal, config.contentHorizontalPadding)
                .padding(.top, config.initialSize.height)
                .measureIdealSize(into: $measuredClickContentSize)
                .onDisappear {
                    if notchState != .clickExpanded {
                        measuredClickContentSize = .zero
                    }
                }
                .frame(width: animatedWidth, height: animatedHeight, alignment: .top)
                .clipped()
                .id(notchState)
                .allowsHitTesting(true)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func expandedOverlayIcons(config: ResolvedNotchConfiguration) -> some View {
        NotchExpandedChrome(
            config: config,
            mode: currentMode,
            notchState: notchState,
            animatedWidth: animatedWidth,
            showRightHUDOverlay: showRightHUDOverlay,
            navigationStack: $navigationStack,
            isPinned: $isPinned,
            iconsLeftWidth: $notchIconsLeftWidth,
            iconsRightWidth: $notchIconsRightWidth,
            iconsIntrinsicWidth: notchIconsIntrinsicWidth,
            onPin: { pinned in
                if pinned {
                    collapseTask?.cancel()
                    isCollapseTimerActive = false
                }
            },
            onOpenBlipHub: openBlipHub,
            onOpenAgentS: {
                openBlipHub()
                navigationStack.append(.agentS)
            }
        )
    }

    @ViewBuilder
    private var hudOverlayView: some View {
        if let config = config, showRightHUDOverlay {
            NotchHUDOverlayContent(config: config, animatedWidth: animatedWidth)
            .opacity(hudOverlayOpacity)
            .blur(radius: hudOverlayBlur)
            .allowsHitTesting(hudOverlayOpacity > 0.5)
            .zIndex(3)
        }
    }

    // MARK: - Setup and Teardown
    private func setupMonitors() {
        if let runtimeStateSource {
            NotchRuntimeState.shared.register(
                source: runtimeStateSource,
                isExpanded: notchState != .initial && !isManuallyHidden
            )
        }
        dragManager.startMonitoring()
        liveActivityManager.showLyricsBinding = $showLyrics

        MenuBarInteractionManager.shared.setSuspended(isInteractive)

        TrackpadGestureHandler.shared.onSwipe = { dx, dy in
            self.handleTrackpadSwipe(vector: CGVector(dx: dx, dy: dy))
        }
        TrackpadGestureHandler.shared.onTwoFingerTap = {
            self.handleTrackpadTwoFingerTap()
        }

        if fileDropFlowObserver == nil {
            fileDropFlowObserver = NotificationCenter.default.addObserver(
                forName: .fileDropFlowCompleted,
                object: nil,
                queue: .main
            ) { _ in
                guard self.pendingFileDropSequences.isEmpty,
                      self.completedFileDrops.isEmpty else { return }
                self.awaitingDropCompletion = false
                if self.notchState == .clickExpanded,
                   !self.isPinned,
                   !self.isFileDragSessionInProgress {
                    self.startWidgetSwitchProtection()
                }
            }
        }

        startNotchInteractionMonitoring()
        startSnapZoneEscapeMonitoring()
        updateMouseEventHandling(isInteractive: isInteractive)
        updateWindowSharingBehavior(shouldBeHidden: shouldHideWindowForSharing)
        lastActivityShapeSignature = liveActivityManager.notchShapeSignature
        evaluateInactiveNotchVisibility()
    }

    private func teardownMonitors() {
        popoverPresentation.reset()
        if let runtimeStateSource {
            NotchRuntimeState.shared.unregister(source: runtimeStateSource)
        }
        dragManager.stopMonitoring()
        TrackpadGestureHandler.shared.stopMonitoring()
        TrackpadGestureHandler.shared.onSwipe = nil
        TrackpadGestureHandler.shared.onTwoFingerTap = nil
        stopHiddenNotchSwipeMonitor()
        inactiveRehideTask?.cancel()
        if let fileDropFlowObserver {
            NotificationCenter.default.removeObserver(fileDropFlowObserver)
            self.fileDropFlowObserver = nil
        }
        collapseTask?.cancel()
        dragEndCollapseTask?.cancel()
        dragEndCollapseTask = nil
        dropZoneResolutionTask?.cancel()
        dropZoneResolutionTask = nil
        cancelWidgetSwitchProtection()
        stopSnapZoneEscapeMonitoring()
        stopNotchInteractionMonitoring()
        MenuBarInteractionManager.shared.setSuspended(false)
    }

    // MARK: - Event Handlers
    private func handleTap() {
        guard !isManuallyHidden else { return }
        guard !shouldBlockNotchExpansionWhileLocked else { return }
        guard let config = config else { return }
        if notchState == .clickExpanded { return }

        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            collapseTask?.cancel()
            isCollapseTimerActive = false
            measuredClickContentSize = .zero
            navigationStack = [.defaultWidgets]
            notchState = .clickExpanded
            return
        }

        collapseTask?.cancel()
        isCollapseTimerActive = false
        if isPinned { return }

        let activityType = liveActivityManager.currentActivity
        if (notchState == .autoExpanded || notchState == .hoverExpanded) {
            let initiateWidgetView: (NotchWidgetMode) -> Void = { mode in
                self.measuredClickContentSize = .zero
                self.navigationStack = [mode]
                self.notchState = .clickExpanded
            }
            if activityType == .music, settings.settings.musicOpenOnClick { initiateWidgetView(.musicPlayer); return }
            if activityType == .weather, settings.settings.weatherOpenOnClick { initiateWidgetView(.weatherPlayer); return }
            if activityType == .sports, settings.settings.sportsOpenOnClick, PremiumGate.hasAccess(.sportsWidget) { initiateWidgetView(.sportsPlayer); return }
            if activityType == .finance, settings.settings.financeOpenOnClick, PremiumGate.hasAccess(.financeWidget) { initiateWidgetView(.financePlayer); return }
            if activityType == .calendar, settings.settings.calendarOpenOnClick { initiateWidgetView(.calendarPlayer); return }
            if activityType == .fileShelf, settings.settings.clickToOpenFileShelf { initiateWidgetView(.fileShelf); return }
            if activityType == .timer, settings.settings.clickToShowTimerView { initiateWidgetView(.timerDetailView); return }
            if activityType == .continuity { initiateWidgetView(.continuityDetail); return }
            if activityType == .continuityExternal { initiateWidgetView(.continuityActivityDetail); return }
            if activityType == .intelligenceAgent { initiateWidgetView(.agentS); return }
            if activityType == .updateAvailable { initiateWidgetView(.updateAvailable); return }
        }

        switch notchState {
        case .initial, .autoExpanded, .hoverExpanded:
            self.expansionAnimation = config.expandAnimation
            measuredClickContentSize = .zero
            var targetStack: [NotchWidgetMode]
            if settings.settings.clickToOpenFileShelf && !FileShelfManager.shared.files.isEmpty {
                targetStack = [.fileShelf]
            } else if settings.settings.rememberLastMenu, let savedStack = settings.lastNotchNavigationStack, !savedStack.isEmpty {
                targetStack = savedStack.map { $0.toNotchWidgetMode() }
            } else {
                targetStack = [.defaultWidgets]
            }
            navigationStack = targetStack
            notchState = .clickExpanded
        case .clickExpanded:
            return
        }
    }

    private func handleHover(hovering: Bool) {
        guard !isManuallyHidden else { return }
        guard let config = config else { return }
        self.isHovered = hovering

        if hovering {
            TrackpadGestureHandler.shared.startMonitoring()
        } else {
            TrackpadGestureHandler.shared.stopMonitoring()
            suppressHoverAfterReveal = false
            cancelHoverExpandTask()
        }

        if hovering {
            guard !suppressHoverAfterReveal else { return }
            guard !shouldBlockNotchExpansionWhileLocked else { return }
            collapseTask?.cancel()
            isCollapseTimerActive = false
            let activityType = liveActivityManager.currentActivity

            if activityType == .fileShelf, settings.settings.hoverToOpenFileShelf {
                cancelHoverExpandTask()
                if notchState != .clickExpanded {
                    navigationStack = [.fileShelf]
                    notchState = .clickExpanded
                }
        } else if settings.settings.expandOnHover && !isFullViewActivity && !isInteractiveLiveActivity {
                if notchState != .clickExpanded {
                    notchWindow?.orderFront(nil)
                    self.expansionAnimation = config.expandAnimation
                    var targetStack: [NotchWidgetMode]
                    if settings.settings.hoverToOpenFileShelf && !FileShelfManager.shared.files.isEmpty {
                        targetStack = [.fileShelf]
                    } else if settings.settings.rememberLastMenu, let savedStack = settings.lastNotchNavigationStack, !savedStack.isEmpty {
                        targetStack = savedStack.map { $0.toNotchWidgetMode() }
                    } else {
                        targetStack = [.defaultWidgets]
                    }
                    navigationStack = targetStack
                    let delay = settings.settings.expandOnHoverDelay
                    if delay > 0 {
                        cancelHoverExpandTask()
                        hoverExpandTask = Task { @MainActor in
                            do {
                                try await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                            } catch { return }
                            guard !Task.isCancelled, self.isHovered else { return }
                            guard !self.dragManager.isDraggingInActivationZone else { return }
                            guard self.notchState != .clickExpanded else { return }
                            guard settings.settings.expandOnHover else { return }
                            guard !self.isInteractiveLiveActivity else { return }
                            self.notchState = .clickExpanded
                        }
                    } else {
                        cancelHoverExpandTask()
                        guard !isInteractiveLiveActivity else { return }
                        notchState = .clickExpanded
                    }
                }
            } else {
                cancelHoverExpandTask()
                if notchState == .initial || notchState == .autoExpanded {
                    guard !isInteractiveLiveActivity else { return }
                    notchState = .hoverExpanded
                    haptic()
                }
            }
        } else {
            if notchState == .clickExpanded {
                handleClickExpandedHoverOut(config: config)
            } else {
                scheduleCollapse(after: 0)
            }
        }
    }

    private func handleActivityChange(_: ActivityType) {
        let newActivity = liveActivityManager.effectiveActivity(onDisplayID: notchDisplayID)
        if newActivity != .none {
            inactiveHideUserOverride = false
            if completeHideReason == .inactive {
                revealNotchFromCompleteHide()
            } else if completeHideReason == .manualSwipe {
                return
            }
        } else if completeHideReason == .manualSwipe {
            return
        } else if completeHideReason == .inactive {
            return
        }

        guard notchState != .clickExpanded, let config = config else {
            evaluateInactiveNotchVisibility()
            return
        }

        if newActivity != .none {
            activitySwitchBlurWindowEnd = Date().addingTimeInterval(Self.activitySwitchBlurWindow)
            blurRemovalTask?.cancel()
            blurRemovalTask = nil
            if reduceMotion {
                activityBlurRadius = 0
                activityContentScale = 1.0
            } else {
                activityBlurRadius = config.activityBlurRadiusMax
                activityContentScale = 0.9
                DispatchQueue.main.async {
                    withAnimation(config.focusPullAnimation) {
                        self.activityBlurRadius = 0
                        self.activityContentScale = 1.0
                    }
                }
            }
        }

        let previousState = notchState
        notchState = newActivity != .none ? .autoExpanded : .initial
        if previousState == notchState {
            handleStateChange(from: notchState, to: notchState, refreshSize: false)
            lastActivityShapeSignature = liveActivityManager.notchShapeSignature
        }
        evaluateInactiveNotchVisibility()
    }

    private func handleFullScreenDisplayChange() {
        handleActivityChange(liveActivityManager.currentActivity)
    }

    private func handleStateChange(from oldState: NotchState, to newState: NotchState, refreshSize: Bool = true) {
        guard let config = config else { return }
        if isManuallyHidden {
            animatedWidth = 0
            animatedHeight = 0
            notchWindow?.alphaValue = 0
            return
        }

        let isContentUpdate = oldState == newState
        let animation: Animation
        if isContentUpdate {
            animation = config.bottomContentAnimation
        } else {
            switch newState {
            case .initial:
                animation = (oldState == .clickExpanded) ? config.collapseAnimation : config.activityToActivityAnimation
            case .hoverExpanded: animation = config.hoverAnimation
            case .clickExpanded: animation = self.expansionAnimation
            case .autoExpanded: animation = (oldState == .clickExpanded) ? config.collapseAnimation : config.activityToActivityAnimation
            }
        }

        withAnimation(animation) {
            updateRadiiForCurrentState(state: newState)
            self.liveActivityHorizontalPadding = liveActivityManager.activityHasBottomContent ?
            config.activityWithContentHorizontalPadding :
            config.activityDefaultHorizontalPadding
            if isContentUpdate && refreshSize {
                refreshAnimatedSizeForCurrentState()
            }
        }

        if isContentUpdate { return }

        if newState == .clickExpanded {
            clickExpandedOpenedAt = Date()
        }

        if newState != .clickExpanded {
            CircleToSearchManager.shared.endResultsPresentation()
        }

        if oldState == .clickExpanded && newState != .clickExpanded {
            if navigationStack.contains(.mirrorPlayer) {
                navigationStack.removeAll { $0 == .mirrorPlayer }
                if navigationStack.isEmpty {
                    navigationStack = [.defaultWidgets]
                }
            }
            if MirrorCameraManager.shared.isLive {
                MirrorCameraManager.shared.teardown()
            }
        }

        switch newState {
        case .initial:
            let wasShowingActivity = (oldState == .autoExpanded || oldState == .hoverExpanded)
            if wasShowingActivity { isAnimatingActivityOut = true }
            self.canRenderAutoContent = false
            collapseTask?.cancel(); isCollapseTimerActive = false
            cancelHoverExpandTask()
            cancelWidgetSwitchProtection()

            let idleMorphAnimation = (oldState == .clickExpanded)
                ? config.collapseAnimation
                : config.activityToActivityAnimation

            withAnimation(idleMorphAnimation) {
                shadowOpacity = 0
                if wasShowingActivity {
                    autoContentOpacity = 0
                    if !reduceMotion { activityBlurRadius = 20; activityContentScale = 0.9 }
                }
                animatedWidth = config.initialSize.width; animatedHeight = config.initialSize.height
                animatedContentScale = 1.0
                isPinned = false
            }
            syncNotchHostWindowHeight(contentHeight: config.initialSize.height)

            DispatchQueue.main.asyncAfter(deadline: .now() + config.activityAnimationOutDelay) {
                guard self.notchState == .initial else { return }
                if wasShowingActivity { self.isAnimatingActivityOut = false }
                self.activityBlurRadius = 0; self.activityContentScale = 1.0
            }

        case .hoverExpanded:
            isAnimatingActivityOut = false; self.canRenderAutoContent = true

            let scale = activeScaleFactor
            let rawWidth = isLiveActivityActive ? measuredAutoContentSize.width * scale : config.hoverExpandedSize.width
            let rawHeight = isLiveActivityActive ? measuredAutoContentSize.height * scale : config.hoverExpandedSize.height
            let targetWidth = max(rawWidth, config.initialSize.width)
            let targetHeight = max(rawHeight, config.initialSize.height)

            withAnimation(config.hoverAnimation) {
                animatedWidth = targetWidth; animatedHeight = targetHeight
                if isLiveActivityActive { autoContentOpacity = 1 }
                animatedContentScale = scale
                shadowOpacity = 1
            }

        case .clickExpanded:
            isAnimatingActivityOut = false; self.canRenderAutoContent = false

            shadowOpacity = 0

            if isLiveActivityActive && (oldState == .autoExpanded || oldState == .hoverExpanded) {
                withAnimation(config.activityBlurAnimation) {
                    autoContentOpacity = 0
                    if !reduceMotion { activityBlurRadius = config.activityBlurRadiusMax; activityContentScale = 1.05 }
                }
            }

            withAnimation(self.expansionAnimation) {
                autoContentOpacity = 0
            }
             DispatchQueue.main.asyncAfter(deadline: .now() + config.contentUpdateDelay) {
                withAnimation(config.focusPullAnimation) {
                    self.activityContentScale = 1.0
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.expansionAnimation = config.expandAnimation
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if self.notchState == .clickExpanded {
                    withAnimation(.easeIn(duration: 0.2)) { self.shadowOpacity = 1 }
                }
            }

        case .autoExpanded:
            isAnimatingActivityOut = false
            let isCollapsingFromClick = (oldState == .clickExpanded)
            if isCollapsingFromClick {
                cancelWidgetSwitchProtection()
                self.canRenderAutoContent = false
                if !reduceMotion {
                    withAnimation(config.blurAnimation) { activityContentScale = 0.92; activityBlurRadius = config.activityBlurRadiusMax * 1.5 }
                }
            } else {
                self.canRenderAutoContent = true; self.autoContentOpacity = 1
            }
            let animationToUse = isCollapsingFromClick ? config.collapseAnimation : config.activityToActivityAnimation

            shadowOpacity = 0

            withAnimation(animationToUse) {
                animatedWidth = max(measuredAutoContentSize.width, config.initialSize.width)
                animatedHeight = max(measuredAutoContentSize.height, config.initialSize.height)
                animatedContentScale = 1.0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + config.activitySizeChangeDelay) {
                withAnimation(config.blurRemovalAnimation) {
                    self.activityBlurRadius = 0; self.activityContentScale = 1.0
                }
            }
            if isCollapsingFromClick {
                DispatchQueue.main.asyncAfter(deadline: .now() + config.autoContentRenderDelay) {
                    if self.notchState == .autoExpanded {
                        self.canRenderAutoContent = true
                        withAnimation(config.activityOpacityAnimation) { self.autoContentOpacity = 1 }
                    }
                }
            }
        }
        updateMouseEventHandling(isInteractive: isInteractive)
    }

    private func refreshAnimatedSizeForCurrentState() {
        guard let config = config else { return }
        switch notchState {
        case .initial:
            animatedWidth = config.initialSize.width
            animatedHeight = config.initialSize.height
        case .autoExpanded:
            animatedWidth = max(measuredAutoContentSize.width, config.initialSize.width)
            animatedHeight = max(measuredAutoContentSize.height, config.initialSize.height)
        case .hoverExpanded:
            let scale = activeScaleFactor
            let rawWidth = isLiveActivityActive ? measuredAutoContentSize.width * scale : config.hoverExpandedSize.width
            let rawHeight = isLiveActivityActive ? measuredAutoContentSize.height * scale : config.hoverExpandedSize.height
            animatedWidth = max(rawWidth, config.initialSize.width)
            animatedHeight = max(rawHeight, config.initialSize.height)
        case .clickExpanded:
            break
        }
    }

    private func handlePreviewItemChange(newItem: ShelfItem?) {
        if newItem != nil {
            navigationStack.append(.fileActionPreview)
        } else {
            if navigationStack.last == .fileActionPreview {
                navigationStack.removeLast()
            }
        }
    }

    private func handleNavigationStackChange(oldStack: [NotchWidgetMode], newStack: [NotchWidgetMode]) {
        guard let config = config else { return }
        if oldStack.contains(.circleToSearch) && !newStack.contains(.circleToSearch) {
            CircleToSearchManager.shared.endResultsPresentation()
        }
        if oldStack.contains(.snapZones) && !newStack.contains(.snapZones) {
            SnapPreviewManager.shared.hidePreview()
        }
        if oldStack.contains(.mirrorPlayer) && !newStack.contains(.mirrorPlayer) {
            MirrorCameraManager.shared.teardown()
        }

        if notchState == .clickExpanded && oldStack != newStack {
            let panelJustOpened = Date().timeIntervalSince(clickExpandedOpenedAt) < 0.1
            if !panelJustOpened {
                self.expansionAnimation = config.widgetSwitchAnimation
                startWidgetSwitchProtection()
            }
        }

        if notchState == .clickExpanded {
            if settings.settings.rememberLastMenu {
                let restorableStack = newStack.compactMap { toRestorableMenu(mode: $0) }
                if !restorableStack.isEmpty {
                    settings.lastNotchNavigationStack = restorableStack
                }
            }
        }
    }

    private func handleFileDrop(urls: [URL], at screenLocation: NSPoint) -> Bool {
        let fileManager = FileManager.default
        let readableURLs = urls.filter {
            $0.isFileURL
                && fileManager.fileExists(atPath: $0.path)
                && fileManager.isReadableFile(atPath: $0.path)
        }
        guard !readableURLs.isEmpty else { return false }

        let finalLocation = updateNotchDragLocation(from: screenLocation)
        let fallbackDropZone: DropZone?
        let wasDraggedFromShelf = isFileDragSessionInProgress
            ? activeFileDragIsFromShelf
            : dragState.isDraggingFromShelf
        fallbackDropZone = activeDropZone ?? (wasDraggedFromShelf ? nil : .shelf)
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.shariq.Sapphire")
            .appendingPathComponent("TemporaryDrop")
        let accessGrants = readableURLs.map { url in
            (url: url, shouldStopAccessing: url.startAccessingSecurityScopedResource())
        }

        let sequence = nextFileDropSequence
        nextFileDropSequence &+= 1
        pendingFileDropSequences.insert(sequence)
        awaitingDropCompletion = true

        Task {
            let copiedURLs = await Task.detached(priority: .userInitiated) {
                let fileManager = FileManager.default
                return accessGrants.compactMap { grant -> URL? in
                    let sourceURL = grant.url
                    defer {
                        if grant.shouldStopAccessing { sourceURL.stopAccessingSecurityScopedResource() }
                    }

                    let destinationDirectory = temporaryRoot.appendingPathComponent(UUID().uuidString)
                    let destinationURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
                    do {
                        try fileManager.createDirectory(
                            at: destinationDirectory,
                            withIntermediateDirectories: true
                        )
                        try fileManager.copyItem(at: sourceURL, to: destinationURL)
                        return destinationURL
                    } catch {
                        print("[NotchController] Failed to copy dropped file: \(error.localizedDescription)")
                        return nil
                    }
                }
            }.value

            await MainActor.run {
                self.pendingFileDropSequences.remove(sequence)
                self.completedFileDrops[sequence] = FileDropResult(
                    fallbackZone: fallbackDropZone,
                    finalLocation: finalLocation,
                    copiedURLs: copiedURLs,
                    wasDraggedFromShelf: wasDraggedFromShelf
                )
                self.routeCompletedFileDropsInOrder()
            }
        }
        return true
    }

    private func routeCompletedFileDropsInOrder(allowUnresolvedTarget: Bool = false) {
        guard !isFileDragSessionInProgress else {
            awaitingDropCompletion = !pendingFileDropSequences.isEmpty || !completedFileDrops.isEmpty
            return
        }

        while let result = completedFileDrops.removeValue(forKey: nextFileDropSequenceToRoute) {
            guard !result.copiedURLs.isEmpty else {
                nextFileDropSequenceToRoute &+= 1
                continue
            }

            let resolvedZone: DropZone?
            if let finalLocation = result.finalLocation, !dropZoneFrames.isEmpty {
                resolvedZone = SnapZoneHitTesting.nearest(
                    dropZoneFrames.map { (zone: $0.key, frame: $0.value) },
                    to: finalLocation
                ) { $0.frame }?.zone
                    ?? result.fallbackZone
            } else if result.finalLocation != nil, !allowUnresolvedTarget {
                completedFileDrops[nextFileDropSequenceToRoute] = result
                scheduleDropZoneResolutionFallback()
                break
            } else {
                resolvedZone = result.fallbackZone
            }

            nextFileDropSequenceToRoute &+= 1
            dragState.didJustDrop = true
            NotificationCenter.default.post(name: .fileDropFlowCompleted, object: nil)

            switch resolvedZone {
            case .shelf:
                FileShelfManager.shared.addFiles(from: result.copiedURLs)
                navigationStack = [.fileShelf]
            case .airdrop:
                SharingManager.shared.share(items: result.copiedURLs, via: .sendViaAirDrop)
                navigationStack = []
            case .device(let peerID):
                ContinuityManager.shared.sendFiles(result.copiedURLs, toPeerID: peerID)
                navigationStack = []
            case nil:
                if result.wasDraggedFromShelf {
                    navigationStack = []
                } else {
                    FileShelfManager.shared.addFiles(from: result.copiedURLs)
                    navigationStack = [.fileShelf]
                }
            }
        }

        awaitingDropCompletion = !pendingFileDropSequences.isEmpty || !completedFileDrops.isEmpty
        if !awaitingDropCompletion,
           !dragState.didJustDrop,
           !isFileDragSessionInProgress,
           !isFileDropTargeted,
           navigationStack.last == .fileShelfLanding,
           !isPinned {
            notchState = isLiveActivityActive ? .autoExpanded : .initial
        }
    }

    private func handleDropZoneFramesChange(_ frames: [DropZone: CGRect]) {
        dropZoneFrames = frames
        guard !frames.isEmpty else { return }
        dropZoneResolutionTask?.cancel()
        dropZoneResolutionTask = nil
        routeCompletedFileDropsInOrder()
    }

    private func scheduleDropZoneResolutionFallback() {
        guard dropZoneResolutionTask == nil else { return }
        dropZoneResolutionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            dropZoneResolutionTask = nil
            routeCompletedFileDropsInOrder(allowUnresolvedTarget: true)
        }
    }

    private func handleDragActivationChange(isDragging: Bool) async {
        collapseTask?.cancel()
        isCollapseTimerActive = false

        if isDragging {
            guard !shouldSuppressSnapZoneActivation else { return }
            if isPinned {
                isPinned = false
            }

            dragState.didJustDrop = false

            if isFileDropTargeted {
                notchState = .clickExpanded
                navigationStack = [.fileShelfLanding]

            } else {
                if settings.settings.snapDragEnabled {
                    self.navigationStack = [.snapZones]
                    notchState = .clickExpanded
                }
            }

        } else {
            guard navigationStack.last == .snapZones else { return }
            try? await Task.sleep(for: .milliseconds(50))
            (NSApp.delegate as? AppDelegate)?.revertNotchWindowFocus()

            if dragState.didJustDrop {
                return
            }

            if awaitingDropCompletion {
                return
            }

            if isFileDropTargeted || isFileDragSessionInProgress {
                return
            }

            self.notchState = isLiveActivityActive ? .autoExpanded : .initial
        }
    }

    private func handleWindowDragChange(isDragging: Bool) {
        collapseTask?.cancel()
        isCollapseTimerActive = false

        if isDragging {
            dragEndCollapseTask?.cancel()
            dragEndCollapseTask = nil
            if isPinned {
                isPinned = false
            }

            self.navigationStack = [.snapZones]
            if notchState != .clickExpanded {
                notchState = .clickExpanded
            }

        } else {
            (NSApp.delegate as? AppDelegate)?.revertNotchWindowFocus()

            guard navigationStack.last == .snapZones else { return }
            dragEndCollapseTask?.cancel()
            dragEndCollapseTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled,
                      !isPinned,
                      !isHovered,
                      !dragManager.isDraggingInActivationZone,
                      !isFileDropTargeted,
                      !isFileDragSessionInProgress,
                      navigationStack.last == .snapZones else { return }
                notchState = isLiveActivityActive ? .autoExpanded : .initial
                dragEndCollapseTask = nil
            }
        }
    }

    private func handleFileDropTargetChange(isTargeted: Bool) {
        guard isTargeted, cursorIsOnMyScreen else { return }
        presentFileDragLanding()
    }

    private func presentFileDragLanding() {
        collapseTask?.cancel()
        collapseTask = nil
        isCollapseTimerActive = false
        dragEndCollapseTask?.cancel()
        dragEndCollapseTask = nil
        SnapPreviewManager.shared.hidePreview()
        if navigationStack.last != .fileShelfLanding {
            navigationStack = [.fileShelfLanding]
        }
        if notchState != .clickExpanded {
            notchState = .clickExpanded
        }
    }

    private func handleSizeChange(_ newSize: CGSize, for state: NotchState) {
        guard config != nil else { return }
        if state == .clickExpanded && notchState == .clickExpanded {
            guard newSize.width > 1 && newSize.height > 1 else { return }
            let minimumWidth = currentMode == .defaultWidgets ? notchIconsIntrinsicWidth : 0
            let targetWidth = max(newSize.width, minimumWidth)
            guard abs(targetWidth - animatedWidth) > 1 || abs(newSize.height - animatedHeight) > 1 else { return }
            withAnimation(self.expansionAnimation) {
                animatedWidth = targetWidth
                animatedHeight = newSize.height
            }
            syncNotchHostWindowHeight(contentHeight: newSize.height)

        } else if state == .autoExpanded {
            updateAutoContentSize()
        }
    }

    private func applyNotchIconsWidthFloor() {
        guard notchState == .clickExpanded, currentMode == .defaultWidgets else { return }
        let targetWidth = max(animatedWidth, notchIconsIntrinsicWidth)
        guard abs(targetWidth - animatedWidth) > 1 else { return }
        withAnimation(self.expansionAnimation) {
            animatedWidth = targetWidth
        }
    }

    private func handleShowLyricsChange(newValue: Bool) {
        if newValue {
            navigationStack.append(.musicLyrics)
            DispatchQueue.main.async { self.showLyrics = false }
        }
    }

    private func handleTrackpadSwipe(vector: CGVector) {
        guard !isCalendarHovered else {
            return
        }
        guard let config = config else { return }

        if isManuallyHidden {
            return
        }

        guard Date() >= revealSettlingUntil else { return }

        let isCollapsed = notchState == .initial || notchState == .hoverExpanded
        let isSwipeUp = vector.dy < 0

        if settings.settings.swipeToHideNotch, isCollapsed {
            let verticalThreshold: CGFloat = 10.0
            let isVertical = abs(vector.dy) > abs(vector.dx) && abs(vector.dy) > verticalThreshold
            if isVertical, isSwipeUp {
                haptic()
                hideNotchCompletely(reason: .manualSwipe)
                return
            }
        }

        if isCollapsed {
            let verticalThreshold: CGFloat = 10.0
            if abs(vector.dy) > abs(vector.dx) && abs(vector.dy) > verticalThreshold {
                if settings.settings.swipeToHideNotch, isSwipeUp {
                    return
                }
                guard !shouldBlockNotchExpansionWhileLocked else { return }
                haptic()
                self.expansionAnimation = config.swipeOpenAnimation
                measuredClickContentSize = .zero
                navigationStack = [.defaultWidgets]
                notchState = .clickExpanded
                return
            }
        }
        else if notchState == .clickExpanded {
            guard currentMode != .nearDrop else {
                return
            }

            let allowsMenuSwitch = settings.settings.swipeToSwitchWidgets
                && navigationStack.count <= 1
                && (currentMode == .defaultWidgets || currentMode == .fileShelf)

            if allowsMenuSwitch, abs(vector.dx) > abs(vector.dy) && abs(vector.dx) > 10 {
                haptic()
                let isSwipeRight = vector.dx > 0
                let invertGestures = settings.settings.invertMusicGestures

                let isLogicalBackward = (isSwipeRight && !invertGestures) || (!isSwipeRight && invertGestures)

                if isLogicalBackward {
                    if navigationStack.count > 1 {
                        navigationStack.removeLast()
                    } else if currentMode == .fileShelf {
                        navigationStack = [.defaultWidgets]
                    }
                } else {
                    if currentMode == .defaultWidgets {
                        navigationStack.append(.fileShelf)
                    } else if currentMode == .fileShelf {
                        navigationStack = [.defaultWidgets]
                    }
                }
                return
            }
        }

        guard isLiveActivityActive && (notchState == .autoExpanded || notchState == .hoverExpanded) else { return }

        if abs(vector.dx) > abs(vector.dy) {
            if liveActivityManager.currentActivity == .music {
                let isSwipeRight = vector.dx > 0
                let invert = settings.settings.invertMusicGestures
                let shouldSkipForward = (isSwipeRight && !invert) || (!isSwipeRight && invert)
                let shouldGoBackward = (!isSwipeRight && !invert) || (isSwipeRight && invert)

                if shouldSkipForward && settings.settings.swipeToSkipMusic {
                    haptic()
                    MusicManager.shared.transientIcon = .skippedForward
                    Task { await MusicManager.shared.nextTrack() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if MusicManager.shared.transientIcon == .skippedForward { MusicManager.shared.transientIcon = nil }
                    }
                } else if shouldGoBackward && settings.settings.swipeToRewindMusic {
                    haptic()
                    MusicManager.shared.transientIcon = .skippedBackward
                    Task { await MusicManager.shared.previousTrack() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if MusicManager.shared.transientIcon == .skippedBackward { MusicManager.shared.transientIcon = nil }
                    }
                }
            } else if settings.settings.swipeToDismissLiveActivity {
                haptic()
                liveActivityManager.dismissCurrentActivity()
            }
        }
    }

    private func hideNotchCompletely(reason: NotchCompleteHideReason) {
        switch reason {
        case .manualSwipe:
            guard settings.settings.swipeToHideNotch else { return }
        case .inactive:
            guard shouldHideWhenInactive else { return }
            guard !inactiveHideUserOverride else { return }
        }
        guard completeHideReason == nil else {
            completeHideReason = reason
            return
        }

        notchLog.info("hideNotchCompletely: displayID=\(notchDisplayID.map(String.init) ?? "nil", privacy: .public) reason=\(String(describing: reason), privacy: .public)")
        completeHideReason = reason
        if reason == .manualSwipe {
            inactiveHideUserOverride = false
        }
        isPinned = false
        isHovered = false
        collapseTask?.cancel()
        isCollapseTimerActive = false
        cancelHoverExpandTask()
        cancelWidgetSwitchProtection()
        navigationStack = [.defaultWidgets]
        notchState = .initial
        TrackpadGestureHandler.shared.stopMonitoring()

        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
            animatedWidth = 0
            animatedHeight = 0
            shadowOpacity = 0
        }
        if let dynamicWindow = notchWindow as? DynamicFocusWindow {
            dynamicWindow.setMouseEventHandlingEnabled()
        } else {
            notchWindow?.ignoresMouseEvents = true
        }
        notchWindow?.alphaValue = 0
        syncNotchHostWindowHeight(contentHeight: 0)
        if let runtimeStateSource {
            NotchRuntimeState.shared.update(
                source: runtimeStateSource,
                isUserNear: false,
                isExpanded: false
            )
        }
        startHiddenNotchSwipeMonitor()
    }

    private func revealNotchFromCompleteHide() {
        guard completeHideReason != nil else { return }
        let wasManualSwipeReveal = completeHideReason == .manualSwipe
        notchLog.info("revealNotchFromCompleteHide: displayID=\(notchDisplayID.map(String.init) ?? "nil", privacy: .public) previousReason=\(completeHideReason.map { "\($0)" } ?? "nil", privacy: .public) effectiveActivity=\(String(describing: effectiveActivity), privacy: .public) currentActivity=\(String(describing: liveActivityManager.currentActivity), privacy: .public) swipeOverride=\(inactiveHideUserOverride, privacy: .public)")
        completeHideReason = nil
        stopHiddenNotchSwipeMonitor()
        if let dynamicWindow = notchWindow as? DynamicFocusWindow {
            dynamicWindow.setMouseEventHandlingEnabled()
        }
        notchWindow?.alphaValue = 1
        if wasManualSwipeReveal {
            revealSettlingUntil = Date().addingTimeInterval(Self.revealSettlingInterval)
            suppressHoverAfterReveal = true
        }
        guard let config else { return }

        let hasActivity = effectiveActivity != .none
        if hasActivity, notchState != .clickExpanded {
            notchState = .autoExpanded
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                animatedWidth = config.initialSize.width
                animatedHeight = config.initialSize.height
            }
            syncNotchHostWindowHeight(contentHeight: config.initialSize.height)
        }
        updateMouseEventHandling(isInteractive: isInteractive)
    }

    private var shouldHideWhenInactive: Bool {
        let displayID = notchWindow?.screen?.displayIdentifier
        return settings.settings.resolvedHideNotchWhenInactive(forDisplayID: displayID)
    }

    private func evaluateInactiveNotchVisibility() {
        if liveActivityManager.currentActivity == .lockScreen { return }
        let hideWhenInactive = shouldHideWhenInactive
        let evaluation = (hideWhenInactive, completeHideReason)
        if lastInactiveVisibilityEvaluation?.hideWhenInactive != evaluation.0
            || lastInactiveVisibilityEvaluation?.hideReason != evaluation.1 {
            notchLog.info("evaluateInactiveNotchVisibility: displayID=\(notchDisplayID.map(String.init) ?? "nil", privacy: .public) shouldHideWhenInactive=\(hideWhenInactive) completeHideReason=\(completeHideReason.map { "\($0)" } ?? "nil") effectiveActivity=\(effectiveActivity.rawValue, privacy: .public)")
            lastInactiveVisibilityEvaluation = evaluation
        }
        guard hideWhenInactive else { return }
        if completeHideReason == .manualSwipe { return }

        let hasActivity = effectiveActivity != .none
        let isBusy = notchState == .clickExpanded
            || isPinned
            || isHovered
            || dragManager.isDraggingInActivationZone
            || windowDrag.isDragging

        if hasActivity {
            inactiveHideUserOverride = false
            if completeHideReason == .inactive {
                revealNotchFromCompleteHide()
            }
            return
        }

        guard !isBusy else { return }
        guard !inactiveHideUserOverride else { return }

        if completeHideReason == nil, notchState == .initial || notchState == .hoverExpanded {
            hideNotchCompletely(reason: .inactive)
        }
    }

    private func startHiddenNotchSwipeMonitor() {
        guard let displayID = notchDisplayID else { return }
        HiddenNotchRevealMonitor.shared.start(displayID: displayID)
    }

    private func stopHiddenNotchSwipeMonitor() {
        guard let displayID = notchDisplayID else { return }
        HiddenNotchRevealMonitor.shared.stop(displayID: displayID)
    }

    private static let revealedIdleRehideDelay: Duration = .seconds(3)

    private func scheduleInactiveRehideAfterReveal() {
        inactiveRehideTask?.cancel()
        inactiveRehideTask = Task { @MainActor in
            try? await Task.sleep(for: Self.revealedIdleRehideDelay)
            guard !Task.isCancelled else { return }
            releaseInactiveHideOverrideIfIdle()
        }
    }

    private func releaseInactiveHideOverrideIfIdle() {
        guard inactiveHideUserOverride else {
            evaluateInactiveNotchVisibility()
            return
        }
        guard !isHovered,
              !isPinned,
              notchState != .clickExpanded,
              !dragManager.isDraggingInActivationZone,
              !windowDrag.isDragging else { return }
        notchLog.info("Releasing swipe-reveal override on displayID=\(notchDisplayID.map(String.init) ?? "nil", privacy: .public)")
        inactiveHideUserOverride = false
        evaluateInactiveNotchVisibility()
    }

    private func openMusicHub(mode: NotchWidgetMode) {
        measuredClickContentSize = .zero
        navigationStack = [mode]
        notchState = .clickExpanded
    }

    private func openBlipHub() {
        measuredClickContentSize = .zero
        navigationStack = [.blipHub]
        notchState = .clickExpanded
        (NSApp.delegate as? AppDelegate)?.makeNotchWindowFocusable()
    }

    private func openCircleToSearch(object: String?) {
        measuredClickContentSize = .zero
        switch object {
        case "askBlip":
            navigationStack = [.agentS]
        case "askBlipMissingKey":
            navigationStack = [.geminiApiKeysMissing]
        default:
            navigationStack = [.circleToSearch]
        }
        notchState = .clickExpanded
        (NSApp.delegate as? AppDelegate)?.makeNotchWindowFocusable()
    }

    private func handleTrackpadTwoFingerTap() {
        guard (notchState == .autoExpanded || notchState == .hoverExpanded) else { return }

        if liveActivityManager.currentActivity == .microphone && settings.settings.microphoneLiveActivityEnabled && settings.settings.microphoneLiveActivityBehavior == .iconAndGesture {
            haptic()
            MicrophoneUsageManager.shared.toggleMute()
            return
        }

        if liveActivityManager.cycleSportsActivity() {
            haptic()
            return
        }

        if settings.settings.twoFingerTapToPauseMusic {
            haptic()
            MusicManager.shared.transientIcon = MusicManager.shared.isPlaying ? .paused : .played
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if MusicManager.shared.transientIcon == .paused || MusicManager.shared.transientIcon == .played {
                    MusicManager.shared.transientIcon = nil
                }
            }
            Task {
                if MusicManager.shared.isPlaying {
                    await MusicManager.shared.pause()
                } else {
                    await MusicManager.shared.play()
                }
            }
        }
    }

    // MARK: - Helper Methods
    private func startNotchInteractionMonitoring() {
        guard let window = notchWindow else { return }

        let monitor = hoverMonitor ?? NotchHoverMonitor()
        hoverMonitor = monitor
        monitor.start(
            window: window,
            handlers: NotchHoverMonitorHandlers(
                onPointerEvent: { refreshNotchInteractionState() },
                onMouseDrag: { isInside, location in
                    handleProbeMouseDrag(isInside: isInside, screenLocation: location)
                },
                onMouseDragEnded: { location in
                    handleProbeMouseDragEnded(at: location)
                },
                onFileDrag: { isTargeted, location in
                    handleProbeFileDrag(isTargeted: isTargeted, screenLocation: location)
                },
                onFileDragEnded: { location, dropWasAccepted in
                    handleProbeFileDragEnded(
                        at: location,
                        dropWasAccepted: dropWasAccepted
                    )
                },
                onFileDrop: { urls, location in
                    handleFileDrop(urls: urls, at: location)
                }
            )
        )
        refreshNotchInteractionState()
    }

    private func stopNotchInteractionMonitoring() {
        hoverMonitor?.stop()
        hoverMonitor = nil
        activeSnapZone = nil
        activeDropZone = nil
        notchDragLocationState.update(nil)
        dropZoneFrames = [:]
        snapZoneHitRegions = []
        isFileDropTargeted = false
        isFileDragSessionInProgress = false
        activeFileDragIsFromShelf = false
        routeCompletedFileDropsInOrder(allowUnresolvedTarget: true)
        isHandlingActiveWindowDrag = false
        lastSampledMouseLocation = nil
        lastPublishedInteractiveFrame = .null
    }

    private func handleProbeMouseDrag(isInside: Bool, screenLocation: NSPoint) {
        if isInside {
            dragEndCollapseTask?.cancel()
            dragEndCollapseTask = nil
        }
        if windowDrag.isDragging,
           settings.settings.snapOnWindowDragEnabled,
           !shouldSuppressSnapZoneActivation {
            let isOnThisScreen = notchWindow?.screen?.frame.contains(screenLocation) ?? cursorIsOnMyScreen
            if isOnThisScreen, !isHandlingActiveWindowDrag {
                isHandlingActiveWindowDrag = true
                handleWindowDragChange(isDragging: true)
            } else if !isOnThisScreen, isHandlingActiveWindowDrag {
                isHandlingActiveWindowDrag = false
                handleWindowDragChange(isDragging: false)
            }
        }
        if windowDrag.isDragging, shouldSuppressSnapZoneActivation {
            dragManager.cancelActivation()
            return
        }
        if isInside || isHandlingActiveWindowDrag || navigationStack.last == .snapZones {
            updateNotchDragLocation(from: screenLocation)
        }
        guard settings.settings.snapDragEnabled else {
            dragManager.cancelActivation()
            return
        }
        dragManager.updateDrag(
            isInsideActivationZone: isInside || isNearNotchForSnapActivation(screenLocation)
        )
    }

    private static let snapActivationOutset = CGSize(width: 140, height: 70)
    private static let snapActivationRetainOutset = CGSize(width: 220, height: 130)

    private func isNearNotchForSnapActivation(_ screenLocation: NSPoint) -> Bool {
        guard let window = notchWindow, let config else { return false }
        if let screenFrame = window.screen?.frame, !screenFrame.contains(screenLocation) {
            return false
        }
        let notchFrame = window.convertToScreen(interactiveFrame(for: window, config: config))
        guard !notchFrame.isEmpty else { return false }
        let outset = dragManager.isActivationPending
            ? Self.snapActivationRetainOutset
            : Self.snapActivationOutset
        return notchFrame
            .insetBy(dx: -outset.width, dy: -outset.height)
            .contains(screenLocation)
    }

    private func handleProbeMouseDragEnded(at screenLocation: NSPoint) {
        let finalLocation = updateNotchDragLocation(from: screenLocation)
        let wasShowingSnapZones = navigationStack.last == .snapZones
        let finalSnapZone: SnapZone?
        if !wasShowingSnapZones {
            finalSnapZone = nil
        } else if let finalLocation, !snapZoneHitRegions.isEmpty {
            finalSnapZone = SnapZoneHitTesting.nearest(snapZoneHitRegions, to: finalLocation) { $0.frame }?.zone
        } else {
            finalSnapZone = activeSnapZone
        }

        if let finalSnapZone {
            SnappingManager.snap(zone: finalSnapZone)
        }
        activeSnapZone = nil
        notchDragLocationState.update(nil)
        dragManager.endDrag()

        guard wasShowingSnapZones else { return }
        dragEndCollapseTask?.cancel()
        dragEndCollapseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled,
                  !isPinned,
                  !isFileDropTargeted,
                  !isFileDragSessionInProgress,
                  navigationStack.last == .snapZones else { return }
            notchState = isLiveActivityActive ? .autoExpanded : .initial
            dragEndCollapseTask = nil
        }
    }

    private func handleProbeFileDrag(isTargeted: Bool, screenLocation: NSPoint) {
        if isTargeted {
            dragEndCollapseTask?.cancel()
            dragEndCollapseTask = nil
        }
        updateNotchDragLocation(from: screenLocation)
        dragManager.cancelActivation()

        if isTargeted, !isFileDragSessionInProgress {
            isFileDragSessionInProgress = true
            activeFileDragIsFromShelf = dragState.isDraggingFromShelf
            displayedFileDragMode = activeFileDragIsFromShelf ? .existingFile : .newFile
            dragState.didJustDrop = false
        }
        if isFileDropTargeted != isTargeted {
            isFileDropTargeted = isTargeted
        }
        if isTargeted {
            presentFileDragLanding()
        }
    }

    private func handleProbeFileDragEnded(
        at screenLocation: NSPoint,
        dropWasAccepted: Bool
    ) {
        updateNotchDragLocation(from: screenLocation)

        isFileDropTargeted = false
        isFileDragSessionInProgress = false
        activeDropZone = nil
        activeSnapZone = nil
        notchDragLocationState.update(nil)
        dragManager.cancelActivation()
        routeCompletedFileDropsInOrder()
        activeFileDragIsFromShelf = false

        guard !dropWasAccepted,
              navigationStack.last == .fileShelfLanding,
              !isPinned else { return }
        notchState = isLiveActivityActive ? .autoExpanded : .initial
    }

    @discardableResult
    private func updateNotchDragLocation(from screenLocation: NSPoint) -> CGPoint? {
        guard let window = notchWindow, let contentView = window.contentView else { return nil }
        let windowPoint = window.convertPoint(fromScreen: screenLocation)
        let swiftUILocation = CGPoint(
            x: windowPoint.x,
            y: contentView.bounds.height - windowPoint.y
        )
        notchDragLocationState.update(swiftUILocation)
        return swiftUILocation
    }

    private func refreshNotchInteractionState() {
        guard let config = config, let window = notchWindow else { return }

        if isManuallyHidden {
            if isHovered { isHovered = false }
            updateMouseEventHandling(isInteractive: false)
            return
        }

        let mouseLocation = window.mouseLocationOutsideOfEventStream
        let interactiveBounds = interactiveFrame(for: window, config: config)
        let isNear = isMouseNearNotchFrame(interactiveBounds, mouseLocation: mouseLocation)
        if let runtimeStateSource {
            NotchRuntimeState.shared.update(source: runtimeStateSource, isUserNear: isNear)
        }
        let detectionBounds = interactiveBounds.insetBy(
            dx: -Self.hoverDetectionMargin,
            dy: -Self.hoverDetectionMargin
        )
        let isPointerInside = detectionBounds.contains(mouseLocation)

        if !isInteractive, !isNear, lastSampledMouseLocation == mouseLocation {
            return
        }

        lastSampledMouseLocation = mouseLocation

        if !isInteractive && !isNear {
            if isHovered {
                handleHover(hovering: false)
            }
            updateMouseEventHandling(isInteractive: false)
            return
        }

        if interactiveBounds != lastPublishedInteractiveFrame {
            lastPublishedInteractiveFrame = interactiveBounds
        }

        if suppressHoverAfterReveal, !isPointerInside {
            suppressHoverAfterReveal = false
        }

        if isPointerInside != isHovered, !dragManager.isDraggingInActivationZone, !windowDrag.isDragging {
            if !isPointerInside, notchState == .clickExpanded, widgetSwitchProtectionTask != nil {
                return
            }
            handleHover(hovering: isPointerInside)
        }

        updateMouseEventHandling(isInteractive: isInteractive || isPointerInside)
    }

    private func updateRuntimeExpansionState() {
        guard let runtimeStateSource else { return }
        NotchRuntimeState.shared.update(
            source: runtimeStateSource,
            isExpanded: notchState != .initial && !isManuallyHidden
        )
    }

    private func isMouseNearNotchFrame(_ notchFrame: CGRect, mouseLocation: CGPoint) -> Bool {
        guard !notchFrame.isEmpty else { return false }
        let proximityFrame = notchFrame.insetBy(
            dx: -Self.hoverProximityMargin,
            dy: -Self.hoverProximityMargin
        )
        return proximityFrame.contains(mouseLocation)
    }

    private func interactiveFrame(for window: NSWindow, config: ResolvedNotchConfiguration) -> CGRect {
        if isManuallyHidden { return .zero }

        let contentBounds = window.contentView?.bounds ?? .zero
        guard !contentBounds.isEmpty else { return .zero }

        let notchWidth: CGFloat
        let notchHeight: CGFloat
        switch notchState {
        case .initial:
            notchWidth = config.initialSize.width
            notchHeight = config.initialSize.height
        case .hoverExpanded, .autoExpanded, .clickExpanded:
            notchWidth = animatedWidth
            notchHeight = animatedHeight
        }

        let topInset = config.topInset - config.topBuffer
        let frame = CGRect(
            x: contentBounds.midX - (notchWidth / 2),
            y: contentBounds.maxY - notchHeight - topInset,
            width: notchWidth,
            height: notchHeight
        ).integral

        return frame.insetBy(dx: -1, dy: -1)
    }

    private func toRestorableMenu(mode: NotchWidgetMode) -> RestorableNotchMenu? {
        switch mode {
        case .defaultWidgets: return .defaultWidgets
        case .musicPlayer: return .musicPlayer
        case .musicQueueAndPlaylists: return .musicQueueAndPlaylists
        case .musicDevices: return .musicDevices
        case .nearDrop: return .nearDrop
        case .fileShelf: return .fileShelf
        case .multiAudio: return .multiAudio
        case .weatherPlayer: return .weatherPlayer
        case .calendarPlayer: return .calendarPlayer
        case .timerDetailView: return .timerDetailView
        case .sportsPlayer: return .sportsPlayer
        case .financePlayer: return .financePlayer
        case .shopifyOrders: return nil
        case .notesPlayer: return .notesPlayer
        case .clipboardPlayer: return .clipboardPlayer
        case .mirrorPlayer: return nil
        case .musicApiKeysMissing, .geminiApiKeysMissing, .musicLoginPrompt, .musicLyrics,
                .musicPlaylistDetail, .musicArtistDetail, .musicAlbumDetail, .snapZones, .fileShelfLanding, .fileActionPreview,
                .multiAudioDeviceAdjust, .multiAudioAppEQ, .multiAudioApp8D, .multiAudioAppSurround, .multiAudioEQ, .dragActivated,
                .agentS, .blipHub, .circleToSearch, .updateAvailable, .focusSessionDetailView, .batteryDetailView,
                .storageDetailView, .continuityDetail, .continuityActivityDetail:
            return nil
        }
    }

    private func updateRadiiForCurrentState(state: NotchState) {
        guard let config = config else { return }
        let hasBottom = liveActivityManager.activityHasBottomContent

        switch state {
        case .initial:
            animatedCornerRadius = config.initialCornerRadius
            animatedBottomCornerRadius = config.initialCornerRadius
        case .hoverExpanded:
            if isLiveActivityActive {
                animatedCornerRadius = config.autoExpandedCornerRadius + (hasBottom ? 10 : 0)
                if case .full(_, _, let customRadius) = liveActivityManager.activityContent {
                    animatedBottomCornerRadius = customRadius ?? (hasBottom ? config.liveActivityBottomCornerRadius : animatedCornerRadius)
                } else {
                    animatedBottomCornerRadius = hasBottom ? config.liveActivityBottomCornerRadius : animatedCornerRadius
                }
            } else {
                animatedCornerRadius = config.initialCornerRadius
                animatedBottomCornerRadius = config.initialCornerRadius
            }
        case .clickExpanded:
            animatedCornerRadius = config.clickExpandedCornerRadius
            animatedBottomCornerRadius = config.clickExpandedCornerRadius
        case .autoExpanded:
            animatedCornerRadius = config.autoExpandedCornerRadius + (hasBottom ? 10 : 0)
            if case .full(_, _, let customRadius) = liveActivityManager.activityContent {
                animatedBottomCornerRadius = customRadius ?? (hasBottom ? config.liveActivityBottomCornerRadius : animatedCornerRadius)
            } else {
                animatedBottomCornerRadius = hasBottom ? config.liveActivityBottomCornerRadius : animatedCornerRadius
            }
        }
    }

    private func updateAutoContentSize() {
        guard let config = config, notchState == .autoExpanded || (notchState == .hoverExpanded && isLiveActivityActive) else { return }
        let scale = activeScaleFactor
        let targetWidth = measuredAutoContentSize.width * scale
        let targetHeight = measuredAutoContentSize.height * scale
        let epsilon: CGFloat = 0.5

        guard targetWidth > 0 && targetHeight > 0,
              (abs(targetWidth - animatedWidth) > epsilon || abs(targetHeight - animatedHeight) > epsilon) else { return }

        let currentActivityType = liveActivityManager.currentActivity
        let isExemptFromBlur = reduceMotion
            || currentActivityType == .music || currentActivityType == .systemHUD
            || Date() < activitySwitchBlurWindowEnd

        if !isExemptFromBlur {
            withAnimation(.easeIn(duration: config.activityBlurUpdateDelay)) { activityBlurRadius = 15 }
        }

        withAnimation(config.activityToActivityAnimation) {
            animatedWidth = targetWidth
            animatedHeight = targetHeight
        }

        if !isExemptFromBlur {
            blurRemovalTask?.cancel()
            blurRemovalTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(config.autoContentRenderDelay))
                guard !Task.isCancelled else { return }
                withAnimation(config.blurRemovalAnimation) { self.activityBlurRadius = 0 }
            }
        } else if Date() >= activitySwitchBlurWindowEnd {
            blurRemovalTask?.cancel()
            blurRemovalTask = nil
            activityBlurRadius = 0
        }
    }

    private func updateMouseEventHandling(isInteractive: Bool) {
        guard let window = notchWindow else { return }

        if isManuallyHidden {
            if let dynamicWindow = window as? DynamicFocusWindow {
                dynamicWindow.setMouseEventHandlingEnabled()
            } else {
                window.ignoresMouseEvents = true
            }
            hoverMonitor?.update(hoverRect: .null, pointerIsInside: false)
            return
        }

        let pointerIsInInteractionBounds: Bool
        if let config {
            let frame = interactiveFrame(for: window, config: config)
                .insetBy(dx: -Self.hoverDetectionMargin, dy: -Self.hoverDetectionMargin)
            pointerIsInInteractionBounds = frame.contains(window.mouseLocationOutsideOfEventStream)
        } else {
            pointerIsInInteractionBounds = false
        }
        let shouldReceiveMouseEvents = isInteractive
            && isPointerInteractionActive
            && (pointerIsInInteractionBounds || isPointerCaptureActive)
        if let dynamicWindow = window as? DynamicFocusWindow {
            dynamicWindow.setMouseEventHandlingEnabled(shouldReceiveMouseEvents)
        } else if window.contentView != nil {
            window.ignoresMouseEvents = !shouldReceiveMouseEvents
        }

        if let config {
            let frame = interactiveFrame(for: window, config: config)
            hoverMonitor?.update(
                hoverRect: frame.insetBy(dx: -Self.hoverDetectionMargin, dy: -Self.hoverDetectionMargin),
                pointerIsInside: isHovered
            )
        }
    }

    private func updateWindowSharingBehavior(shouldBeHidden: Bool) {
        guard let window = notchWindow else { return }
        let desired: NSWindow.SharingType = shouldBeHidden ? .none : .readOnly
        if window.sharingType != desired {
            window.sharingType = desired
        }
    }

    private func syncNotchHostWindowHeight(contentHeight: CGFloat) {
        (NSApp.delegate as? AppDelegate)?.updateNotchHostWindowHeight(requiredContentHeight: contentHeight)
    }

    private func handlePopoverPresentation(owner: UUID, isPresented: Bool) {
        let wasHolding = popoverPresentation.holdsExpansion
        popoverPresentation.setPresented(isPresented, owner: owner)
        if isPresented {
            collapseTask?.cancel()
            collapseTask = nil
            isCollapseTimerActive = false
        } else if wasHolding && !popoverPresentation.holdsExpansion {
            refreshNotchInteractionState()
            // 弹窗打开时已记录 hover=false，关闭时不会再出现一次离开事件。
            // 即使鼠标还在宽缓冲区内，也恢复 clickExpanded 的正常离开行为。
            if notchState == .clickExpanded && !isHovered {
                scheduleCollapse(after: 0)
            } else {
                evaluateCollapseIfCursorOutsideHoverZone()
            }
        }
    }

    private func handleClickExpandedHoverOut(config: ResolvedNotchConfiguration) {
        guard !isPinned, !popoverPresentation.holdsExpansion else { return }
        guard widgetSwitchProtectionTask == nil else { return }
        scheduleCollapse(after: 0)
    }

    private func startWidgetSwitchProtection() {
        widgetSwitchProtectionTask?.cancel()
        widgetSwitchSettleTask?.cancel()
        widgetSwitchProtectionGeneration &+= 1
        let generation = widgetSwitchProtectionGeneration

        widgetSwitchProtectionTask = Task { @MainActor in
            defer {
                if generation == self.widgetSwitchProtectionGeneration {
                    self.widgetSwitchProtectionTask = nil
                }
            }
            try? await Task.sleep(for: .seconds(Self.widgetSwitchProtectionDuration))
            guard !Task.isCancelled else { return }
            guard generation == self.widgetSwitchProtectionGeneration else { return }
            self.evaluateCollapseIfCursorOutsideHoverZone()
        }
        scheduleWidgetSwitchSettledCheck()
    }

    private func scheduleWidgetSwitchSettledCheck() {
        guard widgetSwitchProtectionTask != nil else { return }
        widgetSwitchSettleTask?.cancel()
        let generation = widgetSwitchProtectionGeneration
        widgetSwitchSettleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled,
                  generation == self.widgetSwitchProtectionGeneration,
                  let window = self.notchWindow,
                  let config = self.config else { return }
            let hoverBounds = self.interactiveFrame(for: window, config: config)
                .insetBy(dx: -Self.hoverCollapseMargin, dy: -Self.hoverCollapseMargin)
            guard hoverBounds.contains(window.mouseLocationOutsideOfEventStream) else { return }
            self.widgetSwitchProtectionTask?.cancel()
            self.widgetSwitchProtectionTask = nil
            self.widgetSwitchSettleTask = nil
        }
    }

    private func cancelWidgetSwitchProtection() {
        widgetSwitchProtectionGeneration &+= 1
        widgetSwitchProtectionTask?.cancel()
        widgetSwitchProtectionTask = nil
        widgetSwitchSettleTask?.cancel()
        widgetSwitchSettleTask = nil
    }

    private func evaluateCollapseIfCursorOutsideHoverZone() {
        guard let window = notchWindow, let config = config, !isPinned,
              !popoverPresentation.holdsExpansion else { return }
        let mouseLocation = window.mouseLocationOutsideOfEventStream
        let interactiveBounds = interactiveFrame(for: window, config: config)
        let hoverBounds = notchState == .initial
            ? interactiveBounds
            : interactiveBounds.insetBy(dx: -Self.hoverCollapseMargin, dy: -Self.hoverCollapseMargin)
        guard !hoverBounds.contains(mouseLocation) else { return }
        guard !dragManager.isDraggingInActivationZone && !windowDrag.isDragging else { return }
        scheduleCollapse(after: 0)
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        collapseTask?.cancel()
        collapseTask = nil
        guard !isPinned,
              !popoverPresentation.holdsExpansion,
              !isFileDropTargeted,
              !isFileDragSessionInProgress,
              !awaitingDropCompletion else {
            isCollapseTimerActive = false
            return
        }
        isCollapseTimerActive = true
        collapseTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                guard !Task.isCancelled else { return }
                if !self.popoverPresentation.holdsExpansion
                    && !self.isHovered
                    && !self.dragManager.isDraggingInActivationZone
                    && !self.windowDrag.isDragging
                    && !self.isFileDropTargeted
                    && !self.isFileDragSessionInProgress
                    && !self.awaitingDropCompletion {
                    self.notchState = isLiveActivityActive ? .autoExpanded : .initial
                    self.releaseInactiveHideOverrideIfIdle()
                }
                self.isCollapseTimerActive = false
            } catch {
                self.isCollapseTimerActive = false
            }
        }
    }

    private func cancelHoverExpandTask() {
        hoverExpandTask?.cancel()
        hoverExpandTask = nil
    }
}

private struct NotchHUDOverlayContent: View {
    @ObservedObject private var hudManager = SystemHUDManager.shared
    @EnvironmentObject private var settings: SettingsModel

    let config: ResolvedNotchConfiguration
    let animatedWidth: CGFloat

    var body: some View {
        if let hud = hudManager.currentHUD {
            let trailingPadding = config.defaultModeIconsHorizontalPadding
            let availableWidth = max(0, animatedWidth - trailingPadding)
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    SystemHUDSlimActivityView.left(type: hud, settings: settings)
                    SystemHUDSlimActivityView.right(
                        type: hud,
                        settings: settings,
                        availableWidth: availableWidth
                    )
                }
                .padding(.trailing, trailingPadding)
            }
            .frame(height: config.initialSize.height)
        }
    }
}

enum MusicBottomContentKind: Equatable {
    case none, peek, lyrics, upNext

    init(_ contentType: MusicBottomContentType) {
        switch contentType {
        case .none: self = .none
        case .peek: self = .peek
        case .lyrics: self = .lyrics
        case .upNext: self = .upNext
        }
    }
}

enum LiveActivityAnimationKey: Equatable {
    case none
    case full(AnyHashable)
    case music(MusicBottomContentKind)
    case standard(AnyHashable)
}

enum NotchShapeSignature: Equatable {
    case none
    case full(bottomCornerRadius: CGFloat?)
    case music(MusicBottomContentKind)
    case standard
}

extension LiveActivityManager {
    var activityAnimationKey: LiveActivityAnimationKey {
        switch activityContent {
        case .none:
            return .none
        case .full(_, let id, _):
            return .full(id)
        case .standard(let data, let id):
            if case .music(let bottomContentType) = data {
                return .music(MusicBottomContentKind(bottomContentType))
            }
            return .standard(id)
        }
    }

    var notchShapeSignature: NotchShapeSignature {
        switch activityContent {
        case .none:
            return .none
        case .full(_, _, let bottomCornerRadius):
            return .full(bottomCornerRadius: bottomCornerRadius)
        case .standard(let data, _):
            if case .music(let bottomContentType) = data {
                return .music(MusicBottomContentKind(bottomContentType))
            }
            return .standard
        }
    }

    var activityHasBottomContent: Bool {
        switch activityContent {
        case .full:
            return true
        case .standard(let data, _):
            switch data {
            case .music(let bottomContentType):
                return bottomContentType != .none
            case .focusSession:
                return true
            default:
                return false
            }
        case .none:
            return false
        }
    }
}
