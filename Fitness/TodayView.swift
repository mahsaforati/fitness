import SwiftUI
import SwiftData

// Today: log every set right on this screen.
// - The exercise you're on opens up with a row per set (swipe left to remove one); finished exercises close with a ✓ and the next one opens.
// - Tap a set row to log it with last session's numbers; tap a logged row to change it right there (− / +).
// - Start with one pre-filled set and a Log button; then Repeat logs the same numbers again and Add opens a new set to change.
// - Everything saves as soon as you log it (one record per set per day), and a rest timer starts:
//   the big ring at the top counts the rest down, then goes back to showing your sets.
// - Each exercise has a ring that fills set by set; a finished one turns green.
struct TodayView: View {
    @AppStorage("units") private var unitsRaw = UnitSystem.imperial.rawValue
    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .imperial }
    @AppStorage(PlanTemplate.overrideKey) private var overrideRaw = ""
    @AppStorage(PlanTemplate.templatesKey) private var templatesRaw = ""   // redraw when the Plan tab edits a workout
    @AppStorage("restSeconds") private var restSeconds = 80   // 1:20
    @AppStorage(PlanTemplate.editsKey) private var editsRaw = ""   // today's added/removed exercises
    @Environment(\.modelContext) private var context
    @Query(sort: \SetLog.date) private var allLogs: [SetLog]

    @State private var path: [ExerciseTemplate] = []
    @State private var expandedID: String? = ""       // nil = follow progress; "" = all closed (how Today starts)
    @State private var extraSets: [String: Int] = [:]  // sets added (+) or removed (−) vs the plan, for today
    @State private var editing: SetEdit?
    @State private var restEnd: Date?
    @State private var restTotal: Double = 80   // seconds this rest started with (+10s adds to it), for the line
    @State private var restFor: String?         // the exercise the rest line shows under
    @State private var logCount = 0
    @State private var restDoneCount = 0
    @State private var showingAdd = false
    @State private var pendingRemoval: ExerciseTemplate?
    @State private var confirmingReset = false
    @State private var showingWorkouts = false
    @State private var justFinished: String?   // exercise held open for a moment before the next one opens
    @State private var celebration: WorkoutCelebration?   // the "Workout done!" screen, shown when every exercise is done
    // First-set numbers changed with − / + before logging (in the units shown), by exercise ID.
    private struct Draft { var weight: Double; var reps: Int }
    @State private var drafts: [String: Draft] = [:]
    // Shared with WorkoutHeader: picking another workout after finishing brings back its Start button.
    @AppStorage("workoutTimerFinished") private var timerFinished = false
    @AppStorage("workoutTimerStarted") private var timerStarted = false
    @AppStorage("workoutTimerStart") private var timerStartedAt = 0.0
    @AppStorage("workoutTimerElapsed") private var timerElapsed = 0.0
    @AppStorage("workoutTimerDay") private var timerDay = ""

    private var today: Date { .now }
    private var dayStart: Date { Calendar.current.startOfDay(for: .now) }
    private var scheduled: WorkoutTemplate { PlanTemplate.scheduledWorkout(for: today, logs: allLogs) }
    private var planned: WorkoutTemplate { PlanTemplate.workout(for: today, override: overrideRaw, logs: allLogs) }
    private var editKey: String { PlanTemplate.editKey(today, planned.id) }
    private var dayEdit: DayEdit { PlanTemplate.edits(from: editsRaw)[editKey] ?? DayEdit() }
    // What you're doing today: the plan with today's removals/additions. The plan itself is untouched.
    private var workout: WorkoutTemplate { PlanTemplate.applying(dayEdit, to: planned) }

    // Picking the scheduled workout clears the override.
    private func pickWorkout(_ id: String) {
        overrideRaw = id == scheduled.id ? "" : "\(PlanTemplate.dayKey(today))|\(id)"
    }

    // The body is split into small pieces so Xcode can type-check it quickly.
    var body: some View {
        NavigationStack(path: $path) {
            withFeedback(withDialogs(withNavigation(todayList)))
        }
    }

    private var todayList: some View {
        let states = workout.exercises.map(state(for:))
        let doneCount = states.filter(\.done).count
        let setsDone = states.reduce(0) { $0 + min($1.logged.count, $1.count) }
        let setsTotal = states.reduce(0) { $0 + $1.count }
        let openID = expandedID ?? states.first(where: { !$0.done })?.ex.id
        return List {
            headerSection(done: doneCount, total: states.count, setsDone: setsDone, setsTotal: setsTotal)
            ForEach(blocks(states)) { b in
                blockSection(b, openID: openID)
            }
            addExerciseSection
        }
        .environment(\.defaultMinListRowHeight, 0)   // lets the rest line sit close under the exercise name
    }

    private func openWorkouts() { showingWorkouts = true }

    // Skip: tap the ring (or the Skip button) while resting. Instant: no fade, the ring jumps straight back to the sets.
    private func skipRest() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { restEnd = nil }
    }

    private func headerSection(done: Int, total: Int, setsDone: Int, setsTotal: Int) -> some View {
        let header = WorkoutHeader(title: workout.displayTitle, done: done, total: total,
                                   setsDone: setsDone, setsTotal: setsTotal,
                                   restEnd: restEnd, restTotal: restTotal, skipRest: skipRest,
                                   showWorkouts: openWorkouts, startOver: clearTodaysSets,
                                   onAllDone: { time in
                                       celebration = WorkoutCelebration(title: workout.name, focus: workout.focus,
                                                                        time: time, sets: setsDone, exercises: total)
                                   })
        return Section {
            header
                .listRowBackground(Color.clear)
                // Its own alignment, separate from the exercises: 12pt in from the card edges on both sides.
                .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                .listRowSeparator(.hidden)
        }
    }

    private var addExerciseSection: some View {
        Section {
            Button { showingAdd = true } label: {
                Label("Add exercise", systemImage: "plus.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
            }
        } footer: {
            editFooter
        }
    }

    @ViewBuilder
    private var editFooter: some View {
        if !dayEdit.isEmpty {
            HStack {
                Text(editSummary)
                Spacer()
                Button("Reset to plan") { confirmingReset = true }
                    .font(.footnote.bold())
            }
        }
    }

    private func withNavigation<V: View>(_ v: V) -> some View {
        v.navigationTitle(workout.name)           // used for the back button on pushed pages
            .toolbar(.hidden, for: .navigationBar)   // Today draws its own title row
            .navigationDestination(for: ExerciseTemplate.self) { ExerciseHowToView(exercise: $0) }
            .sheet(isPresented: $showingWorkouts) {
                WorkoutsSheet(todayID: planned.id, scheduledID: scheduled.id, onPick: pickWorkout)
            }
            .sheet(isPresented: $showingAdd) {
                AddExerciseSheet(current: Set(workout.exercises.map(\.id)), onAdd: addExercise)
            }
            .fullScreenCover(item: $celebration) { c in
                CelebrationView(celebration: c) { celebration = nil }   // Done: back to Today, Start is ready again
            }
    }

    private var removingBinding: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    private func withDialogs<V: View>(_ v: V) -> some View {
        v.confirmationDialog("Remove \(pendingRemoval?.name ?? "exercise") from today?",
                             isPresented: removingBinding,
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
    }

    private func withFeedback<V: View>(_ v: V) -> some View {
        v.task(id: restEnd) { await finishRest() }
            .sensoryFeedback(.success, trigger: logCount)
            .sensoryFeedback(.impact(weight: .heavy), trigger: restDoneCount)
            .onChange(of: workout.id) { workoutChanged() }
    }

    private func finishRest() async {
        guard let end = restEnd else { return }
        try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
        if !Task.isCancelled, restEnd == end {
            restEnd = nil
            restDoneCount += 1
        }
    }

    private func workoutChanged() {
        expandedID = ""   // a newly picked workout starts with every exercise closed
        extraSets = [:]
        if timerFinished { resetTimer() }   // finished one workout, now doing another
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
            if groupOpen {
                supersetRows(b)   // one card: log both exercises of a round at once
            } else {
                ForEach(b.states, id: \.ex.id) { s in
                    if s.ex.id == openID {
                        expandedRows(s)
                    } else {
                        collapsedRow(s)
                    }
                }
            }
        } header: {
            if b.isSuperset {
                Label(groupOpen ? "Superset · Round \(min(completedRounds(b) + 1, roundsTotal(b))) of \(roundsTotal(b))" : "Superset",
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Tone.ink)
            }
        } footer: {
            if b.isSuperset {
                Text("Do one set of each back to back, log the round, then rest.")
            }
        }
    }

    // MARK: - Superset round card
    // Rounds: round n = set n of each exercise. Finished rounds collapse to one line;
    // the current round shows each exercise with − / + for weight and reps, and one "Log round".
    // An exercise with fewer sets drops out of the later rounds. Rest starts after each round.

    private func roundsTotal(_ b: Block) -> Int { b.states.map(\.count).max() ?? 0 }

    private func completedRounds(_ b: Block) -> Int {
        var r = 0
        while r < roundsTotal(b) {
            let n = r + 1
            let complete = b.states.allSatisfy { $0.count < n || $0.logged[n] != nil }
            if !complete { break }
            r = n
        }
        return r
    }

    private func roundNumbers(upTo n: Int) -> [Int] { n > 0 ? Array(1...n) : [] }

    @ViewBuilder
    private func supersetRows(_ b: Block) -> some View {
        let total: Int = roundsTotal(b)
        let finished: Int = completedRounds(b)
        let current: Int = finished + 1
        supersetNames(b)
        ForEach(roundNumbers(upTo: finished), id: \.self) { r in
            doneRoundRow(b, r)
        }
        if current <= total {
            ForEach(Array(b.states.enumerated()), id: \.element.ex.id) { i, st in
                if st.count >= current {
                    roundExerciseRow(st, number: i + 1, round: current)
                }
            }
            logRoundButton(b, round: current, participants: b.states.filter { $0.count >= current })
        } else {
            addRoundButton(b)
        }
    }

    // The exercises, numbered, each with How. Tap outside How to close the superset.
    private func supersetNames(_ b: Block) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(b.states.enumerated()), id: \.element.ex.id) { i, st in
                HStack(spacing: 8) {
                    Text("\(i + 1)")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(width: 14, alignment: .leading)
                    Text(st.ex.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    howButton(st)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { expandedID = ""; editing = nil } }
    }

    // "Round 1        10×12 · BW×8 · 30 s" — swipe left to remove the round.
    private func doneRoundRow(_ b: Block, _ r: Int) -> some View {
        let parts: [String] = b.states.compactMap { st in
            st.logged[r].map { compactText($0.weightKg, $0.reps, st.ex) }
        }
        return HStack {
            Text("Round \(r)").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(parts.joined(separator: " · "))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Tone.ink)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation { removeRound(b, r) }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func removeRound(_ b: Block, _ r: Int) {
        for st in b.states where st.logged[r] != nil {
            removeSet(st.ex, r)
        }
    }

    private func isBodyweight(_ ex: ExerciseTemplate) -> Bool {
        Self.startingKg(for: ex, units: units) == 0
    }

    private func roundKey(_ st: ExState, _ r: Int) -> String { "\(st.ex.id)#\(r)" }

    private func roundValues(_ st: ExState, _ r: Int) -> (weight: Double, reps: Int) {
        let sug = suggestion(st, r)
        let d = drafts[roundKey(st, r)]
        return (d?.weight ?? displayWeight(sug.kg), d?.reps ?? sug.reps)
    }

    // One exercise in the current round, by its number: − / + for weight (BW or none) and reps / seconds.
    private func roundExerciseRow(_ st: ExState, number: Int, round r: Int) -> some View {
        let key: String = roundKey(st, r)
        let v = roundValues(st, r)
        return HStack(spacing: 4) {
            Text("\(number)")
                .font(.footnote).foregroundStyle(.secondary)
                .frame(width: 14, alignment: .leading)
            Spacer(minLength: 4)
            amountControls(st.ex, key: key, weight: v.weight, reps: v.reps)
        }
    }

    // Weight × reps steppers; bodyweight shows "BW ×" and only reps; timed exercises show only seconds.
    @ViewBuilder
    private func amountControls(_ ex: ExerciseTemplate, key: String, weight: Double, reps: Int) -> some View {
        if ex.isTimed {
            repsControl(id: key, weight: 0, reps: reps, timed: true)
        } else if isBodyweight(ex) && weight == 0 {
            Text("BW").font(.body.weight(.semibold))
            Text("×").foregroundStyle(.secondary)
            repsControl(id: key, weight: weight, reps: reps)
        } else {
            weightControl(id: key, weight: weight, reps: reps)
            Text("×").foregroundStyle(.secondary)
            repsControl(id: key, weight: weight, reps: reps)
        }
    }

    private func logRoundButton(_ b: Block, round r: Int, participants: [ExState]) -> some View {
        Button {
            logRound(b, round: r, participants: participants)
        } label: {
            Text("Log round")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Tone.ink)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Capsule().fill(Color(.systemGray5)))
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 2)
    }

    private func logRound(_ b: Block, round r: Int, participants: [ExState]) {
        autoStartWorkout()
        for st in participants {
            let v = roundValues(st, r)
            upsert(st.ex.id, r, kg: st.ex.isTimed ? 0 : units.toKg(v.weight), reps: v.reps)
            drafts[roundKey(st, r)] = nil
        }
        try? context.save()
        logCount += 1
        restTotal = Double(restSeconds)
        restFor = b.states[0].ex.id
        restEnd = .now.addingTimeInterval(TimeInterval(restSeconds))
        if r >= roundsTotal(b), let last = b.states.last {
            advance(from: last.ex)   // that was the last round: move on to the next exercise
        }
    }

    // All planned rounds done: add one more round for every exercise in the superset.
    private func addRoundButton(_ b: Block) -> some View {
        Button {
            withAnimation {
                for st in b.states { extraSets[st.ex.id] = st.count + 1 - st.ex.sets }
            }
        } label: {
            Label("Add round", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Tone.ink)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Capsule().fill(Color(.systemGray5)))
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 2)
    }

    // MARK: - Rows

    private func collapsedRow(_ s: ExState) -> some View {
        Button {
            withAnimation { expandedID = s.ex.id; editing = nil }
        } label: {
            HStack(spacing: 14) {
                SetRing(done: s.loggedCount, total: s.count, finished: s.done)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.ex.name).font(.headline).foregroundStyle(Color.primary)
                    subtitleText(s, collapsedSubtitle(s))
                }
                Spacer()
                if !s.done {
                    Image(systemName: "chevron.down").font(.footnote).foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .listRowBackground(rowBackground(s))
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

    // The open exercise: a header row, the logged sets, then Log (first set) or Repeat / Add.
    @ViewBuilder
    private func expandedRows(_ s: ExState) -> some View {
        exerciseHeader(s)
        setsArea(s)
    }

    // A finished exercise's rows turn light sage.
    private func rowBackground(_ s: ExState) -> Color {
        s.done ? Tone.done : Color(.secondarySystemGroupedBackground)
    }

    // Done exercises say so in dark sage; the rest stay grey.
    private func subtitleText(_ s: ExState, _ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(s.done ? .medium : .regular))
            .foregroundStyle(s.done ? Tone.doneText : Color.secondary)
    }

    private func exerciseHeader(_ s: ExState) -> some View {
        HStack(alignment: .center) {
            Button {
                withAnimation { expandedID = ""; editing = nil }
            } label: {
                HStack(spacing: 14) {
                    SetRing(done: s.loggedCount, total: s.count, finished: s.done)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.ex.name).font(.headline).foregroundStyle(Color.primary)
                        subtitleText(s, s.done ? collapsedSubtitle(s) : planLine(s))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            howButton(s)
        }
        .padding(.vertical, 4)
        .listRowBackground(rowBackground(s))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) { removeButton(s, iconOnly: true) }
        .contextMenu { removeButton(s) }
    }

    @ViewBuilder
    private func howButton(_ s: ExState) -> some View {
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

    // Before the first set: one pre-filled set with a Log button.
    // After that: the sets you've logged, then Repeat (same numbers again) and Add (a new set to change).
    @ViewBuilder
    private func setsArea(_ s: ExState) -> some View {
        let loggedNumbers: [Int] = s.logged.keys.sorted()
        ForEach(loggedNumbers, id: \.self) { n in
            setRow(s, n)
        }
        nextAction(s, next: (loggedNumbers.last ?? 0) + 1, firstSet: loggedNumbers.isEmpty)
            .listRowBackground(rowBackground(s))
    }

    @ViewBuilder
    private func nextAction(_ s: ExState, next: Int, firstSet: Bool) -> some View {
        if let e = editing, e.exercise.id == s.ex.id, e.setNumber == next {
            setRow(s, next)   // editing a new set (from Add, or changing the first set before logging it)
        } else if firstSet {
            firstSetRow(s)
        } else {
            repeatAddRow(s, next)
        }
    }

    // First set: weight and reps pre-filled (last time, or a starting value) with − / + right in the row,
    // then a light grey Log button.
    private func firstSetRow(_ s: ExState) -> some View {
        let sug = suggestion(s, 1)
        let id: String = s.ex.id
        let w: Double = drafts[id]?.weight ?? displayWeight(sug.kg)
        let r: Int = drafts[id]?.reps ?? sug.reps
        return HStack(spacing: 4) {
            amountControls(s.ex, key: id, weight: w, reps: r)
            Spacer(minLength: 4)
            logButton(s, weight: w, reps: r)
        }
    }

    private var weightStep: Double { units == .imperial ? 5 : 2.5 }

    private func weightControl(id: String, weight w: Double, reps r: Int) -> some View {
        HStack(spacing: 4) {
            miniButton("minus", label: "Less weight") {
                drafts[id] = Draft(weight: max(0, w - weightStep), reps: r)
            }
            weightText(w).frame(minWidth: 44)
            miniButton("plus", label: "More weight") {
                drafts[id] = Draft(weight: w + weightStep, reps: r)
            }
        }
    }

    @ViewBuilder
    private func weightText(_ w: Double) -> some View {
        if w > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(format(units.toKg(w))).font(.body.weight(.semibold)).monospacedDigit()
                Text(units.label).font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text("BW").font(.body.weight(.semibold))
        }
    }

    // Reps, or seconds for timed exercises (5 s steps, shown as "30 s").
    private func repsControl(id: String, weight w: Double, reps r: Int, timed: Bool = false) -> some View {
        let step: Int = timed ? 5 : 1
        return HStack(spacing: 4) {
            miniButton("minus", label: timed ? "Less time" : "Fewer reps") {
                drafts[id] = Draft(weight: w, reps: max(step, r - step))
            }
            Text(timed ? "\(r) s" : String(r))
                .font(.body.weight(.semibold)).monospacedDigit()
                .frame(minWidth: timed ? 36 : 22)
            miniButton("plus", label: timed ? "More time" : "More reps") {
                drafts[id] = Draft(weight: w, reps: r + step)
            }
        }
    }

    private func logButton(_ s: ExState, weight w: Double, reps r: Int) -> some View {
        Button {
            logSet(s.ex, 1, kg: s.ex.isTimed ? 0 : units.toKg(w), reps: r)
            drafts[s.ex.id] = nil
        } label: {
            Text("Log")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Tone.ink)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(Capsule().fill(Color(.systemGray5)))
        }
        .buttonStyle(.borderless)
    }

    private func miniButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(Tone.ink)
                .frame(width: 26, height: 26)   // plain − / +, no background
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    // Repeat logs another set with the numbers of the last one; Add opens a new set to change first.
    private func repeatAddRow(_ s: ExState, _ next: Int) -> some View {
        let last = s.logged[next - 1]
        return HStack(spacing: 10) {
            Button {
                if let last { logSet(s.ex, next, kg: last.weightKg, reps: last.reps) }
            } label: {
                Label("Repeat", systemImage: "repeat")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tone.ink)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Capsule().fill(Color(.systemGray5)))
            }
            .buttonStyle(.borderless)
            Button {
                withAnimation {
                    editing = SetEdit(exercise: s.ex, setNumber: next,
                                      weight: displayWeight(last?.weightKg ?? 0),
                                      reps: last?.reps ?? 10, isLogged: false)
                }
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tone.ink)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Capsule().fill(Color(.systemGray5)))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    // A set row, or the inline − / + editor when that set is being edited.
    @ViewBuilder
    private func setRow(_ s: ExState, _ n: Int) -> some View {
        if let e = editing, e.exercise.id == s.ex.id, e.setNumber == n {
            InlineSetEditor(edit: e, units: units,
                            onSave: { edit in withAnimation { editing = nil }; saveEdit(edit) },
                            onRemove: { withAnimation { editing = nil; if e.isLogged { removeSet(s.ex, n) } } },
                            onCancel: { withAnimation { editing = nil } })
                .id(e.id)
                .listRowBackground(rowBackground(s))
        } else {
            setButtonRow(s, n)
        }
    }

    private func setButtonRow(_ s: ExState, _ n: Int) -> some View {
        let log = s.logged[n]
        let sug = suggestion(s, n)
        let value: String = log.map { setText($0.weightKg, $0.reps, s.ex) } ?? (sug.known ? setText(sug.kg, sug.reps, s.ex) : "Tap to enter")
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
            .padding(.leading, 54)   // lines up with the exercise name, past its ring
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .listRowBackground(rowBackground(s))   // logged sets show in bold; light sage once the exercise is done
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
        var loggedCount: Int { min(logged.count, count) }

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
    // else last session's last set. With no history yet it's preloaded with a starting value:
    // the plan's reps, and 10 lb (5 kg) — or bodyweight for bodyweight/band exercises.
    private func suggestion(_ s: ExState, _ n: Int) -> (kg: Double, reps: Int, known: Bool) {
        if let l = s.last[n] { return (l.weightKg, l.reps, true) }
        if let p = s.logged.filter({ $0.key < n }).max(by: { $0.key < $1.key })?.value { return (p.weightKg, p.reps, true) }
        if let l = s.last.max(by: { $0.key < $1.key })?.value { return (l.weightKg, l.reps, true) }
        let reps = Int(s.ex.reps.prefix(while: \.isNumber)) ?? 10
        return (Self.startingKg(for: s.ex, units: units), reps, true)
    }

    private static let bodyweightIDs: Set<String> = ["dead-bug", "plank", "push-up", "side-plank", "lateral-walk"]

    private static func startingKg(for ex: ExerciseTemplate, units: UnitSystem) -> Double {
        if bodyweightIDs.contains(ex.id) { return 0 }
        if let c = ExerciseCatalog.exercise(id: ex.id), c.equipment != "dumbbell" { return 0 }
        return units == .imperial ? 10 / 2.20462 : 5
    }

    // "3 × 10 · 25 lb" (last time), or "Done · 3 × 10 · 30 lb" (today's top weight). The ring shows the set count.
    private func collapsedSubtitle(_ s: ExState) -> String {
        if s.done {
            var parts = ["Done", "\(s.ex.sets) × \(s.ex.reps)"]
            if let kg = s.logged.values.map(\.weightKg).max(), kg > 0 { parts.append("\(format(kg)) \(units.label)") }
            return parts.joined(separator: " · ")
        }
        var parts = ["\(s.ex.sets) × \(s.ex.reps)"]
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
        autoStartWorkout()
        upsert(ex.id, n, kg: kg, reps: reps)
        try? context.save()
        logCount += 1
        guard startRest else { return }
        // In a superset, rest only once every exercise in it has done this round's set.
        if roundComplete(ex, n) {
            restTotal = Double(restSeconds)
            restFor = ex.id
            restEnd = .now.addingTimeInterval(TimeInterval(restSeconds))
        } else {
            restEnd = nil
        }
        let nowDone = (0..<before.count).allSatisfy { before.logged[$0 + 1] != nil || $0 + 1 == n }
        if !before.done && nowDone { advance(from: ex) }
    }

    private func saveEdit(_ e: SetEdit) {
        logSet(e.exercise, e.setNumber, kg: units.toKg(e.weight), reps: e.reps, startRest: !e.isLogged)
    }

    // Remove a set row: delete its record (if logged) and renumber the sets after it.
    private func removeSet(_ ex: ExerciseTemplate, _ n: Int) {
        let s = state(for: ex)
        if let log = s.logged[n] { context.delete(log) }
        for (k, log) in s.logged where k > n { log.setNumber = k - 1 }
        extraSets[ex.id] = max(0, s.count - 1 - ex.sets)   // the plan's target stays; only extra sets go
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

    // Starting again after ending a workout: clear today's sets for it so every exercise is back
    // to its original state (pre-filled first set, nothing logged).
    private func clearTodaysSets() {
        withAnimation {
            for ex in workout.exercises { deleteTodaysLogs(of: ex.id) }
            extraSets = [:]
            drafts = [:]
            editing = nil
            expandedID = ""   // back to the beginning: everything closed
            restEnd = nil
        }
    }

    // Logging a set does what ▶ does if the workout isn't running: starts the timer and shows the
    // progress bar. Not started yet → starts from 0:00. Paused → carries on. Stopped earlier → a new
    // timer from 0:00 (your logged sets are kept). Already running → nothing changes.
    private func autoStartWorkout() {
        let todayKey = PlanTemplate.dayKey(.now)
        if timerDay != todayKey {   // a timer left from another day starts fresh
            resetTimer()
            timerDay = todayKey
        }
        guard timerStartedAt == 0 else { return }   // already running
        if timerFinished {
            timerElapsed = 0
            timerFinished = false
        }
        timerStartedAt = Date.now.timeIntervalSince1970
        withAnimation(.easeOut(duration: 0.25)) { timerStarted = true }
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
            expandedID = ""
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
    // An exercise just got all its sets: keep it open for 0.65 s so it's clear it's finished,
    // then slowly close it and open the next one.
    private func advance(from ex: ExerciseTemplate) {
        editing = nil
        expandedID = ex.id
        justFinished = ex.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.65))
            guard justFinished == ex.id else { return }   // something else happened meanwhile
            let partners = PlanTemplate.supersetGroup(of: ex, in: workout)
            let next = partners.first { $0.id != ex.id && !state(for: $0).done }
                ?? workout.exercises.first { $0.id != ex.id && !state(for: $0).done }
            withAnimation(.easeInOut(duration: 0.7)) {
                expandedID = next?.id ?? ""
                justFinished = nil
                if restEnd != nil, let next { restFor = next.id }   // keep resting under the exercise that's open now
            }
        }
    }

    // MARK: - Formatting

    private func displayWeight(_ kg: Double) -> Double { (units.display(kg) * 10).rounded() / 10 }

    private func format(_ kg: Double) -> String {
        let v = displayWeight(kg)
        return v == v.rounded() ? String(Int(v)) : String(v)
    }

    private func setText(_ kg: Double, _ reps: Int, _ ex: ExerciseTemplate? = nil) -> String {
        if ex?.isTimed == true { return "\(reps) s" }
        return kg > 0 ? "\(format(kg)) \(units.label) × \(reps)" : "BW × \(reps)"
    }

    // Short form for superset rounds: "10×12", "BW×8", "30 s".
    private func compactText(_ kg: Double, _ reps: Int, _ ex: ExerciseTemplate) -> String {
        if ex.isTimed { return "\(reps) s" }
        return kg > 0 ? "\(format(kg))×\(reps)" : "BW×\(reps)"
    }
}

