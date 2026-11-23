import SwiftUI

struct DetectionOverlayView: View {
    let objects: [DetectedObject]
    var body: some View {
        GeometryReader { proxy in
            ForEach(objects) { object in
                let r = object.box
                let rect = CGRect(x: r.minX * proxy.size.width, y: (1 - r.maxY) * proxy.size.height, width: r.width * proxy.size.width, height: r.height * proxy.size.height)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10).stroke(Color.yellow, lineWidth: 3)
                    Text(object.label + (object.distanceMeters.map { String(format: " %.1fm", $0) } ?? ""))
                        .font(.custom(AppTypography.fontName, size: 13, relativeTo: .footnote).weight(.bold))
                        .foregroundStyle(.black).padding(5).background(.yellow, in: RoundedRectangle(cornerRadius: 5)).offset(y: -27)
                }.frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
