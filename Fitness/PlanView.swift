import SwiftUI

// Plan tab: units and your workout templates (tap one to see and edit it).
struct PlanView: View {
    @AppStorage("units") private var unitsRaw = UnitSystem.imperial.rawValue
    @AppStorage(PlanTemplate.templatesKey) private var templatesRaw = ""
    @State private var confirmingReset = false

    private var workouts: [WorkoutTemplate] { PlanTemplate.templates(from: templatesRaw) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Units", selection: $unitsRaw) {
                        Text("Imperial").tag(UnitSystem.imperial.rawValue)
                        Text("Metric").tag(UnitSystem.metric.rawValue)
                    }.pickerStyle(.segmented)
                }

                Section {
                    ForEach(workouts) { w in
                        NavigationLink(value: w.id) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(w.title).font(.headline)
                                Text("\(w.exercises.count) exercises · \(w.exercises.reduce(0) { $0 + $1.sets }) sets")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Workouts")
                } footer: {
                    Text("Tap a workout to see it and change its exercises, sets and reps. Changes apply from your next session.")
                }

                if !templatesRaw.isEmpty {
                    Section {
                        Button("Reset to the original plan", role: .destructive) { confirmingReset = true }
                    }
                }
            }
            .navigationTitle("Your plan")
            .navigationDestination(for: String.self) { id in
                WorkoutTemplateEditor(workoutID: id)
            }
            .confirmationDialog("Reset all workouts to the original plan?", isPresented: $confirmingReset,
                                titleVisibility: .visible) {
                Button("Reset", role: .destructive) { templatesRaw = "" }
            } message: {
                Text("Your changes to workout names, exercises, sets and reps are undone. Logged sets are kept.")
            }
        }
    }
}

// MARK: - One workout: rename, reorder, add, remove and edit exercises

struct WorkoutTemplateEditor: View {
    let workoutID: String
    @AppStorage(PlanTemplate.templatesKey) private var templatesRaw = ""
    @State private var showingAdd = false

    private var workouts: [WorkoutTemplate] { PlanTemplate.templates(from: templatesRaw) }
    private var workout: WorkoutTemplate? { workouts.first { $0.id == workoutID } }

    // Save one changed workout (all workouts are stored together).
    private func update(_ change: (inout WorkoutTemplate) -> Void) {
        var all = workouts
        guard let i = all.firstIndex(where: { $0.id == workoutID }) else { return }
        change(&all[i])
        templatesRaw = PlanTemplate.encodeTemplates(all)
    }

    private var titleBinding: Binding<String> {
        Binding(get: { workout?.title ?? "" },
                set: { newTitle in update { $0.title = newTitle } })
    }

    var body: some View {
        List {
            Section("Name") {
                TextField("Workout name", text: titleBinding)
            }

            Section {
                ForEach(workout?.exercises ?? []) { ex in
                    NavigationLink {
                        ExerciseTemplateEditor(workoutID: workoutID, exerciseID: ex.id)
                    } label: {
                        exerciseRow(ex)
                    }
                }
                .onMove { from, to in update { $0.exercises.move(fromOffsets: from, toOffset: to) } }
                .onDelete { offsets in update { $0.exercises.remove(atOffsets: offsets) } }

                Button {
                    showingAdd = true
                } label: {
                    Label("Add exercise", systemImage: "plus")
                }
            } header: {
                Text("Exercises")
            } footer: {
                Text("Tap an exercise to change its sets, reps or superset. Use Edit to reorder or remove.")
            }
        }
        .navigationTitle(workout?.title ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(isPresented: $showingAdd) {
            AddExerciseSheet(current: Set(workout?.exercises.map(\.id) ?? [])) { ex in
                update { w in
                    var added = ex
                    added.superset = nil   // a new exercise starts on its own
                    w.exercises.append(added)
                }
            }
        }
    }

    private func exerciseRow(_ ex: ExerciseTemplate) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ex.name).font(.subheadline.weight(.semibold))
            Text(detail(ex)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func detail(_ ex: ExerciseTemplate) -> String {
        var text = "\(ex.sets) × \(ex.reps)"
        if let tag = ex.superset { text += " · superset \(supersetNumber(tag))" }
        return text
    }

    // Superset tags shown as 1, 2… in the order they appear in this workout.
    private func supersetNumber(_ tag: String) -> Int {
        var tags: [String] = []
        for e in workout?.exercises ?? [] {
            if let t = e.superset, !tags.contains(t) { tags.append(t) }
        }
        return (tags.firstIndex(of: tag) ?? 0) + 1
    }
}

// MARK: - One exercise in a workout: name, sets, reps, superset

struct ExerciseTemplateEditor: View {
    let workoutID: String
    let exerciseID: String
    @AppStorage(PlanTemplate.templatesKey) private var templatesRaw = ""

