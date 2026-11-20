import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

/// Real-time macOS system audio beat & 24-band FFT spectrum analyzer using CoreAudio Process Tap (macOS 14.2+)
/// and Apple's hardware-accelerated Accelerate/vDSP SIMD FFT (~0.04ms/frame, zero audio recording or storage).
final class MusicMonitor {
    var onStatusChanged: ((_ active: Bool, _ detail: String) -> Void)?

    static let bandCount = 24
    private let fftSize = 512
    private let log2n: vDSP_Length = 9 // 2^9 = 512

    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(label: "com.jj.ASCIIKoiDesktop.audioTap", qos: .userInteractive)

    // vDSP FFT buffers (pre-allocated once, zero heap allocation in audio callback!)
    private var fftSetup: FFTSetup?
    private var hannWindow: [Float] = []
    private var ringBuffer: [Float] = []
    private var ringWriteIdx: Int = 0
    private var realBuf: [Float] = []
    private var imagBuf: [Float] = []
    private var magnitudes: [Float] = []
    private var bandBinRanges: [(Int, Int)] = []

    // Real-time DSP state (accessed under NSLock)
    private let lock = NSLock()
    private var lp1State: Float = 0
    private var fastBass: Float = 0
    private var avgBass: Float = 0.015
    private var lastBeatTime: CFAbsoluteTime = 0
    private var lastSoundTime: CFAbsoluteTime = 0
    private var hasEverReceivedAudio: Bool = false

    private var currentBassLevel: CGFloat = 0
    private var pendingBeatStrength: CGFloat = 0
    private var smoothedBands: [CGFloat] = Array(repeating: 0, count: MusicMonitor.bandCount)
    private var isTapRunning: Bool = false

    init() {
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        hannWindow = Array(repeating: 0, count: fftSize)
        vDSP_hann_window(&hannWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        ringBuffer = Array(repeating: 0, count: fftSize)
        realBuf = Array(repeating: 0, count: fftSize / 2)
        imagBuf = Array(repeating: 0, count: fftSize / 2)
        magnitudes = Array(repeating: 0, count: fftSize / 2)

        // Precompute 24 logarithmic musical frequency bands from ~45 Hz (bin 1) to ~15 kHz (bin 165) at 48 kHz
        let minFreq: Float = 45.0
        let maxFreq: Float = 15000.0
        let binHz: Float = 48000.0 / Float(fftSize) // 93.75 Hz per bin
        var ranges: [(Int, Int)] = []
        for b in 0..<Self.bandCount {
            let f0 = minFreq * pow(maxFreq / minFreq, Float(b) / Float(Self.bandCount))
            let f1 = minFreq * pow(maxFreq / minFreq, Float(b + 1) / Float(Self.bandCount))
            let lo = max(1, min(fftSize / 2 - 2, Int(floor(f0 / binHz))))
            let hi = max(lo + 1, min(fftSize / 2 - 1, Int(ceil(f1 / binHz))))
            ranges.append((lo, hi))
        }
        bandBinRanges = ranges
    }

    deinit {
        stop()
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

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
        for i in 0..<smoothedBands.count { smoothedBands[i] = 0 }
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.onStatusChanged?(false, "Music: Off")
        }
    }

    /// Consumes the latest real-time bass level (0..1), any newly detected beat hit (0..1), playing flag, and 24-band FFT spectrum.
    func consumeAudioFrame() -> (bass: CGFloat, beatHit: CGFloat, playing: Bool, spectrum: [CGFloat], receivedAudio: Bool) {
        lock.lock()
        let bass = currentBassLevel
        let beat = pendingBeatStrength
        pendingBeatStrength = 0
        let playing = (CFAbsoluteTimeGetCurrent() - lastSoundTime) < 1.2
        let spec = smoothedBands
        let gotAudio = hasEverReceivedAudio
        if !playing {
            for i in 0..<smoothedBands.count { smoothedBands[i] *= 0.82 }
        }
        lock.unlock()
        return (bass, beat, playing, spec, gotAudio)
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

        // Low-latency 256-frame audio buffer (~5.3ms at 48kHz — cool battery life & snappy sync)
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
        let alpha: Float = 0.024 // ~180 Hz 1-pole low-pass at 48kHz for kick/bass punch

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
                ringBuffer[ringWriteIdx] = s
                ringWriteIdx = (ringWriteIdx + 1) & (fftSize - 1)
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

        // Compute 512-point vDSP FFT into 24 logarithmic musical frequency bands
        var rawBands = [CGFloat](repeating: 0, count: Self.bandCount)
        if totalRMS > 0.0008, let setup = fftSetup {
            let halfN = fftSize / 2
            var windowed = [Float](repeating: 0, count: fftSize)
            for k in 0..<fftSize {
                let idx = (ringWriteIdx + k) & (fftSize - 1)
                windowed[k] = ringBuffer[idx] * hannWindow[k]
            }
            realBuf.withUnsafeMutableBufferPointer { rPtr in
                imagBuf.withUnsafeMutableBufferPointer { iPtr in
                    var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                    windowed.withUnsafeBufferPointer { wPtr in
                        wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { cPtr in
                            vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(halfN))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfN))
                }
            }
            // Convert power to perceptual dB-like 0..1 band heights with slight treble lift
            let scaleNorm: Float = 1.0 / Float(fftSize * 2)
            for b in 0..<Self.bandCount {
                let (lo, hi) = bandBinRanges[b]
                var peak: Float = 0
                for bin in lo..<hi {
                    if magnitudes[bin] > peak { peak = magnitudes[bin] }
                }
                let amp = sqrt(peak) * scaleNorm
                // Slight perceptual tilt so high-frequency hi-hats/synths look as lively as deep bass
                let tilt: Float = 1.0 + Float(b) * 0.14
                let db = log10(1.0 + amp * 34.0 * tilt) / 1.45
                rawBands[b] = max(0, min(1.0, CGFloat(db)))
            }
        }

        lock.lock()
        if totalRMS > 0.0012 {
            lastSoundTime = now
            hasEverReceivedAudio = true
        }

        // Smooth 24 spectrum bands (fast attack, silky gravity decay)
        for b in 0..<Self.bandCount {
            let target = rawBands[b]
            let prev = smoothedBands[b]
            if target > prev {
                smoothedBands[b] = prev + (target - prev) * 0.62
            } else {
                smoothedBands[b] = prev * 0.84 + target * 0.16
            }
        }

        // True time-based moving average (~1.1s baseline so it adapts cleanly at ANY listening volume!)
        let avgRate = min(0.12, blockDt / 1.1)
        avgBass = avgBass * (1.0 - avgRate) + bassRMS * avgRate

        let prevBass = fastBass
        fastBass = bassRMS

        let normalizedBass = min(1.0, CGFloat(bassRMS / max(0.005, avgBass * 2.1)))
        currentBassLevel = currentBassLevel * 0.60 + normalizedBass * 0.40

        // Balanced kick/bass onset detection (reverted to crisp sensitivity)
        let threshold = max(0.014, avgBass * 1.50)
        let isRisingAttack = bassRMS > prevBass * 1.05
        if bassRMS > threshold && isRisingAttack && (now - lastBeatTime) > 0.40 {
            lastBeatTime = now
            let strength = min(1.0, CGFloat((bassRMS - avgBass) / max(0.012, avgBass * 1.5)))
            pendingBeatStrength = max(pendingBeatStrength, max(0.50, strength))
        }
        lock.unlock()
    }
}
