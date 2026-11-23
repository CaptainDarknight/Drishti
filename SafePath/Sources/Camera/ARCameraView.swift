import SwiftUI
import AVFoundation
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var camera: CameraSession

    func makeUIView(context: Context) -> CameraPreviewHostView {
        let view = CameraPreviewHostView()
        let preview = AVCaptureVideoPreviewLayer(session: camera.captureSession)
        preview.videoGravity = .resizeAspectFill
        if let connection = preview.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        view.previewLayer = preview
        view.layer.addSublayer(preview)
        return view
    }

    func updateUIView(_ view: CameraPreviewHostView, context: Context) {
        view.previewLayer?.session = camera.captureSession
    }
}

final class CameraPreviewHostView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet { setNeedsLayout() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}
