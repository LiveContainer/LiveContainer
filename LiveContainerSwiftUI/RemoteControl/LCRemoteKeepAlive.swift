//
//  LCRemoteKeepAlive.swift
//  LiveContainerSwiftUI
//
//  Keep-alive for the remote service. iOS suspends the app and the socket dies, so:
//   - audio      : loop a silent track (UIBackgroundModes: audio is declared), stays online when locked / backgrounded
//   - screenAwake: isIdleTimerDisabled, pairs with Guided Access to stay in the foreground
//   - or both together
//
//  The Info.plist already declares audio / location / voip / processing background modes,
//  so the audio option needs no project changes. For long unattended runs the stablest combo is:
//  Guided Access + Auto-Lock Never + screenAwake.
//

import AVFoundation
import UIKit

enum LCRemoteKeepAliveMode: String, CaseIterable, Identifiable {
    case off
    case audio
    case screenAwake
    case audioAndScreen

    var id: String { rawValue }

    var usesAudio: Bool { self == .audio || self == .audioAndScreen }
    var keepsScreenOn: Bool { self == .screenAwake || self == .audioAndScreen }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .audio: return "Silent audio (online while locked)"
        case .screenAwake: return "Screen stays awake"
        case .audioAndScreen: return "Silent audio + screen stays awake"
        }
    }

    static let defaultsKey = "LCRemoteKeepAlive"

    /// Defaults to .audio, so enabling the remote service implies silent-audio keep-alive with no extra setup.
    static var stored: LCRemoteKeepAliveMode {
        get {
            if let raw = LCUtils.appGroupUserDefault.string(forKey: defaultsKey),
               let mode = LCRemoteKeepAliveMode(rawValue: raw) {
                return mode
            }
            return .audio
        }
        set { LCUtils.appGroupUserDefault.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

@MainActor
final class LCRemoteKeepAlive {
    static let shared = LCRemoteKeepAlive()

    private var player: AVAudioPlayer?
    private var interruptionObserver: NSObjectProtocol?
    private var watchdog: Timer?
    private(set) var mode: LCRemoteKeepAliveMode = .off

    private init() {}

    func apply(_ mode: LCRemoteKeepAliveMode) {
        self.mode = mode
        LCRemoteKeepAliveMode.stored = mode

        if mode.usesAudio {
            startAudio()
            startWatchdog()
        } else {
            stopAudio()
            stopWatchdog()
        }
        UIApplication.shared.isIdleTimerDisabled = mode.keepsScreenOn
        LCRemoteLogStore.shared.append("keepalive -> \(mode.rawValue)", src: "api")
    }

    /// Used when stopping the service: stops audio / screen-awake but **does not** change the user's preference
    func suspend() {
        stopAudio()
        stopWatchdog()
        UIApplication.shared.isIdleTimerDisabled = false
        LCRemoteLogStore.shared.append("keepalive suspended (mode stays \(mode.rawValue))", src: "api")
    }

    func restore() {
        apply(LCRemoteKeepAliveMode.stored)
    }

    /// State exposed through the API
    var status: [String: Any] {
        ["mode": mode.rawValue,
         "audioPlaying": player?.isPlaying ?? false,
         "idleTimerDisabled": UIApplication.shared.isIdleTimerDisabled]
    }

    // MARK: - Silent audio

    private func startAudio() {
        if let player, player.isPlaying { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // mixWithOthers: don't cut off the guest app's own audio
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let p = try AVAudioPlayer(data: LCRemoteKeepAlive.silentWAV(seconds: 2))
            p.numberOfLoops = -1
            p.volume = 0.05
            p.prepareToPlay()
            p.play()
            player = p

            if interruptionObserver == nil {
                interruptionObserver = NotificationCenter.default.addObserver(
                    forName: AVAudioSession.interruptionNotification,
                    object: nil, queue: .main) { [weak self] note in
                        guard let self else { return }
                        let raw = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
                        if raw == AVAudioSession.InterruptionType.ended.rawValue {
                            Task { @MainActor in
                                if self.mode.usesAudio { self.restartAudio() }
                            }
                        }
                    }
            }
        } catch {
            LCRemoteLogStore.shared.append("keepalive audio failed: \(error.localizedDescription)", src: "api")
        }
    }

    /// When the guest app starts and takes over the audio session the player can stop silently without an
    /// interruption callback, so re-check every 10 s that it is still playing.
    private func startWatchdog() {
        stopWatchdog()
        let t = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.mode.usesAudio else { return }
                if self.player?.isPlaying != true {
                    LCRemoteLogStore.shared.append("keepalive watchdog: audio stopped, restarting", src: "api")
                    self.restartAudio()
                } else {
                    try? AVAudioSession.sharedInstance().setActive(true)
                }
            }
        }
        watchdog = t
    }

    private func stopWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
    }

    private func restartAudio() {
        player?.stop()
        player = nil
        startAudio()
    }

    private func stopAudio() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Build a silent WAV (44-byte header + all-zero PCM)

    static func silentWAV(seconds: Double, sampleRate: Int = 8000) -> Data {
        let channels = 1
        let bitsPerSample = 16
        let frames = Int(Double(sampleRate) * max(0.5, seconds))
        let dataBytes = frames * channels * bitsPerSample / 8

        var d = Data()
        func append32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func append16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }

        d.append(contentsOf: Array("RIFF".utf8))
        append32(UInt32(36 + dataBytes))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8))
        append32(16)
        append16(1)                                        // PCM
        append16(UInt16(channels))
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * channels * bitsPerSample / 8))  // byte rate
        append16(UInt16(channels * bitsPerSample / 8))     // block align
        append16(UInt16(bitsPerSample))
        d.append(contentsOf: Array("data".utf8))
        append32(UInt32(dataBytes))
        d.append(Data(count: dataBytes))
        return d
    }
}
