import SwiftUI
struct AnnualSummary: View {
    @EnvironmentObject var store: Store
    var person: String, year: String
    var body: some View {
        let r = Roster.annual(store.data,person,year), unit = Double(store.data.unit)
        VStack(alignment:.leading,spacing:5) {
            Text(store.name(person)+" · "+year+"年年假").font(.headline)
            Text("总额 "+number(Double(r.total)/unit)+"天 · 已休 "+number(Double(r.used)/unit)+"天").font(.subheadline)
            Text("已安排 "+number(Double(r.planned)/unit)+"天 · 剩余 "+number(Double(r.remaining)/unit)+"天").font(.subheadline.bold()).foregroundStyle(store.color("annual"))
        }.padding(.vertical,4)
    }
}
