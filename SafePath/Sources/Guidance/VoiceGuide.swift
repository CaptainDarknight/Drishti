import AVFoundation

final class VoiceGuide {
    private let synthesizer = AVSpeechSynthesizer()
    func speak(distance: Double, direction: String, urgent: Bool) {
        let text = urgent ? "Stop. Object very close." : (distance < 1 ? "Object ahead, less than one meter." : "Object on your \(direction.lowercased()), \(Int(distance.rounded())) meters.")
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.47; utterance.pitchMultiplier = 1; utterance.volume = 1
        synthesizer.speak(utterance)
    }
    func speakUnknown(direction: String) {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: "Possible obstacle on your \(direction.lowercased()). Distance unknown.")
        utterance.rate = 0.47; utterance.pitchMultiplier = 1; utterance.volume = 1
        synthesizer.speak(utterance)
    }
    func clearPath() {
        guard !synthesizer.isSpeaking else { return }
        let utterance = AVSpeechUtterance(string: "Path clear."); utterance.rate = 0.47; synthesizer.speak(utterance)
    }
    func pause() { synthesizer.pauseSpeaking(at: .immediate) }
    func resume() { synthesizer.continueSpeaking() }
}
