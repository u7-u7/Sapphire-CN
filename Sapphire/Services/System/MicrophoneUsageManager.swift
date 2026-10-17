//
//  MicrophoneUsageManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import Foundation
import Combine
import AudioToolbox
import CoreAudio
import OSLog

@MainActor
final class MicrophoneUsageManager: ObservableObject {
    static let shared = MicrophoneUsageManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "MicrophoneUsageManager")
    private let gainDefaultsKey = "SapphireMicrophoneAmplifierGain"
    private let amplifierEnabledDefaultsKey = "SapphireMicrophoneAmplifierEnabled"

    @Published private(set) var isMicInUse: Bool = false
    @Published private(set) var isMuted: Bool = false
    @Published private(set) var audioLevel: Float = 0.0
    @Published private(set) var peakLevel: Float = 0.0
    @Published private(set) var isClipping: Bool = false
    @Published var amplifierEnabled: Bool {
        didSet {
            UserDefaults.standard.set(amplifierEnabled, forKey: amplifierEnabledDefaultsKey)
            updateMeteringTap()
        }
    }
    @Published var amplifierGain: Float {
        didSet {

            amplifierGain = min(max(amplifierGain, 1.0), 4.0)
            UserDefaults.standard.set(amplifierGain, forKey: gainDefaultsKey)
            updateMeteringTap()
        }
    }

    private var defaultInputListener: AudioObjectPropertyListenerBlock?
    private var deviceRunningListeners: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]
    private var micUsageUpdateTask: Task<Void, Never>?
    private var micInactivityConfirmationTask: Task<Void, Never>?
    private var processListListener: AudioObjectPropertyListenerBlock?
    private var currentDefaultInputDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var meteringTap: MicrophoneMeteringTap?
    private var meterResetTask: Task<Void, Never>?
    private var activeBundlesObserver: NSObjectProtocol?

    private init() {
        amplifierEnabled = UserDefaults.standard.object(forKey: amplifierEnabledDefaultsKey) as? Bool ?? false
        amplifierGain = min(max(UserDefaults.standard.object(forKey: gainDefaultsKey) as? Float ?? 1.5, 1.0), 4.0)
        DispatchQueue.main.async { self.setup() }
    }

    deinit {
        var defaultAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        if let block = defaultInputListener { AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, .main, block) }
        var listAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        if let block = processListListener { AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &listAddr, .main, block) }
        for (deviceID, block) in deviceRunningListeners {
            var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            _ = AudioObjectRemovePropertyListenerBlock(deviceID, &addr, .main, block)
        }
        meteringTap?.stop()
        micInactivityConfirmationTask?.cancel()
        meterResetTask?.cancel()
        if let activeBundlesObserver {
            NotificationCenter.default.removeObserver(activeBundlesObserver)
        }
    }

    private func setup() {
        refreshMonitoredInputDevices()
        observeDefaultInputDeviceChanges()
        activeBundlesObserver = NotificationCenter.default.addObserver(forName: .multiAudioActiveBundlesDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateMicUsageState() }
        }
    }

    private func observeDefaultInputDeviceChanges() {
        var defaultAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        defaultInputListener = { [weak self] _, _ in Task { @MainActor in self?.refreshMonitoredInputDevices() } }
        if let block = defaultInputListener { AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, .main, block) }

        var listAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        processListListener = { [weak self] _, _ in Task { @MainActor in self?.scheduleMicUsageUpdate() } }
        if let block = processListListener { AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &listAddr, .main, block) }
    }

    private func refreshMonitoredInputDevices() {
        refreshDefaultInputDevice()
        let inputDevices = Self.allInputDeviceIDs()
        let monitored = Set(inputDevices)
        for deviceID in deviceRunningListeners.keys where !monitored.contains(deviceID) { removeRunningListener(for: deviceID) }
        for deviceID in inputDevices where deviceRunningListeners[deviceID] == nil { addRunningListener(for: deviceID) }
        updateMicUsageState()
    }

    private func refreshDefaultInputDevice() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr { currentDefaultInputDeviceID = deviceID }
    }

    private func addRunningListener(for deviceID: AudioDeviceID) {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in Task { @MainActor in self?.scheduleMicUsageUpdate() } }
        deviceRunningListeners[deviceID] = block
        AudioObjectAddPropertyListenerBlock(deviceID, &addr, .main, block)
    }

    private func removeRunningListener(for deviceID: AudioDeviceID) {
        guard let block = deviceRunningListeners.removeValue(forKey: deviceID) else { return }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectRemovePropertyListenerBlock(deviceID, &addr, .main, block)
    }

    private func scheduleMicUsageUpdate() {
        micUsageUpdateTask?.cancel()
        micUsageUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            self.micUsageUpdateTask = nil
            self.updateMicUsageState()
        }
    }

    private func updateMicUsageState(confirmingInactivity: Bool = false) {
        let inUse = Self.anyProcessUsingMicrophone()
        if inUse {
            micInactivityConfirmationTask?.cancel()
            micInactivityConfirmationTask = nil
            if !isMicInUse { isMicInUse = true }
        } else if isMicInUse {
            if confirmingInactivity {
                isMicInUse = false
            } else {
                confirmMicrophoneInactivity()
            }
        }
        let muteDeviceID = MultiAudioManager.shared.currentInputDeviceID ?? currentDefaultInputDeviceID
        let muted = MultiAudioManager.shared.areAllInputsMuted || (muteDeviceID != kAudioObjectUnknown && Self.readInputMuteState(of: muteDeviceID))
        if isMuted != muted { isMuted = muted }
        if !isMicInUse {
            audioLevel = 0
            peakLevel = 0
            isClipping = false
        }
        updateMeteringTap()
    }

    private func confirmMicrophoneInactivity() {
        // 进程或设备属性可能短暂不可读；复查确认停用，避免录制期间误停采样。
        guard micInactivityConfirmationTask == nil else { return }
        micInactivityConfirmationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.micInactivityConfirmationTask = nil
            self.updateMicUsageState(confirmingInactivity: true)
        }
    }

    private func updateMeteringTap() {
        guard isMicInUse, currentDefaultInputDeviceID != kAudioObjectUnknown else {
            meteringTap?.stop()
            meteringTap = nil
            return
        }
        let gain = amplifierEnabled ? amplifierGain : 1.0
        // CoreAudio 会为采样启停发送状态通知；配置未变时复用，避免反馈循环反复刷新系统隐私提示。
        if let meteringTap,
           meteringTap.deviceID == currentDefaultInputDeviceID,
           meteringTap.gain == gain {
            return
        }
        meteringTap?.stop()
        meteringTap = nil
        let tap = MicrophoneMeteringTap(deviceID: currentDefaultInputDeviceID, gain: gain) { [weak self] level, peak, clipping in
            Task { @MainActor in self?.publishMeter(level: level, peak: peak, clipping: clipping) }
        }
        guard tap.start() else { return }
        meteringTap = tap
    }

    private func publishMeter(level: Float, peak: Float, clipping: Bool) {
        audioLevel = min(max(level, 0), 1)
        peakLevel = min(max(peak, 0), 1)
        if clipping {
            isClipping = true
            meterResetTask?.cancel()
            meterResetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled else { return }
                self.isClipping = false
            }
        }
    }

    func toggleMute() { setMuted(!isMuted) }
    func setMuted(_ muted: Bool) { MultiAudioManager.shared.setAllInputMutes(muted); isMuted = muted }
    func applyExternalMuteState(_ muted: Bool) { isMuted = muted }

    private static func anyProcessUsingMicrophone() -> Bool {
        let ourBundleID = Bundle.main.bundleIdentifier
        let ourProcessID = ProcessInfo.processInfo.processIdentifier
        for objectID in allProcessObjectIDs() where processIsRunningInput(objectID) {
            let processID = readProcessID(objectID)
            let bundleID = readProcessBundleID(objectID)
            let inputDeviceNames = processInputDeviceIDs(objectID).map { CoreAudioDevices.name(of: $0) }
            guard MicrophoneUsageFilter.shouldCount(
                processID: processID,
                bundleID: bundleID,
                inputDeviceNames: inputDeviceNames,
                ownProcessID: ourProcessID,
                ownBundleID: ourBundleID
            ) else { continue }
            return true
        }
        return false
    }

    private static func allProcessObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func processIsRunningInput(_ objectID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    private static func processInputDeviceIDs(_ objectID: AudioObjectID) -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyDevices, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard !ids.isEmpty,
              AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func readProcessID(_ objectID: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var processID: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &processID) == noErr else { return nil }
        return processID
    }

    private static func readProcessBundleID(_ objectID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var bundleID: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &bundleID) == noErr,
              let bundleID else { return nil }
        let id = bundleID.takeRetainedValue() as String
        return id.isEmpty ? nil : id
    }

    private static func allInputDeviceIDs() -> [AudioDeviceID] {
        (CoreAudioDevices.all() ?? []).filter {
            CoreAudioDevices.hasChannels($0, scope: kAudioObjectPropertyScopeInput)
                && MicrophoneUsageFilter.isMicrophoneInputDevice(name: CoreAudioDevices.name(of: $0))
        }
    }

    private static func readInputMuteState(of deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var muted: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted) == noErr && muted != 0
    }
}