// MARK: - Colours (match the Calendar / Figma)

private enum Tone {
    static let done  = Color(red: 0.890, green: 0.910, blue: 0.878) // #E3E8E0 sage
    static let check = Color(red: 0.420, green: 0.520, blue: 0.400) // darker sage for ✓
    static let ink   = Color(red: 0.110, green: 0.098, blue: 0.090) // #1C1917
    static let ring  = Color(red: 0.369, green: 0.478, blue: 0.345) // #5E7A58 set rings, done circle
    static let doneText = Color(red: 0.247, green: 0.353, blue: 0.231) // #3F5A3B "Done · …"
    static let ringTrack = Color(red: 0.941, green: 0.937, blue: 0.933) // #F0EFEE
}

// MARK: - Set ring (each exercise)
// Fills a part per set: "2/3" in the middle. Done = a solid sage circle with a white ✓.
private struct SetRing: View {
    let done: Int
    let total: Int
    let finished: Bool

    var body: some View {
        ZStack {
            if finished {
                Circle().fill(Tone.ring)
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().stroke(Color(.systemGray5), lineWidth: 5).padding(2.5)
                Circle()
                    .trim(from: 0, to: total > 0 ? CGFloat(done) / CGFloat(total) : 0)
                    .stroke(Tone.ring, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(2.5)
                Text("\(done)/\(total)")
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary)
            }
        }
        .frame(width: 40, height: 40)
        .animation(.easeOut(duration: 0.35), value: done)
        .animation(.easeOut(duration: 0.35), value: finished)
        .accessibilityElement()
        .accessibilityLabel(finished ? "Done" : "\(done) of \(total) sets")
    }
}

