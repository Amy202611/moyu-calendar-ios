import SwiftUI
import EventKit
@MainActor final class SystemCalendars: ObservableObject {
    @Published private(set) var calendars: [EKCalendar] = []
    @Published var status = "未读取系统日历"
    @Published var selected = UserDefaults.standard.stringArray(forKey:"holidayCalendarIDs") ?? [] {
        didSet { UserDefaults.standard.set(selected,forKey:"holidayCalendarIDs") }
    }
    let eventStore = EKEventStore()
    func authorize() async {
        do {
            let allowed: Bool
            if #available(iOS 17.0, *) { allowed = try await eventStore.requestFullAccessToEvents() }
            else { allowed = try await eventStore.requestAccess(to:.event) }
            guard allowed else { status = "未授权，请到系统设置允许日历读取"; return }
            calendars = eventStore.calendars(for:.event).sorted { $0.title < $1.title }; status = "选择节假日订阅日历后点击同步"
        } catch { status = error.localizedDescription }
    }
    func sync(_ holidays: Holidays, year: Int) {
        let authorization = EKEventStore.authorizationStatus(for:.event)
        guard authorization == .authorized else { status = "请先授权读取系统日历"; return }
        let chosen = eventStore.calendars(for:.event).filter { selected.contains($0.calendarIdentifier) }
        guard !chosen.isEmpty else { holidays.setSystemRows([],year:year); status = "未选择日历，已清除此年度的系统叠加数据"; return }
        guard let start = Day.date("\(year)-01-01"), let end = Day.date("\(year+1)-01-01") else { return }
        let predicate = eventStore.predicateForEvents(withStart:Day.calendar.startOfDay(for:start),end:Day.calendar.startOfDay(for:end),calendars:chosen)
        var result: [String:HolidayRow] = [:]
        for event in eventStore.events(matching:predicate) where event.isAllDay {
            guard let title = event.title, !title.isEmpty, title.count <= 200, let begin = event.startDate, let finish = event.endDate else { continue }
            var day = max(Day.key(begin),"\(year)-01-01"), count = 0
            while day.hasPrefix("\(year)-"), let date = Day.date(day), Day.calendar.startOfDay(for:date) < finish, count < 366 {
                let row = HolidayRow(country:"SYS",date:day,name:title,kind:"system",source:"系统日历·"+event.calendar.title)
                result[row.id] = row; day = Day.add(day,1); count += 1
            }
        }
        holidays.setSystemRows(Array(result.values),year:year); status = "已同步 \(result.count) 条全天节日；不修改系统日历"
    }
}
struct SystemCalendarPreferences: View {
    @EnvironmentObject var holidays: Holidays
    @EnvironmentObject var store: Store
    @StateObject private var system = SystemCalendars()
    @State private var year = Day.calendar.component(.year,from:Date())
    var body: some View {
        Form {
            Section {
                Text("选择手机中的节假日订阅日历。仅读取所选日历的全天事件，作为“机·”节日叠加显示，不改动个人排班。")
                Button("授权并列出系统日历") { Task { await system.authorize() } }
                Stepper("\(String(year))年",value:$year,in:1901...2098)
                ForEach(system.calendars,id: \.calendarIdentifier) { calendar in
                    Toggle(calendar.title,isOn:Binding(get:{ system.selected.contains(calendar.calendarIdentifier) },set:{ enabled in
                        system.selected.removeAll { $0 == calendar.calendarIdentifier }; if enabled { system.selected.append(calendar.calendarIdentifier) }
                    }))
                }
                Button("同步所选年度") { system.sync(holidays,year:year); store.updateWidgets(holidays) }
                Text(system.status).font(.caption)
            }
            Section { Text("系统节假日更新依赖手机日历订阅源；点击同步后更新本应用。联网自动校对中国和美国来源是另一条独立更新途径。").font(.caption) }
        }.navigationTitle("手机节假日日历")
    }
}
