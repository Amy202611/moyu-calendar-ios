import SwiftUI
import WidgetKit
extension Store {
    func updateWidgets(_ holidays: Holidays? = nil) {
        guard let root = WidgetStorage.container() else { return }
        do {
            var rows: [WidgetDay] = []
            let first = String(Day.today.prefix(7))+"-01"
            let start = Day.add(first,-31), end = Day.add(first,93)
            var date = start
            while date <= end {
                var badges: [WidgetBadge] = []
                for person in data.people {
                    if let shift = Roster.shift(data,person.id,date) {
                        let key = shift == .night ? person.id : shift.rawValue
                        badges.append(WidgetBadge(title:person.name+"·"+shift.title,color:data.colors[key] ?? "#39856a",person:person.id))
                    }
                    if let duty = Roster.duty(data,person.id,date) {
                        badges.append(WidgetBadge(title:person.name+"·值班 "+duty.time,color:data.colors["duty"] ?? "#7951c9",person:person.id))
                    }
                    for entry in data.entries where entry.person == person.id && entry.date == date {
                        badges.append(WidgetBadge(title:person.name+"·"+entry.type.title+" "+number(Double(entry.minutes)/Double(data.unit))+"天",color:data.colors[entry.type.rawValue] ?? "#39856a",person:person.id))
                    }
                }
                let notes = data.people.compactMap { p -> String? in
                    guard let n = data.dayNotes?[date]?[p.id], !n.isEmpty else { return nil }; return p.name+"："+n
                }.joined(separator:"；")
                rows.append(WidgetDay(date:date,lunar:data.settings.lunar ? Day.lunar(date) : "",holiday:holidays?.labels(date,settings:data.settings).joined(separator:" / ") ?? "",note:notes,badges:badges,color:badges.last?.color ?? "#24364b"))
                date = Day.add(date,1)
            }
            var summaries: [String:String] = [:]
            let year = String(Day.today.prefix(4))
            for id in ["p1","p2","all"] {
                let stats = Roster.statistics(data,id,year+"-01-01",Day.today)
                let annual = data.people.filter { id == "all" || $0.id == id }.reduce(0) { $0+Roster.annual(data,$1.id,year).remaining }
                summaries[id] = "加班 "+number(Double(stats.overtime)/Double(data.unit))+"天 · 倒休 "+number(Double(stats.leave)/Double(data.unit))+"天 · 年假余 "+number(Double(annual)/Double(data.unit))+"天"
            }
            var snapshot = WidgetSnapshot(generated:Date(),days:rows,summaries:summaries,names:Dictionary(uniqueKeysWithValues:data.people.map { ($0.id,$0.name) }),weekStart:data.weekStart,todayColor:data.colors["today"] ?? "#e2edf9")
            if holidays == nil, let previous = WidgetStorage.read() {
                let old = Dictionary(uniqueKeysWithValues:previous.days.map { ($0.date,$0.holiday) })
                for i in snapshot.days.indices { snapshot.days[i].holiday = old[snapshot.days[i].date] ?? "" }
            }
            try JSONEncoder().encode(snapshot).write(to:root.appendingPathComponent("widget.json"),options:.atomic)
            WidgetCenter.shared.reloadAllTimelines()
        } catch { self.error = "小组件同步失败："+error.localizedDescription }
    }
}
struct WidgetPreferences: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var holidays: Holidays
    var body: some View {
        Form {
            Section("桌面小组件") {
                Text("长按桌面空白处 → 编辑 → 添加小组件 → 摸鱼日历，选择“我”“搭班人”或“两人”。支持今日卡片和月历。")
                Button("同步到小组件") { store.updateWidgets(holidays) }
                if let snapshot = WidgetStorage.read() { Text("最近同步："+snapshot.generated.formatted()).font(.caption) }
                else { Text("尚未建立共享容器。小组件需要安装带 Widget 的 SideStore 版本，并保留扩展及 App Groups 权限。").font(.caption) }
            }
            Section {
                Text("排班与颜色修改后自动同步。节假日联网校对后同步；小组件刷新频率由 iOS 决定。点击日期可打开对应日历。").font(.caption)
                Text("免费 Apple ID 能否注册共享 App Group 取决于 SideStore 与账号实际返回结果；若签名失败，可安装基础未签名版，保留全部应用内功能。").font(.caption)
            }
        }.navigationTitle("桌面小组件")
    }
}