enum MicrophoneUsageFilter {
    private static let ignoredBundleIDPrefixes = [
        "com.apple.siri", "com.apple.Siri", "com.apple.assistant", "com.apple.audio",
        "com.apple.coreaudio", "com.apple.mediaremote", "com.apple.accessibility.heard",
        "com.apple.hearingd", "com.apple.voicebankingd", "com.apple.systemsound",
        "com.apple.speech", "com.apple.dictation", "com.apple.corespeech",
        "com.apple.CoreSpeech", "com.apple.VoiceControl", "com.apple.voicecontrol"
    ]

    static func shouldCount(
        processID: pid_t?,
        bundleID: String?,
        inputDeviceNames: [String?],
        ownProcessID: pid_t,
        ownBundleID: String?
    ) -> Bool {
        if processID == ownProcessID { return false }
        if let bundleID {
            if bundleID == ownBundleID { return false }
            if ignoredBundleIDPrefixes.contains(where: bundleID.hasPrefix) { return false }
        }
        return inputDeviceNames.contains(where: { isMicrophoneInputDevice(name: $0) })
    }

    static func isMicrophoneInputDevice(name: String?) -> Bool {
        guard let name else { return true }
        return !name.hasPrefix("Sapphire-")
    }
}

private final class MicrophoneMeteringTap {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "MicrophoneMeteringTap")
    let deviceID: AudioDeviceID
    let gain: Float
    private let callback: (Float, Float, Bool) -> Void
    private var ioProcID: AudioDeviceIOProcID?
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.sapphire.microphone-meter", qos: .userInteractive)

    init(deviceID: AudioDeviceID, gain: Float, callback: @escaping (Float, Float, Bool) -> Void) {
        self.deviceID = deviceID; self.gain = gain; self.callback = callback
    }

    func start() -> Bool {
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, deviceID, queue) { [weak self] _, inputData, _, _, _ in
            self?.measure(inputData)
        }
        guard status == noErr, let proc else {
            logger.error("Could not create microphone IO proc for device \(self.deviceID): \(status)")
            return false
        }
        let startStatus = AudioDeviceStart(deviceID, proc)
        guard startStatus == noErr else {
            logger.error("Could not start microphone IO proc for device \(self.deviceID): \(startStatus)")
            AudioDeviceDestroyIOProcID(deviceID, proc)
            return false
        }
        ioProcID = proc; isRunning = true
        return true
    }

    func stop() {
        guard isRunning, let proc = ioProcID else { return }
        AudioDeviceStop(deviceID, proc)
        AudioDeviceDestroyIOProcID(deviceID, proc)
        ioProcID = nil; isRunning = false
    }

    private func measure(_ data: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: data))
        var sum: Float = 0
        var peak: Float = 0
        var count = 0
        for buffer in buffers {
            guard let bytes = buffer.mData else { continue }
            let samples = bytes.assumingMemoryBound(to: Float.self)
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            for index in 0..<sampleCount {
                let amplified = samples[index] * gain
                let magnitude = abs(amplified)
                sum += magnitude * magnitude
                peak = max(peak, magnitude)
            }
            count += sampleCount
        }
        guard count > 0 else { return }
        let rms = min(sqrt(sum / Float(count)) * 2.2, 1.0)
        callback(rms, min(peak, 1.0), peak >= 0.98)
    }
}
