import SwiftUI

struct PlanView: View {
    @AppStorage("units") private var unitsRaw = UnitSystem.imperial.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Units", selection: $unitsRaw) {
                        Text("Imperial").tag(UnitSystem.imperial.rawValue)
                        Text("Metric").tag(UnitSystem.metric.rawValue)
                    }.pickerStyle(.segmented)
                }
                Section("Template") {
                    ForEach(PlanTemplate.phase1) { Text($0.title) }
                    Text("Excel import — coming next").foregroundStyle(.secondary)
                }
                Section("Acknowledgements") {
                    NavigationLink("Exercise list (MIT License)") {
                        ScrollView {
                            Text(ExerciseCatalog.licenseNotice)
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .navigationTitle("Exercise list")
                    }
                }
            }
            .navigationTitle("Your plan")
        }
    }
}
