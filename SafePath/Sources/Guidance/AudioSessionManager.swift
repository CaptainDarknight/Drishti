import AVFoundation
import Foundation

final class AudioSessionManager {
    var onInterruption: ((Bool) -> Void)?
    init() { NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)), name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance()) }
    func configure() { try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers]); try? AVAudioSession.sharedInstance().setActive(true) }
    @objc private func interrupted(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, let kind = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        onInterruption?(kind == .began)
        if kind == .ended { try? AVAudioSession.sharedInstance().setActive(true) }
    }
}
