import Foundation
import ARKit
import Vision
import AVFoundation
import Combine
import simd
import OSLog

final class CameraSession: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    private let logger = Logger(subsystem: "com.example.safepath", category: "Camera")
    private let detector = ObjectDetector()
    var onDetections: (([DetectedObject]) -> Void)?
    var onPermissionMessage: ((String?) -> Void)?
    private var latestFrame: ARFrame?
    private var isRunning = false

    override init() {
        super.init()
        session.delegateQueue = .main
        session.delegate = self
        detector.onResult = { [weak self] observations in
            Task { @MainActor in self?.publish(observations) }
        }
    }
    func start(completion: ((String?) -> Void)? = nil) {
        onPermissionMessage = completion
        guard ARWorldTrackingConfiguration.isSupported else { logger.error("ARKit world tracking is unsupported"); completion?("AR camera tracking is unavailable on this iPhone."); return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: runSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted { self.runSession() } else { self.logger.error("Camera permission denied"); completion?("Camera access is off. Enable it in iPhone Settings.") }
                }
            }
        default: completion?("Camera access is off. Enable it in iPhone Settings.")
        }
    }
    private func runSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) { configuration.frameSemantics.insert(.smoothedSceneDepth) }
        else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) { configuration.frameSemantics.insert(.sceneDepth) }
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        logger.info("AR camera session started; scene depth enabled: \(configuration.frameSemantics.contains(.smoothedSceneDepth) || configuration.frameSemantics.contains(.sceneDepth))")
        isRunning = true
    }
    func stop() { session.pause(); isRunning = false; logger.info("AR camera session paused") }
    func session(_ session: ARSession, didFailWithError error: Error) { logger.error("AR session failed: \(error.localizedDescription, privacy: .public)") }
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        latestFrame = frame
        detector.process(pixelBuffer: frame.capturedImage)
    }
    private func publish(_ observations: [ObjectCandidate]) {
        guard isRunning else { return }
        let frame = latestFrame
        let objects = observations.map { observation -> DetectedObject in
            let label = observation.label
            let confidence = observation.confidence
            // Vision boxes use a bottom-left origin in the oriented image. For the rear camera's
            // portrait presentation, the center is mapped back into the landscape depth buffer.
            let x = observation.box.midX
            let y = observation.box.midY
            let depth = frame.flatMap { sampleDepth(frame: $0, visionX: x, visionY: y) }
            return DetectedObject(label: label, box: observation.box, confidence: confidence, distanceMeters: depth)
        }
        onDetections?(objects)
    }
    private func sampleDepth(frame: ARFrame, visionX: CGFloat, visionY: CGFloat) -> Double? {
        guard let map = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap else {
            // ARKit estimated-plane raycasting uses tracked feature points on devices without LiDAR.
            // If it cannot find a reliable hit, the UI reports that distance is unavailable.
            let resolution = frame.camera.imageResolution
            let viewportPoint = CGPoint(x: visionX * CGFloat(resolution.height), y: (1 - visionY) * CGFloat(resolution.width))
            guard let query = frame.raycastQuery(from: viewportPoint, allowing: .estimatedPlane, alignment: .any),
                  let result = session.raycast(query).first else { return nil }
            let cameraPosition = SIMD3<Float>(frame.camera.transform.columns.3.x, frame.camera.transform.columns.3.y, frame.camera.transform.columns.3.z)
            let hitPosition = SIMD3<Float>(result.worldTransform.columns.3.x, result.worldTransform.columns.3.y, result.worldTransform.columns.3.z)
            let meters = simd_distance(cameraPosition, hitPosition)
            return meters.isFinite && meters > 0 ? Double(meters) : nil
        }
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        let width = CVPixelBufferGetWidth(map), height = CVPixelBufferGetHeight(map)
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        let floats = base.assumingMemoryBound(to: UInt8.self)
        // Portrait Vision x/y correspond approximately to the rotated raw sensor y/(1-x).
        let px = min(width - 1, max(0, Int(visionY * CGFloat(width))))
        let py = min(height - 1, max(0, Int((1 - visionX) * CGFloat(height))))
        var samples: [Double] = []
        for dy in -2...2 {
            for dx in -2...2 {
                let sx = px + dx, sy = py + dy
                guard sx >= 0, sx < width, sy >= 0, sy < height else { continue }
                let pointer = floats.advanced(by: sy * rowBytes + sx * MemoryLayout<Float32>.size)
                let value = pointer.withMemoryRebound(to: Float32.self, capacity: 1) { Double($0.pointee) }
                if value.isFinite && value > 0 { samples.append(value) }
            }
        }
        guard !samples.isEmpty else { return nil }
        samples.sort()
        return samples[samples.count / 2]
    }
}
