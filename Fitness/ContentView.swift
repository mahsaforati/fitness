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
// Built from your logged sets (no sample data):
// - Weekly / Monthly switch (plain text choice, like the units in Settings)
// - a chart of one exercise's top set per week (last 8) or per month (last 6), with the change since the first
// - three tiles: sessions this week, volume this week, personal records in the last 30 days
// - Recent PRs: the latest sets that beat your previous best for that exercise

struct ProgressTabView: View {
    @Query(sort: \SetLog.date) private var logs: [SetLog]
    @AppStorage("units") private var unitsRaw = UnitSystem.imperial.rawValue
    @AppStorage(PlanTemplate.templatesKey) private var templatesRaw = ""   // redraw when workouts change
    @State private var monthly = false
    @State private var exerciseID: String?

    private var units: UnitSystem { UnitSystem(rawValue: unitsRaw) ?? .imperial }
    private var cal: Calendar { Calendar.current }

    private static let stone = Color(red: 0.267, green: 0.251, blue: 0.235)   // #44403C
    private static let light = Color(red: 0.839, green: 0.827, blue: 0.820)   // #D6D3D1
    private static let sage  = Color(red: 0.420, green: 0.520, blue: 0.400)   // darker sage, like the ✓

    var body: some View {
        NavigationStack {
            List {
                Section { PageTitle("Progress") }.pageTitleRow()
                if logs.isEmpty {
                    Section {
                        ContentUnavailableView("No progress yet",
                                               systemImage: "chart.bar",
                                               description: Text("Log a few sets on Today and your progress shows up here."))
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section { periodChoice }
                        .pageTitleRow()   // lines up with the title
                    Section { chartCard }
                    Section { statTiles }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    recentPRsSection
                }
            }
            .navigationTitle("Progress")
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Weekly / Monthly

    private var periodChoice: some View {
        HStack(spacing: 18) {
            choice("Weekly", selected: !monthly) { monthly = false }
            choice("Monthly", selected: monthly) { monthly = true }
            Spacer()
        }
    }

    private func choice(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(label) { withAnimation { action() } }
            .buttonStyle(.borderless)
            .font(.body.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Chart of one exercise

    // Exercises you've logged, most logged first.
    private var loggedExercises: [String] {
        let counts = Dictionary(grouping: logs, by: \.exerciseID).mapValues(\.count)
        return counts.keys.sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) }
    }

    private var selectedID: String? { exerciseID ?? loggedExercises.first }

    private struct Bucket: Identifiable {
        let start: Date
        let label: String
        let value: Double?   // top weight (in the units shown), or top reps if bodyweight
        var id: Date { start }
    }

    // Bodyweight / timed exercises chart reps (or seconds) instead of weight.
    private func usesWeight(_ id: String) -> Bool {
        logs.contains { $0.exerciseID == id && $0.weightKg > 0 }
    }

    private func buckets(for id: String) -> [Bucket] {
        let component: Calendar.Component = monthly ? .month : .weekOfYear
        let count = monthly ? 6 : 8
        guard let current = cal.dateInterval(of: component, for: .now)?.start else { return [] }
        let mine = logs.filter { $0.exerciseID == id }
        let byWeight = usesWeight(id)
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

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let id = selectedID {
                exercisePicker(id)
                let data = buckets(for: id)
                changeLine(id, data)
                Chart(data) { b in
                    if let v = b.value {
                        BarMark(x: .value("Period", b.label), y: .value("Top set", v))
                            .foregroundStyle(b.start == data.last?.start ? Self.stone : Self.light)
                            .cornerRadius(5)
                    }
                }
                .chartXScale(domain: data.map(\.label))
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 190)
            }
        }
        .padding(.vertical, 6)
    }

    private func exercisePicker(_ id: String) -> some View {
        Menu {
            ForEach(loggedExercises, id: \.self) { e in
                Button(ExerciseCatalog.name(for: e)) { exerciseID = e }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(ExerciseCatalog.name(for: id)) · top set")
                    .font(.headline).foregroundStyle(Color.primary)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
    }

    // "+10 lb since Oct 5" (or reps), using the first and latest periods that have sets.
    @ViewBuilder
    private func changeLine(_ id: String, _ data: [Bucket]) -> some View {
        let filled = data.filter { $0.value != nil }
        if let first = filled.first, let last = filled.last, filled.count > 1,
           let a = first.value, let b = last.value {
            let diff = b - a
            let unit = usesWeight(id) ? " \(units.label)" : " reps"
            let sign = diff > 0 ? "+" : (diff < 0 ? "−" : "±")
            Text("\(sign)\(number(abs(diff)))\(unit) since \(first.label)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(diff > 0 ? Self.sage : Color.secondary)
        } else {
            Text(monthly ? "Log more months to see your change" : "Log more weeks to see your change")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: Tiles

    private var weekLogs: [SetLog] {
        guard let start = cal.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        return logs.filter { $0.date >= start }
    }

    private var statTiles: some View {
        let sessions = Set(weekLogs.map { cal.startOfDay(for: $0.date) }).count
        let volumeKg = weekLogs.reduce(0) { $0 + $1.weightKg * Double($1.reps) }
        let recentPRs = prs.filter { $0.date >= (cal.date(byAdding: .day, value: -30, to: .now) ?? .now) }.count
        return HStack(spacing: 10) {
            tile("\(sessions)", "sessions this week")
            tile("\(number((units.display(volumeKg)).rounded())) \(units.label)", "volume this week")
            tile("\(recentPRs)", "PRs in 30 days")
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title3.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: Personal records

    // A PR is a set heavier than every earlier set of that exercise (for bodyweight: more reps).
    private struct PR: Identifiable {
        let id: PersistentIdentifier
        let exerciseID: String
        let date: Date
        let weightKg: Double
        let reps: Int
    }

    private var prs: [PR] {
        var best: [String: Double] = [:]
        var out: [PR] = []
        for log in logs {   // oldest first
            let byWeight = log.weightKg > 0
            let score = byWeight ? log.weightKg : Double(log.reps)
            let key = log.exerciseID + (byWeight ? "#w" : "#r")
            if let prev = best[key] {
                if score > prev {
                    best[key] = score
                    out.append(PR(id: log.persistentModelID, exerciseID: log.exerciseID, date: log.date,
                                  weightKg: log.weightKg, reps: log.reps))
                }
            } else {
                best[key] = score   // the first time isn't a record yet
            }
        }
        return out
    }

    @ViewBuilder
    private var recentPRsSection: some View {
        let recent = Array(prs.suffix(5).reversed())
        Section("Recent PRs") {
            if recent.isEmpty {
                Text("Beat a previous best and it shows up here.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(recent) { pr in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ExerciseCatalog.name(for: pr.exerciseID)).font(.subheadline.weight(.semibold))
                            Text(pr.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(pr.weightKg > 0
                             ? "\(number((units.display(pr.weightKg) * 10).rounded() / 10)) \(units.label) × \(pr.reps)"
                             : "BW × \(pr.reps)")
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                }
            }
        }
    }

    private func number(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}
