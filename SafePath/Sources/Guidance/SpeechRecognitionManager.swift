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
    private var isStarting = false
    private var tapInstalled = false
    private var startGeneration = 0

    func start() {
        guard !isActive && !isStarting else { stop(); return }
        isStarting = true
        startGeneration += 1
        let generation = startGeneration
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self, self.startGeneration == generation else { return }
                guard status == .authorized else {
                    self.fail("Enable speech recognition in Settings to speak a destination.")
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard self.startGeneration == generation else { return }
                        guard granted else {
                            self.fail("Enable microphone access in Settings to speak a destination.")
                            return
                        }
                        self.beginRecording(generation: generation)
                    }
                }
            }
        }
    }
    private func beginRecording(generation: Int) {
        guard isStarting, generation == startGeneration else { return }
        guard let recognizer, recognizer.isAvailable else { fail("Speech recognition is temporarily unavailable."); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in request.append(buffer) }
            tapInstalled = true
            engine.prepare(); try engine.start(); isActive = true; isStarting = false
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    DispatchQueue.main.async { self.onText?(text) }
                    if result.isFinal { DispatchQueue.main.async { self.stop() } }
                }
                if error != nil { DispatchQueue.main.async { self.stop() } }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
                guard let self, self.startGeneration == generation, self.isActive else { return }
                self.stop()
            }
        } catch { fail("Could not start voice input. Check microphone access and try again.") }
    }
    func stop() {
        guard isActive || isStarting else { return }
        startGeneration += 1
        isActive = false
        isStarting = false
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); task?.cancel()
        request = nil; task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        DispatchQueue.main.async { self.onFinish?() }
    }
    private func fail(_ message: String) {
        startGeneration += 1
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); task?.cancel(); request = nil; task = nil
        isActive = false; isStarting = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        onError?(message)
    }
}
