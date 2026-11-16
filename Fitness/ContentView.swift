import SwiftUI
import SwiftData
import Charts

struct ContentView: View {
    var body: some View {
        TabView {
            TodayView().tabItem { Label("Today", systemImage: "figure.strengthtraining.traditional") }
            CalendarView().tabItem { Label("Calendar", systemImage: "calendar") }
            ProgressTabView().tabItem { Label("Progress", systemImage: "chart.bar") }
            PlanView().tabItem { Label("Plan", systemImage: "list.bullet.rectangle") }
        }
        .tint(Color(white: 0.15))
    }
}

// MARK: - Page title
// The big title row used on Today, Calendar, Progress and Plan: same size, colour and place.
// Put it in the first List section with .pageTitleRow() so it sits 12pt in from the card edges, like Today.

private enum PageTone {
    static let ink   = Color(red: 0.110, green: 0.098, blue: 0.090) // #1C1917
    static let track = Color(red: 0.906, green: 0.898, blue: 0.894) // #E7E5E4
    static let stone = Color(red: 0.267, green: 0.251, blue: 0.235) // #44403C
}

struct PageTitle<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 32

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(PageTone.ink)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.top, 8)
    }
}

extension PageTitle where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

// Grey round icon button, like the dumbbell on Today.
struct PageRoundButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    init(_ icon: String, label: String, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PageTone.stone)
                .frame(width: 36, height: 36)
                .background(Circle().fill(PageTone.track))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }
}

extension View {
    // Same row setup as Today's title: no card, no line, 12pt in from the card edges.
    func pageTitleRow() -> some View {
        self.listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
            .listRowSeparator(.hidden)
    }
}

// MARK: - Progress tab
// One page, built from your logged sets (no sample data), top to bottom:
// - subtitle: where you are in the 26-week plan and your weekly streak
// - summary card: plan progress bar, sessions this week, volume this week (vs last), PRs in 30 days
// - last 8 weeks: one column per week, one square per workout (dark = all sets, light = some, grey = none)
// - exercises: best set in the last 8 weeks, a small trend line, the change, PR tag; tap for the full chart
// - this week by body part: sets for upper, lower and core
// A PR (personal record) is a set heavier than every earlier set of that exercise (or more reps / longer).

private enum ProgressTone {
    static let ink   = Color(red: 0.110, green: 0.098, blue: 0.090) // #1C1917
    static let stone = Color(red: 0.267, green: 0.251, blue: 0.235) // #44403C
    static let track = Color(red: 0.906, green: 0.898, blue: 0.894) // #E7E5E4
    static let light = Color(red: 0.839, green: 0.827, blue: 0.820) // #D6D3D1
    static let sage  = Color(red: 0.478, green: 0.545, blue: 0.455) // #7A8B74
    static let sageLight = Color(red: 0.788, green: 0.820, blue: 0.773) // #C9D1C5
    static let sageTag = Color(red: 0.890, green: 0.910, blue: 0.878) // #E3E8E0
    static let sageText = Color(red: 0.294, green: 0.353, blue: 0.278) // #4B5A47
}

// Shared maths over the logged sets.
private struct ProgressData {
    let logs: [SetLog]          // oldest first
    let cal = Calendar.current

    static let planWeeks = 26

    func weekStart(_ date: Date) -> Date { cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date }
    var thisWeek: Date { weekStart(.now) }
    func week(_ back: Int) -> Date { cal.date(byAdding: .weekOfYear, value: -back, to: thisWeek) ?? thisWeek }
    func logs(inWeek start: Date) -> [SetLog] {
        let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
        return logs.filter { $0.date >= start && $0.date < end }
    }
    func sessions(inWeek start: Date) -> Int { Set(logs(inWeek: start).map { cal.startOfDay(for: $0.date) }).count }

    // Week of the plan, counted from the week of your first logged set.
    var planWeek: Int {
        guard let first = logs.first?.date else { return 1 }
        let weeks = cal.dateComponents([.weekOfYear], from: weekStart(first), to: thisWeek).weekOfYear ?? 0
        return min(weeks + 1, Self.planWeeks)
    }

    // Weeks in a row with at least one session (this week counts once it has one).
    var streak: Int {
        var back = sessions(inWeek: thisWeek) > 0 ? 0 : 1
        var count = 0
        while back < 520, sessions(inWeek: week(back)) > 0 { count += 1; back += 1 }
        return count
    }

    func volumeKg(_ week: Date) -> Double { logs(inWeek: week).reduce(0) { $0 + $1.weightKg * Double($1.reps) } }

