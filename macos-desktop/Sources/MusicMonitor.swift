import CoreAudio
import Foundation

/// Lightweight macOS audio activity monitor using CoreAudio.
/// Detects whether any audio/music is currently playing on the default output device
/// (Spotify, Apple Music, YouTube, browser, etc.) with zero microphone or privacy permissions.
final class MusicMonitor {
    var onMusicStateChanged: ((Bool) -> Void)?
    private(set) var isAudioPlaying: Bool = false
    private var timer: Timer?

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let playing = checkDefaultOutputRunning()
        if playing != isAudioPlaying {
            isAudioPlaying = playing
            DispatchQueue.main.async { [weak self] in
                self?.onMusicStateChanged?(playing)
            }
        }
    }

    private func checkDefaultOutputRunning() -> Bool {
        var deviceId = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status1 = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceId)
        guard status1 == noErr, deviceId != 0 else { return false }

        var isRunning: UInt32 = 0
        var runSize = UInt32(MemoryLayout<UInt32>.size)
        var runAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status2 = AudioObjectGetPropertyData(deviceId, &runAddr, 0, nil, &runSize, &isRunning)
        return status2 == noErr && isRunning != 0
    }
}
