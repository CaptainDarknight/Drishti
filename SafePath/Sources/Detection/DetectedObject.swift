import Foundation
import CoreGraphics

struct DetectedObject: Identifiable {
    let id = UUID()
    let label: String
    let box: CGRect
    let confidence: Float
    let distanceMeters: Double?
    var horizontalPosition: CGFloat { box.midX }
}