// MARK: - Workout ring (header)
// Before you start: a big white Start button (green border, green ▶) where the ring goes.
// Once started: the ring fills light sage with today's sets, "6/15" with the workout time under it.
// Tap the ring to pause: it shows a green ▶ and the stopped time (tap again to resume).
// While resting it turns dark and counts the rest down; a tap then skips the rest.
// After ending: the Start button again (the finished time shows under the title); Start begins the workout from scratch.
private enum WorkoutPhase { case notStarted, running, paused, finished }

private struct HeaderRing: View {
    let phase: WorkoutPhase
    let setsDone: Int
    let setsTotal: Int
    let restEnd: Date?
    let restTotal: Double
    let workoutTime: (Date) -> TimeInterval
    let start: () -> Void
    let togglePause: () -> Void
    let skipRest: () -> Void

    static let sageFill = Color(red: 0.788, green: 0.820, blue: 0.773) // #C9D1C5
    private let size: CGFloat = 92
    private let line: CGFloat = 9

    private var resting: Bool { restEnd != nil && phase == .running }

    var body: some View {
        Group {
            if phase == .notStarted || phase == .finished {   // after ending, Start is ready again
                startButton
            } else {
                ring
            }
        }
        .animation(.easeInOut(duration: 0.25), value: phase)
    }

