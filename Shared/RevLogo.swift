import SwiftUI

/// Rev's diamond logo, drawn from the same geometry as rev-ai/assets/logo-mark.svg
/// (24x24 viewBox: diamond 2.5→21.5, stroke 1.8, centre dot r 2.6) so it stays sharp at any size.
struct RevLogo: View {
    static let blue = Color(red: 10 / 255, green: 132 / 255, blue: 1) // #0a84ff
    var color: Color = RevLogo.blue

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let u = side / 24
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 12 * u, y: 2.5 * u))
                    p.addLine(to: CGPoint(x: 21.5 * u, y: 12 * u))
                    p.addLine(to: CGPoint(x: 12 * u, y: 21.5 * u))
                    p.addLine(to: CGPoint(x: 2.5 * u, y: 12 * u))
                    p.closeSubpath()
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.8 * u, lineJoin: .round))
                Circle()
                    .fill(color)
                    .frame(width: 5.2 * u, height: 5.2 * u)
                    .position(x: 12 * u, y: 12 * u)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