    private var workouts: [WorkoutTemplate] { PlanTemplate.templates(from: templatesRaw) }
    private var workout: WorkoutTemplate? { workouts.first { $0.id == workoutID } }
    private var exercise: ExerciseTemplate? { workout?.exercises.first { $0.id == exerciseID } }

    private func update(_ change: (inout ExerciseTemplate) -> Void) {
        var all = workouts
        guard let w = all.firstIndex(where: { $0.id == workoutID }),
              let e = all[w].exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        change(&all[w].exercises[e])
        templatesRaw = PlanTemplate.encodeTemplates(all)
    }

    private var setsBinding: Binding<Int> {
        Binding(get: { exercise?.sets ?? 3 }, set: { v in update { $0.sets = v } })
    }
    private var repsBinding: Binding<String> {
        Binding(get: { exercise?.reps ?? "" }, set: { v in update { $0.reps = v } })
    }

    // Superset choices: on its own, or together with the exercise above / below.
    private var neighbours: (above: ExerciseTemplate?, below: ExerciseTemplate?) {
        guard let list = workout?.exercises, let i = list.firstIndex(where: { $0.id == exerciseID }) else { return (nil, nil) }
        return (i > 0 ? list[i - 1] : nil, i + 1 < list.count ? list[i + 1] : nil)
    }

    var body: some View {
        Form {
            if let ex = exercise {
                Section {
                    Text(ex.name).font(.headline)
                }
                Section {
                    Stepper("Sets: \(ex.sets)", value: setsBinding, in: 1...10)
                    HStack {
                        Text(ex.isTimed ? "Time" : "Reps")
                        Spacer()
                        TextField("10–12", text: repsBinding)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Reps can be a range like 10–12, \"8 / leg\", or a time like \"30–40 s\" for holds.")
                }
                Section {
                    supersetControls(ex)
                } header: {
                    Text("Superset")
                } footer: {
                    Text("Exercises in a superset are done back to back, one set of each, then rest.")
                }
            } else {
                Text("This exercise isn't in the workout any more.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(exercise?.name ?? "Exercise")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func supersetControls(_ ex: ExerciseTemplate) -> some View {
        let n = neighbours
        if ex.superset != nil {
            Button("Take out of the superset", role: .destructive) { update { $0.superset = nil } }
        }
        if let above = n.above, above.superset == nil || above.superset != ex.superset {
            Button("Superset with \(above.name) (above)") { join(above) }
        }
        if let below = n.below, below.superset == nil || below.superset != ex.superset {
            Button("Superset with \(below.name) (below)") { join(below) }
        }
    }

    // Put this exercise in the same superset as `other` (giving `other` a new tag if it has none).
    private func join(_ other: ExerciseTemplate) {
        var all = workouts
        guard let w = all.firstIndex(where: { $0.id == workoutID }),
              let o = all[w].exercises.firstIndex(where: { $0.id == other.id }),
              let e = all[w].exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let tag = all[w].exercises[o].superset ?? "\(workoutID)-\(UUID().uuidString.prefix(6))"
        all[w].exercises[o].superset = tag
        all[w].exercises[e].superset = tag
        templatesRaw = PlanTemplate.encodeTemplates(all)
    }
}
