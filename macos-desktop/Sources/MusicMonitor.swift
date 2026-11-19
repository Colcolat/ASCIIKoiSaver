import CoreAudio
import Foundation

/// Lightweight macOS audio activity monitor using CoreAudio.
/// Checks ALL audio output devices (speakers, AirPods, Bluetooth, external monitors, etc.)
/// with zero microphone or privacy permissions.
final class MusicMonitor {
    var onMusicStateChanged: ((Bool) -> Void)?
    private(set) var isAudioPlaying: Bool = false
    private var timer: Timer?
    private let bgQueue = DispatchQueue(label: "com.jj.ASCIIKoiDesktop.musicMonitor", qos: .utility)

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        bgQueue.async { [weak self] in
            guard let self = self else { return }
            let playing = self.checkAnyOutputRunning()
            if playing != self.isAudioPlaying {
                self.isAudioPlaying = playing
                DispatchQueue.main.async { [weak self] in
                    self?.onMusicStateChanged?(playing)
                }
            }
        }
    }

    private func checkAnyOutputRunning() -> Bool {
        var propSize: UInt32 = 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &propSize) == noErr,
              propSize > 0 else { return false }

        let count = Int(propSize) / MemoryLayout<AudioDeviceID>.size
        var devices = Array(repeating: AudioDeviceID(0), count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &propSize, &devices) == noErr else {
            return false
        }

        for dev in devices {
            // Only check devices that have at least one output stream
            var streamSize: UInt32 = 0
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyDataSize(dev, &streamAddr, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { continue }

            var isRunning: UInt32 = 0
            var runSize = UInt32(MemoryLayout<UInt32>.size)
            var runAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(dev, &runAddr, 0, nil, &runSize, &isRunning) == noErr, isRunning != 0 {
                return true
            }
        }
        return false
    }
}