    private var startButton: some View {
        Button(action: start) {
            ZStack {
                Circle().fill(Color.white)
                Circle().strokeBorder(Tone.ring, lineWidth: 3)
                Image(systemName: "play.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Tone.ring)
                    .offset(x: 3)   // a triangle looks centred a little to the right
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Start workout")
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }

    private var ring: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let time = workoutTime(ctx.date)
            let left = restEnd.map { max(0, $0.timeIntervalSince(ctx.date)) } ?? 0
            let fill = fraction(left: left)
            ZStack {
                Circle().stroke(Tone.ringTrack, lineWidth: line)
                Circle()
                    .trim(from: 0, to: fill)
                    .stroke(stroke, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: fill)
                center(time: time, left: left)
            }
            .padding(line / 2)
            .frame(width: size, height: size)
            .contentShape(Circle())
            .onTapGesture(perform: tap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label(time: time, left: left))
            .accessibilityAddTraits(phase == .finished ? [] : .isButton)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }

    private func fraction(left: TimeInterval) -> CGFloat {
        if phase == .finished { return 1 }
        if resting { return restTotal > 0 ? CGFloat(min(1, left / restTotal)) : 0 }
        return setsTotal > 0 ? CGFloat(min(1, Double(setsDone) / Double(setsTotal))) : 0
    }

    private var stroke: Color {
        if phase == .finished || (setsTotal > 0 && setsDone >= setsTotal && !resting) { return Tone.ring }
        return resting ? Tone.ink : Self.sageFill
    }

    @ViewBuilder
    private func center(time: TimeInterval, left: TimeInterval) -> some View {
        switch phase {
        case .paused:
            VStack(spacing: 2) {
                Image(systemName: "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Tone.ring)
                    .offset(x: 2)
                small(clock(time))
            }
        case .finished:
            VStack(spacing: 1) {
                Text("Done in").font(.system(size: 11, weight: .bold)).foregroundStyle(Tone.doneText)
                big(clock(time), size: 16)
            }
        default:
            if resting {
                VStack(spacing: 1) {
                    Text("Rest").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    big(restClock(left), size: 18)
                }
            } else {
                VStack(spacing: 1) {
                    big("\(setsDone)/\(setsTotal)", size: setsTotal >= 100 ? 15 : 18)
                    small(clock(time))
                }
            }
        }
    }

    private func big(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Tone.ink)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
    }

    private func small(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    // Paused → resume. Resting → skip the rest. Running → pause.
    private func tap() {
        switch phase {
        case .paused: togglePause()
        case .running: if resting { skipRest() } else { togglePause() }
        default: break
        }
    }

    private func label(time: TimeInterval, left: TimeInterval) -> String {
        switch phase {
        case .paused: return "Workout paused at \(clock(time)). Tap to resume"
        case .finished: return "Done in \(clock(time))"
        default:
            if resting { return "Rest, \(Int(left.rounded(.up))) seconds left. Tap to skip" }
            return "\(setsDone) of \(setsTotal) sets, workout time \(clock(time)). Tap to pause"
        }
    }

    // "4:05", or "1:02:09" past an hour
    private func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    private func restClock(_ t: TimeInterval) -> String {
        let secs = Int(t.rounded(.up))
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }
}

// MARK: - Workout done! (shown when every exercise is done)
// Confetti, a big green ✓, "Workout done!", the time / sets / exercises, and Done back to Today.

struct WorkoutCelebration: Identifiable {
    let id = UUID()
    let title: String      // "Workout A"
    let focus: String      // "Lower body + core"
    let time: TimeInterval
    let sets: Int
    let exercises: Int
}

private struct CelebrationView: View {
    let celebration: WorkoutCelebration
    let done: () -> Void
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color(red: 0.961, green: 0.961, blue: 0.957).ignoresSafeArea()   // #F5F5F4
            if !reduceMotion { ConfettiView().ignoresSafeArea() }
            VStack(spacing: 22) {
                Spacer(minLength: 40)
                ZStack {
                    Circle().fill(Tone.ring)
                    Image(systemName: "checkmark")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 108, height: 108)
                .shadow(color: Tone.ring.opacity(0.3), radius: 15, y: 10)
                .scaleEffect(shown ? 1 : 0.4)
                .opacity(shown ? 1 : 0)
                .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text("Workout done!")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(Tone.ink)
                    Text("\(celebration.title) · \(celebration.focus)")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .offset(y: shown ? 0 : 16)
                .opacity(shown ? 1 : 0)
                HStack(spacing: 8) {
                    tile(clock(celebration.time), "time")
                    tile("\(celebration.sets)", "sets")
                    tile("\(celebration.exercises)", "exercises")
                }
                .offset(y: shown ? 0 : 16)
                .opacity(shown ? 1 : 0)
                Spacer()
                Button(action: done) {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Tone.ink))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.65)) { shown = true } }
        .sensoryFeedback(.success, trigger: shown)
        .gesture(DragGesture().onEnded { if $0.translation.height > 80 { done() } })   // swipe down = Done
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 24, weight: .bold)).monospacedDigit().foregroundStyle(Tone.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .accessibilityElement(children: .combine)
    }

    private func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// Sage, stone and gold pieces that fall once from the top over a few seconds.
