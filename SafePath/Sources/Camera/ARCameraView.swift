import SwiftUI
import ARKit

struct ARCameraView: UIViewRepresentable {
    @ObservedObject var camera: CameraSession
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = camera.session
        view.automaticallyUpdatesLighting = false
        view.backgroundColor = .black
        return view
    }
    func updateUIView(_ view: ARSCNView, context: Context) { view.session = camera.session }
}
