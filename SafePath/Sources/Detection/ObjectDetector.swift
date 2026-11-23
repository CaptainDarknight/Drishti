import Foundation
import Vision
import CoreVideo
import OSLog

struct ObjectCandidate {
    let label: String
    let box: CGRect
    let confidence: Float
}

/// Lightweight on-device obstacle proposals for phones without a bundled Core ML model.
/// Deliberately limits Vision to one rectangle request at a low rate for older iPhones.
final class ObjectDetector {
    private let queue = DispatchQueue(label: "drishti.vision", qos: .userInitiated)
    private let lock = NSLock()
    private let logger = Logger(subsystem: "com.example.safepath", category: "Vision")
    private var running = false
    private var lastFrame = Date.distantPast
    var onResult: (([ObjectCandidate]) -> Void)?

    func process(pixelBuffer: CVPixelBuffer) {
        lock.lock()
        guard !running, Date().timeIntervalSince(lastFrame) >= 0.8 else {
            lock.unlock()
            return
        }
        running = true
        lastFrame = .now
        lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            defer {
                self.lock.lock()
                self.running = false
                self.lock.unlock()
            }

            let request = VNDetectRectanglesRequest()
            request.minimumConfidence = 0.60
            request.minimumSize = 0.10
            request.maximumObservations = 4

            do {
                try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right).perform([request])
            } catch {
                self.logger.error("Vision frame analysis failed: \(error.localizedDescription, privacy: .public)")
                return
            }

            let candidates = (request.results ?? []).map {
                ObjectCandidate(label: "Possible obstacle", box: $0.boundingBox, confidence: $0.confidence)
            }
            self.onResult?(candidates)
        }
    }
}
