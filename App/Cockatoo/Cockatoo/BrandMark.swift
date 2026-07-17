import SwiftUI

/// Cockatoo's compact-bust identity. The same 100×100 construction is
/// mirrored in `research/brand-assets/app-icon/cockatoo-mark.svg` and the icon
/// renderer. It is drawn from first principles rather than traced from a photo.
enum CockatooMarkStyle {
    case color
    case solid
}

struct CockatooMark: View {
    var style: CockatooMarkStyle = .color
    var bodyColor: Color = Theme.ink
    var crestColor: Color = Theme.gold
    var eyeColor: Color = .clear

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let origin = CGPoint(
                x: (geometry.size.width - side) / 2,
                y: (geometry.size.height - side) / 2
            )
            let markRect = CGRect(origin: origin, size: CGSize(width: side, height: side))
            let crestFill = style == .solid ? bodyColor : crestColor

            ZStack {
                CockatooToolbarCrestRootShape().fill(crestFill)
                CockatooToolbarCrestShape().fill(crestFill)
                CockatooToolbarBodyShape().fill(bodyColor)
                CockatooToolbarUpperBeakShape()
                    .fill(eyeColor)
                    .overlay(CockatooToolbarUpperBeakShape().stroke(bodyColor, lineWidth: side * 0.018))
                Circle()
                    .fill(eyeColor)
                    .frame(width: side * 0.06, height: side * 0.06)
                    .position(x: origin.x + side * 0.69, y: origin.y + side * 0.36)
            }
            .frame(width: markRect.width, height: markRect.height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Menu-bar-specific body based on the selected "Compact Bust" direction.
/// It deliberately uses a short neck instead of the app icon's circular C so
/// the silhouette reads as a cockatoo profile before it reads as a letterform.
struct CockatooToolbarBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let t = BrandTransform(rect: rect)
        var path = Path()

        path.move(to: t.point(29, 92))
        path.addCurve(
            to: t.point(36, 45),
            control1: t.point(34, 78),
            control2: t.point(36, 62)
        )
        path.addCurve(
            to: t.point(55, 14),
            control1: t.point(36, 29),
            control2: t.point(43, 18)
        )
        path.addCurve(
            to: t.point(83, 31),
            control1: t.point(69, 10),
            control2: t.point(80, 18)
        )
        path.addCurve(
            to: t.point(80, 48),
            control1: t.point(85, 38),
            control2: t.point(84, 43)
        )
        path.addCurve(
            to: t.point(73, 65),
            control1: t.point(76, 53),
            control2: t.point(73, 59)
        )
        path.addCurve(
            to: t.point(79, 92),
            control1: t.point(72, 73),
            control2: t.point(75, 84)
        )
        path.addCurve(
            to: t.point(29, 92),
            control1: t.point(65, 98),
            control2: t.point(43, 98)
        )
        path.closeSubpath()
        return path
    }
}

/// Shared root placed behind the head so the feather gaps end cleanly before
/// they reach the head silhouette.
struct CockatooToolbarCrestRootShape: Shape {
    func path(in rect: CGRect) -> Path {
        let t = BrandTransform(rect: rect)
        var path = Path()
        path.move(to: t.point(38, 20))
        path.addCurve(
            to: t.point(54, 36),
            control1: t.point(49, 20),
            control2: t.point(54, 27)
        )
        path.addCurve(
            to: t.point(38, 50),
            control1: t.point(54, 45),
            control2: t.point(48, 50)
        )
        path.addCurve(
            to: t.point(38, 20),
            control1: t.point(42, 42),
            control2: t.point(43, 29)
        )
        path.closeSubpath()
        return path
    }
}

/// Three broad, swept-back feathers whose separated silhouettes remain
/// distinct when the mark is rasterised at status-item size.
struct CockatooToolbarCrestShape: Shape {
    func path(in rect: CGRect) -> Path {
        let t = BrandTransform(rect: rect)
        var path = Path()

        path.move(to: t.point(51, 22))
        path.addCurve(
            to: t.point(12, 3),
            control1: t.point(37, 19),
            control2: t.point(22, 12)
        )
        path.addCurve(
            to: t.point(38, 31),
            control1: t.point(10, 12),
            control2: t.point(19, 24)
        )
        path.addCurve(
            to: t.point(51, 22),
            control1: t.point(44, 32),
            control2: t.point(49, 28)
        )
        path.closeSubpath()

        path.move(to: t.point(47, 29))
        path.addCurve(
            to: t.point(6, 16),
            control1: t.point(31, 29),
            control2: t.point(17, 24)
        )
        path.addCurve(
            to: t.point(39, 39),
            control1: t.point(8, 28),
            control2: t.point(20, 37)
        )
        path.addCurve(
            to: t.point(47, 29),
            control1: t.point(44, 38),
            control2: t.point(47, 34)
        )
        path.closeSubpath()

        path.move(to: t.point(42, 37))
        path.addCurve(
            to: t.point(7, 32),
            control1: t.point(28, 40),
            control2: t.point(16, 38)
        )
        path.addCurve(
            to: t.point(40, 46),
            control1: t.point(12, 44),
            control2: t.point(25, 49)
        )
        path.addCurve(
            to: t.point(42, 37),
            control1: t.point(43, 43),
            control2: t.point(44, 40)
        )
        path.closeSubpath()

        return path
    }
}

/// Broad upper mandible tucked close under the brow: a cockatoo bill rather
/// than the long pointed hook associated with eagle marks.
struct CockatooToolbarUpperBeakShape: Shape {
    func path(in rect: CGRect) -> Path {
        let t = BrandTransform(rect: rect)
        var path = Path()
        path.move(to: t.point(78, 40))
        path.addCurve(to: t.point(93, 46), control1: t.point(84, 36), control2: t.point(91, 39))
        path.addCurve(to: t.point(84, 69), control1: t.point(95, 53), control2: t.point(91, 61))
        path.addCurve(to: t.point(78, 58), control1: t.point(85, 64), control2: t.point(82, 59))
        path.addCurve(to: t.point(72, 51), control1: t.point(74, 59), control2: t.point(71, 56))
        path.addCurve(to: t.point(78, 40), control1: t.point(72, 46), control2: t.point(75, 42))
        path.closeSubpath()
        return path
    }
}

private struct BrandTransform {
    let scale: CGFloat
    let origin: CGPoint

    init(rect: CGRect) {
        let side = min(rect.width, rect.height)
        scale = side / 100
        origin = CGPoint(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2
        )
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }
}
