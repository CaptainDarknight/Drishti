import Foundation
import Vision
import CoreML
import ImageIO
import OSLog

struct ObjectCandidate {
    let label: String
    let box: CGRect
    let confidence: Float
}

final class ObjectDetector {
    private let queue = DispatchQueue(label: "safepath.vision", qos: .userInitiated)
    private let lock = NSLock()
    private let logger = Logger(subsystem: "com.example.safepath", category: "Vision")
    private var model: VNCoreMLModel?
    private var running = false
    private var lastFrame = Date.distantPast
    var onResult: (([ObjectCandidate]) -> Void)?

    init() {
        // Optional integration: add YOLOv8n.mlmodelc to the app bundle. If absent, Vision's
        // built-in rectangle detector is used. Packaged .mlpackage files should be compiled by Xcode.
        let compiledURL = Bundle.main.url(forResource: "YOLOv8n", withExtension: "mlmodelc")
        let packageURL = Bundle.main.url(forResource: "YOLOv8n", withExtension: "mlpackage")
        let modelURL = compiledURL ?? packageURL.flatMap { try? MLModel.compileModel(at: $0) }
        if let url = modelURL, let loaded = try? MLModel(contentsOf: url), let visionModel = try? VNCoreMLModel(for: loaded) {
            model = visionModel
            logger.info("Optional YOLOv8n model loaded")
        } else {
            logger.info("YOLOv8n absent; using Vision rectangle fallback")
        }
    }
    func process(pixelBuffer: CVPixelBuffer) {
        lock.lock()
        guard !running, Date().timeIntervalSince(lastFrame) >= 0.15 else { lock.unlock(); return }
        running = true; lastFrame = .now
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            defer { self.lock.lock(); self.running = false; self.lock.unlock() }
            let request: VNRequest
            if let model = self.model {
                let coreMLRequest = VNCoreMLRequest(model: model)
                coreMLRequest.imageCropAndScaleOption = .scaleFill
                request = coreMLRequest
            }
            else {
                let rectangles = VNDetectRectanglesRequest()
                rectangles.minimumConfidence = 0.55
                rectangles.minimumSize = 0.08
                rectangles.maximumObservations = 8
                request = rectangles
            }
            do { try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right).perform([request]) }
            catch { self.logger.error("Vision detection request failed: \(error.localizedDescription, privacy: .public)"); return }
            let objects: [ObjectCandidate]
            if let recognized = request.results as? [VNRecognizedObjectObservation] {
                objects = recognized.map { ObjectCandidate(label: $0.labels.first?.identifier ?? "Object", box: $0.boundingBox, confidence: $0.labels.first?.confidence ?? $0.confidence) }
            } else {
                objects = ((request.results as? [VNRectangleObservation]) ?? []).map { ObjectCandidate(label: "Possible obstacle", box: $0.boundingBox, confidence: $0.confidence) }
            }
            self.onResult?(objects)
        }
    }
}
