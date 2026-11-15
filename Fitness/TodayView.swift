import SwiftUI
import SwiftData

// Today: log every set right on this screen.
// - The exercise you're on opens up with a row per set (swipe left to remove one); finished exercises close with a ✓ and the next one opens.
// - Tap a set row to log it with last session's numbers; tap a logged row to change it right there (− / +).
// - "Same as last time" logs all remaining sets in one tap; "+ Add set" adds an extra set.
// - Everything saves as soon as you log it (one record per set per day), and a rest timer starts.
struct TodayView: View {
    @AppStorage("units") private var unitsRaw = UnitSystem.imperial.rawValue
    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .imperial }
    @AppStorage(PlanTemplate.overrideKey) private var overrideRaw = ""
    @AppStorage("restSeconds") private var restSeconds = 80   // 1:20
    @AppStorage(PlanTemplate.editsKey) private var editsRaw = ""   // today's added/removed exercises
    @Environment(\.modelContext) private var context
    @Query(sort: \SetLog.date) private var allLogs: [SetLog]

    @State private var path: [ExerciseTemplate] = []
    @State private var expandedID: String? = nil      // nil = follow progress; "" = all closed
    @State private var extraSets: [String: Int] = [:]  // sets added (+) or removed (−) vs the plan, for today
    @State private var editing: SetEdit?
    @State private var restEnd: Date?
    @State private var logCount = 0
    @State private var restDoneCount = 0
    @State private var showingAdd = false
    @State private var pendingRemoval: ExerciseTemplate?
    @State private var confirmingReset = false
    @State private var showingWorkouts = false
    // Shared with WorkoutHeader: picking another workout after finishing brings back its Start button.
    @AppStorage("workoutTimerFinished") private var timerFinished = false
    @AppStorage("workoutTimerStarted") private var timerStarted = false
    @AppStorage("workoutTimerStart") private var timerStartedAt = 0.0
    @AppStorage("workoutTimerElapsed") private var timerElapsed = 0.0

    private var today: Date { .now }
    private var dayStart: Date { Calendar.current.startOfDay(for: .now) }
    private var scheduled: WorkoutTemplate { PlanTemplate.scheduledWorkout(for: today) }
    private var planned: WorkoutTemplate { PlanTemplate.workout(for: today, override: overrideRaw) }
    private var editKey: String { PlanTemplate.editKey(today, planned.id) }
    private var dayEdit: DayEdit { PlanTemplate.edits(from: editsRaw)[editKey] ?? DayEdit() }
    // What you're doing today: the plan with today's removals/additions. The plan itself is untouched.
    private var workout: WorkoutTemplate { PlanTemplate.applying(dayEdit, to: planned) }

    // Picking the scheduled workout clears the override.
    private func pickWorkout(_ id: String) {
        overrideRaw = id == scheduled.id ? "" : "\(PlanTemplate.dayKey(today))|\(id)"
    }

    // "Workout A" with its focus ("Lower body") underneath, and a small dumbbell button at the end.
    // The button opens Your workouts (A, B, C with previews) to swap today's workout.
    private var titleRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 10) {
                // "Workout A · Lower body" → "Workout A" on top, "Lower body" smaller underneath
                let parts = workout.title.components(separatedBy: " · ")
                VStack(alignment: .leading, spacing: 0) {
                    Text(parts[0])
                        .font(.title.bold())
                        .foregroundStyle(Tone.ink)
                        .lineLimit(1)
                    if parts.count > 1 {
                        Text(parts.dropFirst().joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
                Button { showingWorkouts = true } label: {
                    Image(systemName: "dumbbell.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.267, green: 0.251, blue: 0.235))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(red: 0.906, green: 0.898, blue: 0.894)))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Your workouts")
            }
        }
        .padding(.top, 8)
    }

    var body: some View {
        let states = workout.exercises.map(state(for:))
        let doneCount = states.filter(\.done).count
        let openID = expandedID ?? states.first(where: { !$0.done })?.ex.id

        NavigationStack(path: $path) {
            List {
                Section {
                    titleRow
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                        .listRowSeparator(.hidden)
                    // Same section as the title so there's only a small gap between them.
                    WorkoutHeader(done: doneCount, total: states.count)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 16, leading: 4, bottom: 0, trailing: 4))
                        .listRowSeparator(.hidden)
                }

                ForEach(blocks(states)) { b in
                    blockSection(b, openID: openID)
                }

                Section {
                    Button { showingAdd = true } label: {
                        Label("Add exercise", systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                    }
                } footer: {
                    if !dayEdit.isEmpty {
                        HStack {
                            Text(editSummary)
                            Spacer()
                            Button("Reset to plan") { confirmingReset = true }.font(.footnote.bold())
                        }
                    }
                }
            }
            .navigationTitle(workout.title)          // used for the back button on pushed pages
            .toolbar(.hidden, for: .navigationBar)   // Today draws its own title row (with the swap button)
            .navigationDestination(for: ExerciseTemplate.self) { ExerciseHowToView(exercise: $0) }
            .sheet(isPresented: $showingWorkouts) {
                WorkoutsSheet(todayID: planned.id, scheduledID: scheduled.id, onPick: pickWorkout)
            }
            .sheet(isPresented: $showingAdd) {
                AddExerciseSheet(current: Set(workout.exercises.map(\.id)), onAdd: addExercise)
            }
            .confirmationDialog("Remove \(pendingRemoval?.name ?? "exercise") from today?",
                                isPresented: Binding(get: { pendingRemoval != nil },
                                                     set: { if !$0 { pendingRemoval = nil } }),
                                titleVisibility: .visible,
                                presenting: pendingRemoval) { ex in
                Button("Remove and delete today's sets", role: .destructive) { removeExercise(ex) }
            } message: { _ in
                Text("The sets you've logged for it today will be deleted. Your plan won't change.")
            }
            .confirmationDialog("Reset today to the plan?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { resetEdits() }
            } message: {
                Text("Removed exercises come back. Exercises you added, and any sets logged for them today, are removed.")
            }
            .safeAreaInset(edge: .bottom) {
                if let end = restEnd {
                    RestBar(end: end,
                            add: { restEnd = end.addingTimeInterval(10) },
                            skip: { restEnd = nil })
                }
            }
            .task(id: restEnd) {
                guard let end = restEnd else { return }
                try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
                if !Task.isCancelled, restEnd == end {
                    restEnd = nil
                    restDoneCount += 1
                }
            }
            .sensoryFeedback(.success, trigger: logCount)
            .sensoryFeedback(.impact(weight: .heavy), trigger: restDoneCount)
            .onChange(of: workout.id) {
                expandedID = nil
                extraSets = [:]
                if timerFinished { resetTimer() }   // finished one workout, now doing another
            }
        }
    }

    // MARK: - Supersets
    // The list is split into blocks: runs of normal exercises, and each superset on its own
    // section with a "Superset" header. Opening any exercise of a superset opens all of them.

    private struct Block: Identifiable {
        let tag: String?          // superset tag, nil for normal exercises
        var states: [ExState]
        var id: String { states.first?.ex.id ?? "" }
        var isSuperset: Bool { tag != nil && states.count > 1 }
    }

    private func blocks(_ states: [ExState]) -> [Block] {
        var out: [Block] = []
        for s in states {
            if let last = out.last, last.tag == s.ex.superset {
                out[out.count - 1].states.append(s)
            } else {
                out.append(Block(tag: s.ex.superset, states: [s]))
            }
        }
        return out
    }

    @ViewBuilder
    private func blockSection(_ b: Block, openID: String?) -> some View {
        let groupOpen = b.isSuperset && b.states.contains { $0.ex.id == openID }
        Section {
            ForEach(Array(b.states.enumerated()), id: \.element.ex.id) { i, s in
                let badge: Int? = b.isSuperset ? i + 1 : nil
                if s.ex.id == openID || groupOpen {
                    expandedRows(s, badge: badge)
                } else {
                    collapsedRow(s, badge: badge)
                }
            }
        } header: {
            if b.isSuperset {
                Label("Superset", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Tone.ink)
            }
        } footer: {
            if b.isSuperset {
                Text("Do one set of each back to back, then rest.")
            }
        }
    }

    // Small numbered circle showing an exercise's place in its superset (1, 2…).
    @ViewBuilder
    private func supersetBadge(_ n: Int?) -> some View {
        if let n {
            Text("\(n)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Tone.ink))
        }
    }

    // MARK: - Rows

    private func collapsedRow(_ s: ExState, badge: Int? = nil) -> some View {
        Button {
            withAnimation { expandedID = s.ex.id; editing = nil }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        supersetBadge(badge)
                        Text(s.ex.name).font(.headline).foregroundStyle(Color.primary)
                    }
                    Text(collapsedSubtitle(s)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if s.done {
                    Image(systemName: "checkmark").font(.subheadline.bold()).foregroundStyle(Tone.check)
                        .accessibilityLabel("Done")
                } else {
                    Image(systemName: "chevron.down").font(.footnote).foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) { removeButton(s, iconOnly: true) }
        .contextMenu { removeButton(s) }
    }

    // Swipe shows just the trash icon (VoiceOver still reads "Remove from today"); the long-press menu keeps the text.
    private func removeButton(_ s: ExState, iconOnly: Bool = false) -> some View {
        Button { requestRemove(s) } label: {
            if iconOnly {
                Image(systemName: "trash").accessibilityLabel("Remove from today")
            } else {
                Label("Remove from today", systemImage: "trash")
            }
        }
        .tint(.red)
    }

    // The open exercise: a header row, one row per set, then a row with "+ Add set" / "Same as last time".
    @ViewBuilder
    private func expandedRows(_ s: ExState, badge: Int? = nil) -> some View {
        HStack(alignment: .top) {
            Button {
                withAnimation { expandedID = ""; editing = nil }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        supersetBadge(badge)
                        Text(s.ex.name).font(.headline).foregroundStyle(Color.primary)
                    }
                    Text(planLine(s)).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            if ExerciseLibrary.info(for: s.ex.id) != nil || ExerciseCatalog.exercise(id: s.ex.id) != nil {
                Button { path.append(s.ex) } label: {
                    Text("How")
                        .font(.footnote.bold())
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color(.systemGray5)))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) { removeButton(s, iconOnly: true) }
        .contextMenu { removeButton(s) }

        ForEach(0..<s.count, id: \.self) { i in
            setRow(s, i + 1)
        }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation { extraSets[s.ex.id] = s.count + 1 - s.ex.sets }
                } label: {
                    Label("Add set", systemImage: "plus").font(.subheadline).foregroundStyle(Color.primary)
                }
                .buttonStyle(.borderless)
                Spacer()
                if !s.last.isEmpty && !s.done {
                    Button { sameAsLastTime(s) } label: {
                        Text("Same as last time ✓")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color(.systemGray5)))
                    }
                    .buttonStyle(.borderless)
                }
            }
            Text("Tap a set to log it · tap a logged set to change it · swipe left to remove")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    // A set row, or the inline − / + editor when that set is being edited.
    @ViewBuilder
    private func setRow(_ s: ExState, _ n: Int) -> some View {
        if let e = editing, e.exercise.id == s.ex.id, e.setNumber == n {
            InlineSetEditor(edit: e, units: units,
                            onSave: { edit in withAnimation { editing = nil }; saveEdit(edit) },
                            onRemove: { withAnimation { editing = nil; removeSet(s.ex, n) } },
                            onCancel: { withAnimation { editing = nil } })
                .id(e.id)
                .listRowBackground(Color(.secondarySystemGroupedBackground))
        } else {
            setButtonRow(s, n)
        }
    }

    private func setButtonRow(_ s: ExState, _ n: Int) -> some View {
        let log = s.logged[n]
        let sug = suggestion(s, n)
        let value: String = log.map { setText($0.weightKg, $0.reps) } ?? (sug.known ? setText(sug.kg, sug.reps) : "Tap to enter")
        return Button {
            if let log {
                withAnimation {
                    editing = SetEdit(exercise: s.ex, setNumber: n, weight: displayWeight(log.weightKg),
                                      reps: log.reps, isLogged: true)
                }
            } else if sug.known {
                logSet(s.ex, n, kg: sug.kg, reps: sug.reps)
            } else {
                // First time: nothing to copy yet, so ask for the numbers.
                withAnimation {
                    editing = SetEdit(exercise: s.ex, setNumber: n, weight: displayWeight(sug.kg),
                                      reps: sug.reps, isLogged: false)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text("Set \(n)")
                    .foregroundStyle(log != nil ? Tone.ink : Color.secondary)
                Spacer()
                Text(value)
                    .font(.body.weight(log != nil ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(log != nil ? Tone.ink : Color.secondary)
            }
            .padding(.leading, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .listRowBackground(log != nil ? Tone.done : Color(.secondarySystemGroupedBackground))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation { removeSet(s.ex, n) }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .contextMenu {
            if log == nil {
                Button("Change before logging", systemImage: "slider.horizontal.3") {
                    editing = SetEdit(exercise: s.ex, setNumber: n, weight: displayWeight(sug.kg),
                                      reps: sug.reps, isLogged: false)
                }
            }
        }
    }

    // MARK: - Data for one exercise

    private struct ExState {
        let ex: ExerciseTemplate
        let logged: [Int: SetLog]   // today's sets by set number
        let last: [Int: SetLog]     // previous session's sets by set number
        let count: Int              // set rows shown today (plan ± added/removed sets)
        var done: Bool { (0..<count).allSatisfy { logged[$0 + 1] != nil } }
    }

    private func state(for ex: ExerciseTemplate) -> ExState {
        let start = dayStart
        let mine = allLogs.filter { $0.exerciseID == ex.id }
        var logged: [Int: SetLog] = [:]
        for log in mine where log.date >= start && logged[log.setNumber] == nil { logged[log.setNumber] = log }
        var last: [Int: SetLog] = [:]
        if let latest = mine.last(where: { $0.date < start }) {
            let day = Calendar.current.startOfDay(for: latest.date)
            for log in mine where log.date >= day && log.date < start && last[log.setNumber] == nil {
                last[log.setNumber] = log
            }
        }
        let count = max(ex.sets + extraSets[ex.id, default: 0], logged.keys.max() ?? 0, 0)
        return ExState(ex: ex, logged: logged, last: last, count: count)
    }

    // What a set row offers: last session's same set, else the set before it today,
    // else last session's last set. `known` is false when there's no history yet.
    private func suggestion(_ s: ExState, _ n: Int) -> (kg: Double, reps: Int, known: Bool) {
        if let l = s.last[n] { return (l.weightKg, l.reps, true) }
        if let p = s.logged.filter({ $0.key < n }).max(by: { $0.key < $1.key })?.value { return (p.weightKg, p.reps, true) }
        if let l = s.last.max(by: { $0.key < $1.key })?.value { return (l.weightKg, l.reps, true) }
        return (0, Int(s.ex.reps.prefix(while: \.isNumber)) ?? 10, false)
    }

    private func collapsedSubtitle(_ s: ExState) -> String {
        var parts = ["\(s.ex.sets) × \(s.ex.reps)"]
        let count = s.logged.count
        if count > 0 && !s.done { parts.append("\(count)/\(s.count) sets") }
        if let w = lastWeight(s) { parts.append(w) }
        return parts.joined(separator: " · ")
    }

    private func planLine(_ s: ExState) -> String {
        guard let w = lastWeight(s) else { return "\(s.ex.sets) × \(s.ex.reps)" }
        return "\(s.ex.sets) × \(s.ex.reps) · last time \(w)"
    }

    private func lastWeight(_ s: ExState) -> String? {
        guard let kg = s.last.values.map(\.weightKg).max(), kg > 0 else { return nil }
        return "\(format(kg)) \(units.label)"
    }

    // MARK: - Saving (every change saves right away)

    private func logSet(_ ex: ExerciseTemplate, _ n: Int, kg: Double, reps: Int, startRest: Bool = true) {
        let before = state(for: ex)
        upsert(ex.id, n, kg: kg, reps: reps)
        try? context.save()
        logCount += 1
        guard startRest else { return }
        // In a superset, rest only once every exercise in it has done this round's set.
        if roundComplete(ex, n) {
            restEnd = .now.addingTimeInterval(TimeInterval(restSeconds))
        } else {
            restEnd = nil
        }
        let nowDone = (0..<before.count).allSatisfy { before.logged[$0 + 1] != nil || $0 + 1 == n }
        if !before.done && nowDone { advance(from: ex) }
    }

    private func sameAsLastTime(_ s: ExState) {
        for i in 0..<s.count where s.logged[i + 1] == nil {
            let n = i + 1
            let v = suggestion(s, n)
            upsert(s.ex.id, n, kg: v.kg, reps: v.reps)
        }
        try? context.save()
        logCount += 1
        advance(from: s.ex)
    }

    private func saveEdit(_ e: SetEdit) {
        logSet(e.exercise, e.setNumber, kg: units.toKg(e.weight), reps: e.reps, startRest: !e.isLogged)
    }

    // Remove a set row: delete its record (if logged) and renumber the sets after it.
    private func removeSet(_ ex: ExerciseTemplate, _ n: Int) {
        let s = state(for: ex)
        if let log = s.logged[n] { context.delete(log) }
        for (k, log) in s.logged where k > n { log.setNumber = k - 1 }
        extraSets[ex.id] = s.count - 1 - ex.sets
        try? context.save()
    }

    // One record per set per day: update today's record if there is one.
    private func upsert(_ exerciseID: String, _ n: Int, kg: Double, reps: Int) {
        let start = dayStart
        if let existing = allLogs.first(where: { $0.exerciseID == exerciseID && $0.setNumber == n && $0.date >= start }) {
            existing.weightKg = kg
            existing.reps = reps
        } else {
            context.insert(SetLog(exerciseID: exerciseID, setNumber: n, weightKg: kg, reps: reps))
        }
    }

    // MARK: - Editing today's exercises (saved for today only, never changes the plan)

    private var editSummary: String {
        var parts: [String] = []
        if !dayEdit.removed.isEmpty { parts.append("\(dayEdit.removed.count) removed") }
        if !dayEdit.added.isEmpty { parts.append("\(dayEdit.added.count) added") }
        return "Changed for today only · " + parts.joined(separator: ", ")
    }

    private func updateEdit(_ change: (inout DayEdit) -> Void) {
        // Past days' edits are kept (a few bytes each) so the Calendar can count against what you actually did.
        var all = PlanTemplate.edits(from: editsRaw)
        var e = all[editKey] ?? DayEdit()
        change(&e)
        all[editKey] = e.isEmpty ? nil : e
        editsRaw = PlanTemplate.encode(all)
    }

    // Ask first only if sets were already logged for it today.
    private func requestRemove(_ s: ExState) {
        if s.logged.isEmpty { removeExercise(s.ex) } else { pendingRemoval = s.ex }
    }

    private func resetTimer() {
        timerStartedAt = 0
        timerElapsed = 0
        timerFinished = false
        withAnimation(.easeOut(duration: 0.25)) { timerStarted = false }
    }

    private func removeExercise(_ ex: ExerciseTemplate) {
        deleteTodaysLogs(of: ex.id)
        extraSets[ex.id] = nil
        if expandedID == ex.id { expandedID = nil }
        withAnimation {
            updateEdit { e in
                if let i = e.added.firstIndex(of: ex.id) { e.added.remove(at: i) }
                else if !e.removed.contains(ex.id) { e.removed.append(ex.id) }
            }
        }
    }

    // Re-adding a planned exercise you removed puts it back in its usual place.
    private func addExercise(_ ex: ExerciseTemplate) {
        withAnimation {
            updateEdit { e in
                if let i = e.removed.firstIndex(of: ex.id) { e.removed.remove(at: i) }
                else if !e.added.contains(ex.id) { e.added.append(ex.id) }
            }
            expandedID = ex.id
        }
    }

    private func resetEdits() {
        for id in dayEdit.added { deleteTodaysLogs(of: id); extraSets[id] = nil }
        withAnimation {
            updateEdit { $0 = DayEdit() }
            expandedID = nil
        }
    }

    private func deleteTodaysLogs(of exerciseID: String) {
        let start = dayStart
        for log in allLogs where log.exerciseID == exerciseID && log.date >= start { context.delete(log) }
        try? context.save()
    }

    // True when set `n` of `ex` was the last one needed for this round of its superset
    // (every other exercise in it has set n logged, or has fewer than n sets). Always true for normal exercises.
    private func roundComplete(_ ex: ExerciseTemplate, _ n: Int) -> Bool {
        PlanTemplate.supersetGroup(of: ex, in: workout).allSatisfy { m in
            guard m.id != ex.id else { return true }
            let ms = state(for: m)
            return ms.logged[n] != nil || n > ms.count
        }
    }

    // Close the finished exercise and open the next one that isn't done
    // (another exercise in the same superset first, so the superset stays open until all of it is done).
    private func advance(from ex: ExerciseTemplate) {
        let partners = PlanTemplate.supersetGroup(of: ex, in: workout)
        let next = partners.first { $0.id != ex.id && !state(for: $0).done }
            ?? workout.exercises.first { $0.id != ex.id && !state(for: $0).done }
        withAnimation { expandedID = next?.id ?? ""; editing = nil }
    }

    // MARK: - Formatting

    private func displayWeight(_ kg: Double) -> Double { (units.display(kg) * 10).rounded() / 10 }

    private func format(_ kg: Double) -> String {
        let v = displayWeight(kg)
        return v == v.rounded() ? String(Int(v)) : String(v)
    }

    private func setText(_ kg: Double, _ reps: Int) -> String {
        kg > 0 ? "\(format(kg)) \(units.label) × \(reps)" : "BW × \(reps)"
    }
}

// MARK: - Colours (match the Calendar / Figma)

private enum Tone {
    static let done  = Color(red: 0.890, green: 0.910, blue: 0.878) // #E3E8E0 sage
    static let check = Color(red: 0.420, green: 0.520, blue: 0.400) // darker sage for ✓
    static let ink   = Color(red: 0.110, green: 0.098, blue: 0.090) // #1C1917
}

// MARK: - Inline set editor (− / + for weight and reps)

struct SetEdit: Identifiable {
    let exercise: ExerciseTemplate
    let setNumber: Int
    var weight: Double   // in the units being shown
    var reps: Int
    let isLogged: Bool
    var id: String { "\(exercise.id)-\(setNumber)" }
}

// Shown in place of a set row while you change it.
struct InlineSetEditor: View {
    @State var edit: SetEdit
    let units: UnitSystem
    let onSave: (SetEdit) -> Void
    let onRemove: () -> Void
    let onCancel: () -> Void

    private var step: Double { units == .imperial ? 5 : 2.5 }
    private let ink = Color(red: 0.110, green: 0.098, blue: 0.090)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set \(edit.setNumber)").font(.subheadline.weight(.semibold))

            stepperRow(title: "Weight",
                       value: edit.weight == 0 ? "BW" : "\(weightText) \(units.label)",
                       minus: { edit.weight = max(0, edit.weight - step) },
                       plus: { edit.weight += step })
            stepperRow(title: "Reps",
                       value: "\(edit.reps)",
                       minus: { edit.reps = max(0, edit.reps - 1) },
                       plus: { edit.reps += 1 })

            HStack(spacing: 16) {
                if edit.isLogged {
                    Button("Remove", role: .destructive, action: onRemove)
                        .buttonStyle(.borderless)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Button(edit.isLogged ? "Save" : "Log set") { onSave(edit) }
                    .buttonStyle(.borderedProminent)
                    .tint(ink)
            }
            .font(.subheadline)
        }
        .padding(.leading, 8)
        .padding(.vertical, 6)
    }

    private var weightText: String {
        edit.weight == edit.weight.rounded() ? String(Int(edit.weight)) : String(format: "%.1f", edit.weight)
    }

    private func stepperRow(title: String, value: String,
                            minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Button(action: minus) { Image(systemName: "minus").frame(width: 28, height: 22) }
                .buttonStyle(.bordered)
                .buttonRepeatBehavior(.enabled)
            Text(value)
                .font(.headline).monospacedDigit()
                .frame(minWidth: 64)
            Button(action: plus) { Image(systemName: "plus").frame(width: 28, height: 22) }
                .buttonStyle(.bordered)
                .buttonRepeatBehavior(.enabled)
        }
        .tint(.primary)
    }
}

// MARK: - Add an exercise to today

private struct AddExerciseSheet: View {
    let current: Set<String>                  // exercises already in today's list
    let onAdd: (ExerciseTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var homeOnly = true        // dumbbell + bodyweight only
    @State private var bodyPart = "all"
    @State private var preview: CatalogExercise?

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    // Catalog exercises matching the search and filters.
    private var matches: [CatalogExercise] {
        ExerciseCatalog.all.filter { ex in
            !current.contains(ex.id)
                && (!homeOnly || ExerciseCatalog.homeEquipment.contains(ex.equipment))
                && (bodyPart == "all" || ex.bodyPart == bodyPart)
                && (q.isEmpty || ex.name.lowercased().contains(q) || ex.target.contains(q)
                    || ex.secondary.contains { $0.contains(q) })
        }
    }

    private func planOptions(_ w: WorkoutTemplate) -> [ExerciseTemplate] {
        w.exercises.filter { !current.contains($0.id) && (q.isEmpty || $0.name.lowercased().contains(q)) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Equipment", selection: $homeOnly) {
                        Text("Dumbbell + bodyweight").tag(true)
                        Text("All equipment").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    Picker("Body part", selection: $bodyPart) {
                        Text("All").tag("all")
                        ForEach(ExerciseCatalog.bodyParts, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }

                // Your plan's exercises first (they have your animations).
                if bodyPart == "all" {
                    ForEach(PlanTemplate.phase1) { w in
                        let options = planOptions(w)
                        if !options.isEmpty {
                            Section("Your plan · \(w.title)") {
                                ForEach(options) { ex in
                                    Button { add(ex) } label: {
                                        row(ex.name, "\(ex.sets) × \(ex.reps)")
                                    }
                                }
                            }
                        }
                    }
                }

                Section("All exercises · \(matches.count)") {
                    ForEach(matches) { ex in
                        HStack {
                            Button { add(ExerciseCatalog.template(id: ex.id)) } label: {
                                row(ex.name, "\(ex.target.capitalized) · \(ex.equipment)")
                            }
                            .buttonStyle(.borderless)
                            Button { preview = ex } label: {
                                Image(systemName: "info.circle").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("How to do \(ex.name)")
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search exercises or muscles")
            .navigationTitle("Add to today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(item: $preview) { ex in
                CatalogDetailView(exercise: ex, onAdd: { add(ExerciseCatalog.template(id: ex.id)) })
            }
        }
    }

    private func row(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(Color.primary)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func add(_ ex: ExerciseTemplate?) {
        guard let ex else { return }
        onAdd(ex)
        dismiss()
    }
}

// How-to for an exercise from the big list: muscles, equipment and steps (no pictures).
struct CatalogDetailView: View {
    let exercise: CatalogExercise
    var onAdd: (() -> Void)? = nil

    var body: some View {
        Form {
            Section { ExerciseVideoView(file: exercise.video) }
            Section("How to") {
                ForEach(Array(exercise.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(i + 1)").font(.subheadline.bold()).monospacedDigit()
                        Text(step)
                    }
                }
            }
            Section("Muscles") {
                LabeledContent("Main", value: exercise.target.capitalized)
                if !exercise.secondary.isEmpty {
                    LabeledContent("Also works", value: exercise.secondary.map(\.capitalized).joined(separator: ", "))
                }
                LabeledContent("Equipment", value: exercise.equipment.capitalized)
            }
            if let onAdd {
                Section {
                    Button("Add to today", systemImage: "plus.circle", action: onAdd)
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Workout header: Start button, then progress bar + timer
// Before you start: one big "Start workout" button, no progress bar.
// Once started: a thick bar shows "2 of 6" and the time, with Pause/Resume and Stop beside it.
// Stop asks first, then freezes the bar at your finishing time. Long-press the bar to start over.
// The timer is saved, so it keeps going if you leave the app, and everything resets on a new day.

private struct WorkoutHeader: View {
    let done: Int
    let total: Int

    @AppStorage("workoutTimerStart") private var startedAt = 0.0      // when it was last started; 0 = not running
    @AppStorage("workoutTimerElapsed") private var elapsed = 0.0      // seconds banked before the last start
    @AppStorage("workoutTimerDay") private var day = ""               // day the timer belongs to
    @AppStorage("workoutTimerStarted") private var started = false    // pressed Start today
    @AppStorage("workoutTimerFinished") private var finished = false  // pressed Stop today
    @State private var confirmingStop = false

    private var running: Bool { startedAt > 0 }

    private static let sage     = Color(red: 0.478, green: 0.545, blue: 0.455) // #7A8B74
    private static let sageFill = Color(red: 0.788, green: 0.820, blue: 0.773) // #C9D1C5
    private static let track    = Color(red: 0.906, green: 0.898, blue: 0.894) // #E7E5E4
    private static let stone    = Color(red: 0.267, green: 0.251, blue: 0.235) // #44403C

    var body: some View {
        Group {
            if finished {
                finishedView
            } else if started || running || elapsed > 0 {   // also covers a timer started before this update
                HStack(spacing: 8) {
                    bar
                    circleButton(running ? "pause.fill" : "play.fill",
                                 label: running ? "Pause workout timer" : "Resume workout timer",
                                 action: togglePause)
                    circleButton("stop.fill", label: "Stop workout") { confirmingStop = true }
                }
            } else {
                startButton
            }
        }
        .onAppear(perform: newDayCheck)
        .confirmationDialog("End this workout?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("End workout", role: .destructive, action: stop)
        } message: {
            Text("The timer stops at its current time. Your logged sets stay as they are.")
        }
    }

    // After Stop: the Start button comes back, with "✓ Done in 42:10 · 6 of 6" underneath.
    // Starting again begins a fresh timer; logged sets stay as they are.
    private var finishedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            startButton
            Label("Done in \(format(elapsed)) · \(done) of \(total)", systemImage: "checkmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Tone.check)
                .padding(.leading, 4)
        }
    }

    private var startButton: some View {
        Button(action: start) {
            Label("Start workout", systemImage: "play.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Capsule().fill(Self.sage))
        }
        .buttonStyle(.borderless)
    }

    // Thick bar: progress fill, "2 of 6" on the left, the time on the right.
    private var bar: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            ZStack(alignment: .leading) {
                Capsule().fill(Self.track)
                GeometryReader { geo in
                    Capsule().fill(Self.sageFill)
                        .frame(width: total > 0 && done > 0
                               ? max(34, geo.size.width * CGFloat(done) / CGFloat(total)) : 0)
                }
                HStack {
                    Text(finished ? "Finished · \(done) of \(total)"
                         : running ? "\(done) of \(total)" : "Paused · \(done) of \(total)")
                        .foregroundStyle(Self.stone)
                    Spacer()
                    Text(format(totalTime(at: ctx.date)))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(running || finished ? Tone.ink : Color.secondary)
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
            }
            .frame(height: 36)
            .animation(.easeOut(duration: 0.3), value: done)
        }
        .contentShape(Capsule())
        .contextMenu {
            Button("Start over", systemImage: "arrow.counterclockwise", role: .destructive, action: reset)
        }
        .accessibilityElement(children: .combine)
    }

    private func circleButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(Tone.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Self.track))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    private func totalTime(at date: Date) -> TimeInterval {
        elapsed + (running ? max(0, date.timeIntervalSince1970 - startedAt) : 0)
    }

    private func start() {
        newDayCheck()
        withAnimation(.easeOut(duration: 0.25)) { started = true }
        if finished { elapsed = 0 }   // starting again after finishing: fresh timer
        finished = false
        startedAt = Date.now.timeIntervalSince1970
    }

    private func togglePause() {
        if running {
            elapsed = totalTime(at: .now)
            startedAt = 0
        } else {
            startedAt = Date.now.timeIntervalSince1970
        }
    }

    private func stop() {
        elapsed = totalTime(at: .now)
        startedAt = 0
        finished = true
    }

    private func reset() {
        startedAt = 0
        elapsed = 0
        finished = false
        withAnimation(.easeOut(duration: 0.25)) { started = false }
    }

    // A timer left over from another day starts again from the Start button.
    private func newDayCheck() {
        let today = PlanTemplate.dayKey(.now)
        if day != today {
            reset()
            day = today
        }
    }

    // "4:05", or "1:02:09" past an hour
    private func format(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Rest timer bar

private struct RestBar: View {
    let end: Date
    let add: () -> Void
    let skip: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, Int(end.timeIntervalSince(ctx.date).rounded(.up)))
            HStack(spacing: 12) {
                Image(systemName: "timer")
                Text("Rest \(left / 60):\(String(format: "%02d", left % 60))")
                    .font(.headline).monospacedDigit()
                Spacer()
                Button("+10s", action: add).buttonStyle(.bordered)
                Button("Skip", action: skip).buttonStyle(.bordered)
            }
            .tint(.primary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Your workouts (browse A, B, C with a preview; swap today's workout)

private struct WorkoutsSheet: View {
    let todayID: String
    let scheduledID: String
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(PlanTemplate.phase1) { w in
                    Section {
                        NavigationLink(value: w.id) { card(w) }
                    }
                }
            }
            .navigationTitle("Your workouts")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in
                if let w = PlanTemplate.workout(id: id) {
                    WorkoutPreview(workout: w, isToday: w.id == todayID, isScheduled: w.id == scheduledID) {
                        onPick(w.id)
                        dismiss()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // Title, a badge for today / scheduled, then a short preview of the exercises.
    private func card(_ w: WorkoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(w.title).font(.headline)
                Spacer()
                if w.id == todayID { badge("Today") }
                else if w.id == scheduledID { badge("Scheduled") }
            }
            Text("\(w.exercises.count) exercises · \(w.exercises.reduce(0) { $0 + $1.sets }) sets")
                .font(.caption).foregroundStyle(.secondary)
            Text(w.exercises.map(\.name).joined(separator: " · "))
                .font(.footnote).foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Tone.check)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Tone.done))
    }
}

private struct WorkoutPreview: View {
    let workout: WorkoutTemplate
    let isToday: Bool
    let isScheduled: Bool
    let onPick: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(workout.exercises) { ex in
                    NavigationLink {
                        ExerciseHowToView(exercise: ex)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name).font(.subheadline.weight(.semibold))
                            Text("\(ex.sets) × \(ex.reps)" + (ex.superset != nil ? " · superset" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("Tap an exercise to see how to do it.")
            }
        }
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if isToday {
                Label("This is today's workout", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tone.check)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Capsule().fill(Tone.done))
                    .padding(.horizontal).padding(.bottom, 8)
            } else {
                Button(action: onPick) {
                    Text(isScheduled ? "Go back to the scheduled workout" : "Do this workout today")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Capsule().fill(Color(red: 0.478, green: 0.545, blue: 0.455)))
                }
                .buttonStyle(.borderless)
                .padding(.horizontal).padding(.bottom, 8)
            }
        }
    }
}

// MARK: - How-to page

struct ExerciseHowToView: View {
    let exercise: ExerciseTemplate

    var body: some View {
        Form {
            if let file = ExerciseCatalog.videoFile(for: exercise.id) {
                Section { ExerciseVideoView(file: file) }
            }
            if let info = ExerciseLibrary.info(for: exercise.id) {
                if ExerciseCatalog.videoFile(for: exercise.id) == nil {
                    Section { HowToCarousel(info: info) }   // no video for this one (hip thrust)
                } else {
                    Section("How to") {
                        ForEach(Array(info.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(i + 1)").font(.subheadline.bold()).monospacedDigit()
                                Text(step)
                            }
                        }
                        Text("Avoid: \(info.avoid)").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Muscles") {
                        Text(info.muscles.joined(separator: " · "))
                    }
                }
            } else if let c = ExerciseCatalog.exercise(id: exercise.id) {
                Section("How to") {
                    ForEach(Array(c.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(i + 1)").font(.subheadline.bold()).monospacedDigit()
                            Text(step)
                        }
                    }
                }
                Section("Muscles") {
                    LabeledContent("Main", value: c.target.capitalized)
                    LabeledContent("Equipment", value: c.equipment.capitalized)
                }
            }
            Section("Plan") {
                Text("\(exercise.sets) × \(exercise.reps)")
                if let partners = supersetPartners {
                    Label("Superset with \(partners)", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
        .navigationTitle(exercise.name)
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
