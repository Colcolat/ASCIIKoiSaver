import AudioToolbox
import CoreAudio
import Foundation

/// Real-time macOS system audio rhythm & bass-beat analyzer using CoreAudio Process Tap (macOS 14.2+).
/// Isolates low-frequency kick/bass energy (low-pass ~260 Hz) and detects real beat onsets
/// with zero audio recording or storage.
final class MusicMonitor {
    var onStatusChanged: ((_ active: Bool, _ detail: String) -> Void)?

    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(label: "com.jj.ASCIIKoiDesktop.audioTap", qos: .userInteractive)

    // Real-time DSP state (accessed under NSLock)
    private let lock = NSLock()
    private var lpState: Float = 0
    private var avgBass: Float = 0.015
    private var lastBeatTime: CFAbsoluteTime = 0
    private var lastSoundTime: CFAbsoluteTime = 0

    private var currentBassLevel: CGFloat = 0
    private var pendingBeatStrength: CGFloat = 0
    private var isTapRunning: Bool = false

    func start() {
        stop()
        setupCoreAudioTap()
    }

    func stop() {
        if aggregateDeviceID != kAudioObjectUnknown {
            if let proc = ioProcID {
                AudioDeviceStop(aggregateDeviceID, proc)
                AudioDeviceDestroyIOProcID(aggregateDeviceID, proc)
                ioProcID = nil
            }
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        isTapRunning = false
        lock.lock()
        currentBassLevel = 0
        pendingBeatStrength = 0
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.onStatusChanged?(false, "Music: Off")
        }
    }

    /// Consumes the latest real-time bass level (0..1) and any newly detected beat hit (0..1).
    func consumeAudioFrame() -> (bass: CGFloat, beatHit: CGFloat, playing: Bool) {
        lock.lock()
        let bass = currentBassLevel
        let beat = pendingBeatStrength
        pendingBeatStrength = 0
        let playing = (CFAbsoluteTimeGetCurrent() - lastSoundTime) < 1.2
        lock.unlock()
        return (bass, beat, playing)
    }

    private func setupCoreAudioTap() {
        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDesc.uuid = UUID()
        tapDesc.isPrivate = true
        tapDesc.muteBehavior = .unmuted

        var createdTap: AudioObjectID = kAudioObjectUnknown
        let tapErr = AudioHardwareCreateProcessTap(tapDesc, &createdTap)
        guard tapErr == noErr, createdTap != kAudioObjectUnknown else {
            DispatchQueue.main.async { [weak self] in
                self?.onStatusChanged?(false, "Music: Permission needed (Audio)")
            }
            return
        }
        tapID = createdTap

        let aggUID = "com.jj.ASCIIKoiDesktop.tap.\(UUID().uuidString)"
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "ASCIIKoiTapDevice",
            kAudioAggregateDeviceUIDKey as String: aggUID,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapUIDKey as String: tapDesc.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey as String: false
                ]
            ]
        ]

        var createdAgg: AudioObjectID = kAudioObjectUnknown
        let aggErr = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &createdAgg)
        guard aggErr == noErr, createdAgg != kAudioObjectUnknown else {
            stop()
            DispatchQueue.main.async { [weak self] in
                self?.onStatusChanged?(false, "Music: Audio tap unavailable")
            }
            return
        }
        aggregateDeviceID = createdAgg

        // Request low-latency 256-frame audio buffer (~5ms at 48kHz)
        var bufferFrames: UInt32 = 256
        var bufAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(aggregateDeviceID, &bufAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &bufferFrames)

        var procID: AudioDeviceIOProcID?
        let ioErr = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDeviceID, ioQueue) { [weak self] _, inInputData, _, _, _ in
            self?.processAudioBufferList(inInputData)
        }
        guard ioErr == noErr, let validProc = procID else {
            stop()
            return
        }
        ioProcID = validProc

        let startErr = AudioDeviceStart(aggregateDeviceID, validProc)
        if startErr != noErr {
            stop()
            return
        }

        isTapRunning = true
        DispatchQueue.main.async { [weak self] in
            self?.onStatusChanged?(true, "Music: Real-Time Beat Sync ♪")
        }
    }

    private func processAudioBufferList(_ bufferListPtr: UnsafePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferListPtr))
        var sumSqBass: Float = 0
        var sumSqTotal: Float = 0
        var sampleCount: Int = 0
        var lp = lpState
        let alpha: Float = 0.042 // ~280 Hz low-pass at 48kHz to isolate kick drum & bassline

        for buf in abl {
            guard let mData = buf.mData, buf.mDataByteSize > 0 else { continue }
            let count = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
            let samples = mData.assumingMemoryBound(to: Float.self)
            let stride = max(1, Int(buf.mNumberChannels))
            var i = 0
            while i < count {
                let s = samples[i]
                lp += alpha * (s - lp)
                sumSqBass += lp * lp
                sumSqTotal += s * s
                sampleCount += 1
                i += stride
            }
        }
        lpState = lp
        guard sampleCount > 0 else { return }

        let bassRMS = sqrt(sumSqBass / Float(sampleCount))
        let totalRMS = sqrt(sumSqTotal / Float(sampleCount))
        let now = CFAbsoluteTimeGetCurrent()

        lock.lock()
        if totalRMS > 0.0025 {
            lastSoundTime = now
        }

        // Smooth adaptive baseline so it works equally well at low or high volume!
        avgBass = avgBass * 0.93 + bassRMS * 0.07
        let normalizedBass = min(1.0, CGFloat(bassRMS / max(0.015, avgBass * 2.2)))
        currentBassLevel = currentBassLevel * 0.65 + normalizedBass * 0.35

        // Detect sharp bass/kick onset on the leading attack transient with 0.28s spacing
        let threshold = max(0.0075, avgBass * 1.26)
        if bassRMS > threshold && (now - lastBeatTime) > 0.28 {
            lastBeatTime = now
            let strength = min(1.0, CGFloat((bassRMS - avgBass) / max(0.01, avgBass * 1.4)))
            pendingBeatStrength = max(pendingBeatStrength, max(0.45, strength))
        }
        lock.unlock()
    }
}
