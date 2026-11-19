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

        // Request ultra-low-latency 128-frame audio buffer (~2.6ms at 48kHz)
        var bufferFrames: UInt32 = 128
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
        let alpha: Float = 0.022 // 1-pole ~165 Hz low-pass at 48kHz (half the phase lag of 2-pole)

        for buf in abl {
            guard let mData = buf.mData, buf.mDataByteSize > 0 else { continue }
            let count = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
            let samples = mData.assumingMemoryBound(to: Float.self)
            let stride = max(1, Int(buf.mNumberChannels))
            var i = 0
            while i < count {
                let s = samples[i]
                lp1 += alpha * (s - lp1)
                sumSqBass += lp1 * lp1
                sumSqTotal += s * s
                sampleCount += 1
                i += stride
            }
        }
        lp1State = lp1
        guard sampleCount > 0 else { return }

        let bassRMS = sqrt(sumSqBass / Float(sampleCount))
        let totalRMS = sqrt(sumSqTotal / Float(sampleCount))
        let now = CFAbsoluteTimeGetCurrent()
        let blockDt = max(0.002, min(0.05, Float(sampleCount) / 48000.0))

        lock.lock()
        if totalRMS > 0.003 {
            lastSoundTime = now
        }

        // True time-based moving average (~1.2s baseline so quiet bass doesn't fool it)
        let avgRate = min(0.12, blockDt / 1.2)
        avgBass = avgBass * (1.0 - avgRate) + bassRMS * avgRate

        // Zero-lag transient check directly on the 2.6ms block RMS vs previous block
        let prevBass = fastBass
        fastBass = bassRMS

        let normalizedBass = min(1.0, CGFloat(bassRMS / max(0.02, avgBass * 2.4)))
        currentBassLevel = currentBassLevel * 0.65 + normalizedBass * 0.35

        // Fire immediately on the very first 2.6ms rising attack block of a strong kick/bass hit
        let threshold = max(0.022, avgBass * 1.55)
        let isRisingAttack = bassRMS > prevBass * 1.06
        if bassRMS > threshold && isRisingAttack && (now - lastBeatTime) > 0.40 {
            lastBeatTime = now
            let strength = min(1.0, CGFloat((bassRMS - avgBass) / max(0.015, avgBass * 1.6)))
            pendingBeatStrength = max(pendingBeatStrength, max(0.50, strength))
        }
        lock.unlock()
    }
}
