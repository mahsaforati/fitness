import SwiftUI
import UIKit
import ImageIO

// The big exercise list (1,324 exercises) you can add to a day from "Add exercise".
// Text only (names, muscles, equipment, steps) from the exercises-dataset by Hasan Emir Yıldırım,
// MIT License — https://github.com/hasaneyldrm/exercises-dataset (full notice kept below in `licenseNotice`).
// Exercise videos (GIFs) are © Gym visual — https://gymvisual.com/ — used under the owner's licence
// (no on-screen credit required under that licence). The plan's videos are in the app (ExerciseVideos/);
// the rest download the first time you open them and are kept on the phone.

struct CatalogExercise: Codable, Identifiable, Hashable {
    let id: String          // "lib-0001"
    let name: String
    let bodyPart: String    // "upper legs", "back", "chest"…
    let equipment: String   // "dumbbell", "body weight", "band"…
    let target: String      // main muscle, e.g. "glutes"
    let secondary: [String]
    let steps: [String]
    let video: String       // GIF file name, e.g. "0001-2gPfomN.gif"
}

enum ExerciseCatalog {
    static let all: [CatalogExercise] = {
        guard let url = Bundle.main.url(forResource: "ExerciseCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([CatalogExercise].self, from: data) else { return [] }
        return list
    }()

    private static let byID: [String: CatalogExercise] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    static func exercise(id: String) -> CatalogExercise? { byID[id] }

    // Body parts and equipment in the list, for the filters.
    static let bodyParts: [String] = Array(Set(all.map(\.bodyPart))).sorted()
    static let equipment: [String] = Array(Set(all.map(\.equipment))).sorted()

    // What you have at home — the default filter.
    static let homeEquipment: Set<String> = ["dumbbell", "body weight"]

    // A catalog exercise as something you can log: 3 sets of 10–12 (30 s for cardio).
    static func template(id: String) -> ExerciseTemplate? {
        guard let ex = byID[id] else { return nil }
        return ExerciseTemplate(id: ex.id, name: ex.name, sets: 3,
                                reps: ex.bodyPart == "cardio" ? "30 s" : "10–12")
    }

    // Name for any exercise ID: plan exercises first, then the catalog.
    static func name(for id: String) -> String {
        PlanTemplate.allExercises.first { $0.id == id }?.name ?? byID[id]?.name ?? id
    }

    // Videos for the plan's own exercises (plan ID → closest exercise in the list).
    // Hip thrust has no match in the list, so it keeps its old animation.
    static let planVideos: [String: String] = [
        "goblet-squat": "lib-1760", "db-rdl": "lib-1459", "reverse-lunge": "lib-0381",
        "glute-bridge": "lib-3013", "lateral-walk": "lib-0628", "dead-bug": "lib-0276",
        "db-bench": "lib-0289", "one-arm-row": "lib-0292", "seated-press": "lib-0405",
        "rear-delt-fly": "lib-0383", "push-up": "lib-0662", "plank": "lib-2135",
        "db-deadlift": "lib-0300", "step-up": "lib-0431", "chest-row": "lib-0327",
        "arnold-press": "lib-2137", "side-plank": "lib-0705"
    ]

    // The video file for any exercise ID (plan or list), or nil if there isn't one.
    static func videoFile(for id: String) -> String? {
        (byID[id] ?? planVideos[id].flatMap { byID[$0] })?.video
    }

    static let licenseNotice = """
    Exercise list from exercises-dataset
    Copyright (c) 2026 Hasan Emir Yıldırım — MIT License

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation and data files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """
}


// MARK: - Exercise video (looping GIF)

// Loads the GIF from the app, then from the phone's saved copies, else downloads and saves it.
enum ExerciseVideoStore {
    private static let remote = URL(string: "https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/videos/")!

    private static var folder: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ExerciseVideos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func data(for file: String) async -> Data? {
        let name = (file as NSString).deletingPathExtension
        if let url = Bundle.main.url(forResource: name, withExtension: "gif"),
           let d = try? Data(contentsOf: url) { return d }
        let saved = folder.appendingPathComponent(file)
        if let d = try? Data(contentsOf: saved) { return d }
        guard let (d, response) = try? await URLSession.shared.data(from: remote.appendingPathComponent(file)),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        try? d.write(to: saved, options: .atomic)
        return d
    }

    // All frames of a GIF as one looping image, keeping each frame's own timing.
    static func animatedImage(from data: Data) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var frames: [UIImage] = []
        var total = 0.0
        for i in 0..<CGImageSourceGetCount(src) {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            total += max(delay, 0.02)
            frames.append(UIImage(cgImage: cg))
        }
        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(with: frames, duration: total)
    }
}

private struct AnimatedImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return v
    }

    func updateUIView(_ v: UIImageView, context: Context) {
        if v.image !== image { v.image = image }
    }
}

// The looping video for an exercise.
struct ExerciseVideoView: View {
    let file: String
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.white)
                if let image {
                    AnimatedImage(image: image).padding(8)
                } else if failed {
                    Label("Video needs an internet connection the first time", systemImage: "wifi.slash")
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding()
                } else {
                    ProgressView()
                }
            }
            .frame(height: 240)
        }
        .task(id: file) {
            failed = false
            if let d = await ExerciseVideoStore.data(for: file),
               let img = ExerciseVideoStore.animatedImage(from: d) {
                image = img
            } else {
                failed = true
            }
        }
    }
}