private struct ConfettiView: View {
    private struct Piece {
        let x: Double        // 0…1 across the screen
        let delay: Double    // seconds before it starts falling
        let speed: Double    // points per second
        let size: CGSize
        let color: Color
        let spin: Double     // radians per second
        let round: Bool
    }

    @State private var pieces: [Piece] = (0..<70).map { _ in
        let colors: [Color] = [Tone.ring, Color(red: 0.788, green: 0.820, blue: 0.773), Color(red: 0.890, green: 0.910, blue: 0.878),
                               Color(red: 0.659, green: 0.635, blue: 0.620), Tone.ink, Color(red: 0.839, green: 0.659, blue: 0.361)]
        return Piece(x: .random(in: 0...1), delay: .random(in: 0...1.6), speed: .random(in: 180...320),
                     size: CGSize(width: [6, 8, 10].randomElement()!, height: [6, 12, 14].randomElement()!),
                     color: colors.randomElement()!, spin: .random(in: -6...6), round: Bool.random())
    }
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSince(start)
                for p in pieces {
                    let local = t - p.delay
                    guard local > 0 else { continue }
                    let y = local * p.speed - 20
                    guard y < size.height + 20 else { continue }
                    var piece = g
                    piece.translateBy(x: p.x * size.width + sin(local * 2 + p.spin) * 12, y: y)
                    piece.rotate(by: .radians(local * p.spin))
                    let rect = CGRect(x: -p.size.width / 2, y: -p.size.height / 2, width: p.size.width, height: p.size.height)
                    piece.fill(p.round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 2), with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
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

            if edit.exercise.isTimed {
                stepperRow(title: "Time",
                           value: "\(edit.reps) s",
                           minus: { edit.reps = max(5, edit.reps - 5) },
                           plus: { edit.reps += 5 })
            } else {
                stepperRow(title: "Weight",
                           value: edit.weight == 0 ? "BW" : "\(weightText) \(units.label)",
                           minus: { edit.weight = max(0, edit.weight - step) },
                           plus: { edit.weight += step })
                stepperRow(title: "Reps",
                           value: "\(edit.reps)",
                           minus: { edit.reps = max(0, edit.reps - 1) },
                           plus: { edit.reps += 1 })
            }

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
            Button(action: minus) { Image(systemName: "minus").frame(width: 28, height: 28).contentShape(Rectangle()) }
                .buttonStyle(.borderless)
                .buttonRepeatBehavior(.enabled)
            Text(value)
                .font(.headline).monospacedDigit()
                .frame(minWidth: 64)
            Button(action: plus) { Image(systemName: "plus").frame(width: 28, height: 28).contentShape(Rectangle()) }
                .buttonStyle(.borderless)
                .buttonRepeatBehavior(.enabled)
        }
        .tint(.primary)
    }
}

