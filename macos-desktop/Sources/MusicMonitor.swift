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
    private var lp1State: Float = 0
    private var lp2State: Float = 0
    private var fastBass: Float = 0
    private var avgBass: Float = 0.02
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
        var lp1 = lp1State
        var lp2 = lp2State
        let alpha: Float = 0.022 // 2-pole ~165 Hz low-pass at 48kHz to isolate real kick/bass punches

        for buf in abl {
            guard let mData = buf.mData, buf.mDataByteSize > 0 else { continue }
            let count = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
            let samples = mData.assumingMemoryBound(to: Float.self)
            let stride = max(1, Int(buf.mNumberChannels))
            var i = 0
            while i < count {
                let s = samples[i]
                lp1 += alpha * (s - lp1)
                lp2 += alpha * (lp1 - lp2)
                sumSqBass += lp2 * lp2
                sumSqTotal += s * s
                sampleCount += 1
                i += stride
            }
        }
        lp1State = lp1
        lp2State = lp2
        guard sampleCount > 0 else { return }

        let bassRMS = sqrt(sumSqBass / Float(sampleCount))
        let totalRMS = sqrt(sumSqTotal / Float(sampleCount))
        let now = CFAbsoluteTimeGetCurrent()
        let blockDt = max(0.002, min(0.05, Float(sampleCount) / 48000.0))

        lock.lock()
        if totalRMS > 0.003 {
            lastSoundTime = now
        }

        // True time-based moving averages (independent of 256-frame callback rate!)
        let avgRate = min(0.12, blockDt / 1.2)      // ~1.2s baseline so quiet bass doesn't fool it
        avgBass = avgBass * (1.0 - avgRate) + bassRMS * avgRate

        let prevFast = fastBass
        let fastRate = min(0.65, blockDt / 0.020)   // ~20ms fast attack envelope
        fastBass = fastBass * (1.0 - fastRate) + bassRMS * fastRate

        let normalizedBass = min(1.0, CGFloat(fastBass / max(0.02, avgBass * 2.4)))
        currentBassLevel = currentBassLevel * 0.65 + normalizedBass * 0.35

        // Trigger ONLY on strong, rising kick/bass punches (1.55x over 1.2s avg) with 0.42s beat spacing
        let threshold = max(0.020, avgBass * 1.55)
        let isRisingAttack = fastBass > prevFast * 1.05
        if fastBass > threshold && isRisingAttack && (now - lastBeatTime) > 0.42 {
            lastBeatTime = now
            let strength = min(1.0, CGFloat((fastBass - avgBass) / max(0.015, avgBass * 1.6)))
            pendingBeatStrength = max(pendingBeatStrength, max(0.50, strength))
        }
        lock.unlock()
    }
}