    // PRs, oldest first.
    var prs: [SetLog] {
        var best: [String: Double] = [:]
        var out: [SetLog] = []
        for log in logs {
            let byWeight = log.weightKg > 0
            let key = log.exerciseID + (byWeight ? "#w" : "#r")
            let score = byWeight ? log.weightKg : Double(log.reps)
            if let prev = best[key] {
                if score > prev { best[key] = score; out.append(log) }
            } else {
                best[key] = score
            }
        }
        return out
    }

    var monthAgo: Date { cal.date(byAdding: .day, value: -30, to: .now) ?? .now }
}

struct ProgressTabView: View {
    @Query(sort: \SetLog.date) private var logs: [SetLog]
    @AppStorage("units") private var unitsRaw = UnitSystem.imperial.rawValue
    @AppStorage(PlanTemplate.templatesKey) private var templatesRaw = ""   // redraw when workouts change

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .imperial }
    private var data: ProgressData { ProgressData(logs: logs) }

    var body: some View {
        NavigationStack {
            List {
                Section { PageTitle("Progress", subtitle: subtitle) }.pageTitleRow()
                if logs.isEmpty {
                    Section {
                        ContentUnavailableView("No progress yet",
                                               systemImage: "chart.bar",
                                               description: Text("Log a few sets on Today and your progress shows up here."))
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section { summaryCard }
                    Section { weeksGrid }
                    exercisesSection
                    bodyPartSection
                }
            }
            .navigationTitle("Progress")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { ExerciseProgressView(exerciseID: $0) }
        }
    }

    private var subtitle: String? {
        guard !logs.isEmpty else { return nil }
        let d = data
        let streak = d.streak
        let week = "Week \(d.planWeek) of \(ProgressData.planWeeks)"
        return streak > 1 ? "\(week) · \(streak)-week streak" : week
    }

    // MARK: Summary

    private var summaryCard: some View {
        let d = data
        let perWeek = max(PlanTemplate.phase1.count, 1)
        let thisVol = d.volumeKg(d.thisWeek)
        let lastVol = d.volumeKg(d.week(1))
        let prCount = d.prs.filter { $0.date >= d.monthAgo }.count
        return VStack(alignment: .leading, spacing: 12) {
            ProgressBar(fraction: Double(d.planWeek) / Double(ProgressData.planWeeks), color: ProgressTone.sage)
            HStack(alignment: .top) {
                stat("\(d.sessions(inWeek: d.thisWeek)) / \(perWeek)", "this week")
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(whole(units.display(thisVol))) \(units.label)").font(.headline).monospacedDigit()
                    volumeChange(thisVol, lastVol)
                }
                Spacer()
                stat("\(prCount)", "PRs · 30 days")
            }
        }
        .padding(.vertical, 4)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func volumeChange(_ now: Double, _ before: Double) -> some View {
        if before > 0 {
            let pct = Int(((now - before) / before * 100).rounded())
            HStack(spacing: 4) {
                Text("volume").foregroundStyle(.secondary)
                Text(pct >= 0 ? "+\(pct)%" : "−\(abs(pct))%")
                    .foregroundStyle(pct > 0 ? ProgressTone.sage : Color.secondary)
            }
            .font(.caption)
        } else {
            Text("volume").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Last 8 weeks

    private enum Done { case all, some, none }

    // For each workout in the plan (rows) and each of the last 8 weeks (columns).
    private var grid: [[Done]] {
        let d = data
        let workouts = PlanTemplate.phase1
        let weeks = (0..<8).reversed().map { d.week($0) }
        let perWeek: [[Date: [SetLog]]] = weeks.map { w in
            Dictionary(grouping: d.logs(inWeek: w)) { d.cal.startOfDay(for: $0.date) }
        }
        return workouts.map { workout -> [Done] in
            let planned = workout.exercises.reduce(0) { $0 + $1.sets }
            return perWeek.map { days -> Done in
                var best = Done.none
                for dayLogs in days.values where CalendarView.workout(for: dayLogs)?.id == workout.id {
                    if dayLogs.count >= planned { return Done.all }
                    best = .some
                }
                return best
            }
        }
    }

    private var weeksGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last 8 weeks").font(.subheadline.weight(.semibold))
                Spacer()
                Text(PlanTemplate.phase1.map(\.id).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 5) {
                ForEach(Array(grid.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 5) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(color(cell))
                                .frame(height: 16)
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Workouts done in each of the last 8 weeks")
        }
        .padding(.vertical, 4)
    }

    private func color(_ d: Done) -> Color {
        switch d {
        case .all: return ProgressTone.sage
        case .some: return ProgressTone.sageLight
        case .none: return ProgressTone.track
        }
    }

    // MARK: Exercises

    private var loggedExercises: [String] {
        let recent = logs.filter { $0.date >= data.week(7) }
        let counts = Dictionary(grouping: recent, by: \.exerciseID).mapValues(\.count)
        return counts.keys.sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) }
    }

    @ViewBuilder
    private var exercisesSection: some View {
        let ids = loggedExercises
        let prIDs = Set(data.prs.filter { $0.date >= data.monthAgo }.map(\.exerciseID))
        if !ids.isEmpty {
            Section {
                ForEach(ids, id: \.self) { id in
                    NavigationLink(value: id) {
                        ExerciseTrendRow(exerciseID: id, logs: logs, units: units, hasPR: prIDs.contains(id))
                    }
                }
            } header: {
                Text("Exercises · best set, last 8 weeks")
            }
        }
    }

    // MARK: Body parts

    @ViewBuilder
    private var bodyPartSection: some View {
        let week = data.logs(inWeek: data.thisWeek)
        let counts = Dictionary(grouping: week) { ProgressTabView.region(for: $0.exerciseID) }.mapValues(\.count)
        let rows = [PartCount(name: "Upper", sets: counts[.upper] ?? 0),
                    PartCount(name: "Lower", sets: counts[.lower] ?? 0),
                    PartCount(name: "Core", sets: counts[.core] ?? 0)]
        let top = max(rows.map { $0.sets }.max() ?? 0, 1)
        Section("This week by body part") {
            VStack(spacing: 10) {
                ForEach(rows) { row in
                    let n = row.sets
                    HStack(spacing: 10) {
                        Text(row.name).font(.subheadline).frame(width: 52, alignment: .leading)
                        ProgressBar(fraction: Double(n) / Double(top), color: ProgressTone.stone)
                        Text("\(n)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                            .frame(width: 26, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private struct PartCount: Identifiable {
        let name: String
        let sets: Int
        var id: String { name }
    }

    static func region(for id: String) -> BodyRegion {
        (PlanTemplate.allExercises.first { $0.id == id } ?? ExerciseCatalog.template(id: id))?.region ?? .other
    }

    private func whole(_ v: Double) -> String { v.rounded().formatted(.number.precision(.fractionLength(0))) }
}

// Thin rounded bar on the grey track.
private struct ProgressBar: View {
    let fraction: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(ProgressTone.track)
                Capsule().fill(color).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 8)
    }
}

// MARK: - One exercise row: name, best set, trend line, change

private func formatNumber(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
}

private struct ExerciseTrendRow: View {
    let exerciseID: String
    let logs: [SetLog]
    let units: UnitSystem
    let hasPR: Bool

    private var cal: Calendar { Calendar.current }
    private var mine: [SetLog] { logs.filter { $0.exerciseID == exerciseID } }
    private var byWeight: Bool { mine.contains { $0.weightKg > 0 } }
    private var timed: Bool {
        (PlanTemplate.allExercises.first { $0.id == exerciseID } ?? ExerciseCatalog.template(id: exerciseID))?.isTimed ?? false
    }

    // Top value per week for the last 8 weeks (nil = nothing logged).
    private var weekly: [Double?] {
        guard let current = cal.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        return (0..<8).reversed().map { back in
            guard let start = cal.date(byAdding: .weekOfYear, value: -back, to: current),
                  let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let inside = mine.filter { $0.date >= start && $0.date < end }
            return byWeight ? inside.map { units.display($0.weightKg) }.max()
                            : inside.map { Double($0.reps) }.max()
        }
    }

    private var bestSet: SetLog? {
        guard let start = cal.date(byAdding: .weekOfYear, value: -7,
                                   to: cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now) else { return nil }
        let recent = mine.filter { $0.date >= start }
        return recent.max { a, b in
            byWeight ? (a.weightKg, a.reps) < (b.weightKg, b.reps) : a.reps < b.reps
        }
    }

    private var bestText: String {
        guard let s = bestSet else { return "" }
        if timed { return "\(s.reps) s" }
        if !byWeight { return "BW × \(s.reps)" }
        return "\(formatNumber((units.display(s.weightKg) * 10).rounded() / 10)) \(units.label) × \(s.reps)"
    }

    private var change: Double? {
        let filled = weekly.compactMap { $0 }
        guard filled.count > 1, let a = filled.first, let b = filled.last else { return nil }
        return ((b - a) * 10).rounded() / 10
    }

    private var changeText: String {
        guard let c = change else { return "" }
        let unit = timed ? "s" : ""
        if c == 0 { return "±0" }
        return (c > 0 ? "+" : "−") + formatNumber(abs(c)) + unit
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ExerciseCatalog.name(for: exerciseID)).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if hasPR { prTag }
                }
                Text(bestText).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 8)
            Sparkline(values: weekly, color: (change ?? 0) > 0 ? ProgressTone.sage : ProgressTone.light)
                .frame(width: 64, height: 22)
            Text(changeText)
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle((change ?? 0) > 0 ? ProgressTone.sage : Color.secondary)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private var prTag: some View {
        Text("PR")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(ProgressTone.sageText)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 5).fill(ProgressTone.sageTag))
            .accessibilityLabel("New personal record")
    }
}

