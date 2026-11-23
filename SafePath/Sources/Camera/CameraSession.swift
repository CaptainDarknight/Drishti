import Foundation
import AVFoundation
import Vision
import Combine
import OSLog
import CoreVideo
import CoreMedia

final class CameraSession: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let captureSession = AVCaptureSession()
    private let logger = Logger(subsystem: "com.example.safepath", category: "Camera")
    private let sessionQueue = DispatchQueue(label: "drishti.camera.session", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "drishti.camera.frames", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let detector = ObjectDetector()
    private var isConfigured = false
    private var startGeneration = 0
    private var isStartingOnMain = false
    private var runningOnMain = false
    var onDetections: (([DetectedObject]) -> Void)?

    override init() {
        super.init()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        detector.onResult = { [weak self] observations in
            DispatchQueue.main.async { self?.publish(observations) }
        }
    }

    func start(completion: ((String?) -> Void)? = nil) {
        guard !runningOnMain else { completion?(nil); return }
        guard !isStartingOnMain else { return }
        isStartingOnMain = true
        startGeneration += 1
        let generation = startGeneration
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart(generation: generation, completion: completion)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.startGeneration == generation else { return }
                    guard granted else {
                        self.isStartingOnMain = false
                        completion?("Camera access is off. Enable it in iPhone Settings → Drishti → Camera.")
                        return
                    }
                    self.configureAndStart(generation: generation, completion: completion)
                }
            }
        default:
            isStartingOnMain = false
            completion?("Camera access is off. Enable it in iPhone Settings → Drishti → Camera.")
        }
    }

    private func configureAndStart(generation: Int, completion: ((String?) -> Void)?) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configureIfNeeded()
                if !self.captureSession.isRunning { self.captureSession.startRunning() }
                guard self.captureSession.isRunning else { throw CameraSetupError.startFailed }
                DispatchQueue.main.async {
                    guard self.startGeneration == generation else {
                        self.sessionQueue.async { self.stopSessionOnQueue() }
                        return
                    }
                    self.isStartingOnMain = false
                    self.runningOnMain = true
                    self.logger.info("Camera capture session started")
                    completion?(nil)
                }
            } catch {
                self.logger.error("Could not start camera: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async {
                    guard self.startGeneration == generation else { return }
                    self.isStartingOnMain = false
                    self.runningOnMain = false
                    completion?("Drishti could not start the camera. Close other camera apps, check Camera permission, and try again.")
                }
            }
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraSetupError.noRearCamera
        }
        let input = try AVCaptureDeviceInput(device: device)
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        captureSession.sessionPreset = .high
        guard captureSession.canAddInput(input) else { throw CameraSetupError.cannotAddInput }
        captureSession.addInput(input)
        guard captureSession.canAddOutput(videoOutput) else {
            captureSession.removeInput(input)
            throw CameraSetupError.cannotAddOutput
        }
        captureSession.addOutput(videoOutput)
        isConfigured = true
    }

    func stop() {
        startGeneration += 1
        isStartingOnMain = false
        runningOnMain = false
        sessionQueue.async { [weak self] in self?.stopSessionOnQueue() }
    }

    private func stopSessionOnQueue() {
        if captureSession.isRunning { captureSession.stopRunning() }
        logger.info("Camera capture session stopped")
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        detector.process(pixelBuffer: pixelBuffer)
    }

    private func publish(_ observations: [ObjectCandidate]) {
        guard runningOnMain else { return }
        let objects = observations.map { observation in
            DetectedObject(label: observation.label, box: observation.box, confidence: observation.confidence, distanceMeters: nil)
        }
        onDetections?(objects)
    }
}

private enum CameraSetupError: Error {
    case noRearCamera
    case cannotAddInput
    case cannotAddOutput
    case startFailed
}
