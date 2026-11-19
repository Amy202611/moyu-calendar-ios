import SwiftUI
struct LedgerView: View {
    @EnvironmentObject var store: Store
    @State private var person = "p1"
    @State private var remainingOnly = false
    @State private var editing: Entry?
    private func redemptions(_ id: String) -> [(Entry,Int)] {
        store.data.entries.filter { $0.type == .leave }.compactMap { e in
            let m = (e.allocations ?? []).filter { $0.overtimeId == id }.reduce(0) { $0+$1.minutes }
            return m > 0 ? (e,m) : nil
        }.sorted { $0.0.date < $1.0.date }
    }
    var body: some View {
        List {
            Section { PersonPicker(person:$person); Toggle("只看有余额的加班",isOn:$remainingOnly) }
            ForEach(store.data.entries.filter { $0.type == .overtime && (person == "all" || $0.person == person) }.sorted { $0.date > $1.date }) { entry in
                let links = redemptions(entry.id)
                let used = links.reduce(0) { $0+$1.1 }
                if !remainingOnly || entry.minutes > used {
                    Section {
                        Button { editing = entry } label: { EntryRow(entry:entry) }.buttonStyle(.plain)
                        Text("核销 "+number(Double(used)/Double(store.data.unit))+"天 · 剩余 "+number(Double(entry.minutes-used)/Double(store.data.unit))+"天").font(.subheadline.bold())
                        ForEach(links,id: \.0.id) { leave,minutes in
                            Button { editing = leave } label: {
                                VStack(alignment:.leading) {
                                    Text(leave.date+" · "+(leave.date > Day.today ? "已安排倒休 " : "已倒休 ")+number(Double(minutes)/Double(store.data.unit))+"天")
                                    if !leave.note.isEmpty { Text(leave.note).font(.caption) }
                                }
                            }
                        }
                    }
                }
            }
        }.navigationTitle("加班销假台账").sheet(item:$editing) { RecordEditor(entry:$0) }
    }
}
