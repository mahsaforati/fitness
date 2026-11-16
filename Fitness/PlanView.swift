import SwiftUI

// Plan tab: your workout templates (tap one to see and edit it); ⚙︎ top right opens Settings.
struct PlanView: View {
    @AppStorage(PlanTemplate.templatesKey) private var templatesRaw = ""
    @State private var confirmingReset = false
    @State private var showingSettings = false

    private var workouts: [WorkoutTemplate] { PlanTemplate.templates(from: templatesRaw) }

    // A new workout gets the next free letter: D, E… (or W27, W28… after Z).
    private var nextWorkoutID: String {
        let used = Set(workouts.map(\.id))
        for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" where !used.contains(String(c)) { return String(c) }
        var n = 27
        while used.contains("W\(n)") { n += 1 }
        return "W\(n)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(workouts) { w in
                        NavigationLink(value: w.id) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(w.displayTitle).font(.headline)
                                Text("\(w.exercises.count) exercises · \(w.exercises.reduce(0) { $0 + $1.sets }) sets")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    NavigationLink(value: "new:" + nextWorkoutID) {
                        Label("New workout", systemImage: "plus")
                    }
                } header: {
                    Text("Workouts")
                } footer: {
                    Text("Tap a workout to see it; tap Edit there to change it. Workouts come up on Today in this order (A → B → C …).")
                }

