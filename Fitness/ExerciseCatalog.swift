import Foundation

// The big exercise list (1,324 exercises) you can add to a day from "Add exercise".
// Text only (names, muscles, equipment, steps) from the exercises-dataset by Hasan Emir Yıldırım,
// MIT License — https://github.com/hasaneyldrm/exercises-dataset (notice shown on the Plan tab).
// Its pictures/GIFs are © Gym visual and need a separate licence, so they aren't included.

struct CatalogExercise: Codable, Identifiable, Hashable {
    let id: String          // "lib-0001"
    let name: String
    let bodyPart: String    // "upper legs", "back", "chest"…
    let equipment: String   // "dumbbell", "body weight", "band"…
    let target: String      // main muscle, e.g. "glutes"
    let secondary: [String]
    let steps: [String]
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

    static let licenseNotice = """
    Exercise list from exercises-dataset
    Copyright (c) 2026 Hasan Emir Yıldırım — MIT License

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation and data files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """
}
