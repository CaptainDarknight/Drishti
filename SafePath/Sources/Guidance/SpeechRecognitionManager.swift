import Foundation
import Speech
import AVFoundation

final class SpeechRecognitionManager {
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    var onText: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onFinish: (() -> Void)?
    private var isActive = false

    func start() {
        guard !isActive else { stop(); return }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self else { return }
            guard status == .authorized else { DispatchQueue.main.async { self.onError?("Enable speech recognition in Settings to speak a destination.") }; return }
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                guard granted else { DispatchQueue.main.async { self.onError?("Enable microphone access in Settings to speak a destination.") }; return }
                DispatchQueue.main.async { self.beginRecording() }
            }
        }
    }
    private func beginRecording() {
        guard let recognizer, recognizer.isAvailable else { onError?("Speech recognition is temporarily unavailable."); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in request.append(buffer) }
            engine.prepare(); try engine.start(); isActive = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    DispatchQueue.main.async { self.onText?(text) }
                    if result.isFinal { self.stop() }
                }
                if error != nil { self.stop() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in self?.stop() }
        } catch { onError?("Could not start voice input. Check microphone access and try again.") }
    }
    func stop() {
        guard isActive else { return }
        isActive = false
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        request?.endAudio(); task?.cancel()
        request = nil; task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        DispatchQueue.main.async { self.onFinish?() }
    }
}
