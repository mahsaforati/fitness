import SwiftUI
import AVFoundation
import UIKit

// MARK: - How-to page (design A: "Hero 4:5")
//
// A full-width 4:5 video at the top with the exercise name over it, round Back and Pause buttons
// floating over the video, then Steps / Muscles / Avoid tabs, and the plan in a bar at the bottom.
//
// Video spec for the animator: 4:5 portrait, 1080 × 1350 px, 30 fps, one rep (~4 s) as a seamless loop,
// MP4 in HEVC (H.265) at ~1.2 Mbps, no audio, plain flat background (or transparent) → ~0.5–0.7 MB each.
// Keep the figure out of the top ~165 px (buttons), the bottom ~235 px (exercise name) and ~55 px at each side.
//
// Until those are done, every exercise shows the same placeholder clip (HowToPlaceholder.mp4, a 9:16 squat).
// It's fitted to the height of the 4:5 frame; the sides are filled with a blurred copy of the same video.

enum HowToVideo {
    // Placeholder for every exercise until the new animations are finished.
    static let placeholderURL = Bundle.main.url(forResource: "HowToPlaceholder", withExtension: "mp4")

    // The video for an exercise. Swap this for a per-exercise lookup once the new videos exist.
    static func url(for exerciseID: String) -> URL? { placeholderURL }

    // Shown behind the video while it loads (and if a video file is missing).
    static let backdrop = LinearGradient(
        colors: [Color(red: 0.298, green: 0.369, blue: 0.310),    // #4C5E4F
                 Color(red: 0.451, green: 0.549, blue: 0.486),    // #738C7C
                 Color(red: 0.592, green: 0.675, blue: 0.604)],   // #97AC9A
        startPoint: .top, endPoint: .bottom)
}

private enum HowTone {
    static let ink      = Color(red: 0.110, green: 0.098, blue: 0.090) // #1C1917
    static let sage     = Color(red: 0.890, green: 0.910, blue: 0.878) // #E3E8E0
    static let sageText = Color(red: 0.247, green: 0.353, blue: 0.231) // #3F5A3B
    static let page     = Color(red: 0.980, green: 0.980, blue: 0.976) // #FAFAF9
    static let workedBG = Color(red: 0.965, green: 0.867, blue: 0.843) // #F6DDD7
    static let workedFG = Color(red: 0.541, green: 0.180, blue: 0.110) // #8A2E1C
    static let chipBG   = Color(red: 0.941, green: 0.937, blue: 0.933) // #F0EFEE
}

struct ExerciseHowToView: View {
    let exercise: ExerciseTemplate

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: HowTab = .steps
    @State private var playing = true

