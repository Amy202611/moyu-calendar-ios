import SwiftUI
@main struct MoyuApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notificationDelegate
    @State private var selectedTab = 0
    @StateObject private var store = Store()
    @StateObject private var holidays = Holidays()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            TabView(selection:$selectedTab) {
                NavigationStack { MonthView() }.tabItem { Label("日历",systemImage:"calendar") }.tag(0)
                NavigationStack { PeopleView() }.tabItem { Label("排班",systemImage:"square.stack.3d.up") }.tag(1)
                NavigationStack { StatisticsView() }.tabItem { Label("统计",systemImage:"chart.bar") }.tag(2)
                NavigationStack { PreferencesView() }.tabItem { Label("我的",systemImage:"person.crop.circle") }.tag(3)
            }.environmentObject(store).environmentObject(holidays).tint(Color(hex:"#28765b"))
            .alert("提示",isPresented:Binding(get:{ store.error != nil },set:{ if !$0 { store.error = nil } })) { Button("知道了",role:.cancel) {} } message: { Text(store.error ?? "") }
            .task { await holidays.refresh(force:false); store.updateWidgets(holidays); await store.scheduleNotifications() }
            .onOpenURL { url in if url.scheme == "moyu-calendar", let day = url.pathComponents.last, Day.date(day) != nil { selectedTab = 0; store.linkDay = day } }
            .onReceive(NotificationCenter.default.publisher(for:Notification.Name("moyu.openDay"))) { event in if let day = event.object as? String, Day.date(day) != nil { selectedTab = 0; store.linkDay = day } }
            .onChange(of:holidays.checkedAt) { _ in store.updateWidgets(holidays) }
            .onChange(of:phase) { p in if p == .active { Task { await holidays.refresh(force:false); store.updateWidgets(holidays); await store.scheduleNotifications() } } }
        }
    }
}
struct PersonPicker: View {
    @EnvironmentObject var store: Store
    @Binding var person: String
    var all = true
    var body: some View { Picker("人员",selection:$person) { ForEach(store.data.people) { Text($0.name).tag($0.id) }; if all { Text("两人").tag("all") } }.pickerStyle(.segmented) }
}
struct Badge: View {
    var title: String, color: Color
    var body: some View { Text(title).font(.system(size:9,weight:.medium)).lineLimit(1).minimumScaleFactor(0.6).padding(3).foregroundStyle(color).background(color.opacity(0.12),in:RoundedRectangle(cornerRadius:4)) }
}
struct Metric: View {
    var title: String, value: String, color: Color
    var body: some View { VStack(alignment:.leading,spacing:7) { Text(title).font(.caption); Text(value).font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.6) }.frame(maxWidth:.infinity,alignment:.leading).padding(12).foregroundStyle(color).background(color.opacity(0.08),in:RoundedRectangle(cornerRadius:15)) }
}
struct MonthView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var holidays: Holidays
    @State private var person = "p1"
    @State private var month = String(Day.today.prefix(7))
    @State private var selected = Day.today
    @State private var editDay = false
    @State private var entry: Entry?
    private var people: [Person] { store.data.people.filter { person == "all" || $0.id == person } }
    private var keys: [String] {
        let first = month+"-01"
        guard let d = Day.date(first), let count = Day.calendar.range(of:.day,in:.month,for:d)?.count else { return [] }
        let offset = (Day.weekday(first)-store.data.weekStart+7)%7
        return (0..<offset).map { "_\($0)" }+(0..<count).map { Day.add(first,$0) }
    }
    var body: some View {
        ScrollView {
            VStack(spacing:17) {
                PersonPicker(person:$person)
                HStack {
                    Button { move(-1) } label: { Image(systemName:"chevron.left") }
                    Spacer(); Text(month+"月").font(.title2.bold()); Spacer()
                    Button("今天") { month = String(Day.today.prefix(7)); selected = Day.today }.font(.caption)
                    Button { move(1) } label: { Image(systemName:"chevron.right") }
                }
                summary
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:3),count:7),spacing:7) {
                    ForEach(0..<7,id:\.self) { i in Text(["日","一","二","三","四","五","六"][(i+store.data.weekStart)%7]).font(.caption2).foregroundStyle(.secondary) }
                    ForEach(keys,id:\.self) { key in
                        if key.hasPrefix("_") { Color.clear.frame(minHeight:80) }
                        else { Button { selected = key } label: { DayCell(day:key,person:person,selected:key == selected) }.buttonStyle(.plain) }
                    }
                }
                NavigationLink { HolidayList() } label: { HStack { Image(systemName:"network"); VStack(alignment:.leading) { Text("中美节假日表"); Text(holidays.status).font(.caption2).foregroundStyle(.secondary) }; Spacer(); Image(systemName:"chevron.right") }.padding().background(.thinMaterial,in:RoundedRectangle(cornerRadius:14)) }
                detail
                Text("基础班表与独立值班分开统计，值班不自动记作加班。").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }.background(Color(hex:"#f8f7f3")).navigationTitle("摸鱼日历")
        .toolbar { NavigationLink { PreferencesView() } label: { Image(systemName:"slider.horizontal.3") } }
        .onChange(of:store.linkDay) { day in if let day { month = String(day.prefix(7)); selected = day } }
        .sheet(isPresented:$editDay) { DayEditor(day:selected,person:person == "all" ? "p1" : person) }
        .sheet(item:$entry) { RecordEditor(entry:$0) }
    }
    private var summary: some View {
        let y = String(month.prefix(4)), s = Roster.statistics(store.data,person,y+"-01-01",y+"-12-31")
        let annual = people.reduce(0) { $0+Roster.annual(store.data,$1.id,y).remaining }
        return VStack(alignment:.leading) {
            HStack { Metric(title:"加班 / 天",value:number(Double(s.overtime)/Double(store.data.unit)),color:store.color("overtime")); Metric(title:"倒休已休 / 天",value:number(Double(s.leave)/Double(store.data.unit)),color:store.color("leave")); Metric(title:"年假剩余 / 天",value:number(Double(annual)/Double(store.data.unit)),color:store.color("annual")) }
            Text("可倒休 \(number(Double(s.balance)/Double(store.data.unit))) 天 · 已安排 \(number(Double(s.planned)/Double(store.data.unit))) 天").font(.caption).padding(.top,5)
            ForEach(people) { p in AnnualSummary(person:p.id,year:y) }
        }
    }
    private var detail: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text(selected).font(.headline); Spacer(); Text(Day.lunar(selected)).font(.caption).foregroundStyle(.secondary) }
            ForEach(holidays.labels(selected,settings:store.data.settings),id:\.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            ForEach(people) { p in
                if let s = Roster.shift(store.data,p.id,selected) { Text(p.name+" · "+s.title+" · "+Roster.time(p,s)).font(.subheadline) }
                if let r = Roster.duty(store.data,p.id,selected) { Text(p.name+" · 值班 · "+r.time).font(.subheadline).foregroundStyle(store.color("duty")) }
                if let n = store.data.dayNotes?[selected]?[p.id], !n.isEmpty { Text(p.name+"："+n).font(.caption).foregroundStyle(.secondary) }
            }
            ForEach(store.data.entries.filter { $0.date == selected && (person == "all" || $0.person == person) }) { e in Button { entry = e } label: { EntryRow(entry:e) }.buttonStyle(.plain) }
            HStack { ForEach(Kind.allCases) { kind in Button("＋"+kind.title) { entry = Entry(date:selected,person:person == "all" ? "p1" : person,type:kind,minutes:store.data.unit/2) }.frame(maxWidth:.infinity).font(.subheadline) } }.buttonStyle(.bordered)
            Button("修改当天基础安排 / 添加值班") { editDay = true }.frame(maxWidth:.infinity)
        }.padding().frame(maxWidth:.infinity,alignment:.leading).background(.background,in:RoundedRectangle(cornerRadius:20))
    }
    private func move(_ n: Int) {
        guard let d = Day.date(month+"-01"), let r = Day.calendar.date(byAdding:.month,value:n,to:d), Day.date(Day.key(r)) != nil else { return }
        month = String(Day.key(r).prefix(7)); selected = month+"-01"
    }
}
struct DayCell: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var holidays: Holidays
    var day: String, person: String, selected: Bool
    private var dateColor: Color {
        let d = store.data
        let entries = d.entries.filter { $0.date == day && (person == "all" || $0.person == person) }
        for k in [Kind.annual, .leave, .overtime] where entries.contains(where: { $0.type == k }) { return store.color(k.rawValue) }
        let people = d.people.filter { person == "all" || $0.id == person }
        if people.contains(where: { Roster.duty(d,$0.id,day) != nil }) { return store.color("duty") }
        if let p = people.first(where: { Roster.shift(d,$0.id,day) == .night }) { return store.color(p.id) }
        if let s = people.compactMap({ Roster.shift(d,$0.id,day) }).first { return store.color(s.rawValue) }
        return .primary
    }
    var body: some View {
        VStack(spacing:2) {
            Text(String(Int(day.suffix(2)) ?? 0)).font(.system(size:19,weight:.semibold)).foregroundStyle(dateColor)
            if store.data.settings.lunar { Text(Day.lunar(day)).font(.system(size:8)).foregroundStyle(.secondary).lineLimit(1) }
            ForEach(store.data.people.filter { person == "all" || $0.id == person }) { p in
                if let s = Roster.shift(store.data,p.id,day) { Badge(title:String(p.name.prefix(2))+"·"+s.title,color:store.color(s == .night ? p.id : s.rawValue)) }
                if Roster.duty(store.data,p.id,day) != nil { Badge(title:String(p.name.prefix(2))+"·值班",color:store.color("duty")) }
            }
            ForEach(Kind.allCases) { k in
                let m = store.data.entries.filter { $0.date == day && $0.type == k && (person == "all" || $0.person == person) }.reduce(0) { $0+$1.minutes }
                if m > 0 { Badge(title:k.title+"·"+number(Double(m)/Double(store.data.unit)),color:store.color(k.rawValue)) }
            }
            if let h = holidays.labels(day,settings:store.data.settings).first { Text(h).font(.system(size:7)).lineLimit(1).foregroundStyle(.orange) }
            Spacer(minLength:0)
        }.frame(maxWidth:.infinity,minHeight:80).padding(.vertical,5)
        .background(day == Day.today ? store.color("today") : .clear,in:RoundedRectangle(cornerRadius:9))
        .overlay(RoundedRectangle(cornerRadius:9).stroke(selected ? Color(hex:"#28765b") : .clear,lineWidth:1.5))
    }
}
struct EntryRow: View {
    @EnvironmentObject var store: Store
    var entry: Entry
    var body: some View {
        VStack(alignment:.leading,spacing:4) {
            Text(store.name(entry.person)+" · "+entry.type.title+" "+number(Double(entry.minutes)/Double(store.data.unit))+"天").font(.subheadline.bold()).foregroundStyle(store.color(entry.type.rawValue))
            Text(entry.date+" · "+number(Double(entry.minutes)/60)+"小时").font(.caption).foregroundStyle(.secondary)
            if let part = entry.part, !part.isEmpty { Text(part == "am" ? "上午" : part == "pm" ? "下午" : part).font(.caption) }
            if !entry.note.isEmpty { Text(entry.note).font(.caption) }
            ForEach(Array((entry.allocations ?? []).enumerated()),id:\.offset) { _,a in
                if let o = store.data.entries.first(where:{ $0.id == a.overtimeId }) { Text("来源 \(o.date) · \(o.note) → 核销 \(number(Double(a.minutes)/60))小时").font(.caption2).foregroundStyle(.secondary) }
            }
        }.padding(.vertical,4).frame(maxWidth:.infinity,alignment:.leading)
    }
}
