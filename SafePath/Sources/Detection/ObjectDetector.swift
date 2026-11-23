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
            logger.info("YOLOv8n absent; using Vision boxes with on-device Vision classification")
        }
    }
    func process(pixelBuffer: CVPixelBuffer) {
        lock.lock()
        guard !running, Date().timeIntervalSince(lastFrame) >= 0.35 else { lock.unlock(); return }
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
                rectangles.maximumObservations = 6
                request = rectangles
            }
            do { try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right).perform([request]) }
            catch { self.logger.error("Vision detection request failed: \(error.localizedDescription, privacy: .public)"); return }
            let objects: [ObjectCandidate]
            if let recognized = request.results as? [VNRecognizedObjectObservation] {
                objects = recognized.map { ObjectCandidate(label: $0.labels.first?.identifier ?? "Object", box: $0.boundingBox, confidence: $0.labels.first?.confidence ?? $0.confidence) }
            } else {
                let rectangles = ((request.results as? [VNRectangleObservation]) ?? []).filter { $0.confidence >= 0.55 }
                // Vision's built-in image classifier supplies semantic labels for detected regions
                // when no dedicated object-detection model is bundled with the app.
                let classificationRequests: [VNClassifyImageRequest] = rectangles.prefix(3).map { rectangle in
                    let classification = VNClassifyImageRequest()
                    classification.regionOfInterest = rectangle.boundingBox
                    return classification
                }
                if !classificationRequests.isEmpty {
                    do { try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right).perform(classificationRequests) }
                    catch { self.logger.debug("Region classification unavailable: \(error.localizedDescription, privacy: .public)") }
                }
                objects = rectangles.enumerated().map { index, rectangle in
                    let classification = classificationRequests.indices.contains(index) ? classificationRequests[index].results?.first : nil
                    let hasUsefulLabel = classification.map { $0.confidence >= 0.18 } ?? false
                    let label = hasUsefulLabel ? classification!.identifier.replacingOccurrences(of: "_", with: " ").capitalized : "Possible obstacle"
                    return ObjectCandidate(label: label, box: rectangle.boundingBox, confidence: hasUsefulLabel ? classification!.confidence : rectangle.confidence)
                }
            }
            self.onResult?(objects)
        }
    }
}
