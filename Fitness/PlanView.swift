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
                    PageTitle("Your plan") {
                        PageRoundButton("gearshape", label: "Settings") { showingSettings = true }
                    }
                }
                .pageTitleRow()

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
                }

                if !templatesRaw.isEmpty {
                    Section {
                        Button("Reset to the original plan", role: .destructive) { confirmingReset = true }
                    }
                }
            }
            .navigationTitle("Your plan")                // used for the back button on pushed pages
            .toolbar(.hidden, for: .navigationBar)       // the title row above is drawn like Today's
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
// Opens read-only. Edit makes a working copy and shows everything on one page: the name as a big
// title, and for each exercise its sets (− / +), reps, remove, and a link to make a superset with
// the next one. Drag ≡ to reorder. Nothing is saved until ✓; ✕ throws the copy away.

struct WorkoutTemplateEditor: View {
    let workoutID: String
    var isNew: Bool = false                              // a new workout: starts in edit mode, saved on ✓
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @AppStorage(PlanTemplate.templatesKey) private var templatesRaw = ""
    @State private var draft: WorkoutTemplate?          // non-nil while editing
    @State private var editMode: EditMode = .inactive
    @State private var showingAdd = false
    @State private var openedEditor = false   // opened straight into edit mode once
    @FocusState private var nameFocused: Bool

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
                // Big editable title, with the focus (worked out from the exercises) under it.
                Section {
                    // Big editable title with a small pencil after it; tap anywhere on it to type.
                    HStack(spacing: 8) {
                        // The field is as wide as the name itself (an invisible copy of the text sets
                        // the width), so the pencil sits right after the name.
                        Text(nameBinding.wrappedValue.isEmpty ? "Workout name" : nameBinding.wrappedValue)
                            .font(.title2.bold())
                            .lineLimit(1)
                            .padding(.trailing, 4)
                            .hidden()
                            .overlay(alignment: .leading) {
                                TextField("Workout name", text: nameBinding)
                                    .font(.title2.bold())
                                    .focused($nameFocused)
                            }
                        Image(systemName: "pencil")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { nameFocused = true }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                }
            }
            exerciseSections
            if isEditing {
                Section {
                    Button { showingAdd = true } label: {
                        Text("Add exercise")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Capsule().fill(Color(.systemGray5)))
                    }
                    .buttonStyle(.borderless)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
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
        .contentMargins(.top, 4, for: .scrollContent)   // name sits close under the ✕ / ✓ bar
        .navigationTitle("")   // no workout name in the middle of the top bar
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEditing)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingAdd) {
            AddExerciseSheet(current: Set(shown?.exercises.map(\.id) ?? [])) { ex in
                var added = ex
                added.superset = nil   // a new exercise starts on its own
                draftBinding.wrappedValue.exercises.append(added)
            }
        }
    }

    // Exercises in cards: runs of normal exercises share a card; each superset gets its own card
    // labelled "Superset". Drag (iOS handles) reorders within a card; long-press an exercise →
    // Move up / Move down moves it across cards.
    private struct IndexedExercise: Identifiable {
        let index: Int
        let exercise: ExerciseTemplate
        var id: String { exercise.id }
    }

    private struct ExerciseGroup: Identifiable {
        let range: Range<Int>
        let isSuperset: Bool
        var id: Int { range.lowerBound }
    }

    private func groups(_ list: [ExerciseTemplate]) -> [ExerciseGroup] {
        var out: [ExerciseGroup] = []
        var i = 0
        while i < list.count {
            var j = i + 1
            if let tag = list[i].superset {
                while j < list.count, list[j].superset == tag { j += 1 }
            }
            let isSuperset = j - i > 1
            if !isSuperset {
                // a run of normal exercises shares one card, up to the next superset
                while j < list.count {
                    if let t = list[j].superset, j + 1 < list.count, list[j + 1].superset == t { break }
                    j += 1
                }
            }
            out.append(ExerciseGroup(range: i..<j, isSuperset: isSuperset))
            i = j
        }
        return out
    }

    @ViewBuilder
    private var exerciseSections: some View {
        let list: [ExerciseTemplate] = (isEditing ? draft?.exercises : saved?.exercises) ?? []
        let all: [ExerciseGroup] = groups(list)
        ForEach(all) { g in
            Section {
                groupRows(g, list)
            } header: {
                if g.isSuperset {
                    HStack {
                        Label("Superset", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if isEditing {
                            // Move the whole superset one place up / down.
                            supersetArrow("arrow.up", range: g.range, up: true, canMove: g.range.lowerBound > 0)
                            supersetArrow("arrow.down", range: g.range, up: false,
                                          canMove: g.range.upperBound < list.count)
                        }
                    }
                } else if g.id == 0 {
                    Text("Exercises")
                }
            } footer: {
                if isEditing && g.range.upperBound < list.count {
                    // Link between this card and the next one, in the gap between them.
                    linkControl(g.range.upperBound - 1)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                } else if !isEditing && g.id == all.last?.id {
                    Text("Tap Edit to change this workout.")
                }
            }
        }
    }

    @ViewBuilder
    private func groupRows(_ g: ExerciseGroup, _ list: [ExerciseTemplate]) -> some View {
        if isEditing {
            // Rows are identified by exercise (not position), so a moved row keeps its identity
            // and the rows around it don't redraw.
            ForEach(g.range.map { IndexedExercise(index: $0, exercise: list[$0]) }) { item in
                // The divider + link pill sits inside the card between exercises; the link between
                // two cards goes in the gap below the card (see the footer).
                editRow(item.index, item.exercise, isLast: item.index == g.range.upperBound - 1)
                    .contextMenu { moveMenu(item.index, count: list.count) }
            }
            .onMove { from, to in
                let start = g.range.lowerBound
                moveExercises(from: IndexSet(from.map { $0 + start }), to: to + start)
            }
        } else {
            ForEach(g.range.map { IndexedExercise(index: $0, exercise: list[$0]) }) { item in
                exerciseRow(item.exercise)
            }
        }
    }

    private func supersetArrow(_ icon: String, range: Range<Int>, up: Bool, canMove: Bool) -> some View {
        Button {
            withAnimation { moveSuperset(range, up: up) }
        } label: {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!canMove)
        .opacity(canMove ? 1 : 0.3)
        .accessibilityLabel(up ? "Move superset up" : "Move superset down")
    }

    // Blocks = single exercises, or whole supersets (next-to-each-other exercises with one tag).
    private func blockRanges(_ list: [ExerciseTemplate]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var i = 0
        while i < list.count {
            var j = i + 1
            if let tag = list[i].superset {
                while j < list.count, list[j].superset == tag { j += 1 }
            }
            out.append(i..<j)
            i = j
        }
        return out
    }

    // Swap the superset with the block (exercise or superset) above / below it.
    private func moveSuperset(_ range: Range<Int>, up: Bool) {
        guard var d = draft else { return }
        let list = d.exercises
        var chunks = blockRanges(list).map { Array(list[$0]) }
        guard let k = blockRanges(list).firstIndex(of: range) else { return }
        let other = up ? k - 1 : k + 1
        guard chunks.indices.contains(other) else { return }
        chunks.swapAt(k, other)
        d.exercises = chunks.flatMap { $0 }
        draft = d
    }

    @ViewBuilder
    private func moveMenu(_ i: Int, count: Int) -> some View {
        if i > 0 {
            Button("Move up", systemImage: "arrow.up") { withAnimation { swapExercises(i, i - 1) } }
        }
        if i < count - 1 {
            Button("Move down", systemImage: "arrow.down") { withAnimation { swapExercises(i, i + 1) } }
        }
    }

    private func swapExercises(_ a: Int, _ b: Int) {
        guard var d = draft, d.exercises.indices.contains(a), d.exercises.indices.contains(b) else { return }
        d.exercises.swapAt(a, b)
        draft = d
    }

    // One exercise while editing: name and remove, then sets (− / +) and reps, then the
    // superset link to the next exercise. Drag the ≡ handle to reorder.
    private func editRow(_ i: Int, _ ex: ExerciseTemplate, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(ex.name).font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    withAnimation { _ = draftBinding.wrappedValue.exercises.remove(at: i) }
                } label: {
                    Image(systemName: "trash").font(.footnote).foregroundStyle(.secondary)
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(ex.name)")
            }
            // Sets and reps on one line: "Sets − 3 +      Reps 10–12"
            HStack(spacing: 4) {
                Text("Sets").font(.subheadline).foregroundStyle(.secondary)
                setStepButton("minus", i, by: -1)
                Text("\(ex.sets)")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .frame(minWidth: 18)
                setStepButton("plus", i, by: 1)
                Spacer(minLength: 12)
                Text(ex.isTimed ? "Time" : "Reps").font(.subheadline).foregroundStyle(.secondary)
                repStepButton("minus", i, ex, up: false)
                Text(ex.isTimed ? "\(ex.repCount) s" : "\(ex.repCount)")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .frame(minWidth: ex.isTimed ? 40 : 24)
                repStepButton("plus", i, ex, up: true)
            }
            // Our own divider to the next exercise, with the link pill in the middle of it.
            if !isLast { linkDivider(i).padding(.top, 6) }
        }
        .padding(.top, 4)
        .padding(.bottom, isLast ? 4 : 0)
        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: isLast ? 12 : 0, trailing: 20))
        .listRowSeparator(.hidden)   // our own divider (with the link pill) replaces the system lines
    }

    // ———— + Link as superset ———— (or ———— Unlink ————)
    private func linkDivider(_ i: Int) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color(.separator)).frame(height: 0.5)
            linkControl(i).fixedSize()
            Rectangle().fill(Color(.separator)).frame(height: 0.5)
        }
        .frame(height: 24)
    }

    private func setStepButton(_ icon: String, _ i: Int, by delta: Int) -> some View {
        let sets = draft?.exercises[safe: i]?.sets ?? 3
        let atLimit = delta < 0 ? sets <= 1 : sets >= 10
        return Button {
            setsBinding(i).wrappedValue = min(10, max(1, sets + delta))
        } label: {
            Image(systemName: icon)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.primary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .opacity(atLimit ? 0.3 : 1)
        .accessibilityLabel(delta < 0 ? "Fewer sets" : "More sets")
    }

    private func setsBinding(_ i: Int) -> Binding<Int> {
        Binding(get: { draftBinding.wrappedValue.exercises[safe: i]?.sets ?? 3 },
                set: { v in if draftBinding.wrappedValue.exercises.indices.contains(i) { draftBinding.wrappedValue.exercises[i].sets = v } })
    }

    // Reps (or seconds) as a single number with − / +: 1 rep steps, or 5 s steps for timed holds.
    // Anything after the number ("/ leg", "/ side") is kept; a range like 10–12 becomes 10.
    private func repStepButton(_ icon: String, _ i: Int, _ ex: ExerciseTemplate, up: Bool) -> some View {
        let step = ex.isTimed ? 5 : 1
        let low = ex.isTimed ? 5 : 1
        let atLimit = !up && ex.repCount <= low
        return Button {
            guard var d = draft, d.exercises.indices.contains(i) else { return }
            let n = max(low, min(300, ex.repCount + (up ? step : -step)))
            d.exercises[i].reps = ExerciseTemplate.reps(n, keepingSuffixOf: d.exercises[i].reps, timed: ex.isTimed)
            draft = d
        } label: {
            Image(systemName: icon)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.primary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .buttonRepeatBehavior(.enabled)
        .opacity(atLimit ? 0.3 : 1)
        .accessibilityLabel(up ? (ex.isTimed ? "More time" : "More reps") : (ex.isTimed ? "Less time" : "Fewer reps"))
    }

    private func repsBinding(_ i: Int) -> Binding<String> {
        Binding(get: { draftBinding.wrappedValue.exercises[safe: i]?.reps ?? "" },
                set: { v in if draftBinding.wrappedValue.exercises.indices.contains(i) { draftBinding.wrappedValue.exercises[i].reps = v } })
    }

    // "Link with next as superset", or "Superset with next · Unlink" when they're already linked.
    private func linkControl(_ i: Int) -> some View {
        let list = draftBinding.wrappedValue.exercises
        let linked = list[i].superset != nil && list[i].superset == list[i + 1].superset
        // A small pill centred on the divider: "+ Link as superset", or just "Unlink" once linked.
        return Button {
            withAnimation { if linked { unlink(after: i) } else { link(i, i + 1) } }
        } label: {
            Text(linked ? "Unlink" : "+ Link as superset")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(
                    Capsule().fill(Color(.secondarySystemGroupedBackground))
                        .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 0.5))
                )
        }
        .buttonStyle(.borderless)
    }

    // iOS has already moved the row on screen when you let go, so apply the new order straight
    // away with no extra SwiftUI animation (that second animation made the row "settle" late).
    private func moveExercises(from: IndexSet, to: Int) {
        guard var d = draft else { return }
        d.exercises.move(fromOffsets: from, toOffset: to)
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { draft = d }
    }

    // Put exercises a and b (next to each other) in the same superset.
    private func link(_ a: Int, _ b: Int) {
        var ex = draftBinding.wrappedValue.exercises
        let tag = ex[a].superset ?? ex[b].superset ?? "\(workoutID)-\(UUID().uuidString.prefix(6))"
        let old = ex[b].superset
        ex[a].superset = tag
        ex[b].superset = tag
        // If b was already in a superset with the ones after it, bring those along too.
        if let old, old != tag {
            for k in (b + 1)..<ex.count where ex[k].superset == old { ex[k].superset = tag }
        }
        draftBinding.wrappedValue.exercises = ex
    }

    // Split the superset between exercise i and i + 1: everything after i gets its own group.
    private func unlink(after i: Int) {
        var ex = draftBinding.wrappedValue.exercises
        guard let tag = ex[i].superset else { return }
        let newTag = "\(workoutID)-\(UUID().uuidString.prefix(6))"
        var k = i + 1
        while k < ex.count, ex[k].superset == tag { ex[k].superset = newTag; k += 1 }
        draftBinding.wrappedValue.exercises = ex
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

    // ✕: back to the Plan tab without saving.
    private func cancel() {
        dismiss()
    }

    private func startNewIfNeeded() {
        // Tapping a workout on the Plan tab opens it straight in edit mode.
        if !isNew, draft == nil, saved != nil, !openedEditor {
            openedEditor = true
            startEditing()
            return
        }
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
        dismiss()   // ✓: saved, back to the Plan tab
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

// MARK: - Settings (⚙︎ on the Plan tab): units and rest time

struct SettingsView: View {
    @AppStorage("units") private var unitsRaw = UnitSystem.imperial.rawValue
    @AppStorage("restSeconds") private var restSeconds = 80   // same key Today's rest timer uses
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Plain text choice: the selected one in bold, the other in grey — no pill or circle.
                    HStack(spacing: 18) {
                        Text("Units")
                        Spacer()
                        unitChoice("Imperial", UnitSystem.imperial)
                        unitChoice("Metric", UnitSystem.metric)
                    }
                }
                Section("Rest timer") {
                    PlainStepper(title: "Rest between sets", value: $restSeconds,
                                 range: 10...300, step: 10) { clock($0) }
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

    private func unitChoice(_ label: String, _ unit: UnitSystem) -> some View {
        let selected = unitsRaw == unit.rawValue
        return Button(label) { unitsRaw = unit.rawValue }
            .buttonStyle(.borderless)
            .font(.body.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// A row with a label, then plain − value + (no grey control), like the − / + on Today.
// Hold − or + to keep changing.
struct PlainStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let format: (Int) -> String

    init(title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int,
         format: @escaping (Int) -> String) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer()
            button("minus", label: "Less") { value = max(range.lowerBound, value - step) }
                .opacity(value <= range.lowerBound ? 0.3 : 1)
            Text(format(value))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 44)
            button("plus", label: "More") { value = min(range.upperBound, value + step) }
                .opacity(value >= range.upperBound ? 0.3 : 1)
        }
    }

    private func button(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.primary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel("\(label) \(title.lowercased())")
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