                if !templatesRaw.isEmpty {
                    Section {
                        Button("Reset to the original plan", role: .destructive) { confirmingReset = true }
                    }
                }
            }
            .navigationTitle("Your plan")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .navigationDestination(for: String.self) { value in
                if value.hasPrefix("new:") {
                    WorkoutTemplateEditor(workoutID: String(value.dropFirst(4)), isNew: true)
                } else {
                    WorkoutTemplateEditor(workoutID: value)
                }
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

// MARK: - One workout
// Opens read-only. Edit makes a working copy: rename, add, remove, reorder (drag), and tap an
// exercise to change its sets, reps or superset. Nothing is saved until ✓; ✕ throws the copy away.

private struct ExerciseRef: Hashable, Identifiable { let id: String }

struct WorkoutTemplateEditor: View {
    let workoutID: String
    var isNew: Bool = false                              // a new workout: starts in edit mode, saved on ✓
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @AppStorage(PlanTemplate.templatesKey) private var templatesRaw = ""
    @State private var draft: WorkoutTemplate?          // non-nil while editing
    @State private var editMode: EditMode = .inactive
    @State private var showingAdd = false
    @State private var editingExercise: ExerciseRef?

    private var workouts: [WorkoutTemplate] { PlanTemplate.templates(from: templatesRaw) }
    private var saved: WorkoutTemplate? { workouts.first { $0.id == workoutID } }
    private var shown: WorkoutTemplate? { draft ?? saved }
    private var isEditing: Bool { draft != nil }

    // Edits the name only ("Workout A"); the focus isn't typed, it comes from the exercises.
    private var nameBinding: Binding<String> {
        Binding(get: { draftBinding.wrappedValue.name },
                set: { draftBinding.wrappedValue.title = $0 })
    }

    private var draftBinding: Binding<WorkoutTemplate> {
        Binding(get: { draft ?? saved ?? WorkoutTemplate(id: workoutID, title: "", exercises: []) },
                set: { draft = $0 })
    }

    var body: some View {
        List {
            if isEditing {
                Section {
                    TextField("Workout name", text: nameBinding)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Focus: \(draftBinding.wrappedValue.focus) — worked out from the exercises.")
                }
            } else if let w = saved {
                Section {
                    LabeledContent("Focus", value: w.focus)
                }
            }
            Section {
                exerciseRows
                if isEditing {
                    Button { showingAdd = true } label: { Label("Add exercise", systemImage: "plus") }
                }
            } header: {
                Text("Exercises")
            } footer: {
                Text(isEditing
                     ? "Tap an exercise to change its sets, reps or superset. Drag to reorder, or tap ⊖ to remove. Tap ✓ to save."
                     : "Tap Edit to change this workout.")
            }
            if isEditing && saved != nil && workouts.count > 1 {
                Section {
                    Button("Delete workout", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .onAppear(perform: startNewIfNeeded)
        .confirmationDialog("Delete \(saved?.name ?? "this workout")?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete workout", role: .destructive, action: deleteWorkout)
        } message: {
            Text("It's removed from your plan. Sets you've already logged are kept.")
        }
        .environment(\.editMode, $editMode)
        .navigationTitle(shown?.name ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEditing)
        .toolbar { toolbarContent }
        .navigationDestination(item: $editingExercise) { ref in
            ExerciseTemplateEditor(workout: draftBinding, exerciseID: ref.id)
        }
        .sheet(isPresented: $showingAdd) {
            AddExerciseSheet(current: Set(shown?.exercises.map(\.id) ?? [])) { ex in
                var added = ex
                added.superset = nil   // a new exercise starts on its own
                draftBinding.wrappedValue.exercises.append(added)
            }
        }
    }

    @ViewBuilder
    private var exerciseRows: some View {
        if isEditing {
            ForEach(draftBinding.wrappedValue.exercises) { ex in
                Button { editingExercise = ExerciseRef(id: ex.id) } label: {
                    HStack {
                        exerciseRow(ex)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .foregroundStyle(Color.primary)
            }
            .onMove { from, to in draftBinding.wrappedValue.exercises.move(fromOffsets: from, toOffset: to) }
            .onDelete { offsets in draftBinding.wrappedValue.exercises.remove(atOffsets: offsets) }
        } else {
            ForEach(saved?.exercises ?? []) { ex in
                exerciseRow(ex)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .cancellationAction) {
                Button { cancel() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Cancel changes")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button { save() } label: { Image(systemName: "checkmark") }
                    .accessibilityLabel("Save changes")
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { startEditing() }
            }
        }
    }

    private func startEditing() {
        draft = saved
        withAnimation { editMode = .active }
    }

    private func cancel() {
        if isNew && saved == nil {   // never saved: nothing to go back to
            dismiss()
            return
        }
        withAnimation {
            draft = nil
            editMode = .inactive
        }
    }

    private func startNewIfNeeded() {
        guard isNew, saved == nil, draft == nil else { return }
        draft = WorkoutTemplate(id: workoutID, title: "Workout \(workoutID)", exercises: [])
        editMode = .active
    }

    private func deleteWorkout() {
        var all = workouts
        all.removeAll { $0.id == workoutID }
        guard !all.isEmpty else { return }
        templatesRaw = PlanTemplate.encodeTemplates(all)
        draft = nil
        editMode = .inactive
        dismiss()
    }

    private func save() {
        guard var edited = draft else { return }
        // Store just the name; the focus is always worked out from the exercises.
        edited.title = edited.name.trimmingCharacters(in: .whitespaces)
        if edited.title.isEmpty { edited.title = saved?.name ?? "Workout \(workoutID)" }
        var all = workouts
        if let i = all.firstIndex(where: { $0.id == workoutID }) {
            all[i] = edited
        } else {
            all.append(edited)   // a new workout joins the end of the plan
        }
        templatesRaw = PlanTemplate.encodeTemplates(all)
        withAnimation {
            draft = nil
            editMode = .inactive
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
        for e in shown?.exercises ?? [] {
            if let t = e.superset, !tags.contains(t) { tags.append(t) }
        }
        return (tags.firstIndex(of: tag) ?? 0) + 1
    }
}

// MARK: - One exercise in the workout being edited: sets, reps, superset
// Changes go into the working copy; they're saved with the workout's ✓.

struct ExerciseTemplateEditor: View {
    @Binding var workout: WorkoutTemplate
    let exerciseID: String

    private var index: Int? { workout.exercises.firstIndex { $0.id == exerciseID } }

    private var setsBinding: Binding<Int> {
        Binding(get: { index.map { workout.exercises[$0].sets } ?? 3 },
                set: { v in if let i = index { workout.exercises[i].sets = v } })
    }
    private var repsBinding: Binding<String> {
        Binding(get: { index.map { workout.exercises[$0].reps } ?? "" },
                set: { v in if let i = index { workout.exercises[i].reps = v } })
    }

    var body: some View {
        Form {
            if let i = index {
                let ex = workout.exercises[i]
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
                    supersetControls(i)
                } header: {
                    Text("Superset")
                } footer: {
                    Text("Exercises in a superset are done back to back, one set of each, then rest.")
                }
            } else {
                Text("This exercise isn't in the workout any more.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(index.map { workout.exercises[$0].name } ?? "Exercise")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func supersetControls(_ i: Int) -> some View {
        let list = workout.exercises
        let ex = list[i]
        if ex.superset != nil {
            Button("Take out of the superset", role: .destructive) { workout.exercises[i].superset = nil }
        }
        if i > 0, list[i - 1].superset == nil || list[i - 1].superset != ex.superset {
            Button("Superset with \(list[i - 1].name) (above)") { join(i, with: i - 1) }
        }
        if i + 1 < list.count, list[i + 1].superset == nil || list[i + 1].superset != ex.superset {
            Button("Superset with \(list[i + 1].name) (below)") { join(i, with: i + 1) }
        }
    }

    // Put exercise `i` in the same superset as exercise `o` (giving `o` a new tag if it has none).
    private func join(_ i: Int, with o: Int) {
        let tag = workout.exercises[o].superset ?? "\(workout.id)-\(UUID().uuidString.prefix(6))"
        workout.exercises[o].superset = tag
        workout.exercises[i].superset = tag
    }
}

// MARK: - Settings (⚙︎ on the Plan tab): units and rest time

struct SettingsView: View {
    @AppStorage("units") private var unitsRaw = UnitSystem.imperial.rawValue
    @AppStorage("restSeconds") private var restSeconds = 80   // same key Today's rest timer uses
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Units", selection: $unitsRaw) {
                        Text("Imperial").tag(UnitSystem.imperial.rawValue)
                        Text("Metric").tag(UnitSystem.metric.rawValue)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Rest timer") {
                    Stepper(value: $restSeconds, in: 10...300, step: 10) {
                        HStack {
                            Text("Rest between sets")
                            Spacer()
                            Text(clock(restSeconds)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }

            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func clock(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
}