// MARK: - Add an exercise to today

struct AddExerciseSheet: View {   // also used by the Plan tab's workout editor
    let current: Set<String>                  // exercises already in today's list
    let onAdd: (ExerciseTemplate) -> Void

    init(current: Set<String>, onAdd: @escaping (ExerciseTemplate) -> Void) {
        self.current = current
        self.onAdd = onAdd
    }
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
                    .listRowSeparator(.hidden)
                }
                // Its own card, so it gets proper rounded corners (it shared one with the switch above).
                Section {
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
                            Section("Your plan · \(w.displayTitle)") {
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
                if let avoid = exercise.avoid {
                    Text("Avoid: \(avoid)").font(.footnote).foregroundStyle(.secondary)
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

// MARK: - Workout header: the ring (or Start), the title, then what you can do now
// [Start / ring]  Workout A           [dumbbell]
//                 Lower body + core
// Under it, depending on the moment:
//   paused → [▶ Resume] [■ End workout]   resting → [Skip]   (nothing while just running)
// End asks first, then freezes the time. Finishing the last exercise ends the workout by itself and shows
// the "Workout done!" screen. After ending, the Start button is back: it starts the workout from the beginning. Long-press the ring to reset the timer or do the workout again.
// The timer is saved, so it keeps going if you leave the app, and everything resets on a new day.

private struct WorkoutHeader: View {
    let title: String            // "Workout A · Lower body"
    let done: Int                // exercises done
    let total: Int
    let setsDone: Int
    let setsTotal: Int
    let restEnd: Date?           // resting until then; nil = not resting
    let restTotal: Double
    let skipRest: () -> Void
    let showWorkouts: () -> Void // the dumbbell button: Your workouts
    let startOver: () -> Void    // clear today's sets for this workout
    let onAllDone: (TimeInterval) -> Void   // every exercise done: show the celebration with the workout time
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 32   // a bit larger than .title (28)

    init(title: String, done: Int, total: Int, setsDone: Int, setsTotal: Int,
         restEnd: Date?, restTotal: Double, skipRest: @escaping () -> Void,
         showWorkouts: @escaping () -> Void, startOver: @escaping () -> Void,
         onAllDone: @escaping (TimeInterval) -> Void) {
        self.title = title
        self.done = done
        self.total = total
        self.setsDone = setsDone
        self.setsTotal = setsTotal
        self.restEnd = restEnd
        self.restTotal = restTotal
        self.skipRest = skipRest
        self.showWorkouts = showWorkouts
        self.startOver = startOver
        self.onAllDone = onAllDone
    }

    @AppStorage("workoutTimerStart") private var startedAt = 0.0      // when it was last started; 0 = not running
    @AppStorage("workoutTimerElapsed") private var elapsed = 0.0      // seconds banked before the last start
    @AppStorage("workoutTimerDay") private var day = ""               // day the timer belongs to
    @AppStorage("workoutTimerStarted") private var started = false    // pressed Start today
    @AppStorage("workoutTimerFinished") private var finished = false  // pressed End today
    @State private var confirmingStop = false

    private var running: Bool { startedAt > 0 }
    private var resting: Bool { restEnd != nil && phase == .running }

    private static let track    = Color(red: 0.906, green: 0.898, blue: 0.894) // #E7E5E4
    private static let stone    = Color(red: 0.267, green: 0.251, blue: 0.235) // #44403C

    // In progress = started and not ended yet (also covers a timer started before this update).
    private var inProgress: Bool { !finished && (started || running || elapsed > 0) }

    private var phase: WorkoutPhase {
        if finished { return .finished }
        if inProgress { return running ? .running : .paused }
        return .notStarted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleLine
            actionRow
        }
        .padding(.top, 8)
        .animation(.easeOut(duration: 0.2), value: phase)
        .animation(.easeOut(duration: 0.15), value: resting)
        .onAppear(perform: newDayCheck)
        .onChange(of: done) { endIfAllDone() }
        .confirmationDialog("End this workout?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("End workout", role: .destructive, action: stop)
        } message: {
            Text("The timer stops at its current time. Your logged sets stay as they are.")
        }
    }

    private var titleLine: some View {
        HStack(alignment: .center, spacing: 14) {
            HeaderRing(phase: phase, setsDone: setsDone, setsTotal: setsTotal,
                       restEnd: restEnd, restTotal: restTotal,
                       workoutTime: totalTime(at:), start: tapStart,
                       togglePause: togglePause, skipRest: skipRest)
                .contextMenu {
                    if inProgress {
                        Button("Reset timer", systemImage: "arrow.counterclockwise", role: .destructive, action: reset)
                    }
                }
            titleTexts
            Spacer(minLength: 0)
            roundButton("dumbbell.fill", label: "Your workouts", action: showWorkouts)
        }
    }

    private var titleParts: [String] { title.components(separatedBy: " · ") }

    private var titleTexts: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(titleParts.first ?? title)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(Tone.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(subtitle(at: ctx.date))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    // The focus ("Lower body + core"). While resting the ring shows the rest, so the sets and time move here.
    private func subtitle(at date: Date) -> String {
        if resting { return "\(setsDone) of \(setsTotal) sets · \(format(totalTime(at: date)))" }
        let focus = titleParts.dropFirst().joined(separator: " · ")
        if finished {
            let doneIn = "done in \(format(elapsed))"
            return focus.isEmpty ? "Done in \(format(elapsed))" : "\(focus) · \(doneIn)"
        }
        return focus
    }

    // Start. After an ended workout it starts from the beginning: today's sets for it are cleared first.
    private func tapStart() {
        if finished { startOver() }
        start()
    }

    @ViewBuilder
    private var actionRow: some View {
        switch phase {
        case .paused:
            HStack(spacing: 8) {
                Button(action: togglePause) {
                    Label("Resume", systemImage: "play.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Tone.doneText)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Capsule().fill(Color.white))
                        .overlay(Capsule().strokeBorder(Tone.ring, lineWidth: 2))
                }
                .buttonStyle(.borderless)
                Button(action: askStop) {
                    Label("End workout", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Self.stone)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Capsule().fill(Self.track))
                }
                .buttonStyle(.borderless)
            }
            .transition(.opacity)
        case .running:
            if resting {
                Button(action: skipRest) {
                    Text("Skip")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 92, height: 30)   // the ring's width, so it sits right under it
                        .background(Capsule().fill(Tone.ink))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Skip rest")
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
        default:
            EmptyView()
        }
    }

    private func askStop() { confirmingStop = true }

    // Every exercise done: stop the timer and end the workout (no question), and drop any rest.
    private func endIfAllDone() {
        guard total > 0, done >= total, inProgress else { return }
        skipRest()
        withAnimation(.easeInOut(duration: 0.4)) { stop() }
        onAllDone(elapsed)
    }

    // Grey circle button (the dumbbell).
    private func roundButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Self.stone)
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

    // Title, then a short preview of the exercises.
    private func card(_ w: WorkoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(w.displayTitle).font(.headline)
            Text("\(w.exercises.count) exercises · \(w.exercises.reduce(0) { $0 + $1.sets }) sets")
                .font(.caption).foregroundStyle(.secondary)
            Text(w.exercises.map(\.name).joined(separator: " · "))
                .font(.footnote).foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
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
        .navigationTitle(workout.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(action: onPick) {
                Text("Let's Do This!")
                    .font(.headline)
                    .foregroundStyle(Tone.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Capsule().fill(Color(.systemGray5)))
            }
            .buttonStyle(.borderless)
            .padding(.horizontal).padding(.bottom, 8)
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
                    if let avoid = c.avoid {
                        Text("Avoid: \(avoid)").font(.footnote).foregroundStyle(.secondary)
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

// Timed exercises (plank, side plank): the plan's reps are in seconds ("30–40 s", "20–30 s / side").
// They have no weight; the number logged is seconds.
extension ExerciseTemplate {
    var isTimed: Bool { reps.hasSuffix(" s") || reps.contains(" s /") }
}
