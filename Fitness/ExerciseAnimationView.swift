import SwiftUI

// A simple two-pose figure that loops between a start and end position.
// Coordinates are in a 0...1 square, y pointing down, floor at y = 0.92.
// Placeholder until licensed, realistic animations replace it.

enum BodyPart: Hashable { case arms, torso, legs }
enum Prop { case none, bench, seat, box, incline, lowBench }
enum WeightHold { case none, hand, both, hip }

struct Pose {
    var head: CGPoint
    var shoulder: CGPoint
    var elbow: CGPoint
    var hand: CGPoint
    var hip: CGPoint
    var knee: CGPoint
    var foot: CGPoint
    var elbow2: CGPoint? = nil
    var hand2: CGPoint? = nil
    var knee2: CGPoint? = nil
    var foot2: CGPoint? = nil

    static func lerp(_ a: Pose, _ b: Pose, _ t: CGFloat) -> Pose {
        func l(_ p: CGPoint, _ q: CGPoint) -> CGPoint {
            CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)
        }
        return Pose(head: l(a.head, b.head), shoulder: l(a.shoulder, b.shoulder),
                    elbow: l(a.elbow, b.elbow), hand: l(a.hand, b.hand),
                    hip: l(a.hip, b.hip), knee: l(a.knee, b.knee), foot: l(a.foot, b.foot),
                    elbow2: l(a.elbow2 ?? a.elbow, b.elbow2 ?? b.elbow),
                    hand2: l(a.hand2 ?? a.hand, b.hand2 ?? b.hand),
                    knee2: l(a.knee2 ?? a.knee, b.knee2 ?? b.knee),
                    foot2: l(a.foot2 ?? a.foot, b.foot2 ?? b.foot))
    }
}

/// Shorthand for building poses.
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

struct ExerciseAnimationView: View {
    let info: ExerciseInfo
    var period: Double = 2.6

    private let ink = Color(red: 0.11, green: 0.10, blue: 0.09)
    private let faint = Color(red: 0.66, green: 0.64, blue: 0.62)
    private let worked = Color(red: 0.48, green: 0.55, blue: 0.45)
    private let prop = Color(red: 0.84, green: 0.83, blue: 0.82)

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let t = CGFloat((1 - cos(time * 2 * .pi / period)) / 2)
            let pose = Pose.lerp(info.start, info.end, t)
            Canvas { ctx, size in draw(pose, in: &ctx, size: size) }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Animation of \(info.name)")
    }

    private func draw(_ p: Pose, in ctx: inout GraphicsContext, size: CGSize) {
        let s = min(size.width, size.height)
        let ox = (size.width - s) / 2, oy = (size.height - s) / 2
        func pt(_ q: CGPoint) -> CGPoint { CGPoint(x: ox + q.x * s, y: oy + q.y * s) }
        func line(_ a: CGPoint, _ b: CGPoint, _ color: Color, _ w: CGFloat) {
            var path = Path(); path.move(to: pt(a)); path.addLine(to: pt(b))
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: w * s, lineCap: .round))
        }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            ctx.fill(Path(roundedRect: CGRect(x: ox + x * s, y: oy + y * s, width: w * s, height: h * s),
                          cornerRadius: 0.01 * s), with: .color(prop))
        }
        func color(_ part: BodyPart, far: Bool = false) -> Color {
            let c = info.worked.contains(part) ? worked : ink
            return far ? c.opacity(0.45) : c
        }

        // Floor and props
        line(P(0.06, 0.93), P(0.94, 0.93), prop, 0.012)
        switch info.prop {
        case .none: break
        case .bench:    rect(0.10, 0.72, 0.52, 0.05); rect(0.14, 0.77, 0.04, 0.15); rect(0.54, 0.77, 0.04, 0.15)
        case .seat:     rect(0.34, 0.68, 0.26, 0.24)
        case .box:      rect(0.50, 0.80, 0.26, 0.12)
        case .lowBench: rect(0.06, 0.70, 0.28, 0.22)
        case .incline:
            line(P(0.72, 0.70), P(0.44, 0.46), prop, 0.05)
            rect(0.62, 0.70, 0.04, 0.22)
        }

        let lw: CGFloat = 0.045
        // Far limbs first (lighter), then torso and head, then near limbs.
        line(p.hip, p.knee2 ?? p.knee, color(.legs, far: true), lw)
        line(p.knee2 ?? p.knee, p.foot2 ?? p.foot, color(.legs, far: true), lw)
        line(p.shoulder, p.elbow2 ?? p.elbow, color(.arms, far: true), lw * 0.85)
        line(p.elbow2 ?? p.elbow, p.hand2 ?? p.hand, color(.arms, far: true), lw * 0.85)

        line(p.hip, p.shoulder, color(.torso), lw * 1.3)
        let r = 0.05 * s
        let h = pt(p.head)
        ctx.fill(Path(ellipseIn: CGRect(x: h.x - r, y: h.y - r, width: 2 * r, height: 2 * r)), with: .color(ink))

        line(p.hip, p.knee, color(.legs), lw)
        line(p.knee, p.foot, color(.legs), lw)
        line(p.shoulder, p.elbow, color(.arms), lw * 0.85)
        line(p.elbow, p.hand, color(.arms), lw * 0.85)

        // Dumbbell(s)
        func dumbbell(at c: CGPoint) {
            let q = pt(c), w = 0.07 * s, hgt = 0.04 * s
            ctx.fill(Path(roundedRect: CGRect(x: q.x - w / 2, y: q.y - hgt / 2, width: w, height: hgt),
                          cornerRadius: hgt / 3), with: .color(Color(red: 0.27, green: 0.25, blue: 0.24)))
        }
        switch info.weight {
        case .none: break
        case .hand: dumbbell(at: p.hand)
        case .both: dumbbell(at: p.hand); dumbbell(at: p.hand2 ?? p.hand)
        case .hip:  dumbbell(at: CGPoint(x: p.hip.x, y: p.hip.y - 0.04))
        }
    }
}

/// Swipeable card: page 1 = steps, page 2 = animation.
struct HowToCarousel: View {
    let info: ExerciseInfo

    var body: some View {
        TabView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(info.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)")
                            .font(.caption.bold())
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color(.systemGray5)))
                        Text(step).font(.subheadline)
                    }
                }
                Text("Avoid: \(info.avoid)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Spacer(minLength: 0)
                Text("Swipe for animation →").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 28)

            VStack(spacing: 6) {
                ExerciseAnimationView(info: info)
                Text("Works: " + info.muscles.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 28)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .frame(height: 340)
    }
}