    private var details: HowToDetails { HowToDetails(id: exercise.id) }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Section", selection: $tab) {
                            ForEach(HowTab.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        tabContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .ignoresSafeArea(.container, edges: .top)   // the video runs up under the status bar

            topButtons
        }
        .background(HowTone.page)
        .safeAreaInset(edge: .bottom) { planBar }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { playing = !reduceMotion }
    }

    // MARK: Video + title

    private var hero: some View {
        Color.clear
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                ZStack {
                    HowToVideo.backdrop
                    if let url = HowToVideo.url(for: exercise.id) {
                        LoopingVideoView(url: url, playing: playing)
                            .accessibilityLabel("Video of \(exercise.name)")
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    if let category = details.category {
                        Text(category.uppercased())
                            .font(.footnote.weight(.semibold))
                            .tracking(0.5)
                            .foregroundStyle(HowTone.ink.opacity(0.8))
                    }
                    Text(exercise.name)
                        .font(.largeTitle.bold())
                        .foregroundStyle(HowTone.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(20)
            }
            .clipped()
    }

    private var topButtons: some View {
        HStack {
            CircleIconButton(systemName: "chevron.left", label: "Back") { dismiss() }
            Spacer()
            CircleIconButton(systemName: playing ? "pause.fill" : "play.fill",
                             label: playing ? "Pause video" : "Play video") { playing.toggle() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Tabs

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .steps:
            if details.steps.isEmpty {
                Text("No steps for this one yet.").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(details.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(HowTone.sageText)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(HowTone.sage))
                            Text(step)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        case .muscles:
            VStack(alignment: .leading, spacing: 16) {
                ChipFlow(spacing: 8) {
                    ForEach(details.primary, id: \.self) { chip($0, worked: true) }
                    ForEach(details.secondary, id: \.self) { chip($0, worked: false) }
                }
                if let equipment = details.equipment {
                    LabeledContent("Equipment", value: equipment.capitalized)
                }
            }
        case .avoid:
            if let avoid = details.avoid, !avoid.isEmpty {
                Text(avoid.prefix(1).uppercased() + avoid.dropFirst())
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Nothing noted for this one.").foregroundStyle(.secondary)
            }
        }
    }

    private func chip(_ name: String, worked: Bool) -> some View {
        Text(name.capitalized)
            .font(.subheadline.weight(worked ? .semibold : .regular))
            .foregroundStyle(worked ? HowTone.workedFG : HowTone.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(worked ? HowTone.workedBG : HowTone.chipBG))
    }

    // MARK: Plan bar

    private var planBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Plan").font(.caption).foregroundStyle(.secondary)
                Text("\(exercise.sets) × \(exercise.reps)").font(.headline)
            }
            Spacer()
            if let partners = supersetPartners {
                Label("Superset with \(partners)", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white)
        .overlay(alignment: .top) { Divider() }
    }

    // "Push-ups" — the other exercises in this one's superset, or nil if it isn't in one.
    private var supersetPartners: String? {
        guard exercise.superset != nil,
              let w = PlanTemplate.phase1.first(where: { $0.exercises.contains(exercise) }) else { return nil }
        let names = PlanTemplate.supersetGroup(of: exercise, in: w)
            .filter { $0.id != exercise.id }
            .map(\.name)
        return names.isEmpty ? nil : names.joined(separator: " and ")
    }
}

private enum HowTab: String, CaseIterable, Identifiable {
    case steps, muscles, avoid
    var id: Self { self }
    var title: String {
        switch self {
        case .steps: "Steps"
        case .muscles: "Muscles"
        case .avoid: "Avoid"
        }
    }
}

// Steps, muscles and tips for any exercise: the plan's own write-ups first, then the big list.
private struct HowToDetails {
    var steps: [String] = []
    var avoid: String?
    var primary: [String] = []
    var secondary: [String] = []
    var equipment: String?
    var category: String?     // "Upper legs · Dumbbell"

    init(id: String) {
        if let info = ExerciseLibrary.info(for: id) {
            steps = info.steps
            avoid = info.avoid
            primary = info.muscles
            if let c = ExerciseCatalog.planVideos[id].flatMap({ ExerciseCatalog.exercise(id: $0) }) {
                equipment = c.equipment
                category = "\(c.bodyPart.capitalized) · \(c.equipment.capitalized)"
            }
        } else if let c = ExerciseCatalog.exercise(id: id) {
            steps = c.steps
            avoid = c.avoid
            primary = [c.target]
            secondary = c.secondary
            equipment = c.equipment
            category = "\(c.bodyPart.capitalized) · \(c.equipment.capitalized)"
        }
    }
}

// MARK: - Pieces

private struct CircleIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(HowTone.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.9)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// Chips that wrap onto new lines.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowH = max(rowH, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

// MARK: - Looping video

// Plays a video on a silent loop, fitted inside its frame with a blurred fill behind it.
// Doesn't stop music you have playing.
struct LoopingVideoView: UIViewRepresentable {
    let url: URL
    var playing: Bool

    // The video fitted in the middle, over a blurred, zoomed-in copy of the same video that fills
    // the rest of the frame. A narrower clip (like the 9:16 placeholder) then has no visible edges:
    // the sides are its own background, blurred. Both layers share one player, so they stay in sync.
    final class PlayerView: UIView {
        let fillLayer = AVPlayerLayer()
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        let videoLayer = AVPlayerLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            fillLayer.videoGravity = .resizeAspectFill
            videoLayer.videoGravity = .resizeAspect
            layer.addSublayer(fillLayer)
            addSubview(blur)
            layer.addSublayer(videoLayer)   // added last, so it sits above the blur
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func attach(_ player: AVPlayer) {
            fillLayer.player = player
            videoLayer.player = player
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fillLayer.frame = bounds.insetBy(dx: -20, dy: -20)   // a little bigger, so the blur has no soft edge
            blur.frame = bounds
            videoLayer.frame = bounds
            CATransaction.commit()
        }
    }

    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerView {
        // Mix with other audio so opening How never pauses the user's music or podcast.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])

        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        context.coordinator.player = player

        let view = PlayerView()
        view.backgroundColor = .clear
        view.attach(player)
        if playing { player.play() }
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        guard let player = context.coordinator.player else { return }
        if playing { player.play() } else { player.pause() }
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: Coordinator) {
        coordinator.player?.pause()
        coordinator.looper?.disableLooping()
    }
}

// MARK: - Swipe back with a hidden navigation bar

// The How page hides the navigation bar to draw its own Back button over the video; this keeps
// the edge swipe-back gesture working there.
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