// A small line through the weeks that have a value.
private struct Sparkline: View {
    let values: [Double?]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let points: [(Int, Double)] = values.enumerated().compactMap { pair in
                pair.element.map { (pair.offset, $0) }
            }
            let lo = points.map { $0.1 }.min() ?? 0
            let hi = points.map { $0.1 }.max() ?? 0
            let span = hi - lo
            Path { p in
                for (n, pt) in points.enumerated() {
                    let x = values.count > 1 ? geo.size.width * Double(pt.0) / Double(values.count - 1) : 0
                    let y = span > 0 ? geo.size.height * (1 - (pt.1 - lo) / span) : geo.size.height / 2
                    if n == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - One exercise: full chart (tap a row on Progress)
// Weekly (last 8) or monthly (last 6) top set, with the change since the first period.

struct ExerciseProgressView: View {
    let exerciseID: String
    @Query(sort: \SetLog.date) private var allLogs: [SetLog]
    @AppStorage("units") private var unitsRaw = UnitSystem.imperial.rawValue
    @State private var monthly = false

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .imperial }
    private var cal: Calendar { Calendar.current }
    private var mine: [SetLog] { allLogs.filter { $0.exerciseID == exerciseID } }
    private var byWeight: Bool { mine.contains { $0.weightKg > 0 } }

    private struct Bucket: Identifiable {
        let start: Date
        let label: String
        let value: Double?
        var id: Date { start }
    }

    private var buckets: [Bucket] {
        let component: Calendar.Component = monthly ? .month : .weekOfYear
        let count = monthly ? 6 : 8
        guard let current = cal.dateInterval(of: component, for: .now)?.start else { return [] }
        let fmt = monthly ? Date.FormatStyle().month(.abbreviated) : Date.FormatStyle().month(.abbreviated).day()
        return (0..<count).reversed().compactMap { back -> Bucket? in
            guard let start = cal.date(byAdding: component, value: -back, to: current),
                  let end = cal.date(byAdding: component, value: 1, to: start) else { return nil }
            let inside = mine.filter { $0.date >= start && $0.date < end }
            let top: Double? = byWeight
                ? inside.map(\.weightKg).max().map { (units.display($0) * 10).rounded() / 10 }
                : inside.map { Double($0.reps) }.max()
            return Bucket(start: start, label: start.formatted(fmt), value: top)
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 18) {
                    choice("Weekly", selected: !monthly) { monthly = false }
                    choice("Monthly", selected: monthly) { monthly = true }
                    Spacer()
                }
            }
            .pageTitleRow()
            Section { chart }
        }
        .navigationTitle(ExerciseCatalog.name(for: exerciseID))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choice(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(label) { withAnimation { action() } }
            .buttonStyle(.borderless)
            .font(.body.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var chart: some View {
        let data = buckets
        return VStack(alignment: .leading, spacing: 10) {
            Text(byWeight ? "Top set" : "Most reps").font(.headline)
            changeLine(data)
            Chart(data) { b in
                if let v = b.value {
                    BarMark(x: .value("Period", b.label), y: .value("Top set", v))
                        .foregroundStyle(b.start == data.last?.start ? ProgressTone.stone : ProgressTone.light)
                        .cornerRadius(5)
                }
            }
            .chartXScale(domain: data.map(\.label))
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 220)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func changeLine(_ data: [Bucket]) -> some View {
        let filled = data.filter { $0.value != nil }
        if let first = filled.first, let last = filled.last, filled.count > 1,
           let a = first.value, let b = last.value {
            let diff = b - a
            let unit = byWeight ? " \(units.label)" : " reps"
            let sign = diff > 0 ? "+" : (diff < 0 ? "−" : "±")
            Text("\(sign)\(formatNumber(abs(diff)))\(unit) since \(first.label)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(diff > 0 ? ProgressTone.sage : Color.secondary)
        } else {
            Text(monthly ? "Log more months to see your change" : "Log more weeks to see your change")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
